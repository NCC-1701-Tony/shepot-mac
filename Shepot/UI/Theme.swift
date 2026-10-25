import SwiftUI

/// Shared look of the island, the menu panel, onboarding and the hotkey window.
/// Components use these role tokens, never raw colors.
enum Theme {
    // Accent ramp (one hue).
    /// Icons, borders, checkmarks, the recording dot. Not for fills behind text: white on it is 3.4:1.
    static let accent = Color(red: 0.93, green: 0.36, blue: 0.27)
    /// Fills that carry white text: 4.6:1.
    static let accentSolid = Color(red: 0.80, green: 0.28, blue: 0.20)
    /// Accent-colored text on dark or accent-tinted surfaces: 6:1+.
    static let accentText = Color(red: 1.0, green: 0.52, blue: 0.44)
    static let accentTint = accent.opacity(0.14)

    // Neutrals on the dark panel.
    static let panel = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let panelNS = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    static let surface = Color.black // island, chips, dropdowns
    static let fill = Color.white.opacity(0.04)
    static let fillHover = Color.white.opacity(0.08)
    static let fillSelected = Color.white.opacity(0.10)
    static let track = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55) // 5.5:1 or more on every panel surface

    // Status.
    static let warning = Color.orange
    static let warningTint = Color.orange.opacity(0.12)
    static let success = Color.green
    static let busy = Color.yellow
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.38) // text on dangerTint: 4.8:1
    static let dangerTint = danger.opacity(0.16)
}

// MARK: - Motion

extension Animation {
    /// Respects "Reduce motion": springs become a short fade.
    static func ui(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : base
    }
}

extension AnyTransition {
    /// Movement when allowed, a plain cross-fade under "Reduce motion".
    static func ui(_ base: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : base
    }
}

/// Pressed controls scale to 0.96; disabled ones don't move.
struct PressScaleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Controls

/// Capsule button in island style.
struct PillButton: View {
    enum Kind { case neutral, primary, destructive }

    let title: String
    var systemImage: String?
    var kind = Kind.neutral
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .fixedSize() // never squeeze the label
    }

    private var foreground: Color {
        kind == .destructive ? Theme.danger : Theme.textPrimary
    }

    private var background: Color {
        switch kind {
        case .neutral: Theme.fillSelected
        case .primary: Theme.accentSolid
        case .destructive: Theme.dangerTint
        }
    }
}

/// Native Toggle drawn as an island-style switch.
struct CoralSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.ui(.spring(response: 0.25, dampingFraction: 0.8), reduceMotion: reduceMotion)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Theme.accentSolid : Theme.fillSelected)
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(3).shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// Segmented control: each option is a real button, the selected one is marked for VoiceOver.
/// Switching is instant — it's a high-frequency interaction.
struct Segmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(isOn ? Theme.accentSolid : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.track))
    }
}
