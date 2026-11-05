import AppKit
import ServiceManagement

/// Central state: trigger → record → transcribe → paste, plus user settings.
@MainActor
final class AppState: ObservableObject {
    enum Phase { case idle, recording, transcribing }

    enum TriggerMode: String, CaseIterable {
        case hold   // record while the key is held
        case toggle // press to start, press again to stop
    }

    enum Activation: String, CaseIterable {
        case combo, rightCommand, rightOption
    }

    enum IslandStyle: String, CaseIterable {
        case bottom // floating above the Dock
        case notch  // drops down from the notch / top edge
    }

    enum VisualSource: String, CaseIterable {
        case spectrum // live voice frequencies
        case ribbon   // loudness over time, scrolling
    }

    enum VisualStyle: String, CaseIterable {
        case bars, waves, pixels
    }

    static let languages: [(code: String, name: String)] = [
        ("ru", "Русский"), ("en", "English"), ("auto", "Автоопределение"),
    ]

    @Published private(set) var phase: Phase = .idle {
        didSet { updateOverlay() }
    }
    @Published private(set) var modelStatus = ""
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var downloading: (id: String, progress: Double)?
    @Published private(set) var history = History.load() {
        didSet { History.save(history) }
    }
    @Published private(set) var hotKeyError: String?
    @Published private(set) var isAccessibilityTrusted = Permissions.isAccessibilityTrusted
    @Published private(set) var isMicrophoneAllowed = Permissions.isMicrophoneAllowed
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var error: String?

