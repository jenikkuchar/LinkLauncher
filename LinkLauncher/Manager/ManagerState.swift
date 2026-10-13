import Foundation

enum EditorMode: Equatable {
    case new(prefillURL: String?)
    case edit(Link.ID)
}

struct EditorRequest: Identifiable, Equatable {
    let id = UUID()
    let mode: EditorMode
}

/// Sdílený stav okna správy – umožňuje otevřít editor z launcheru (⌘E/⌘N).
@MainActor
final class ManagerState: ObservableObject {
    @Published var editorRequest: EditorRequest?
}

enum SidebarItem: Hashable {
    case all
    case untagged
    case tag(String)
}

/// České skloňování počtu odkazů.
func linksCountText(_ n: Int) -> String {
    switch n {
    case 1: return "1 odkaz"
    case 2...4: return "\(n) odkazy"
    default: return "\(n) odkazů"
    }
}

extension Link {
    var tagsSortKey: String { tags.joined(separator: ", ") }
    var lastOpenedSortKey: Date { lastOpenedAt ?? .distantPast }
}
