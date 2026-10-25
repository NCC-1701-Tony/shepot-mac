import Carbon.HIToolbox
import SwiftUI

/// Small window that captures a new key combo.
@MainActor
enum HotKeyWindow {
    private static var window: NSWindow?

    static func show(state: AppState) {
        let window = window ?? makeWindow()
        self.window = window
        // Fresh view each time so the key monitor starts again.
        window.contentView = NSHostingView(rootView: HotKeyRecorder { window.close() }.environmentObject(state))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Сочетание для Dictate"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.panelNS
        window.isReleasedWhenClosed = false
        window.level = .floating
        return window
    }
}

private struct HotKeyRecorder: View {
    let close: () -> Void
    @EnvironmentObject private var state: AppState
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 12) {
            Text("Нажмите новое сочетание").font(.headline)
            Text(state.hotKeyCombo.label)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.coral))
            Text("Нужен хотя бы один из ⌃ ⌥ ⇧ ⌘ (или F-клавиша). Esc — отмена.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if let hotKeyError = state.hotKeyError {
                Text(hotKeyError).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        state.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                close()
            } else if let combo = HotKey.Combo(event: event) {
                state.setHotKey(combo)
                if state.hotKeyError == nil { close() } else { state.suspendHotKey() }
            }
            return nil // swallow keys while recording
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        state.resumeHotKey()
    }
}
