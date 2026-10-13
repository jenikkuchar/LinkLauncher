import Foundation

/// Skórování shody jednoho tokenu dotazu s jedním textem (oba už složené).
/// Výsledek je 0…100, `nil` = žádná shoda.
enum FuzzyMatcher {
    static func score(_ query: [Unicode.Scalar], in text: [Unicode.Scalar]) -> Double? {
        guard !query.isEmpty else { return 0 }
        guard query.count <= text.count else { return nil }

        if query.count == text.count, query == text { return 100 }

        // Souvislý podřetězec – preferujeme začátek a hranici slova.
        var bestSubstring: Double?
        var searchFrom = 0
        while let pos = indexOf(query, in: text, from: searchFrom) {
            let s: Double
            if pos == 0 {
                s = 90
            } else if isBoundary(text[pos - 1]) {
                s = 80
            } else {
                s = 65 - min(Double(pos), 20) * 0.5
            }
            bestSubstring = max(bestSubstring ?? 0, s)
            if s >= 80 { break }
            searchFrom = pos + 1
        }
        if let bestSubstring {
            // Kratší text se stejnou shodou je relevantnější.
            let coverage = Double(query.count) / Double(text.count)
            return bestSubstring + coverage * 5
        }

        // Jednoznakový dotaz musí být podřetězec.
        guard query.count >= 2 else { return nil }
        return subsequenceScore(query, in: text)
    }

    /// Fuzzy (podposloupnost) – znaky musí jít ve stejném pořadí. Rozsah 15…50.
    private static func subsequenceScore(_ query: [Unicode.Scalar], in text: [Unicode.Scalar]) -> Double? {
        var qi = 0
        var raw = 0.0
        var prev = -2
        var first = -1
        for ti in 0..<text.count where qi < query.count {
            guard text[ti] == query[qi] else { continue }
            var s = 1.0
            if ti == prev + 1 { s += 2 }
            if ti == 0 || isBoundary(text[ti - 1]) { s += 2.5 }
            raw += s
            if first < 0 { first = ti }
            prev = ti
            qi += 1
        }
        guard qi == query.count else { return nil }
        let span = prev - first + 1
        let gaps = Double(span - query.count)
        // Příliš roztroušená shoda je spíš šum.
        if gaps > Double(query.count) * 4 + 6 { return nil }
        let maxRaw = Double(query.count) * 5.5
        let quality = max(0, raw / maxRaw - gaps * 0.02)
        return 15 + 35 * min(quality, 1)
    }

    private static func indexOf(_ needle: [Unicode.Scalar], in hay: [Unicode.Scalar], from start: Int) -> Int? {
        let n = needle.count
        guard n > 0, hay.count - n >= start else { return nil }
        let first = needle[0]
        var i = start
        let last = hay.count - n
        while i <= last {
            if hay[i] == first {
                var j = 1
                while j < n && hay[i + j] == needle[j] { j += 1 }
                if j == n { return i }
            }
            i += 1
        }
        return nil
    }

    static func isBoundary(_ c: Unicode.Scalar) -> Bool {
        switch c {
        case " ", "-", "_", ".", "/", ":", "?", "&", "=", "#", "(", ")", "[", "]", ",", "|", "+", "@": return true
        default: return false
        }
    }
}
