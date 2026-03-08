import SwiftUI

@main
struct OpenAuthenticatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AccountStore()
    @StateObject private var auth = AuthState()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store, auth: auth)
        } label: {
            Image(systemName: "lock.shield.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
