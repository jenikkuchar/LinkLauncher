import Foundation

/// Vytahuje z HTML `<title>` a odkaz na favicon.
enum HTMLTitleParser {
    static func title(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let openEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title", options: .caseInsensitive, range: openEnd.upperBound..<html.endIndex)
        else { return nil }
        let raw = String(html[openEnd.upperBound..<close.lowerBound])
        let collapsed = decodeEntities(raw)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// `href` první ikony z `<link rel="icon" …>` (případně `shortcut icon`, `apple-touch-icon`).
    static func iconHref(in html: String) -> String? {
        var candidates: [(priority: Int, href: String)] = []
        var searchRange = html.startIndex..<html.endIndex
        while let start = html.range(of: "<link", options: .caseInsensitive, range: searchRange) {
            guard let end = html.range(of: ">", range: start.upperBound..<html.endIndex) else { break }
            let tag = String(html[start.upperBound..<end.lowerBound])
            searchRange = end.upperBound..<html.endIndex
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  let href = attribute("href", in: tag), !href.isEmpty
            else { continue }
            let rels = rel.split(separator: " ")
            if rels.contains("icon") {
                candidates.append((rel.contains("svg") || href.hasSuffix(".svg") ? 2 : 0, href))
            } else if rels.contains("apple-touch-icon") {
                candidates.append((1, href))
            }
        }
        return candidates.min { $0.priority < $1.priority }.map { decodeEntities($0.href) }
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        var searchRange = tag.startIndex..<tag.endIndex
        while let r = tag.range(of: name, options: .caseInsensitive, range: searchRange) {
            searchRange = r.upperBound..<tag.endIndex
            // Celé jméno atributu (ne např. `data-href`).
            if r.lowerBound > tag.startIndex {
                let before = tag[tag.index(before: r.lowerBound)]
                guard before.isWhitespace else { continue }
            }
            var i = r.upperBound
            while i < tag.endIndex, tag[i].isWhitespace { i = tag.index(after: i) }
            guard i < tag.endIndex, tag[i] == "=" else { continue }
            i = tag.index(after: i)
            while i < tag.endIndex, tag[i].isWhitespace { i = tag.index(after: i) }
            guard i < tag.endIndex else { return nil }
            let quote = tag[i]
            if quote == "\"" || quote == "'" {
                let valueStart = tag.index(after: i)
                let valueEnd = tag[valueStart...].firstIndex(of: quote) ?? tag.endIndex
                return String(tag[valueStart..<valueEnd])
            }
            let valueEnd = tag[i...].firstIndex(where: { $0.isWhitespace }) ?? tag.endIndex
            var value = String(tag[i..<valueEnd])
            // Samouzavírací `<link href=/x.ico/>`.
            if valueEnd == tag.endIndex, value.hasSuffix("/") { value.removeLast() }
            return value
        }
        return nil
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let entity = String(s[s.index(after: i)..<semi])
                if let decoded = decodeEntity(entity) {
                    result.append(decoded)
                    i = s.index(after: semi)
                    continue
                }
            }
            result.append(c)
            i = s.index(after: i)
        }
        return result
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "laquo": "«", "raquo": "»",
        "bdquo": "„", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "middot": "·",
        "copy": "©", "reg": "®", "trade": "™",
    ]

    private static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#") {
            let body = entity.dropFirst()
            let value: UInt32?
            if body.hasPrefix("x") || body.hasPrefix("X") {
                value = UInt32(body.dropFirst(), radix: 16)
            } else {
                value = UInt32(body)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return named[entity.lowercased()]
    }
}
