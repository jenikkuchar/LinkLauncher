import Foundation

/// Rozparsovaný dotaz launcheru.
struct ParsedQuery: Equatable {
    /// Složené (bez diakritiky, malá písmena) textové tokeny.
    var terms: [String]
    /// Složené názvy štítků z dokončených tokenů `#štítek` – všechny musí odpovídat přesně (AND).
    var tagFilters: [String]
    /// Pokud uživatel právě píše `#…` (poslední token bez mezery za ním), jeho složený prefix
    /// (může být prázdný). Filtruje prefixově, aby výsledky během psaní nezmizely.
    var pendingTagPrefix: String?

    var isEmpty: Bool { terms.isEmpty && tagFilters.isEmpty && (pendingTagPrefix ?? "").isEmpty }
}

enum QueryParser {
    static func parse(_ query: String) -> ParsedQuery {
        var tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        var pending: String?
        if let last = tokens.last, last.hasPrefix("#"),
           let lastChar = query.last, !lastChar.isWhitespace {
            pending = TextFolding.fold(Tag.normalize(last))
            tokens.removeLast()
        }

        var terms: [String] = []
        var tags: [String] = []
        for token in tokens {
            if token.hasPrefix("#") {
                let name = TextFolding.fold(Tag.normalize(token))
                if !name.isEmpty, !tags.contains(name) { tags.append(name) }
            } else {
                terms.append(TextFolding.fold(token))
            }
        }
        return ParsedQuery(terms: terms, tagFilters: tags, pendingTagPrefix: pending)
    }

    /// Nahradí rozepsaný poslední `#token` celým štítkem a přidá mezeru.
    static func completeTag(in query: String, with tag: String) -> String {
        guard let hashIndex = query.lastIndex(of: "#") else { return query }
        let after = query[hashIndex...]
        guard !after.contains(where: { $0.isWhitespace }) else { return query }
        return String(query[..<hashIndex]) + "#" + tag + " "
    }
}