    // Persisted settings.
    @Published var selectedModel = UserDefaults.standard.string(forKey: Keys.model) ?? ModelCatalog.defaultModel.id {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: Keys.model)
            prepareModel()
        }
    }
    @Published var language = UserDefaults.standard.string(forKey: Keys.language)
        .flatMap { code in AppState.languages.contains { $0.code == code } ? code : nil } ?? "ru" {
        didSet { UserDefaults.standard.set(language, forKey: Keys.language) }
    }
    @Published var triggerMode = TriggerMode(rawValue: UserDefaults.standard.string(forKey: Keys.mode) ?? "") ?? .hold {
        didSet { UserDefaults.standard.set(triggerMode.rawValue, forKey: Keys.mode) }
    }
    @Published var activation = Activation(rawValue: UserDefaults.standard.string(forKey: Keys.activation) ?? "") ?? .combo {
        didSet {
            UserDefaults.standard.set(activation.rawValue, forKey: Keys.activation)
            applyActivation()
        }
    }
    @Published var islandStyle = IslandStyle(rawValue: UserDefaults.standard.string(forKey: Keys.island) ?? "") ?? .bottom {
        didSet {
            UserDefaults.standard.set(islandStyle.rawValue, forKey: Keys.island)
            overlay.setStyle(islandStyle)
        }
    }
    @Published var soundsEnabled = UserDefaults.standard.object(forKey: Keys.sounds) as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: Keys.sounds) }
    }
    @Published var soundSet = SoundSet(rawValue: AppState.storedSoundSet()) ?? .standard {
        didSet { UserDefaults.standard.set(soundSet.rawValue, forKey: Keys.soundSet) }
    }
    @Published var visualSource = VisualSource(rawValue: UserDefaults.standard.string(forKey: Keys.visualSource) ?? "") ?? .spectrum {
        didSet { UserDefaults.standard.set(visualSource.rawValue, forKey: Keys.visualSource) }
    }
    @Published var visualStyle = VisualStyle(rawValue: UserDefaults.standard.string(forKey: Keys.visualStyle) ?? "") ?? .bars {
        didSet { UserDefaults.standard.set(visualStyle.rawValue, forKey: Keys.visualStyle) }
    }
    @Published var skipFinalPeriod = UserDefaults.standard.bool(forKey: Keys.skipPeriod) {
        didSet { UserDefaults.standard.set(skipFinalPeriod, forKey: Keys.skipPeriod) }
    }
    @Published private(set) var hotKeyCombo = AppState.loadCombo()

    /// "air" was renamed to "soft"; keep the user's choice.
    private static func storedSoundSet() -> String {
        let stored = UserDefaults.standard.string(forKey: Keys.soundSet) ?? ""
        switch stored {
        case "air": return "soft"
        case "pixel": return "nature"
        default: return stored
        }
    }

    private enum Keys {
        static let model = "model", language = "language", mode = "triggerMode"
        static let hotKey = "hotKey", activation = "activation", island = "islandStyle"
        static let sounds = "sounds", skipPeriod = "skipFinalPeriod"
        static let soundSet = "soundSet", visualSource = "visualSource", visualStyle = "visualStyle"
    }

    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let hotKey = HotKey()
    private let modifierTrigger = ModifierTrigger()
    let updater = Updater()
    private let meter = LevelMeter()
    private lazy var overlay = OverlayController(state: self, meter: meter)
    private var permissionTimer: Timer?

    // Current session flags.
    private var isStarting = false
    private var stopRequested = false   // trigger released before recording actually started
    private var cancelRequested = false // trigger turned out to be part of a shortcut

    init() {
        refreshInstalled()
        prepareModel()
        setupTriggers()
        recorder.onFrame = { [weak meter] bands, level in
            Task { @MainActor in meter?.push(bands, level: level) }
        }
        if !Onboarding.isDone {
            // First launch: the onboarding walks through permissions and the model.
            DispatchQueue.main.async { [weak self] in
                if let self { Onboarding.show(state: self) }
            }
        } else if !isAccessibilityTrusted {
            Permissions.promptAccessibility()
        }
        // Menu bar apps get no activation events, so poll permissions cheaply.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    // MARK: - Display helpers

    var menuBarSymbol: String {
        if downloading != nil { return "arrow.down.circle" }
        switch phase {
        case .idle: return "waveform"
        case .recording: return "mic.fill"
        case .transcribing: return "ellipsis.circle"
        }
    }

    var selectedModelInfo: WhisperModel {
        ModelCatalog.all.first { $0.id == selectedModel } ?? ModelCatalog.defaultModel
    }

    var languageName: String {
        Self.languages.first { $0.code == language }?.name ?? language
    }

    func title(for activation: Activation) -> String {
        switch activation {
        case .combo: hotKeyCombo.label
        case .rightCommand: "Правый ⌘"
        case .rightOption: "Правый ⌥"
        }
    }

    var statusLine: String {
        switch phase {
        case .idle:
            // Say "not ready" in words, not only with the gray dot.
            guard installed.contains(selectedModel) else { return "Скачайте модель,\nчтобы начать" }
            let key = title(for: activation)
            // Two balanced lines in the panel header.
            return triggerMode == .hold ? "Удерживайте \(key)\nи говорите" : "Нажмите \(key),\nчтобы начать и закончить"
        case .recording: return "Идёт запись…"
        case .transcribing: return "Распознаю…"
        }
    }

    // MARK: - State refresh

    func refreshInstalled() {
        installed = Set(ModelCatalog.all.map(\.id).filter(ModelStore.isInstalled))
    }

    func refreshPermissions() {
        let trusted = Permissions.isAccessibilityTrusted
        if trusted != isAccessibilityTrusted {
            isAccessibilityTrusted = trusted
            if trusted { applyActivation() } // global monitors need a restart after the grant
        }
        isMicrophoneAllowed = Permissions.isMicrophoneAllowed
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Models

    /// Warms up the selected model so it's ready when recording stops.
    func prepareModel() {
        let id = selectedModel
        guard installed.contains(id) else {
            modelStatus = "Модель не скачана"
            return
        }
        modelStatus = "Подготовка модели… Первый раз может занять несколько минут."
        Task {
            do {
                try await transcriber.load(id)
                if selectedModel == id { modelStatus = "Модель готова" }
            } catch {
                if selectedModel == id { modelStatus = "Не удалось загрузить модель (\(Self.brief(error))). Удалите её и скачайте заново." }
            }
        }
    }

    func download(_ model: WhisperModel) async {
        guard downloading == nil else { return }
        downloading = (model.id, 0)
        defer { downloading = nil }
        do {
            try await ModelStore.download(model) { [weak self] fraction in
                Task { @MainActor in self?.downloading = (model.id, fraction) }
            }
            refreshInstalled()
            selectedModel = model.id // a freshly downloaded model is what the user wants
        } catch {
            self.error = "Не удалось скачать \(model.title). Проверьте подключение к интернету и нажмите «Скачать» ещё раз."
        }
    }

    func delete(_ model: WhisperModel) async {
        guard phase == .idle else { return }
        await transcriber.unload(model.id)
        do {
            try ModelStore.delete(model.id)
        } catch {
            self.error = "Не удалось удалить \(model.title). Выйдите из Shepot и удалите папку ~/Library/Application Support/Shepot/Models вручную."
        }
        refreshInstalled()
        if model.id == selectedModel { prepareModel() }
    }

    // MARK: - Settings

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = "Не удалось изменить автозапуск. Убедитесь, что Shepot лежит в «Программах», и попробуйте снова."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - History

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Pastes an older dictation into the frontmost app (used from the island, which doesn't take focus).
    func paste(_ entry: DictationEntry) {
        // Let the popup menu close and focus settle back on the user's window first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.deliver(entry.text) }
    }

    /// Last removal, so it can be undone instead of asking for confirmation.
    @Published private(set) var historyUndo: (message: String, entries: [DictationEntry])?

    func remove(_ entry: DictationEntry) {
        historyUndo = ("Запись удалена", history)
        history.removeAll { $0.id == entry.id }
    }

    func clearHistory() {
        historyUndo = ("История очищена", history)
        history = []
    }

    func undoHistoryChange() {
        if let historyUndo { history = historyUndo.entries }
        historyUndo = nil
    }

    private func addToHistory(_ text: String) {
        historyUndo = nil
        history.insert(DictationEntry(text: text, date: Date()), at: 0)
        if history.count > History.limit { history.removeLast(history.count - History.limit) }
    }

    /// While the user records a new combo, the old one must not fire.
    func suspendHotKey() {
        hotKey.unregister()
    }

    func resumeHotKey() {
        applyActivation()
    }

    func setHotKey(_ combo: HotKey.Combo) {
        modifierTrigger.stop()
        if hotKey.register(combo) {
            hotKeyCombo = combo
            if let data = try? JSONEncoder().encode(combo) {
                UserDefaults.standard.set(data, forKey: Keys.hotKey)
            }
            hotKeyError = nil
            if activation == .combo { applyActivation() } else { activation = .combo }
        } else {
            hotKeyError = "Сочетание \(combo.label) занято другим приложением. Выберите другое."
            applyActivation()
        }
    }

    private static func loadCombo() -> HotKey.Combo {
        guard let data = UserDefaults.standard.data(forKey: Keys.hotKey),
              let combo = try? JSONDecoder().decode(HotKey.Combo.self, from: data)
        else { return HotKey.defaultCombo }
        return combo
    }

    // MARK: - Recording

    private func startRecording() async {
        guard phase == .idle, !isStarting else { return }
        isStarting = true
        stopRequested = false
        cancelRequested = false
        defer { isStarting = false }

        error = nil
        guard installed.contains(selectedModel) else {
            error = "Модель не скачана. Откройте меню Shepot → «Модели» и нажмите «Скачать»."
            flashError("Модель не скачана")
            return
        }
        guard await Permissions.requestMicrophone() else {
            refreshPermissions()
            error = "Нет доступа к микрофону. Включите Shepot в Системных настройках → «Микрофон»."
            flashError("Нет доступа к микрофону")
            return
        }
        do {
            try recorder.start()
        } catch {
            self.error = "Не удалось начать запись. Проверьте, что микрофон подключён, и попробуйте снова."
            return
        }
        phase = .recording
        play(.start)
        if cancelRequested {
            cancelRecording()
        } else if stopRequested {
            await stopAndTranscribe()
        }
    }

    /// Drops the recording without transcribing.
    private func cancelRecording() {
        if isStarting {
            cancelRequested = true
            return
        }
        guard phase == .recording else { return }
        var samples = recorder.stop()
        samples.removeAll()
        play(.stop)
        phase = .idle
    }

    private func stopAndTranscribe() async {
        guard phase == .recording else { return }
        var samples = recorder.stop()
        play(.stop)
        // Ignore accidental taps shorter than 0.3 s.
        guard samples.count > Recorder.sampleRate * 3 / 10 else {
            phase = .idle
            return
        }
        // Near-silent audio makes Whisper invent words ("you"), so don't send it.
        guard (samples.map { abs($0) }.max() ?? 0) > 0.004 else {
            flashError("Микрофон не слышит голос")
            error = "Микрофон почти ничего не записал. Проверьте, какой микрофон выбран в Системных настройках → «Звук» → «Вход», и повторите."
            phase = .idle
            return
        }
        phase = .transcribing
        defer { phase = .idle }
        do {
            let lang = language == "auto" ? nil : language
            let raw = try await transcriber.transcribe(samples, model: selectedModel, language: lang)
            let text = finalized(raw)
            if text.isEmpty {
                flashError("Ничего не распознано")
            } else {
                addToHistory(text)
                deliver(text)
            }
        } catch {
            self.error = "Не удалось распознать речь (\(Self.brief(error))). Попробуйте ещё раз или выберите другую модель."
            flashError("Не удалось распознать")
        }
        samples.removeAll() // audio is never kept after transcription
    }

    private func deliver(_ text: String) {
        refreshPermissions()
        guard isAccessibilityTrusted else {
            // Can't send Cmd+V without Accessibility, so leave the text on the clipboard.
            copy(text)
            error = "Текст в буфере — вставьте его ⌘V. Чтобы он вставлялся сам, включите Shepot в «Универсальном доступе»."
            Permissions.promptAccessibility()
            flashError("Текст в буфере — вставьте ⌘V")
            return
        }
        Paster.paste(text)
        play(.paste)
    }

    /// Drops a single closing period so short messages don't read as formal; "…" and "?" stay.
    private func finalized(_ text: String) -> String {
        guard skipFinalPeriod, text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }

    /// First line of the real cause, so a failure can be told apart without a debugger.
    private static func brief(_ error: Error) -> String {
        String(String(describing: error).split(separator: "\n").first?.prefix(140) ?? "")
    }

    private func flashError(_ text: String) {
        play(.error)
        overlay.showAlert(text, style: islandStyle)
    }

    private func play(_ sound: Sound) {
        if soundsEnabled { sound.play(set: soundSet) }
    }

    /// Plays a sample of a set so it can be judged before choosing it.
    func previewSounds(_ set: SoundSet) {
        Sound.start.play(set: set)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { Sound.paste.play(set: set) }
    }

    private func updateOverlay() {
        switch phase {
        case .recording:
            meter.start()
            overlay.show(.recording, style: islandStyle)
        case .transcribing: // the meter keeps ticking: it also turns the loading wheel
            overlay.show(.transcribing, style: islandStyle)
        case .idle:
            meter.stop()
            overlay.hide()
        }
    }

    // MARK: - Triggers

    private func setupTriggers() {
        hotKey.onPress = { [weak self] in Task { @MainActor in self?.triggerDown() } }
        hotKey.onRelease = { [weak self] in Task { @MainActor in self?.triggerUp() } }
        modifierTrigger.onPress = { [weak self] in
            Task { @MainActor in
                // In toggle mode wait for a clean release, so ⌘-shortcuts don't start dictation.
                if self?.triggerMode == .hold { self?.triggerDown() }
            }
        }
        modifierTrigger.onRelease = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.triggerMode == .hold { self.triggerUp() } else { self.triggerDown() }
            }
        }
        modifierTrigger.onChord = { [weak self] in
            Task { @MainActor in
                if self?.triggerMode == .hold { self?.cancelRecording() }
            }
        }
        applyActivation()
    }

    private func applyActivation() {
        switch activation {
        case .combo:
            modifierTrigger.stop()
            hotKeyError = hotKey.register(hotKeyCombo)
                ? nil
                : "Сочетание \(hotKeyCombo.label) занято другим приложением (например, Superwhisper или Spotlight). Выберите другое."
        case .rightCommand, .rightOption:
            hotKey.unregister()
            hotKeyError = nil
            modifierTrigger.start(activation == .rightCommand ? .rightCommand : .rightOption)
        }
    }

    private func triggerDown() {
        switch (triggerMode, phase) {
        case (_, .idle): Task { await startRecording() }
        case (.toggle, .recording): Task { await stopAndTranscribe() }
        default: break
        }
    }

    private func triggerUp() {
        guard triggerMode == .hold else { return }
        if phase == .recording {
            Task { await stopAndTranscribe() }
        } else if isStarting {
            stopRequested = true
        }
    }
}
