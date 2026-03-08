import Foundation
import CommonCrypto

struct Account: Identifiable, Codable, Equatable {
    var id = UUID()
    var secret: Data
    var name: String
    var issuer: String
    var algorithm: Int  // 1=SHA1, 2=SHA256, 3=SHA512
    var digits: Int     // 6 or 8
    var period: Int     // typically 30

    /// Validate and clamp fields to safe ranges
    var validated: Account {
        var copy = self
        copy.algorithm = (1...3).contains(algorithm) ? algorithm : 1
        copy.digits = (6...8).contains(digits) ? digits : 6
        copy.period = period > 0 ? period : 30
        copy.name = String(name.prefix(256))
        copy.issuer = String(issuer.prefix(256))
        return copy
    }
}

enum TOTP {
    static func generate(secret: Data, date: Date = Date(), digits: Int = 6, algorithm: Int = 1, period: Int = 30) -> String {
        // Guard against invalid inputs
        let safePeriod = period > 0 ? period : 30
        let safeDigits = (1...10).contains(digits) ? digits : 6

        guard !secret.isEmpty else { return String(repeating: "0", count: safeDigits) }

        let counter = UInt64(date.timeIntervalSince1970) / UInt64(safePeriod)
        var bigEndian = counter.bigEndian
        let counterData = Data(bytes: &bigEndian, count: 8)

        let hmacAlg: CCHmacAlgorithm
        let hashLen: Int
        switch algorithm {
        case 2:
            hmacAlg = CCHmacAlgorithm(kCCHmacAlgSHA256)
            hashLen = Int(CC_SHA256_DIGEST_LENGTH)
        case 3:
            hmacAlg = CCHmacAlgorithm(kCCHmacAlgSHA512)
            hashLen = Int(CC_SHA512_DIGEST_LENGTH)
        default:
            hmacAlg = CCHmacAlgorithm(kCCHmacAlgSHA1)
            hashLen = Int(CC_SHA1_DIGEST_LENGTH)
        }

        var hmac = [UInt8](repeating: 0, count: hashLen)
        secret.withUnsafeBytes { secretPtr in
            counterData.withUnsafeBytes { counterPtr in
                guard let secretBase = secretPtr.baseAddress,
                      let counterBase = counterPtr.baseAddress else { return }
                CCHmac(hmacAlg,
                       secretBase, secret.count,
                       counterBase, counterData.count,
                       &hmac)
            }
        }

        let offset = Int(hmac[hashLen - 1] & 0x0F)
        let code = (Int(hmac[offset]) & 0x7F) << 24
                 | (Int(hmac[offset + 1]) & 0xFF) << 16
                 | (Int(hmac[offset + 2]) & 0xFF) << 8
                 | (Int(hmac[offset + 3]) & 0xFF)

        let otp = code % Int(pow(10.0, Double(safeDigits)))
        return String(format: "%0\(safeDigits)d", otp)
    }
}
