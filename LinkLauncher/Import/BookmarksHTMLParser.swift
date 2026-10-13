import Foundation

enum BookmarksImportError: LocalizedError {
    case invalidFormat
    case unreadable

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Soubor není HTML export záložek (formát Netscape Bookmark File)."
        case .unreadable: return "Soubor se nepodařilo přečíst."
        }
    }
}

/// Parser HTML exportu záložek (formát „Netscape Bookmark File“), který exportuje
/// Chrome (Správce záložek → ⋮ → Exportovat záložky) i Safari, Firefox nebo Edge.
enum BookmarksHTMLParser {
    static func parse(data: Data) throws -> [BookmarkNode] {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw BookmarksImportError.unreadable
        }
        return try parse(html: html)
    }

    private final class Folder {
        let id: String
        let name: String
        let isRoot: Bool
        var children: [Child] = []

        init(id: String, name: String, isRoot: Bool) {
            self.id = id
            self.name = name
            self.isRoot = isRoot
        }

        func node() -> BookmarkNode {
            BookmarkNode(
                id: id,
                name: name,
                url: nil,
                children: children.map {
                    switch $0 {
                    case .folder(let folder): return folder.node()
                    case .link(let link): return link
                    }
                },
                isRoot: isRoot
            )
        }
    }

    private enum Child {
        case folder(Folder)
        case link(BookmarkNode)
    }

    static func parse(html: String) throws -> [BookmarkNode] {
        guard html.range(of: "<dl", options: .caseInsensitive) != nil else {
            throw BookmarksImportError.invalidFormat
        }

        var counter = 0
        func nextID() -> String {
            counter += 1
            return "html-\(counter)"
        }

        let root = Folder(id: "html-root", name: "Všechny záložky", isRoot: true)
        // Zásobník otevřených `<DL>` – každý patří nějaké složce.
        var stack: [Folder] = []
        // Složka z posledního `<H3>`, jejíž obsah začne následujícím `<DL>`.
        var pending: Folder?
        var linkCount = 0
        var index = html.startIndex

        while let lt = html[index...].firstIndex(of: "<") {
            guard let gt = html[lt...].firstIndex(of: ">") else { break }
            let tag = html[html.index(after: lt)..<gt]
            index = html.index(after: gt)
            let name = tag.prefix { !$0.isWhitespace && $0 != ">" }.lowercased()

            switch name {
            case "h1":
                // Titulek dokumentu – nic nedělá.
                break
            case "h3":
                let (text, end) = innerText(in: html, from: index, closing: "</h3")
                index = end
                let isToolbar = HTMLTitleParser.attribute("PERSONAL_TOOLBAR_FOLDER", in: String(tag))?.lowercased() == "true"
                let folder = Folder(id: nextID(), name: text, isRoot: isToolbar && stack.count <= 1)
                (stack.last ?? root).children.append(.folder(folder))
                pending = folder
            case "dl":
                if stack.isEmpty {
                    stack.append(root)
                } else if let folder = pending {
                    stack.append(folder)
                } else {
                    stack.append(stack[stack.count - 1])
                }
                pending = nil
            case "/dl":
                if !stack.isEmpty { stack.removeLast() }
            case "a":
                let (text, end) = innerText(in: html, from: index, closing: "</a")
                index = end
                guard let href = HTMLTitleParser.attribute("HREF", in: String(tag)) else { continue }
                let url = HTMLTitleParser.decodeEntities(href).trimmingCharacters(in: .whitespacesAndNewlines)
                let link = BookmarkNode(id: nextID(), name: text, url: url, children: [], isRoot: false)
                (stack.last ?? root).children.append(.link(link))
                linkCount += 1
                pending = nil
            default:
                break
            }
        }

        guard linkCount > 0 || !root.children.isEmpty else { throw BookmarksImportError.invalidFormat }
        return [root.node()]
    }

    /// Text do uzavíracího tagu (dekódované entity, sloučené mezery) a index za ním.
    private static func innerText(in html: String, from start: String.Index, closing: String) -> (String, String.Index) {
        guard let close = html.range(of: closing, options: .caseInsensitive, range: start..<html.endIndex) else {
            return ("", start)
        }
        let raw = String(html[start..<close.lowerBound])
        let text = HTMLTitleParser.decodeEntities(raw)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let end = html[close.upperBound...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
        return (text, end)
    }
}
