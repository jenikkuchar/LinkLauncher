import Foundation

enum ChromeBookmarksError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Soubor Bookmarks nemá očekávaný formát."
        }
    }
}

/// Parser souboru `Bookmarks` (JSON) z profilu Chrome.
enum ChromeBookmarksParser {
    private struct RawFile: Decodable {
        let roots: [String: RawNode]
    }

    private final class RawNode: Decodable {
        let id: String?
        let guid: String?
        let name: String?
        let type: String?
        let url: String?
        let children: [RawNode]?
    }

    /// Pořadí kořenů jako v Chrome.
    private static let rootOrder = ["bookmark_bar", "other", "synced"]
    private static let rootFallbackNames = [
        "bookmark_bar": "Panel záložek",
        "other": "Ostatní záložky",
        "synced": "Mobilní záložky",
    ]

    static func parse(data: Data) throws -> [BookmarkNode] {
        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: data)
        } catch {
            throw ChromeBookmarksError.invalidFormat
        }
        let keys = rootOrder.filter { file.roots[$0] != nil }
            + file.roots.keys.filter { !rootOrder.contains($0) }.sorted()
        var counter = 0
        return keys.compactMap { key -> BookmarkNode? in
            guard let raw = file.roots[key], raw.children != nil else { return nil }
            let name = (raw.name?.isEmpty == false ? raw.name! : rootFallbackNames[key]) ?? key
            let node = convert(raw, fallbackID: "root-\(key)", name: name, isRoot: true, counter: &counter)
            // Prázdné kořeny (např. mobilní záložky) nezobrazovat.
            return node.children.isEmpty ? nil : node
        }
    }

    private static func convert(_ raw: RawNode, fallbackID: String? = nil, name: String? = nil, isRoot: Bool = false, counter: inout Int) -> BookmarkNode {
        counter += 1
        let id = fallbackID ?? raw.id ?? raw.guid ?? "node-\(counter)"
        let isURL = raw.type == "url" || (raw.type == nil && raw.url != nil)
        let children = isURL ? [] : (raw.children ?? []).map { convert($0, counter: &counter) }
        return BookmarkNode(
            id: id,
            name: name ?? raw.name ?? "",
            url: isURL ? (raw.url ?? "") : nil,
            children: children,
            isRoot: isRoot
        )
    }
}
