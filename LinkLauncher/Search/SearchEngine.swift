import Foundation

/// Předpočítaný index pro rychlé vyhledávání (tisíce odkazů při každém stisku klávesy).
struct SearchEngine {
    static let titleWeight = 1.0
    static let tagWeight = 0.75
    static let urlWeight = 0.6

    private struct Entry {
        let link: Link
        let title: [Unicode.Scalar]
        let url: [Unicode.Scalar]
        let tags: [[Unicode.Scalar]]
        let foldedTags: Set<String>
        /// Klíč pro abecední řazení při shodném skóre i počtu otevření.
        let sortKey: String
    }

    private let entries: [Entry]
    /// Všechny štítky s počty, seřazené podle počtu (sestupně) a názvu.
    let tagCounts: [(tag: String, count: Int)]

    init(links: [Link]) {
        var counts: [String: Int] = [:]
        entries = links.map { link in
            for tag in link.tags { counts[tag, default: 0] += 1 }
            return Entry(
                link: link,
                title: TextFolding.scalars(link.title),
                url: TextFolding.foldURL(link.url),
                tags: link.tags.map(TextFolding.scalars),
                foldedTags: Set(link.tags.map(TextFolding.fold)),
                sortKey: TextFolding.fold(link.displayTitle)
            )
        }
        tagCounts = counts
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    func search(_ query: String, now: Date = Date(), limit: Int? = nil) -> [Link] {
        search(QueryParser.parse(query), now: now, limit: limit)
    }

    func search(_ query: ParsedQuery, now: Date = Date(), limit: Int? = nil) -> [Link] {
        let terms = query.terms.map { Array($0.unicodeScalars) }
        // Klíče řazení předpočítané, aby porovnání nekopírovalo celé odkazy.
        var scored: [(index: Int, openCount: Int, lastOpened: Double, score: Double)] = []
        scored.reserveCapacity(entries.count)

        for (index, entry) in entries.enumerated() {
            if !query.tagFilters.isEmpty,
               !query.tagFilters.allSatisfy(entry.foldedTags.contains) {
                continue
            }
            if let pending = query.pendingTagPrefix, !pending.isEmpty,
               !entry.foldedTags.contains(where: { $0.hasPrefix(pending) }) {
                continue
            }
            var total = 0.0
            var matchedAll = true
            for term in terms {
                guard let s = Self.score(term: term, entry: entry) else {
                    matchedAll = false
                    break
                }
                total += s
            }
            guard matchedAll else { continue }
            let link = entry.link
            scored.append((
                index,
                link.openCount,
                link.lastOpenedAt?.timeIntervalSinceReferenceDate ?? -.infinity,
                total.rounded()
            ))
        }

        let entries = self.entries
        // Dotaz jen filtruje; pořadí: nejčastěji otevírané, pak naposledy otevřené,
        // teprve pak kvalita shody s dotazem (rozhoduje hlavně u neotevřených odkazů).
        scored.sort { a, b in
            if a.openCount != b.openCount { return a.openCount > b.openCount }
            if a.lastOpened != b.lastOpened { return a.lastOpened > b.lastOpened }
            if a.score != b.score { return a.score > b.score }
            let ka = entries[a.index].sortKey, kb = entries[b.index].sortKey
            if ka != kb { return ka < kb }
            return a.index < b.index
        }

        let count = limit.map { min($0, scored.count) } ?? scored.count
        return scored.prefix(count).map { entries[$0.index].link }
    }

    private static func score(term: [Unicode.Scalar], entry: Entry) -> Double? {
        var best: Double?
        if let s = FuzzyMatcher.score(term, in: entry.title) {
            best = s * titleWeight
        }
        for tag in entry.tags {
            if let s = FuzzyMatcher.score(term, in: tag) {
                best = max(best ?? 0, s * tagWeight)
            }
        }
        if let s = FuzzyMatcher.score(term, in: entry.url) {
            best = max(best ?? 0, s * urlWeight)
        }
        return best
    }

    /// Návrhy štítků pro rozepsaný `#token`. Prefixové shody první, pak ostatní obsahující text.
    func tagSuggestions(for query: ParsedQuery, limit: Int = 8) -> [String] {
        guard let pending = query.pendingTagPrefix else { return [] }
        let prefix = pending
        // Štítky už použité v jiných tokenech nenabízet.
        let usedSet = Set(query.tagFilters)
        var prefixMatches: [String] = []
        var containsMatches: [String] = []
        for (tag, _) in tagCounts {
            let folded = TextFolding.fold(tag)
            if usedSet.contains(folded) { continue }
            if prefix.isEmpty || folded.hasPrefix(prefix) {
                prefixMatches.append(tag)
            } else if folded.contains(prefix) {
                containsMatches.append(tag)
            }
        }
        return Array((prefixMatches + containsMatches).prefix(limit))
    }
}
