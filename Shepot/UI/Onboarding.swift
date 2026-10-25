import Combine
import SwiftUI

/// First-launch walkthrough: microphone, Accessibility, model, key. Shown once.
@MainActor
enum Onboarding {
    private static let doneKey = "onboardingDone"
    private static var window: NSWindow?
    private static var closeObserver: Any?

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    static func show(state: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.panelNS
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView { window.close() }.environmentObject(state))
        window.center()
        // Closing it any way counts as seen.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in finish() }
        }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func finish() {
        UserDefaults.standard.set(true, forKey: doneKey)
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window = nil
    }
}

private struct OnboardingView: View {
    let close: () -> Void
    @EnvironmentObject private var state: AppState
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stepCount = 5
    // Live permission status while the user flips switches in System Settings.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: microphone
                case 2: accessibility
                case 3: model
                default: key
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 48)
            .id(step)
            .transition(.ui(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)),
                            reduceMotion: reduceMotion))

            footer
        }
        .frame(width: 520, height: 600)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .onReceive(poll) { _ in state.refreshPermissions() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.top, 30)
            Text("Shepot").font(.system(size: 30, weight: .bold))
            Text("Говорите — текст появится там, где стоит курсор. В любом приложении.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 12) {
                feature("lock.fill", "Всё работает на этом Mac, без интернета и подписок")
                feature("waveform", "Распознавание Whisper от OpenAI, хорошо понимает русский")
                feature("mic.slash", "Голос не сохраняется, только текст последних диктовок")
            }
            .padding(.top, 14)
        }
    }

    private var microphone: some View {
        let allowed = Permissions.isMicrophoneGranted
        return stepLayout(
            icon: "mic.fill",
            title: "Доступ к микрофону",
            text: "Shepot слушает микрофон только пока вы держите клавишу, и распознаёт речь прямо на этом Mac."
        ) {
            if allowed {
                done("Микрофон разрешён")
            } else if state.isMicrophoneAllowed {
                PillButton(title: "Разрешить микрофон", kind: .primary) {
                    Task { _ = await Permissions.requestMicrophone(); state.refreshPermissions() }
                }
            } else {
                hint("Доступ был запрещён. Включите Shepot в разделе «Микрофон».")
                PillButton(title: "Открыть настройки", kind: .primary) { Permissions.openMicrophoneSettings() }
            }
        }
    }

    private var accessibility: some View {
        stepLayout(
            icon: "hand.tap.fill",
            title: "Универсальный доступ",
            text: "Нужен, чтобы вставлять текст в другие приложения и слышать правые ⌘ и ⌥. Shepot ничего не читает с экрана."
        ) {
            if state.isAccessibilityTrusted {
                done("Доступ включён")
            } else {
                PillButton(title: "Открыть настройки", kind: .primary) {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                hint("В списке включите переключатель у Shepot. Если его там нет — нажмите «+» и выберите Shepot в «Программах». Это окно заметит изменение само.")
            }
        }
    }

    private var model: some View {
        stepLayout(
            icon: "square.and.arrow.down.fill",
            title: "Модель распознавания",
            text: "Скачивается один раз и дальше работает без интернета. Для начала рекомендуем large-v3-turbo."
        ) {
            VStack(spacing: 8) {
                ForEach(ModelCatalog.all) { ModelCard(model: $0) }
            }
            if state.installed.contains(state.selectedModel) {
                hint("Первая диктовка может занять пару минут — macOS готовит модель. Потом всё быстро.")
            }
        }
    }

    private var key: some View {
        stepLayout(
            icon: "keyboard.fill",
            title: "Клавиша диктовки",
            text: "Выберите, чем включать запись. Поменять можно в любой момент в меню Shepot в строке меню."
        ) {
            Segmented(options: AppState.Activation.allCases, selection: $state.activation) { activation in
                state.title(for: activation)
            }
            Segmented(options: AppState.TriggerMode.allCases, selection: $state.triggerMode) {
                $0 == .hold ? "Удерживать" : "Нажать-нажать"
            }
            Text(tryItText)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accentTint))
                .padding(.top, 6)
        }
    }

    private var tryItText: String {
        let key = state.title(for: state.activation)
        return state.triggerMode == .hold
            ? "Попробуйте: поставьте курсор в любое поле, зажмите \(key), скажите фразу и отпустите."
            : "Попробуйте: поставьте курсор в любое поле, нажмите \(key), скажите фразу и нажмите ещё раз."
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<Self.stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Theme.accent : Theme.fillSelected)
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Шаг \(step + 1) из \(Self.stepCount)")
            Spacer()
            if step > 0 {
                PillButton(title: "Назад") { go(step - 1) }
            }
            if step < Self.stepCount - 1 {
                PillButton(title: step == 0 ? "Начать" : "Далее", kind: .primary) { go(step + 1) }
            } else {
                PillButton(title: "Готово", kind: .primary, action: close)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private func go(_ next: Int) {
        withAnimation(.ui(.spring(response: 0.35, dampingFraction: 0.85), reduceMotion: reduceMotion)) { step = next }
    }

    // MARK: Helpers

    private func stepLayout<Content: View>(icon: String, title: String, text: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.accentTint).frame(width: 72, height: 72)
                Image(systemName: icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)
            Text(title).font(.system(size: 22, weight: .bold))
            Text(text)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) { content() }.padding(.top, 8)
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 20)
            Text(text).font(.system(size: 13))
        }
    }

    private func done(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.success)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
