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

    var body: some View {
        VStack(spacing: 8) {
            if opensUp { dropdown }
            chips
            if !opensUp { dropdown }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.openMenu)
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
        return HStack(spacing: 6) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold))
                Image(systemName: opensUp ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.7)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            } else {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(.black))
        .overlay(Capsule().strokeBorder(isOpen ? Theme.coral : .white.opacity(0.1), lineWidth: isOpen ? 1.5 : 1))
        .contentShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .onTapGesture { model.openMenu = isOpen ? nil : menu }
    }

    // MARK: Dropdown

    @ViewBuilder
    private var dropdown: some View {
        if let menu = model.openMenu {
            Dropdown(entries: entries(for: menu)) { model.openMenu = nil }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: opensUp ? .bottom : .top)))
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
                ScrollView { rows }.scrollIndicators(.never).frame(height: Self.maxHeight)
            } else {
                rows
            }
        }
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .header(let title):
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 3)
                case .separator:
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.vertical, 4)
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
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: checked ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.coral)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovering && enabled ? .white.opacity(0.1) : .clear)
        )
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { if enabled { action() } }
    }
}
