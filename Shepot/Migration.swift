import Foundation

/// One-time move from the old "Dictate" name: models, settings and history.
/// Permissions can't be moved (macOS ties them to the old bundle id), so onboarding runs again.
enum Migration {
    private static let oldDomain = "com.antondanilov.Dictate"
    private static let doneKey = "migratedFromDictate"
    private static let keys = ["model", "language", "triggerMode", "hotKey", "activation", "islandStyle", "history"]

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        if let old = UserDefaults(suiteName: oldDomain) {
            for key in keys where defaults.object(forKey: key) == nil {
                if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
            }
        }
        moveModels()
    }

    private static func moveModels() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appending(path: "Dictate", directoryHint: .isDirectory)
        let new = support.appending(path: "Shepot", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
        } catch {
            return // models will just be downloaded again
        }
        // The "fully downloaded" marker was renamed as well.
        for model in ModelCatalog.all {
            let folder = ModelStore.folder(for: model.id)
            try? fm.moveItem(at: folder.appending(path: ".dictate-complete"), to: folder.appending(path: ".shpt-complete"))
        }
    }
}
