import Foundation

/// Výsledek parsování textu s odkazy.
struct PlainTextImportResult {
    /// Jeden kořen „Text“ se sekcemi (složkami) a odkazy.
    var roots: [BookmarkNode]
    /// Počet neprázdných řádků, ve kterých nebyla nalezena URL (a nejsou nadpisem).
    var skippedLines: Int

    var linkCount: Int { roots.flatMap(\.allBookmarks).count }
}

/// Parser odkazů z prostého textu (jeden odkaz na řádek). Podporované zápisy:
///
///     https://jira.example.com Jira #práce #pm
///     Jira – https://jira.example.com #práce
///     Jira | https://jira.example.com | práce, pm
///     - [Jira](https://jira.example.com) #práce
///     # Práce                ← nadpis = složka pro následující řádky (## = podsložka)
///     Práce:                 ← řádek bez URL končící dvojtečkou = složka
///     // komentář
enum PlainTextBookmarksParser {
    private final class Section {
        let id: String
        let name: String
        let level: Int
        var children: [Child] = []

        init(id: String, name: String, level: Int) {
            self.id = id
            self.name = name
            self.level = level
        }

        func node(isRoot: Bool) -> BookmarkNode {
            BookmarkNode(
                id: id,
                name: name,
                url: nil,
                children: children.map {
                    switch $0 {
                    case .section(let s): return s.node(isRoot: false)
                    case .link(let l): return l
                    }
                },
                isRoot: isRoot
            )
        }
    }

    private enum Child {
        case section(Section)
        case link(BookmarkNode)
    }

    /// Úroveň sekcí „Název:“ – vždy pod všemi Markdown nadpisy (1–6).
    private static let colonSectionLevel = 100

    static func parse(_ text: String) -> PlainTextImportResult {
        var counter = 0
        func nextID() -> String {
            counter += 1
            return "txt-\(counter)"
        }

        let root = Section(id: "txt-root", name: "Text", level: 0)
        // Zásobník otevřených sekcí podle úrovně nadpisu.
        var stack: [Section] = [root]
        var skipped = 0

        func openSection(_ name: String, level: Int) {
            while let last = stack.last, last.level >= level, stack.count > 1 { stack.removeLast() }
            let section = Section(id: nextID(), name: name, level: level)
            stack[stack.count - 1].children.append(.section(section))
            stack.append(section)
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix(";") { continue }

            // Markdown nadpis „# Název“ (mezera za #, jinak jde o štítek).
            if let (level, name) = heading(line) {
                if !name.isEmpty { openSection(name, level: level) }
                continue
            }

            if let parsed = parseLine(line) {
                let node = BookmarkNode(
                    id: nextID(), name: parsed.title, url: parsed.url,
                    children: [], isRoot: false, tags: parsed.tags
                )
                stack[stack.count - 1].children.append(.link(node))
            } else if line.hasSuffix(":"), line.count > 1, !line.contains("://") {
                // „Práce:“ – sekce pod posledním Markdown nadpisem; další „Něco:“ je její sourozenec.
                let name = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { openSection(name, level: colonSectionLevel) }
            } else {
                skipped += 1
            }
        }

        let tree = root.node(isRoot: true)
        return PlainTextImportResult(roots: tree.children.isEmpty ? [] : [tree], skippedLines: skipped)
    }

    // MARK: - Řádek

    struct ParsedLine: Equatable {
        var title: String
        var url: String
        var tags: [String]
    }

