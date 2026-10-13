import Foundation

/// Uzel stromu záložek (složka nebo odkaz).
struct BookmarkNode: Identifiable, Hashable {
    let id: String
    let name: String
    /// `nil` pro složky.
    let url: String?
    let children: [BookmarkNode]
    /// Kořenová složka (celý soubor, Panel záložek) – její název se nepoužívá jako štítek.
    let isRoot: Bool

    var isFolder: Bool { url == nil }
    /// Pro hierarchický `List` – odkazy nemají potomky.
    var optionalChildren: [BookmarkNode]? { isFolder ? children : nil }

    /// Všechny odkazy (listy) v podstromu.
    var allBookmarks: [BookmarkNode] {
        isFolder ? children.flatMap(\.allBookmarks) : [self]
    }
}
