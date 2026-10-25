import SwiftUI

enum MenuEntry {
    case header(String)
    case item(String, checked: Bool = false, enabled: Bool = true, action: () -> Void)
    case separator
}

/// Chips next to the island plus their dropdown, all drawn by the app (no system menus).
struct IslandControls: View {
    @ObservedObject var model: OverlayModel
    let opensUp: Bool // bottom island: dropdown above the chips; notch island: below
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if opensUp { dropdown }
            chips
            if !opensUp { dropdown }
        }
        .animation(.ui(.spring(response: 0.3, dampingFraction: 0.85), reduceMotion: reduceMotion), value: model.openMenu)
    }

    // MARK: Chips

    private var chips: some View {
        HStack(spacing: 8) {
            chip(.model, title: state.selectedModelInfo.title)
            chip(.language, title: state.languageName)
            if !state.history.isEmpty { chip(.history, title: nil) }
        }
    }

    private func chip(_ menu: OverlayModel.Menu, title: String?) -> some View {
        let isOpen = model.openMenu == menu
        return Button { model.openMenu = isOpen ? nil : menu } label: {
            HStack(spacing: 6) {
                if let title {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Image(systemName: isOpen == opensUp ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.7)
                } else {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(isOpen ? Theme.accent : Theme.stroke, lineWidth: isOpen ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityLabel(accessibilityTitle(menu, title: title))
        .accessibilityValue(isOpen ? "открыто" : "")
    }

    private func accessibilityTitle(_ menu: OverlayModel.Menu, title: String?) -> String {
        switch menu {
        case .model: "Модель: \(title ?? "")"
        case .language: "Язык: \(title ?? "")"
        case .history: "История диктовок"
        }
    }

    // MARK: Dropdown

    @ViewBuilder
    private var dropdown: some View {
        if let menu = model.openMenu {
            Dropdown(entries: entries(for: menu)) { model.openMenu = nil }
                .transition(.ui(.opacity.combined(with: .scale(scale: 0.96, anchor: opensUp ? .bottom : .top)),
                                reduceMotion: reduceMotion))
        }
    }

    private func entries(for menu: OverlayModel.Menu) -> [MenuEntry] {
        switch menu {
        case .model: modelEntries()
        case .language: languageEntries()
        case .history: historyEntries()
        }
    }

    private func modelEntries() -> [MenuEntry] {
        var entries: [MenuEntry] = [.header("Модель")]
        for model in ModelCatalog.all {
            if let d = state.downloading, d.id == model.id {
                entries.append(.item("\(model.title) — скачивается \(Int(d.progress * 100))%", enabled: false) {})
            } else if state.installed.contains(model.id) {
                entries.append(.item(model.title, checked: model.id == state.selectedModel) { state.selectedModel = model.id })
            } else {
                entries.append(.item("\(model.title) — скачать \(model.approxSize)", enabled: state.downloading == nil) {
                    Task { await state.download(model) }
                })
            }
        }
        return entries
    }

    private func languageEntries() -> [MenuEntry] {
        [.header("Язык")] + AppState.languages.map { lang in
            .item(lang.name, checked: state.language == lang.code) { state.language = lang.code }
        }
    }

    private func historyEntries() -> [MenuEntry] {
        [.header("История — нажмите, чтобы вставить")] + state.history.map { entry in
            .item(entry.text.replacingOccurrences(of: "\n", with: " ")) { state.paste(entry) }
        }
    }
}

/// Black card with rows, in the island's style.
private struct Dropdown: View {
    let entries: [MenuEntry]
    let close: () -> Void

    private static let maxHeight: CGFloat = 330

    var body: some View {
        Group {
            if entries.count > 10 {
                ScrollView { rows }.frame(height: Self.maxHeight)
            } else {
                rows
            }
        }
        .frame(width: 320)
        // 16 = row radius 9 + padding 6 + border 1, so the corners stay concentric.
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .header(let title):
                    Text(title)
                        .textCase(.uppercase)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.55)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 3)
                case .separator:
                    Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 4)
                case let .item(title, checked, enabled, action):
                    DropdownRow(title: title, checked: checked, enabled: enabled) {
                        close()
                        action()
                    }
                }
            }
        }
        .padding(6)
    }
}

private struct DropdownRow: View {
    let title: String
    let checked: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: checked ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering && enabled ? Theme.fillSelected : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .help(title) // full text when the row is truncated
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
