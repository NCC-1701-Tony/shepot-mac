import SwiftUI

@main
struct ShepotApp: App {
    @StateObject private var state = AppState()

    init() {
        Migration.run() // before AppState reads any settings
    }

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