    static func parseLine(_ input: String) -> ParsedLine? {
        var line = stripBullet(input)

        // Markdown odkaz [název](url)
        var markdownTitle: String?
        var markdownURL: String?
        if let open = line.range(of: "["),
           let mid = line.range(of: "](", range: open.upperBound..<line.endIndex),
           let close = line.range(of: ")", range: mid.upperBound..<line.endIndex) {
            markdownTitle = String(line[open.upperBound..<mid.lowerBound])
            markdownURL = String(line[mid.upperBound..<close.lowerBound])
            line.replaceSubrange(open.lowerBound..<close.upperBound, with: " ")
        }

        // Sloupcový zápis: název | url | štítky
        if markdownURL == nil, line.contains("|") || line.contains("\t") {
            let columns = line.split(whereSeparator: { $0 == "|" || $0 == "\t" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let urlIndex = columns.firstIndex(where: { cleanURLToken($0) != nil }),
               let url = cleanURLToken(columns[urlIndex]) {
                // Sloupce před URL tvoří název, sloupce za ní štítky (oddělené čárkou či mezerou).
                // Když je URL první, první další sloupec je název.
                var before = columns[..<urlIndex].filter { !$0.isEmpty }
                var after = columns[(urlIndex + 1)...].filter { !$0.isEmpty }
                if before.isEmpty, !after.isEmpty { before = [after.removeFirst()] }
                var tags: [String] = []
                var titleParts: [String] = []
                for column in before {
                    let (text, hashTags) = extractHashTags(column)
                    tags += hashTags
                    if !text.isEmpty { titleParts.append(text) }
                }
                for column in after {
                    tags += column.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
                }
                return ParsedLine(title: titleParts.joined(separator: " "), url: url, tags: Tag.normalizeList(tags))
            }
        }

        // Volný zápis: URL kdekoli, #štítky, zbytek je název.
        var url = markdownURL.flatMap(cleanURLToken)
        var titleWords: [String] = []
        var tags: [String] = []
        for token in line.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if token.hasPrefix("#"), token.count > 1 {
                tags.append(token)
            } else if url == nil, let u = cleanURLToken(token) {
                url = u
            } else {
                titleWords.append(token)
            }
        }
        guard let url else { return nil }

        // U Markdown odkazu je název v hranatých závorkách; ostatní text kromě štítků se ignoruje.
        let title = markdownTitle ?? trimSeparators(titleWords.joined(separator: " "))
        return ParsedLine(title: title.trimmingCharacters(in: .whitespaces), url: url, tags: Tag.normalizeList(tags))
    }

    /// `# Název` → (1, "Název"); `## Název` → (2, …). Mezera za `#` je povinná.
    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard let first = rest.first, first.isWhitespace else { return nil }
        // „# https://…“ není nadpis.
        let name = rest.trimmingCharacters(in: .whitespaces)
        if cleanURLToken(name) != nil { return nil }
        return (hashes, name)
    }

    private static func stripBullet(_ line: String) -> String {
        var s = Substring(line)
        if let first = s.first, "-*+•".contains(first), s.dropFirst().first?.isWhitespace == true {
            s = s.dropFirst(2)
        } else if let dot = s.firstIndex(where: { $0 == "." || $0 == ")" }),
                  s[s.startIndex..<dot].allSatisfy(\.isNumber), dot > s.startIndex,
                  s[s.index(after: dot)...].first?.isWhitespace == true {
            s = s[s.index(after: dot)...]
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Token jako URL (bez okolní interpunkce a `<>`), normalizovaná – jinak `nil`.
    static func cleanURLToken(_ raw: String) -> String? {
        var token = raw.trimmingCharacters(in: .whitespaces)
        if token.hasPrefix("<"), token.hasSuffix(">") { token = String(token.dropFirst().dropLast()) }
        while let last = token.last, ",;.)]>\"'".contains(last) { token.removeLast() }
        while let first = token.first, "(<[\"'".contains(first) { token.removeFirst() }
        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace }) else { return nil }
        let lower = token.lowercased()
        let hasWebScheme = lower.hasPrefix("http://") || lower.hasPrefix("https://")
        guard hasWebScheme || lower.hasPrefix("www.") || (!URLTools.hasScheme(token) && URLTools.looksLikeURL(token)) else {
            return nil
        }
        // Slova jako „např.“ nebo „v1.2“ nejsou URL – doména musí končit písmeny.
        if !hasWebScheme {
            let host = token.split(separator: "/").first.map(String.init) ?? token
            let hostWithoutPort = host.split(separator: ":").first.map(String.init) ?? host
            guard let tld = hostWithoutPort.split(separator: ".").last, tld.count >= 2, tld.allSatisfy(\.isLetter) else {
                return nil
            }
        }
        return URLTools.normalize(token)
    }

    private static func extractHashTags(_ text: String) -> (String, [String]) {
        var words: [String] = []
        var tags: [String] = []
        for token in text.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if token.hasPrefix("#"), token.count > 1 { tags.append(token) } else { words.append(token) }
        }
        return (words.joined(separator: " "), tags)
    }

    private static func trimSeparators(_ s: String) -> String {
        let separators: Set<Character> = ["-", "–", "—", "|", ":", "·", "•", ","]
        var result = s.trimmingCharacters(in: .whitespaces)
        while let first = result.first, separators.contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        while let last = result.last, separators.contains(last) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
