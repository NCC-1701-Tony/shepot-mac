import AppKit
import SwiftUI
import Security

/// Looks for a newer release on GitHub and replaces the running app with it.
/// Touches the network only on an explicit check, or at launch if the user turned that on.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: String
        let zipURL: URL
    }

    enum Status: Equatable {
        case idle, checking, upToDate, available(Release), installing, failed(String)
    }

    private struct Failure: Error { let text: String }

    private struct Payload: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        let tag_name: String
        let assets: [Asset]
    }

    static let repo = "NCC-1701-Tony/shepot-mac"
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    @Published private(set) var status = Status.idle
    @Published var checkOnLaunch = UserDefaults.standard.bool(forKey: "checkUpdates") {
        didSet { UserDefaults.standard.set(checkOnLaunch, forKey: "checkUpdates") }
    }

    init() {
        guard checkOnLaunch else { return }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await check()
        }
    }

    func check() async {
        guard status != .checking, status != .installing else { return }
        status = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(text: "GitHub не ответил") }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let version = payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard Self.isNewer(version, than: Self.currentVersion) else { status = .upToDate; return }
            guard let zip = payload.assets.first(where: { $0.name.hasSuffix(".zip") }),
                  let url = URL(string: zip.browser_download_url) else {
                throw Failure(text: "В релизе нет архива для обновления")
            }
            status = .available(Release(version: version, zipURL: url))
        } catch let failure as Failure {
            status = .failed(failure.text)
        } catch {
            status = .failed("Не удалось проверить обновления")
        }
    }

    func install(_ release: Release) async {
        guard case .available = status else { return }
        status = .installing
        do {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("shepot-update-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let (tmp, _) = try await URLSession.shared.download(from: release.zipURL)
            let zip = work.appendingPathComponent("update.zip")
            try fm.moveItem(at: tmp, to: zip)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let fresh = work.appendingPathComponent("Shepot.app")
            guard fm.fileExists(atPath: fresh.path) else { throw Failure(text: "В архиве нет Shepot.app") }
            try Self.verify(fresh)
            let current = Bundle.main.bundleURL
            guard fm.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
                throw Failure(text: "Нет прав на запись в папку приложения")
            }
            Self.swapAfterQuit(fresh: fresh, current: current, work: work)
            NSApp.terminate(nil)
        } catch let failure as Failure {
            status = .failed(failure.text)
        } catch {
            status = .failed("Не удалось установить обновление")
        }
    }

    // MARK: Helpers

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(text: "Не удалось распаковать обновление") }
    }

    /// The downloaded app must satisfy the running app's own signature requirement, i.e. the same certificate.
    private static func verify(_ app: URL) throws {
        let bad = Failure(text: "Подпись обновления не совпадает с подписью приложения")
        var me: SecCode?
        var meStatic: SecStaticCode?
        var requirement: SecRequirement?
        var other: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &other) == errSecSuccess, let other
        else { throw bad }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(other, flags, requirement) == errSecSuccess else { throw bad }
    }

    /// A detached shell waits for this process to exit, swaps the bundle and relaunches it.
    private static func swapAfterQuit(fresh: URL, current: URL, work: URL) {
        func q(_ url: URL) -> String { "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let staged = current.appendingPathExtension("new")
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        /usr/bin/ditto \(q(fresh)) \(q(staged)) && rm -rf \(q(current)) && mv \(q(staged)) \(q(current)) && open \(q(current))
        rm -rf \(q(work))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// Version line with the check / update controls, for the General settings section.
struct UpdateRow: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Версия \(Updater.currentVersion)").font(.system(size: 13))
                    if !caption.isEmpty {
                        Text(caption).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                control
            }
            Toggle(isOn: $updater.checkOnLaunch) {
                Text("Проверять обновления при запуске").font(.system(size: 13))
            }
            .toggleStyle(CoralSwitchStyle())
        }
    }

    @ViewBuilder
    private var control: some View {
        switch updater.status {
        case .checking, .installing:
            ProgressView().controlSize(.small)
        case .available(let release):
            PillButton(title: "Обновить", kind: .primary) { Task { await updater.install(release) } }
        default:
            PillButton(title: "Проверить") { Task { await updater.check() } }
        }
    }

    private var caption: String {
        switch updater.status {
        case .idle: ""
        case .checking: "Проверяю…"
        case .upToDate: "У вас последняя версия"
        case .available(let release): "Доступна версия \(release.version)"
        case .installing: "Устанавливаю, приложение перезапустится"
        case .failed(let text): text
        }
    }
}
