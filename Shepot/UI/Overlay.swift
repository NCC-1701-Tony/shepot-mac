import AppKit
import Combine
import SwiftUI

/// Recent input levels for the island bars.
@MainActor
final class LevelMeter: ObservableObject {
    static let barCount = 11
    @Published private(set) var levels = Array(repeating: Float(0), count: barCount)

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func reset() {
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    enum Mode { case recording, transcribing, failed, idle }
    enum Menu { case model, language, history }
    @Published var mode = Mode.recording
    @Published var openMenu: Menu?
    @Published var style = AppState.IslandStyle.bottom
    @Published var expanded = false
    @Published var notch = CGSize(width: 190, height: 32) // collapsed size in notch style
    @Published var isHovering = false
    @Published var alertText = ""
}

/// Borderless panel that may sit over the menu bar (notch style).
private final class OverlayPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The island. Never activates the app, so paste still goes to the user's window.
/// The panel grows only while a dropdown is open, so it doesn't cover the screen otherwise.
@MainActor
final class OverlayController {
    static let width: CGFloat = 560
    static let closedHeight: CGFloat = 180
    static let openHeight: CGFloat = 560
    private static let behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    private var panel: OverlayPanel
    private let model = OverlayModel()
    private let state: AppState
    private let meter: LevelMeter
    private var wantsVisible = false
    private var alertID = 0 // bumps per alert so an old timer can't close a newer one
    private var alertActive = false
    private var observers: [AnyCancellable] = []

    init(state: AppState, meter: LevelMeter) {
        self.state = state
        self.meter = meter
        panel = Self.makePanel(state: state, meter: meter, model: model)
        // Keep the island while the mouse is over it; collapse once it leaves.
        observers.append(model.$isHovering.dropFirst().sink { [weak self] hovering in
            if !hovering { DispatchQueue.main.async { self?.collapseIfIdle() } }
        })
        // Fires before the change is rendered, so there's room for the dropdown in time.
        observers.append(model.$openMenu.dropFirst().sink { [weak self] menu in
            self?.resize(open: menu != nil)
        })
        observers.append(NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.spaceOrScreenChanged() })
        observers.append(NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.spaceOrScreenChanged() })
    }

    /// A window registered on one Space sometimes never appears after a Space switch.
    /// A fresh window per appearance is cheap and always registers on the current Space.
    private static func makePanel(state: AppState, meter: LevelMeter, model: OverlayModel) -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: closedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver // above full-screen apps and the menu bar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // drawn in SwiftUI instead
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = behavior
        panel.contentView = NSHostingView(rootView: OverlayView(meter: meter, model: model).environmentObject(state))
        return panel
    }

    private func rebuildPanel() {
        panel.orderOut(nil)
        panel = Self.makePanel(state: state, meter: meter, model: model)
    }

    /// Short error on the island itself, so a failed dictation isn't noticed only in the menu.
    func showAlert(_ text: String, style: AppState.IslandStyle) {
        model.alertText = text
        show(.failed, style: style)
        alertActive = true
        alertID += 1
        let id = alertID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard let self, self.alertID == id else { return }
            self.alertActive = false
            if self.model.mode == .failed { self.hide() }
        }
    }

    func show(_ mode: OverlayModel.Mode, style: AppState.IslandStyle) {
        if mode != .failed { alertActive = false }
        model.mode = mode
        wantsVisible = true
        // Re-place and re-raise whenever the island isn't up on this Space yet:
        // a panel left over from another Space or screen would otherwise stay hidden.
        if !panel.isVisible || !panel.isOnActiveSpace || !model.expanded {
            if !model.isHovering { rebuildPanel() }
            model.style = style
            place()
        }
        bringToFront()
        verifyVisible(attempts: 3)
        guard !model.expanded else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsVisible else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { self.model.expanded = true }
        }
    }

    func hide() {
        if alertActive { return } // the alert closes itself
        wantsVisible = false
        model.mode = .idle
        if !model.expanded, !model.isHovering {
            panel.orderOut(nil) // never expanded, nothing to animate
            return
        }
        collapseIfIdle()
    }

    /// Full-screen apps live on their own Space; re-assert the level and behavior before raising.
    private func bringToFront() {
        panel.level = .screenSaver
        panel.collectionBehavior = Self.behavior
        panel.orderFrontRegardless()
    }

    /// Safety net: if the window server didn't actually show the island, rebuild it and retry.
    private func verifyVisible(attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.wantsVisible, attempts > 0 else { return }
            if !self.panel.occlusionState.contains(.visible) {
                self.rebuildPanel()
                self.place()
                self.bringToFront()
                self.verifyVisible(attempts: attempts - 1)
            }
        }
    }

    /// Follows the user to a new Space or a changed display while the island is needed.
    private func spaceOrScreenChanged() {
        guard wantsVisible else { return }
        rebuildPanel()
        place()
        bringToFront()
        verifyVisible(attempts: 3)
    }

    func setStyle(_ style: AppState.IslandStyle) {
        guard model.style != style else { return }
        model.style = style
        if panel.isVisible { place() }
    }

    private func collapseIfIdle() {
        guard !wantsVisible, !model.isHovering, model.expanded else { return }
        model.openMenu = nil
        withAnimation(.easeIn(duration: 0.22)) { model.expanded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.wantsVisible, !self.model.expanded else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Screen under the mouse: bottom center above the Dock, or flush with the top edge.
    private func place() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let height = model.openMenu == nil ? Self.closedHeight : Self.openHeight
        switch model.style {
        case .bottom:
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - Self.width / 2, y: frame.minY + 12, width: Self.width, height: height), display: false)
        case .notch:
            let frame = screen.frame
            model.notch = Self.notchSize(of: screen)
            panel.setFrame(NSRect(x: frame.midX - Self.width / 2, y: frame.maxY - height, width: Self.width, height: height), display: false)
        }
    }

    /// Grows or shrinks the panel, keeping the island's edge (bottom or top) in place.
    private func resize(open: Bool) {
        var frame = panel.frame
        let height = open ? Self.openHeight : Self.closedHeight
        if model.style == .notch { frame.origin.y = frame.maxY - height }
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    /// Real notch size, or a menu-bar-high stub on screens without one.
    private static func notchSize(of screen: NSScreen) -> CGSize {
        let height = screen.safeAreaInsets.top
        if height > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: screen.frame.width - left.width - right.width, height: height)
        }
        return CGSize(width: 190, height: NSStatusBar.system.thickness)
    }
}

