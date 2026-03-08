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

enum Importer {

    /// Route to the correct parser based on file extension
    static func importAccounts(from url: URL) throws -> [Account] {
        switch url.pathExtension.lowercased() {
        case "csv":
            return try importCSV(from: url)
        case "1pux", "zip":
            return try import1PUX(from: url)
        default:
            return try importQRImage(from: url)
        }
    }

    /// Parse a raw otpauth:// URI string
    static func importFromURI(_ uri: String) -> [Account] {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        // Handle multiple URIs (one per line)
        var accounts: [Account] = []
        for line in trimmed.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("otpauth://"), let acc = parseOTPAuth(l) {
                accounts.append(acc)
            } else if l.hasPrefix("otpauth-migration://"), let parsed = try? parseMigration(l) {
                accounts.append(contentsOf: parsed)
            }
        }
        return accounts
    }

    // MARK: - QR Code Image

    static func importQRImage(from imageURL: URL) throws -> [Account] {
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

    // MARK: - 1Password CSV

    static func importCSV(from url: URL) throws -> [Account] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSVRows(content)

        guard let header = rows.first else {
            throw ImportError.invalidData("Empty CSV file.")
        }

        let headerLower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let otpIndex = headerLower.firstIndex(where: {
            $0 == "one-time password" || $0 == "otp" || $0 == "totp" || $0 == "one time password"
        })
        let titleIndex = headerLower.firstIndex(where: {
            $0 == "title" || $0 == "name" || $0 == "service" || $0 == "login"
        })
        let usernameIndex = headerLower.firstIndex(where: {
            $0 == "username" || $0 == "email" || $0 == "account"
        })

        guard let otpCol = otpIndex else {
            throw ImportError.invalidData("No OTP column found. Expected 'one-time password', 'otp', or 'totp'.")
        }

        var accounts: [Account] = []
        for row in rows.dropFirst() {
            guard otpCol < row.count else { continue }
            let otpValue = row[otpCol].trimmingCharacters(in: .whitespaces)
            guard !otpValue.isEmpty else { continue }

            if otpValue.hasPrefix("otpauth://"), var account = parseOTPAuth(otpValue) {
                if let ti = titleIndex, ti < row.count {
                    let title = row[ti].trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty && account.issuer.isEmpty { account.issuer = title }
                }
                if let ui = usernameIndex, ui < row.count {
                    let user = row[ui].trimmingCharacters(in: .whitespaces)
                    if !user.isEmpty && account.name.isEmpty { account.name = user }
                }
                accounts.append(account)
            } else if let secret = base32Decode(otpValue) {
                let issuer = (titleIndex.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil }) ?? ""
                let name = (usernameIndex.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil }) ?? ""
                accounts.append(Account(
                    secret: secret, name: name, issuer: issuer,
                    algorithm: 1, digits: 6, period: 30
                ))
            }
        }

        return accounts
    }

    private static func parseCSVRows(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var field = ""
        var inQuotes = false
        var i = content.startIndex

        while i < content.endIndex {
            let c = content[i]
            if inQuotes {
                if c == "\"" {
                    let next = content.index(after: i)
                    if next < content.endIndex && content[next] == "\"" {
                        field.append("\"")
                        i = content.index(after: next)
                    } else {
                        inQuotes = false
                        i = content.index(after: i)
                    }
                } else {
                    field.append(c)
                    i = content.index(after: i)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                    i = content.index(after: i)
                } else if c == "," {
                    currentRow.append(field)
                    field = ""
                    i = content.index(after: i)
                } else if c == "\n" || c == "\r" {
                    currentRow.append(field)
                    field = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    let next = content.index(after: i)
                    if c == "\r" && next < content.endIndex && content[next] == "\n" {
                        i = content.index(after: next)
                    } else {
                        i = content.index(after: i)
                    }
                } else {
                    field.append(c)
                    i = content.index(after: i)
                }
            }
        }
        currentRow.append(field)
        if !currentRow.allSatisfy({ $0.isEmpty }) {
            rows.append(currentRow)
        }
        return rows
    }

    // MARK: - 1Password 1PUX (ZIP + JSON)

    static func import1PUX(from url: URL) throws -> [Account] {
        let jsonData = try extract1PUXData(from: url)

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let accountsArr = root["accounts"] as? [[String: Any]]
        else {
            throw ImportError.invalidData("Invalid 1PUX structure.")
        }

        var accounts: [Account] = []

        for account in accountsArr {
            guard let vaults = account["vaults"] as? [[String: Any]] else { continue }
            for vault in vaults {
                guard let items = vault["items"] as? [[String: Any]] else { continue }
                for item in items {
                    let overview = item["overview"] as? [String: Any]
                    let title = overview?["title"] as? String ?? item["title"] as? String ?? ""
                    guard let details = item["details"] as? [String: Any] else { continue }

                    // Check loginFields
                    if let loginFields = details["loginFields"] as? [[String: Any]] {
                        for field in loginFields {
                            if let value = field["value"] as? String, looksLikeOTP(value) {
                                if let acc = accountFromOTPValue(value, issuer: title, name: "") {
                                    accounts.append(acc)
                                }
                            }
                        }
                    }

                    // Check sections for OTP fields
                    if let sections = details["sections"] as? [[String: Any]] {
                        for section in sections {
                            guard let fields = section["fields"] as? [[String: Any]] else { continue }
                            for field in fields {
                                guard let value = field["value"] as? [String: Any] else { continue }
                                if let totp = value["totp"] as? String, !totp.isEmpty {
                                    if let acc = accountFromOTPValue(totp, issuer: title, name: "") {
                                        accounts.append(acc)
                                    }
                                } else if let str = value["string"] as? String, looksLikeOTP(str) {
                                    if let acc = accountFromOTPValue(str, issuer: title, name: "") {
                                        accounts.append(acc)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return accounts
    }

    private static func extract1PUXData(from url: URL) throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            // Secure cleanup
            if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
                for file in files {
                    if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int, size > 0 {
                        try? Data(count: size).write(to: file)
                    }
                    try? FileManager.default.removeItem(at: file)
                }
            }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", url.path, "export.data", "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let exportDataURL = tempDir.appendingPathComponent("export.data")
        guard FileManager.default.fileExists(atPath: exportDataURL.path) else {
            throw ImportError.invalidData("Could not find export.data in 1PUX archive.")
        }

        return try Data(contentsOf: exportDataURL)
    }

    private static func looksLikeOTP(_ value: String) -> Bool {
        value.hasPrefix("otpauth://") ||
        value.range(of: "^[A-Z2-7]{16,}=*$", options: .regularExpression) != nil
    }

    private static func accountFromOTPValue(_ value: String, issuer: String, name: String) -> Account? {
        if value.hasPrefix("otpauth://") {
            if var account = parseOTPAuth(value) {
                if account.issuer.isEmpty { account.issuer = issuer }
                if account.name.isEmpty { account.name = name }
                return account
            }
        } else if let secret = base32Decode(value) {
            return Account(
                secret: secret, name: name, issuer: issuer,
                algorithm: 1, digits: 6, period: 30
            )
        }
        return nil
    }

    // MARK: - Google Authenticator Migration Format

    static func parseMigration(_ urlString: String) throws -> [Account] {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value
        else {
            throw ImportError.invalidData("Could not parse migration URL.")
        }

        var b64 = dataParam
        while b64.count % 4 != 0 { b64 += "=" }

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
                case 1: if case .bytes(let d) = ef.value { secret = d }
                case 2: if case .bytes(let d) = ef.value { name = String(data: d, encoding: .utf8) ?? "" }
                case 3: if case .bytes(let d) = ef.value { issuer = String(data: d, encoding: .utf8) ?? "" }
                case 4: if case .varint(let v) = ef.value { algorithm = max(1, Int(v)) }
                case 5: if case .varint(let v) = ef.value { digits = v == 2 ? 8 : 6 }
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

        guard !str.isEmpty else { return nil }

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
