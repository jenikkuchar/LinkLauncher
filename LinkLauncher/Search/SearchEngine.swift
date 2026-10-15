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
        var scored: [(index: Int, tier: Int, openCount: Int, lastOpened: Double, score: Double)] = []
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
            // Vrstva odkazu = nejslabší vrstva ze všech slov dotazu.
            var tier = MatchTier.title
            var matchedAll = true
            for term in terms {
                guard let match = Self.match(term: term, entry: entry) else {
                    matchedAll = false
                    break
                }
                total += match.score
                tier = max(tier, match.tier)
            }
            guard matchedAll else { continue }
            let link = entry.link
            scored.append((
                index,
                tier.rawValue,
                link.openCount,
                link.lastOpenedAt?.timeIntervalSinceReferenceDate ?? -.infinity,
                total.rounded()
            ))
        }

        let entries = self.entries
        // Pořadí: vrstva shody (název → štítek → URL), v ní nejčastěji otevírané,
        // pak naposledy otevřené, teprve pak kvalita shody s dotazem.
        scored.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
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

    /// Kde se slovo dotazu našlo – nižší je silnější (řadí se výš).
    enum MatchTier: Int, Comparable {
        case title = 0, tag = 1, url = 2
        static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
    }

    /// Vrstva = nejsilnější pole, ve kterém slovo je (název před štítkem před URL);
    /// skóre = nejlepší vážená shoda přes všechna pole (rozhoduje až uvnitř vrstvy).
    private static func match(term: [Unicode.Scalar], entry: Entry) -> (tier: MatchTier, score: Double)? {
        var tier: MatchTier?
        var best: Double?
        if let s = FuzzyMatcher.score(term, in: entry.title) {
            tier = .title
            best = s * titleWeight
        }
        for tag in entry.tags {
            if let s = FuzzyMatcher.score(term, in: tag) {
                tier = tier ?? .tag
                best = max(best ?? 0, s * tagWeight)
            }
        }
        if let s = FuzzyMatcher.score(term, in: entry.url) {
            tier = tier ?? .url
            best = max(best ?? 0, s * urlWeight)
        }
        guard let tier, let best else { return nil }
        return (tier, best)
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
