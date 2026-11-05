import AppKit

/// Cleans dictated text with a plain-text rules file: fillers to remove and words to replace.
/// A copy in Application Support (editable by the user) wins over the bundled default.
enum Cleaner {
    struct Rules {
        var remove: [String] = []
        var replace: [(from: String, to: String)] = []
    }

    static let userFile = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Shepot/cleanup.txt")

    private static var bundled: URL? { Bundle.main.url(forResource: "cleanup-ru", withExtension: "txt") }

    /// Opens the user's copy of the rules, creating it from the default first.
    static func openRulesFile() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: userFile.path), let bundled {
            try? fm.createDirectory(at: userFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: bundled, to: userFile)
        }
        NSWorkspace.shared.open(fm.fileExists(atPath: userFile.path) ? userFile : (bundled ?? userFile))
    }

    static func loadRules() -> Rules {
        let url = FileManager.default.fileExists(atPath: userFile.path) ? userFile : bundled
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return Rules() }
        return parse(text)
    }

    static func parse(_ text: String) -> Rules {
        var rules = Rules()
        var section = ""
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") { section = line.lowercased(); continue }
            if section == "[убрать]" {
                rules.remove.append(line)
            } else if section == "[заменить]", let range = line.range(of: "=>") {
                let from = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let to = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !from.isEmpty { rules.replace.append((from, to)) }
            }
        }
        return rules
    }

    static func clean(_ text: String) -> String { clean(text, rules: loadRules()) }

    static func clean(_ text: String, rules: Rules) -> String {
        var s = text
        for (from, to) in rules.replace {
            s = apply(word(from), to: NSRegularExpression.escapedTemplate(for: to), to: s)
        }
        // Longest first, so "э-э-э" goes before "э-э".
        for phrase in rules.remove.sorted(by: { $0.count > $1.count }) {
            let p = word(phrase)
            s = apply(",\\s*" + p + "\\s*,\\s*", to: " ", to: s) // ", как бы, " → " "
            s = apply(p + "\\s*,?\\s*", to: "", to: s)
        }
        // A one- or two-letter word said twice ("я я хочу").
        s = apply("(?<![\\p{L}\\p{N}])(\\p{L}{1,2})(?:\\s+\\1)+(?![\\p{L}\\p{N}])", to: "$1", to: s)
        s = apply("\\s+([,.;:!?…])", to: "$1", to: s)
        s = apply(",\\s*([.!?…])", to: "$1", to: s)
        s = apply(",(\\s*,)+", to: ",", to: s)
        s = apply("^[\\s,;]+", to: "", to: s)
        s = apply("[ \\t]{2,}", to: " ", to: s)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s != text else { return text }
        return capitalized(s, first: text.first?.isUppercase ?? false)
    }

    // MARK: Helpers

    /// The phrase as a whole word: not glued to letters, digits or hyphens.
    private static func word(_ phrase: String) -> String {
        let body = phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        return "(?<![\\p{L}\\p{N}-])" + body + "(?![\\p{L}\\p{N}-])"
    }

    private static func apply(_ pattern: String, to template: String, to text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Re-capitalizes sentence starts that a removal may have left in lower case.
    private static func capitalized(_ text: String, first: Bool) -> String {
        var out = "", cap = first, afterStop = false
        for ch in text {
            if cap, ch.isLetter { out += ch.uppercased(); cap = false; afterStop = false; continue }
            out.append(ch)
            if ".!?…".contains(ch) { afterStop = true }
            else if ch.isWhitespace { if afterStop { cap = true } }
            else { afterStop = false; if ch.isLetter || ch.isNumber { cap = false } }
        }
        return out
    }
}
