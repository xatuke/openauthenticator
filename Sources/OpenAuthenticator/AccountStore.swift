import Foundation
import LocalAuthentication

class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []

    var authContext: LAContext?

    private var legacyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenAuthenticator", isDirectory: true)
        return dir.appendingPathComponent("accounts.json")
    }

    func load(context: LAContext? = nil) {
        authContext = context
        accounts = (try? Keychain.load(context: context)) ?? []
        migrateLegacyIfNeeded()
    }

    /// Wipe secrets from memory when locking
    func purge() {
        for i in accounts.indices {
            let count = accounts[i].secret.count
            accounts[i].secret = Data(repeating: 0, count: count)
        }
        accounts.removeAll()
        authContext = nil
    }

    @discardableResult
    func addAccounts(_ newAccounts: [Account]) -> Int {
        var added = 0
        for account in newAccounts {
            let validated = account.validated
            guard !validated.secret.isEmpty else { continue }
            if !accounts.contains(where: { $0.issuer == validated.issuer && $0.name == validated.name }) {
                accounts.append(validated)
                added += 1
            }
        }
        if added > 0 { save() }
        return added
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        save()
    }

    func removeAll() {
        purge()
        Keychain.deleteAll()
    }

    private func save() {
        do {
            try Keychain.save(accounts: accounts, context: authContext)
        } catch {
            print("Keychain save error: \(error.localizedDescription)")
        }
    }

    /// Migrate plaintext JSON to Keychain, then securely delete the file
    private func migrateLegacyIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL),
              let legacy = try? JSONDecoder().decode([Account].self, from: data),
              !legacy.isEmpty
        else { return }

        for account in legacy {
            let validated = account.validated
            guard !validated.secret.isEmpty else { continue }
            if !accounts.contains(where: { $0.issuer == validated.issuer && $0.name == validated.name }) {
                accounts.append(validated)
            }
        }
        save()

        // Overwrite file with random bytes then zeros before deleting (secure wipe)
        if let fileSize = try? fm.attributesOfItem(atPath: legacyURL.path)[.size] as? Int, fileSize > 0 {
            var random = Data(count: fileSize)
            _ = random.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, fileSize, $0.baseAddress!) }
            try? random.write(to: legacyURL)
            let zeros = Data(count: fileSize)
            try? zeros.write(to: legacyURL)
        }
        try? fm.removeItem(at: legacyURL)
    }
}
