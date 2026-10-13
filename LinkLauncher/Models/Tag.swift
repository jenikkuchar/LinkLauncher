import Foundation

/// Pomocné funkce pro štítky. Štítky se ukládají malými písmeny a bez mezer,
/// aby šly zapsat jako `#štítek` v launcheru.
enum Tag {
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        let parts = s.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," })
        return parts.joined(separator: "-")
    }

    /// Normalizuje a odstraní prázdné a duplicitní štítky (zachová pořadí).
    static func normalizeList(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let n = normalize(tag)
            guard !n.isEmpty, seen.insert(n).inserted else { continue }
            result.append(n)
        }
        return result
    }
}
