import Foundation
import CoreImage

enum ImportError: LocalizedError {
    case noQRCode
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .noQRCode: return "No QR code found in the image."
        case .invalidData(let msg): return "Invalid data: \(msg)"
        }
    }
}

enum QRImporter {
    static func importAccounts(from imageURL: URL) throws -> [Account] {
        guard let image = CIImage(contentsOf: imageURL) else {
            throw ImportError.invalidData("Could not load image.")
        }

        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            throw ImportError.invalidData("Could not create QR detector.")
        }

        let features = detector.features(in: image) as? [CIQRCodeFeature] ?? []
        let messages = features.compactMap(\.messageString)

        guard !messages.isEmpty else {
            throw ImportError.noQRCode
        }

        var accounts: [Account] = []
        for msg in messages {
            if msg.hasPrefix("otpauth-migration://") {
                accounts.append(contentsOf: try parseMigration(msg))
            } else if msg.hasPrefix("otpauth://") {
                if let account = parseOTPAuth(msg) {
                    accounts.append(account)
                }
            }
        }

        return accounts
    }

    // MARK: - Google Authenticator Migration Format

    static func parseMigration(_ urlString: String) throws -> [Account] {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value
        else {
            throw ImportError.invalidData("Could not parse migration URL.")
        }

        // Ensure proper base64 padding
        var b64 = dataParam
        while b64.count % 4 != 0 {
            b64 += "="
        }

        guard let data = Data(base64Encoded: b64) else {
            throw ImportError.invalidData("Could not decode base64 data.")
        }

        let fields = Protobuf.parse(data)
        var accounts: [Account] = []

        for field in fields where field.number == 1 {
            guard case .bytes(let entryData) = field.value else { continue }
            let entryFields = Protobuf.parse(entryData)

            var secret = Data()
            var name = ""
            var issuer = ""
            var algorithm = 1
            var digits = 6

            for ef in entryFields {
                switch ef.number {
                case 1:
                    if case .bytes(let d) = ef.value { secret = d }
                case 2:
                    if case .bytes(let d) = ef.value { name = String(data: d, encoding: .utf8) ?? "" }
                case 3:
                    if case .bytes(let d) = ef.value { issuer = String(data: d, encoding: .utf8) ?? "" }
                case 4:
                    if case .varint(let v) = ef.value { algorithm = max(1, Int(v)) }
                case 5:
                    if case .varint(let v) = ef.value { digits = v == 2 ? 8 : 6 }
                default: break
                }
            }

            accounts.append(Account(
                secret: secret, name: name, issuer: issuer,
                algorithm: algorithm, digits: digits, period: 30
            ))
        }

        return accounts
    }

    // MARK: - Standard otpauth:// URI

    static func parseOTPAuth(_ urlString: String) -> Account? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.host == "totp"
        else { return nil }

        let params = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        guard let secretB32 = params["secret"],
              let secret = base32Decode(secretB32)
        else { return nil }

        let label = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = label.split(separator: ":", maxSplits: 1)
        let issuer = params["issuer"] ?? (parts.count > 1 ? String(parts[0]) : "")
        let name = parts.count > 1 ? String(parts[1]) : label

        let algorithm: Int
        switch params["algorithm"]?.uppercased() {
        case "SHA256": algorithm = 2
        case "SHA512": algorithm = 3
        default: algorithm = 1
        }

        let digits = Int(params["digits"] ?? "6") ?? 6
        let period = Int(params["period"] ?? "30") ?? 30

        return Account(
            secret: secret, name: name, issuer: issuer,
            algorithm: algorithm, digits: digits, period: period
        )
    }

    // MARK: - Base32

    static func base32Decode(_ input: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let str = input.uppercased().replacingOccurrences(of: "=", with: "")

        var bits = ""
        for char in str {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            let value = alphabet.distance(from: alphabet.startIndex, to: index)
            let binary = String(value, radix: 2)
            bits += String(repeating: "0", count: max(0, 5 - binary.count)) + binary
        }

        var bytes: [UInt8] = []
        var i = bits.startIndex
        while bits.distance(from: i, to: bits.endIndex) >= 8 {
            let end = bits.index(i, offsetBy: 8)
            if let byte = UInt8(bits[i..<end], radix: 2) {
                bytes.append(byte)
            }
            i = end
        }

        return Data(bytes)
    }
}
