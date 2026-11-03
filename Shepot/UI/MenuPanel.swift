import SwiftUI

/// Panel under the menu bar icon, styled like the island.
struct MenuPanel: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLanguages = false
    @State private var tab = Tab.history

    private enum Tab: CaseIterable { case history, models, settings, customize }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            notices
            Segmented(options: Tab.allCases, selection: $tab) { tab in
                switch tab {
                case .history: "История"
                case .models: "Модели"
                case .settings: "Основное"
                case .customize: "Кастомизация"
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
                    case .customize: customization
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
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
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Shepot").font(.system(size: 16, weight: .bold))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // The status line below says the same thing in words.
                    Circle().fill(statusColor).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(state.statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        switch state.phase {
        case .recording: Theme.accent
        case .transcribing: Theme.busy
        case .idle: state.installed.contains(state.selectedModel) ? Theme.success : Theme.textSecondary
        }
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        if !state.isAccessibilityTrusted {
            notice("Включите Shepot в «Универсальном доступе», иначе текст не вставится и правые ⌘/⌥ не сработают.",
                   button: "Открыть настройки") {
                Permissions.promptAccessibility()
                Permissions.openAccessibilitySettings()
            }
        }
        if !state.isMicrophoneAllowed {
            notice("Нет доступа к микрофону. Включите Shepot в разделе «Микрофон».", button: "Открыть настройки") {
                Permissions.openMicrophoneSettings()
            }
        }
        if let error = state.error {
            notice(error, button: "Скрыть") { state.error = nil }
        }
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .font(.system(size: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: button, action: action)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.warningTint))
    }

    // MARK: Settings

    private var settings: some View {
        VStack(spacing: 16) {
            section("Запись") { recordingSettings }
            divider
            section("Текст") { textSettings }
            divider
            section("Общее") { generalSettings }
        }
    }

    private var customization: some View {
        VStack(spacing: 16) {
            section("Островок") { islandSettings }
            divider
            section("Звуки") { soundSettings }
        }
    }

    @ViewBuilder
    private var islandSettings: some View {
        Group {
            row("Положение") {
                Segmented(options: AppState.IslandStyle.allCases, selection: $state.islandStyle) {
                    $0 == .bottom ? "Снизу" : "Из чёлки"
                }
            }
            row("Реакция") {
                Segmented(options: AppState.VisualSource.allCases, selection: $state.visualSource) {
                    $0 == .spectrum ? "Спектр" : "Лента"
                }
            }
            row("Вид") {
                Segmented(options: AppState.VisualStyle.allCases, selection: $state.visualStyle) {
                    switch $0 {
                    case .bars: "Столбики"
                    case .waves: "Волны"
                    case .pixels: "Пиксели"
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var soundSettings: some View {
        Group {
            Toggle(isOn: $state.soundsEnabled) {
                Text("Звуки записи и вставки").font(.system(size: 13))
            }
            .toggleStyle(CoralSwitchStyle())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(SoundSet.allCases, id: \.self) { set in
                    let isOn = set == state.soundSet
                    Button {
                        state.soundSet = set
                        state.previewSounds(set)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.title).font(.system(size: 13, weight: .semibold))
                            Text(set.note).font(.system(size: 11))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .foregroundStyle(isOn ? Theme.textPrimary.opacity(0.85) : Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isOn ? Theme.accentSolid : Theme.track))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .opacity(state.soundsEnabled ? 1 : 0.5)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1)
    }

    @ViewBuilder
    private var recordingSettings: some View {
        Group {
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
                    .accessibilityLabel("Изменить сочетание, сейчас \(state.hotKeyCombo.label)")
                }
            }
            if let hotKeyError = state.hotKeyError {
                Text(hotKeyError).font(.system(size: 11)).foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            row("Режим") {
                Segmented(options: AppState.TriggerMode.allCases, selection: $state.triggerMode) {
                    $0 == .hold ? "Удерживать" : "Нажать-нажать"
                }
            }
        }
    }

    @ViewBuilder
    private var textSettings: some View {
        Group {
            row("Язык") {
                PillButton(title: state.languageName, systemImage: showLanguages ? "chevron.up" : "chevron.down") {
                    withAnimation(.ui(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) { showLanguages.toggle() }
                }
                .accessibilityLabel("Язык: \(state.languageName)")
            }
            if showLanguages { languageGrid }
            Toggle(isOn: $state.skipFinalPeriod) {
                Text("Без точки в конце").font(.system(size: 13))
            }
            .toggleStyle(CoralSwitchStyle())
        }
    }

    @ViewBuilder
    private var generalSettings: some View {
        Group {
            Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })) {
                Text("Запускать при входе").font(.system(size: 13))
            }
            .toggleStyle(CoralSwitchStyle())
        }
    }

    private var languageGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(AppState.languages, id: \.code) { lang in
                let isOn = lang.code == state.language
                Button {
                    state.language = lang.code
                    withAnimation(.ui(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) { showLanguages = false }
                } label: {
                    Text(lang.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Capsule().fill(isOn ? Theme.accentSolid : Theme.track))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .transition(.ui(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
    }

    // MARK: History & footer

    @ViewBuilder
    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let undo = state.historyUndo {
                HStack {
                    Text(undo.message).font(.system(size: 12))
                    Spacer()
                    PillButton(title: "Вернуть", systemImage: "arrow.uturn.backward") { state.undoHistoryChange() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.fillSelected))
            }
            if state.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    Text("Пока пусто")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Здесь появятся 10 последних диктовок. Чтобы начать, \(state.triggerMode == .hold ? "удерживайте" : "нажмите") \(state.title(for: state.activation)) и говорите.")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 6) {
                    ForEach(state.history) { HistoryRow(entry: $0) }
                }
                HStack(alignment: .top) {
                    Text("Нажмите на запись, чтобы скопировать. Вставить сразу в текст — кнопкой истории на островке.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    PillButton(title: "Очистить историю") { state.clearHistory() }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("Работает на этом Mac, без интернета", systemImage: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            PillButton(title: "Выйти из Shepot") { NSApp.terminate(nil) }
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
            // Only a downloaded model is selectable; a disabled button would dim the text.
            if isInstalled {
                Button { state.selectedModel = model.id } label: { summary }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(model.title), \(model.note), \(model.approxSize)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                summary
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(model.title), \(model.note), \(model.approxSize), не скачана")
            }
            trailing
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Theme.fillSelected : isHovering ? Theme.fillHover : Theme.fill)
        )
        .overlay(
            // Selection gets a border and the checkmark badge, not color alone.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 1.5 : 1)
        )
        .onHover { isHovering = $0 }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            badge
            info
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize()
                if model.recommended {
                    Text("Рекомендуем")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accentTint))
                        .fixedSize()
                }
            }
            Text("\(model.note) · \(model.approxSize)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
    }

    private var badge: some View {
        ZStack {
            Circle().fill(isSelected ? Theme.accentSolid : Theme.track)
            Image(systemName: isSelected ? "checkmark" : isInstalled ? "waveform" : "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailing: some View {
        if let progress {
            ProgressRing(progress: progress)
        } else if isInstalled {
            if confirmDelete {
                PillButton(title: "Удалить модель", systemImage: "trash", kind: .destructive) {
                    confirmDelete = false
                    Task { await state.delete(model) }
                }
            } else {
                Button {
                    confirmDelete = true
                    // Cancel the confirmation if the user doesn't click again.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmDelete = false }
                } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .opacity(isHovering ? 1 : 0) // visible on hover, still reachable by keyboard and VoiceOver
                .help("Удалить с диска")
                .accessibilityLabel("Удалить \(model.title) с диска")
            }
        } else {
            // One filled action per view: only the recommended model.
            PillButton(title: "Скачать", kind: model.recommended ? .primary : .neutral) {
                Task { await state.download(model) }
            }
            .disabled(state.downloading != nil)
            .opacity(state.downloading != nil ? 0.4 : 1)
            .accessibilityLabel("Скачать \(model.title), \(model.approxSize)")
        }
    }
}

/// One past dictation: click copies, hover shows time and delete.
private struct HistoryRow: View {
    let entry: DictationEntry
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: copy) {
                HStack(alignment: .top, spacing: 10) {
                    Text(entry.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if copied {
                        Label("Скопировано", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                    } else {
                        Text(entry.date, style: .time)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(entry.text) // full text when two lines aren't enough
            .accessibilityLabel(entry.text)
            .accessibilityHint("Скопировать")

            Button { state.remove(entry) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .opacity(isHovering ? 1 : 0)
            .help("Удалить из истории")
            .accessibilityLabel("Удалить запись из истории")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? Theme.fillHover : Theme.fill)
        )
        .onHover { isHovering = $0 }
    }

    private func copy() {
        state.copy(entry.text)
        withAnimation(.ui(.easeOut(duration: 0.15), reduceMotion: reduceMotion)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.ui(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) { copied = false }
        }
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            Text("\(Int(progress * 100))")
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
        }
        .frame(width: 30, height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Скачивается")
        .accessibilityValue("\(Int(progress * 100)) процентов")
    }
}
