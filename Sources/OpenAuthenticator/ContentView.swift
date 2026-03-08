import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: AccountStore
    @ObservedObject var auth: AuthState
    @State private var copiedId: UUID?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showClearConfirm = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""
    @State private var isDragging = false

    var body: some View {
        Group {
            if auth.isUnlocked {
                unlockedBody
            } else {
                lockedBody
            }
        }
        .frame(width: 320)
        .onChange(of: auth.isUnlocked) {
            if auth.isUnlocked {
                store.load(context: auth.authenticatedContext)
            } else {
                store.purge()
            }
        }
    }

    var lockedBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("OpenAuthenticator is Locked")
                .font(.headline)
            Text("Authenticate to view your codes")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = auth.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock") { auth.authenticate() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .onAppear { auth.authenticate() }
    }

    var unlockedBody: some View {
        VStack(spacing: 0) {
            mainContent
                .overlay { dragOverlay }
                .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers)
                    return true
                }
        }
        .alert("Import Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Imported", isPresented: $showImportResult) {
            Button("OK") {}
        } message: {
            Text(importResultMessage)
        }
    }

    var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.accounts.isEmpty {
                emptyState
            } else {
                accountList
            }
            Divider()
            footer
        }
        .frame(width: 320)
    }

    @ViewBuilder
    var dragOverlay: some View {
        if isDragging {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                .background(Color.accentColor.opacity(0.1).cornerRadius(10))
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.accentColor)
                        Text("Drop QR code images")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .padding(4)
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            Text("OpenAuthenticator")
                .font(.headline)
            Spacer()
            Button(action: importQR) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help("Import QR Codes")
            Button(action: { auth.lock() }) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Lock")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No accounts yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Import Google Authenticator export\nQR code images, or drag & drop them here")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Import QR Codes") { importQR() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(32)
    }

    var accountList: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.accounts) { account in
                        AccountRow(
                            account: account,
                            date: timeline.date,
                            isCopied: copiedId == account.id
                        )
                        .onTapGesture { copyCode(for: account, at: timeline.date) }
                        .contextMenu {
                            Button("Copy Code") { copyCode(for: account, at: timeline.date) }
                            Divider()
                            Button("Delete", role: .destructive) { store.remove(account) }
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 380)
        }
    }

    var footer: some View {
        VStack(spacing: 0) {
            if showClearConfirm {
                HStack(spacing: 12) {
                    Text("Remove all \(store.accounts.count) accounts?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        withAnimation { showClearConfirm = false }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    Button("Delete All") {
                        store.removeAll()
                        withAnimation { showClearConfirm = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.red.opacity(0.08))
            } else {
                HStack {
                    if !store.accounts.isEmpty {
                        Button("Clear All") {
                            withAnimation { showClearConfirm = true }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    func copyCode(for account: Account, at date: Date) {
        let code = TOTP.generate(
            secret: account.secret, date: date,
            digits: account.digits, algorithm: account.algorithm,
            period: account.period
        )
        let pb = NSPasteboard.general
        pb.clearContents()
        // Set as concealed type to hint clipboard managers not to record this
        pb.setString(code, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let changeCount = pb.changeCount
        withAnimation { copiedId = account.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { if copiedId == account.id { copiedId = nil } }
        }
        // Auto-clear clipboard after 10s if unchanged
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if pb.changeCount == changeCount {
                pb.clearContents()
            }
        }
    }

    func importQR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = true
        panel.message = "Select all Google Authenticator export QR code images"
        panel.prompt = "Import"

        guard panel.runModal() == .OK else { return }
        processURLs(panel.urls)
    }

    func handleDrop(_ providers: [NSItemProvider]) {
        let queue = DispatchQueue(label: "drop.urls")
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        queue.sync { urls.append(url) }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        queue.sync { urls.append(url) }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            processURLs(urls)
        }
    }

    func processURLs(_ urls: [URL]) {
        var newAccounts: [Account] = []
        var failedImages: [String] = []
        var successCount = 0

        for url in urls {
            do {
                let accounts = try QRImporter.importAccounts(from: url)
                if accounts.isEmpty {
                    failedImages.append(url.lastPathComponent)
                } else {
                    newAccounts.append(contentsOf: accounts)
                    successCount += 1
                }
            } catch {
                failedImages.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if newAccounts.isEmpty {
            errorMessage = failedImages.isEmpty
                ? "No authenticator accounts found in the selected image(s)."
                : "Failed to import:\n" + failedImages.joined(separator: "\n")
            showError = true
        } else {
            let added = store.addAccounts(newAccounts)
            var msg = "Found \(newAccounts.count) account(s) from \(successCount) image(s)."
            if added < newAccounts.count {
                msg += "\n\(newAccounts.count - added) duplicate(s) skipped."
            }
            if !failedImages.isEmpty {
                msg += "\n\(failedImages.count) image(s) had no QR codes."
            }
            importResultMessage = msg
            showImportResult = true
        }
    }
}

struct AccountRow: View {
    let account: Account
    let date: Date
    let isCopied: Bool

    var code: String {
        TOTP.generate(
            secret: account.secret, date: date,
            digits: account.digits, algorithm: account.algorithm,
            period: account.period
        )
    }

    var remaining: Int {
        account.period - (Int(date.timeIntervalSince1970) % account.period)
    }

    var formattedCode: String {
        if code.count == 6 {
            return "\(code.prefix(3)) \(code.suffix(3))"
        } else if code.count == 8 {
            return "\(code.prefix(4)) \(code.suffix(4))"
        }
        return code
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.issuer.isEmpty ? account.name : account.issuer)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(1)

                if !account.issuer.isEmpty && !account.name.isEmpty {
                    Text(account.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if isCopied {
                    Text("Copied!")
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text(formattedCode)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            CountdownRing(remaining: remaining, total: account.period)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
        )
        .contentShape(Rectangle())
    }
}

struct CountdownRing: View {
    let remaining: Int
    let total: Int

    var progress: Double { Double(remaining) / Double(total) }

    var color: Color {
        if remaining <= 5 { return .red }
        if remaining <= 10 { return .orange }
        return .green
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            Text("\(remaining)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 30, height: 30)
    }
}
