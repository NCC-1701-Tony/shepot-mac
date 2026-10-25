import SwiftUI

@main
struct DictateApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        // Menu bar only (LSUIElement): no Dock icon, no main window.
        MenuBarExtra {
            MenuPanel()
                .environmentObject(state)
        } label: {
            Image(systemName: state.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
