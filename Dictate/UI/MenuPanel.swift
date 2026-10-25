import SwiftUI

/// Panel under the menu bar icon, styled like the island.
struct MenuPanel: View {
    @EnvironmentObject private var state: AppState
    @State private var showLanguages = false
    @State private var tab = Tab.history

    private enum Tab: CaseIterable { case history, models, settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            notices
            Segmented(options: Tab.allCases, selection: $tab) { tab in
                switch tab {
                case .history: "История"
                case .models: "Модели"
                case .settings: "Настройки"
                }
            }
            .frame(maxWidth: .infinity)
            // The menu bar window doesn't resize after it first appears,
            // so the panel keeps one size and tabs scroll inside it.
            ScrollView {
                Group {
                    switch tab {
                    case .history: history
                    case .models: models
                    case .settings: settings
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            footer
        }
        .padding(18)
        .frame(width: 400, height: 600)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .onAppear {
            state.refreshPermissions()
            // Open where the user most likely needs to be.
            if !state.installed.contains(state.selectedModel) { tab = .models }
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ModelCatalog.all) { ModelCard(model: $0) }
            Text(state.modelStatus)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Dictate").font(.system(size: 16, weight: .bold))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(state.statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        switch state.phase {
        case .recording: Theme.coral
        case .transcribing: .yellow
        case .idle: state.installed.contains(state.selectedModel) ? .green : .gray
        }
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        if !state.isAccessibilityTrusted {
            notice("Включите Dictate в «Универсальном доступе», иначе текст не вставится и правые ⌘/⌥ не сработают.",
                   button: "Открыть") {
                Permissions.promptAccessibility()
                Permissions.openAccessibilitySettings()
            }
        }
        if !state.isMicrophoneAllowed {
            notice("Нет доступа к микрофону.", button: "Открыть") { Permissions.openMicrophoneSettings() }
        }
        if let error = state.error {
            notice(error, button: "Скрыть") { state.error = nil }
        }
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PillButton(title: button, action: action)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    // MARK: Settings

    private var settings: some View {
        VStack(spacing: 12) {
            row("Клавиша") {
                Segmented(options: AppState.Activation.allCases, selection: $state.activation) { activation in
                    activation == .combo ? "Сочетание" : state.title(for: activation)
                }
            }
            if state.activation == .combo {
                row("Сочетание") {
                    PillButton(title: state.hotKeyCombo.label, systemImage: "keyboard") {
                        HotKeyWindow.show(state: state)
                    }
                }
            }
            if let hotKeyError = state.hotKeyError {
                Text(hotKeyError).font(.system(size: 11)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            row("Режим") {
                Segmented(options: AppState.TriggerMode.allCases, selection: $state.triggerMode) {
                    $0 == .hold ? "Удерживать" : "Нажать-нажать"
                }
            }
            row("Островок") {
                Segmented(options: AppState.IslandStyle.allCases, selection: $state.islandStyle) {
                    $0 == .bottom ? "Снизу" : "Из чёлки"
                }
            }
            row("Язык") {
                PillButton(title: state.languageName, systemImage: showLanguages ? "chevron.up" : "chevron.down") {
                    withAnimation(.easeOut(duration: 0.2)) { showLanguages.toggle() }
                }
            }
            if showLanguages { languageGrid }
            row("Запуск при входе") {
                CoralSwitch(isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
            }
        }
    }

    private var languageGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(AppState.languages, id: \.code) { lang in
                let isOn = lang.code == state.language
                Text(lang.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Capsule().fill(isOn ? Theme.coral : .white.opacity(0.08)))
                    .contentShape(Capsule())
                    .onTapGesture {
                        state.language = lang.code
                        withAnimation(.easeOut(duration: 0.2)) { showLanguages = false }
                    }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: History & footer

    @ViewBuilder
    private var history: some View {
        if state.history.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.bubble").font(.system(size: 22)).foregroundStyle(Theme.secondaryText)
                Text("Здесь появятся 10 последних диктовок")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 6) {
                    ForEach(state.history) { HistoryRow(entry: $0) }
                }
                HStack(alignment: .top) {
                    Text("Нажмите, чтобы скопировать. Вставить сразу в текст можно кнопкой истории на островке.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Очистить") { state.clearHistory() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("Работает на этом Mac, без интернета", systemImage: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            PillButton(title: "Выйти") { NSApp.terminate(nil) }
        }
    }

    // MARK: Helpers

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            content()
        }
    }
}

/// One model as a card: select, download with a progress ring, or delete.
struct ModelCard: View {
    let model: WhisperModel
    @EnvironmentObject private var state: AppState
    @State private var isHovering = false
    @State private var confirmDelete = false

    private var isInstalled: Bool { state.installed.contains(model.id) }
    private var isSelected: Bool { state.selectedModel == model.id && isInstalled }
    private var progress: Double? {
        guard let d = state.downloading, d.id == model.id else { return nil }
        return d.progress
    }

    var body: some View {
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize()
                    if model.recommended {
                        Text("Рекомендуем")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.coral)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.coral.opacity(0.18)))
                            .fixedSize()
                    }
                }
                Text("\(model.note) · \(model.approxSize)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.09 : isHovering ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Theme.coral : .white.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { if isInstalled { state.selectedModel = model.id } }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var badge: some View {
        ZStack {
            Circle().fill(isSelected ? Theme.coral : .white.opacity(0.08))
            Image(systemName: isSelected ? "checkmark" : isInstalled ? "waveform" : "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? .white : Theme.secondaryText)
        }
        .frame(width: 30, height: 30)
    }

    @ViewBuilder
    private var trailing: some View {
        if let progress {
            ProgressRing(progress: progress)
        } else if isInstalled {
            if confirmDelete {
                PillButton(title: "Удалить?") {
                    confirmDelete = false
                    Task { await state.delete(model) }
                }
                .foregroundStyle(.red)
            } else if isHovering {
                Button {
                    confirmDelete = true
                    // Cancel the confirmation if the user doesn't click again.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmDelete = false }
                } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .help("Удалить с диска")
            }
        } else {
            PillButton(title: "Скачать", prominent: true) {
                Task { await state.download(model) }
            }
            .disabled(state.downloading != nil)
            .opacity(state.downloading != nil ? 0.4 : 1)
        }
    }
}

/// One past dictation: click copies, hover shows time and delete.
private struct HistoryRow: View {
    let entry: DictationEntry
    @EnvironmentObject private var state: AppState
    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.text)
                .font(.system(size: 12))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                if copied {
                    Label("Скопировано", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                } else {
                    Text(entry.date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                if isHovering && !copied {
                    Button { state.remove(entry) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .help("Удалить из истории")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.08 : 0.04))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            state.copy(entry.text)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.2)) { copied = false }
            }
        }
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.coral, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            Text("\(Int(progress * 100))")
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
        }
        .frame(width: 30, height: 30)
    }
}
