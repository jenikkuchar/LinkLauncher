import AppKit
import Combine

enum LauncherLayout {
    static let width: CGFloat = 680
    static let searchHeight: CGFloat = 56
    static let suggestionsHeight: CGFloat = 34
    static let rowHeight: CGFloat = 44
    static let listPadding: CGFloat = 6
    static let maxVisibleRows = 10
    static let emptyHeight: CGFloat = 44
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    @Published private(set) var results: [Link] = []
    @Published var selectedIndex = 0
    @Published private(set) var tagSuggestions: [String] = []
    /// Zvyšuje se při každém zobrazení – pole si podle něj vezme fokus.
    @Published private(set) var focusToken = 0
    @Published private(set) var flashMessage: String?

    var onOpen: ((Link) -> Void)?
    var onEdit: ((Link) -> Void)?
    var onAdd: ((String?) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    static let maxResults = 200

    private let store: LinkStore
    private var engine: SearchEngine
    /// Index se přestaví líně – až když je potřeba (např. po `recordOpen` při skrytém panelu).
    private var engineIsStale = false
    private var cancellables = Set<AnyCancellable>()
    private var flashTask: Task<Void, Never>?

    init(store: LinkStore) {
        self.store = store
        engine = SearchEngine(links: store.links)
        store.$links
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.engineIsStale = true
                // `@Published` posílá hodnotu ve `willSet` – přestavět až po změně.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if self.isActive { self.refresh(keepSelection: true) }
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Zda je panel zobrazený (nastavuje controller).
    var isActive = false

    var selectedLink: Link? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    var contentHeight: CGFloat {
        var h = LauncherLayout.searchHeight
        if !tagSuggestions.isEmpty { h += LauncherLayout.suggestionsHeight }
        if !results.isEmpty {
            let rows = CGFloat(min(results.count, LauncherLayout.maxVisibleRows))
            h += 1 + rows * LauncherLayout.rowHeight + LauncherLayout.listPadding * 2
        } else if !query.isEmpty || store.links.isEmpty {
            h += 1 + LauncherLayout.emptyHeight
        }
        return h
    }

    func prepareForShow() {
        flashMessage = nil
        if query.isEmpty {
            refresh()
        } else {
            query = ""
        }
        focusToken += 1
    }

    func refresh(keepSelection: Bool = false) {
        if engineIsStale {
            engine = SearchEngine(links: store.links)
            engineIsStale = false
        }
        let previous = keepSelection ? selectedLink?.id : nil
        let parsed = QueryParser.parse(query)
        results = engine.search(parsed, limit: Self.maxResults)
        tagSuggestions = engine.tagSuggestions(for: parsed)
        if let previous, let i = results.firstIndex(where: { $0.id == previous }) {
            selectedIndex = i
        } else {
            selectedIndex = 0
        }
        onHeightChange?(contentHeight)
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    func open(at index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
        onOpen?(results[index])
    }

    func openSelected() {
        open(at: selectedIndex)
    }

    func copySelected() {
        guard let link = selectedLink else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(link.url, forType: .string)
        flash("URL zkopírována")
    }

    func editSelected() {
        guard let link = selectedLink else { return }
        onEdit?(link)
    }

    func addNew() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefill = URLTools.looksLikeURL(trimmed) ? URLTools.normalize(trimmed) : nil
        onAdd?(prefill)
    }

    /// Tab – doplní první navrhovaný štítek.
    func completeTag(_ tag: String? = nil) {
        guard let tag = tag ?? tagSuggestions.first else { return }
        query = QueryParser.completeTag(in: query, with: tag)
    }

    private func flash(_ message: String) {
        flashMessage = message
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.flashMessage = nil
        }
    }
}
