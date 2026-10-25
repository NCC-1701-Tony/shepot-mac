import Foundation
import WhisperKit

/// WhisperKit isn't marked Sendable; access is serialized by the Transcriber actor.
private final class KitBox: @unchecked Sendable {
    let kit: WhisperKit
    init(_ kit: WhisperKit) { self.kit = kit }
}

/// Keeps one WhisperKit model loaded and runs transcription on it.
actor Transcriber {
    private var current: (id: String, task: Task<KitBox, Error>)?

    func load(_ id: String) async throws {
        _ = try await kit(for: id)
    }

    /// Frees the model before its files are deleted.
    func unload(_ id: String) {
        if current?.id == id { current = nil }
    }

    func transcribe(_ samples: [Float], model id: String, language: String?) async throws -> String {
        let kit = try await kit(for: id).kit
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad // splits long dictation into 30 s windows
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the loaded model, loading it once if needed. Never touches the network.
    private func kit(for id: String) async throws -> KitBox {
        if let current, current.id == id {
            return try await current.task.value
        }
        let config = WhisperKitConfig(
            model: id,
            downloadBase: ModelStore.baseURL,
            modelFolder: ModelStore.folder(for: id).path,
            tokenizerFolder: ModelStore.baseURL,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        let task = Task { KitBox(try await WhisperKit(config)) }
        current = (id, task)
        do {
            return try await task.value
        } catch {
            if current?.id == id { current = nil } // allow retry
            throw error
        }
    }
}
