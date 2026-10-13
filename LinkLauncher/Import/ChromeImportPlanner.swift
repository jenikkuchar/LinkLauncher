import Foundation

enum FolderTagMode: String, CaseIterable, Identifiable {
    case none
    case nearestFolder
    case fullPath

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Nepoužívat"
        case .nearestFolder: return "Nejbližší složka"
        case .fullPath: return "Celá cesta"
        }
    }
}

struct ChromeImportOptions {
    var folderTagMode: FolderTagMode = .nearestFolder
    /// Štítek přidaný všem importovaným odkazům (prázdný = žádný).
    var extraTag: String = ""
}

struct ChromeImportPlan {
    var links: [Link]
    /// Přeskočené duplicity (již v databázi nebo vícekrát ve výběru).
    var skippedDuplicates: Int
    /// Přeskočené nepodporované adresy (např. `javascript:`).
    var skippedUnsupported: Int

    var skipped: Int { skippedDuplicates + skippedUnsupported }
}

enum ChromeImportPlanner {
    /// Sestaví seznam odkazů k importu z vybraných záložek (`selectedIDs` = ID odkazů, ne složek).
    static func plan(
        roots: [BookmarkNode],
        selectedIDs: Set<String>,
        options: ChromeImportOptions,
        existingURLs: [String],
        now: Date = Date()
    ) -> ChromeImportPlan {
        var seen = Set(existingURLs.map(URLTools.duplicateKey))
        var plan = ChromeImportPlan(links: [], skippedDuplicates: 0, skippedUnsupported: 0)
        let extra = Tag.normalize(options.extraTag)

        func visit(_ node: BookmarkNode, path: [String]) {
            if node.isFolder {
                let childPath = node.isRoot ? path : path + [node.name]
                for child in node.children { visit(child, path: childPath) }
                return
            }
            guard selectedIDs.contains(node.id) else { return }
            guard let raw = node.url,
                  let scheme = URL(string: raw)?.scheme?.lowercased(),
                  ["http", "https", "file", "ftp"].contains(scheme),
                  let url = URLTools.normalize(raw)
            else {
                plan.skippedUnsupported += 1
                return
            }
            guard seen.insert(URLTools.duplicateKey(url)).inserted else {
                plan.skippedDuplicates += 1
                return
            }
            var tags: [String]
            switch options.folderTagMode {
            case .none: tags = []
            case .nearestFolder: tags = path.last.map { [$0] } ?? []
            case .fullPath: tags = path
            }
            if !extra.isEmpty { tags.append(extra) }
            let title = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
            plan.links.append(Link(title: title, url: url, tags: tags, createdAt: now))
        }

        for root in roots { visit(root, path: []) }
        return plan
    }
}