// MARK: - Views

struct OverlayView: View {
    @ObservedObject var meter: LevelMeter
    @ObservedObject var model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let islandWidth: CGFloat = 380
    static let islandHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 10) {
            if model.style == .bottom {
                IslandControls(model: model, opensUp: true).opacity(model.expanded ? 1 : 0)
                bottomIsland
            } else {
                notchIsland
                IslandControls(model: model, opensUp: false).opacity(model.expanded ? 1 : 0)
            }
        }
        .onHover { model.isHovering = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.style == .bottom ? .bottom : .top)
    }

    // MARK: Island shapes

    private var bottomIsland: some View {
        content
            .frame(width: Self.islandWidth, height: Self.islandHeight)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            // Under "Reduce motion" the island only fades.
            .scaleEffect(model.expanded || reduceMotion ? 1 : 0.92)
            .offset(y: model.expanded || reduceMotion ? 0 : 14)
            .opacity(model.expanded ? 1 : 0)
            .padding(.bottom, 12)
    }

    private var notchIsland: some View {
        // Under "Reduce motion" it doesn't grow out of the notch, it fades in at full size.
        let open = model.expanded || reduceMotion
        let width = open ? Self.islandWidth : model.notch.width
        let height = model.notch.height + (open ? Self.islandHeight : 0)
        return VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height) // the notch itself
            content.frame(height: Self.islandHeight).opacity(model.expanded ? 1 : 0)
        }
        .frame(width: width, height: height, alignment: .top)
        .clipped()
        .background(NotchShape(radius: 22).fill(Theme.surface))
        .shadow(color: .black.opacity(model.expanded ? 0.35 : 0), radius: 12, y: 4)
        .opacity(reduceMotion && !model.expanded ? 0 : 1)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.mode == .failed { alertContent } else { waveContent }
    }

    private var alertContent: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.dangerTint)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.danger)
                )
            Text(model.alertText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }

    private var waveContent: some View {
        ZStack {
            // Wave stays exactly centered; icon and title sit at the edges.
            bars.frame(width: 110, height: 28)
            HStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    )
                Spacer()
                Text(model.mode == .transcribing ? "Распознаю…" : "Shepot")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var bars: some View {
        switch model.mode {
        case .recording:
            HStack(spacing: 5) {
                ForEach(meter.levels.indices, id: \.self) { i in
                    Capsule().fill(.white).frame(width: 5, height: barHeight(meter.levels[i], index: i))
                }
            }
            .animation(.easeOut(duration: 0.12), value: meter.levels)
        case .transcribing where reduceMotion:
            // No moving wave; the "Распознаю…" label carries the state.
            HStack(spacing: 5) {
                ForEach(0..<LevelMeter.barCount, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.6)).frame(width: 5, height: 10)
                }
            }
        case .transcribing:
            // Calm wave while the model works.
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<LevelMeter.barCount, id: \.self) { i in
                        let phase = (sin(t * 6 - Double(i) * 0.6) + 1) / 2
                        Capsule().fill(.white.opacity(0.6)).frame(width: 5, height: 6 + 8 * phase)
                    }
                }
            }
        case .failed:
            EmptyView()
        case .idle:
            HStack(spacing: 5) {
                ForEach(0..<LevelMeter.barCount, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.35)).frame(width: 5, height: 6)
                }
            }
        }
    }

    /// Middle bars react stronger, like a classic voice meter.
    private func barHeight(_ level: Float, index: Int) -> CGFloat {
        let center = Double(LevelMeter.barCount - 1) / 2
        let weight = 1 - abs(Double(index) - center) / (center + 1) * 0.6
        return 6 + 22 * CGFloat(Double(level) * weight)
    }
}

/// Flat top (merges with the screen edge), rounded bottom corners.
private struct NotchShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

