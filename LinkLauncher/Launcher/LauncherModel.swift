import AppKit
import Combine

enum LauncherLayout {
    static let width: CGFloat = 680
    static let searchHeight: CGFloat = 56
    static let suggestionsHeight: CGFloat = 34
    static let rowHeight: CGFloat = 44
    static let listPadding: CGFloat = 6
    /// 9 viditelných řádků = přesně ty, které mají zkratku ⌘1–⌘9; další po scrollování.
    static let maxVisibleRows = 9
    static let emptyHeight: CGFloat = 44
    static let tagPickerHeight: CGFloat = 48
}

/// Štítek v řadě výběru (Tab) s počtem odkazů.
struct PickerTag: Identifiable, Hashable {
    let tag: String
    let count: Int
    var id: String { tag }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    @Published private(set) var results: [Link] = []
    @Published var selectedIndex = 0
    @Published private(set) var tagSuggestions: [String] = []

    /// Štítky zvolené přes Tab – zobrazují se jako tokeny v poli a filtrují výsledky (AND).
    @Published private(set) var activeTags: [String] = []
    /// Řada štítků pod vyhledáváním (Tab). Text v poli ji pak filtruje.
    @Published private(set) var isTagPickerOpen = false
    @Published private(set) var pickerTags: [PickerTag] = []
    @Published private(set) var pickerIndex = 0
    private var lastPickerFilter = ""
    /// Zvyšuje se při každém zobrazení – pole si podle něj vezme fokus.
    @Published private(set) var focusToken = 0
    @Published private(set) var flashMessage: String?
    /// Barvy štítků (kopie z úložiště pro zobrazení).
    @Published private(set) var tagColors: [String: String] = [:]

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
        tagColors = store.tagColors
        store.$tagColors
            .sink { [weak self] colors in self?.tagColors = colors }
            .store(in: &cancellables)
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
        if isTagPickerOpen {
            h += LauncherLayout.tagPickerHeight
        } else if !tagSuggestions.isEmpty {
            h += LauncherLayout.suggestionsHeight
        }
        if !results.isEmpty {
            let rows = CGFloat(min(results.count, LauncherLayout.maxVisibleRows))
            h += 1 + rows * LauncherLayout.rowHeight + LauncherLayout.listPadding * 2
        } else if !query.isEmpty || !activeTags.isEmpty || store.links.isEmpty {
            h += 1 + LauncherLayout.emptyHeight
        }
        return h
    }

    func prepareForShow() {
        flashMessage = nil
        activeTags = []
        isTagPickerOpen = false
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
        var parsed: ParsedQuery
        if isTagPickerOpen {
            // Text v poli filtruje štítky; výsledky ukazují náhled pro zvýrazněný štítek.
            updatePickerTags()
            parsed = ParsedQuery(terms: [], tagFilters: [], pendingTagPrefix: nil)
            if let highlighted = highlightedPickerTag {
                parsed.tagFilters.append(TextFolding.fold(highlighted))
            }
            tagSuggestions = []
        } else {
            parsed = QueryParser.parse(query)
            tagSuggestions = engine.tagSuggestions(for: parsed)
        }
        for tag in activeTags {
            let folded = TextFolding.fold(tag)
            if !parsed.tagFilters.contains(folded) { parsed.tagFilters.append(folded) }
        }
        results = engine.search(parsed, limit: Self.maxResults)
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

    // MARK: - Výběr štítků (Tab)

    var highlightedPickerTag: String? {
        pickerTags.indices.contains(pickerIndex) ? pickerTags[pickerIndex].tag : nil
    }

    /// Tab: doplní rozepsaný `#štítek`, jinak otevře řadu štítků, v ní pak vybraný štítek použije.
    func handleTab(backwards: Bool = false) {
        if isTagPickerOpen {
            if backwards {
                movePicker(by: -1)
            } else {
                applyHighlightedTag()
            }
        } else if !tagSuggestions.isEmpty {
            completeTag()
        } else {
            openTagPicker()
        }
    }

    func openTagPicker() {
        guard !engine.tagCounts.isEmpty else {
            flash("Zatím žádné štítky")
            return
        }
        isTagPickerOpen = true
        pickerIndex = 0
        lastPickerFilter = ""
        // Rozepsaný text (bez #) rovnou poslouží jako filtr štítků.
        let filter = query.trimmingCharacters(in: .whitespaces)
        if filter.hasPrefix("#") || filter.contains(" ") {
            query = ""
        }
        refresh()
    }

    func closeTagPicker() {
        guard isTagPickerOpen else { return }
        isTagPickerOpen = false
        if query.isEmpty { refresh() } else { query = "" }
    }

    func movePicker(by delta: Int) {
        guard !pickerTags.isEmpty else { return }
        pickerIndex = (pickerIndex + delta + pickerTags.count) % pickerTags.count
        refresh()
    }

    func applyHighlightedTag() {
        guard let tag = highlightedPickerTag else { return }
        applyTag(tag)
    }

    func applyTag(_ tag: String) {
        if !activeTags.contains(tag) { activeTags.append(tag) }
        isTagPickerOpen = false
        if query.isEmpty { refresh() } else { query = "" }
    }

    func removeActiveTag(_ tag: String) {
        activeTags.removeAll { $0 == tag }
        refresh()
    }

    /// ⌫ v prázdném poli odebere poslední štítek. Vrací, zda něco odebral.
    func removeLastActiveTag() -> Bool {
        guard query.isEmpty, !isTagPickerOpen, let last = activeTags.last else { return false }
        removeActiveTag(last)
        return true
    }

    private func updatePickerTags() {
        let available = engine.tagCounts
            .filter { !activeTags.contains($0.tag) }
            .map { PickerTag(tag: $0.tag, count: $0.count) }
        var filter = TextFolding.fold(query.trimmingCharacters(in: .whitespaces))
        while filter.hasPrefix("#") { filter.removeFirst() }
        let previous = highlightedPickerTag
        if filter.isEmpty {
            pickerTags = available
        } else {
            let prefix = available.filter { TextFolding.fold($0.tag).hasPrefix(filter) }
            let contains = available.filter {
                let folded = TextFolding.fold($0.tag)
                return !folded.hasPrefix(filter) && folded.contains(filter)
            }
            pickerTags = prefix + contains
        }
        if filter != lastPickerFilter {
            // Nový filtr – zvýraznit nejlepší shodu.
            lastPickerFilter = filter
            pickerIndex = 0
        } else if let previous, let i = pickerTags.firstIndex(where: { $0.tag == previous }) {
            pickerIndex = i
        } else if !pickerTags.indices.contains(pickerIndex) {
            pickerIndex = 0
        }
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
