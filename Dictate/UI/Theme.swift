import SwiftUI

/// Shared look of the island, the menu panel and the hotkey window.
enum Theme {
    static let coral = Color(red: 0.93, green: 0.36, blue: 0.27)
    static let panel = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let panelNS = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    static let card = Color.white.opacity(0.05)
    static let secondaryText = Color.white.opacity(0.55)
}

/// Capsule button in island style.
struct PillButton: View {
    let title: String
    var systemImage: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(prominent ? Theme.coral : .white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize() // never squeeze the label
    }
}

/// On/off switch in island style.
struct CoralSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.coral : .white.opacity(0.15))
            .frame(width: 38, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).padding(3).shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() }
            }
    }
}

/// Segmented control with a sliding coral thumb.
struct Segmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Text(label(option))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background {
                        if isOn {
                            Capsule().fill(Theme.coral).matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option }
                    }
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}
