import Foundation
import WhisperKit

struct WhisperModel: Identifiable, Hashable {
    let id: String          // folder name in argmaxinc/whisperkit-coreml
    let title: String
    let approxSize: String
    let note: String
    var recommended = false
    let variant: ModelVariant // used to fetch the matching tokenizer
}

enum ModelCatalog {
    static let all: [WhisperModel] = [
        WhisperModel(id: "openai_whisper-large-v3-v20240930", title: "large-v3-turbo", approxSize: "≈1,6 ГБ",
                     note: "Быстрая и точная", recommended: true, variant: .largev3),
        WhisperModel(id: "openai_whisper-medium", title: "medium", approxSize: "≈1,5 ГБ",
                     note: "Точная, но медленнее", variant: .medium),
        WhisperModel(id: "openai_whisper-small", title: "small", approxSize: "≈0,5 ГБ",
                     note: "Самая лёгкая и быстрая", variant: .small),
        WhisperModel(id: "openai_whisper-large-v3", title: "large-v3", approxSize: "≈3 ГБ",
                     note: "Максимум точности, медленная", variant: .largev3),
    ]
    static let defaultModel = all[0]
}

/// Models on disk: ~/Library/Application Support/Shepot/Models
enum ModelStore {
    static let repo = "argmaxinc/whisperkit-coreml"
    static let baseURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Shepot/Models", directoryHint: .isDirectory)

    /// Written after model + tokenizer are fully downloaded.
    private static let completeMarker = ".shpt-complete"

    static func folder(for id: String) -> URL {
        HubApiWrapper(downloadBase: baseURL)
            .localRepoLocation(HubApiWrapper.Repo(id: repo))
            .appending(path: id, directoryHint: .isDirectory)
    }

    /// The marker alone isn't trusted: a model missing a CoreML part can't load.
    static func isInstalled(_ id: String) -> Bool {
        let dir = folder(for: id)
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appending(path: completeMarker).path)
            && ["AudioEncoder", "TextDecoder", "MelSpectrogram"].allSatisfy {
                fm.fileExists(atPath: dir.appending(path: "\($0).mlmodelc").path)
            }
    }

    static func delete(_ id: String) throws {
        try FileManager.default.removeItem(at: folder(for: id))
    }

    /// The only place the app goes online, and only on explicit user action.
    static func download(_ model: WhisperModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(variant: model.id, downloadBase: baseURL, from: repo) {
            progress($0.fractionCompleted)
        }
        // Tokenizer lives in a separate repo; fetch it now so later loads stay offline.
        _ = try await ModelUtilities.loadTokenizer(for: model.variant, tokenizerFolder: baseURL)
        FileManager.default.createFile(atPath: folder(for: model.id).appending(path: completeMarker).path, contents: nil)
    }
}
