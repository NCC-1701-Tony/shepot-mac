import Foundation

struct DictationEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    let text: String
    let date: Date
}

/// Last dictations, newest first. Text only — audio is never stored.
enum History {
    static let limit = 10
    private static let key = "history"

    static func load() -> [DictationEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([DictationEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func save(_ entries: [DictationEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
