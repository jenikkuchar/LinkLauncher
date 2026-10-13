import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CheckState {
    case off, mixed, on

    var symbol: String {
        switch self {
        case .off: return "square"
        case .mixed: return "minus.square.fill"
        case .on: return "checkmark.square.fill"
        }
    }
}

enum ImportSource: String, CaseIterable, Identifiable {
    case chromeProfile
    case htmlFile
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chromeProfile: return "Profil Chrome"
        case .htmlFile: return "HTML soubor"
        case .text: return "Text"
        }
    }
}

@MainActor
final class BookmarksImportModel: ObservableObject {
    @Published var source: ImportSource = .chromeProfile {
        didSet { if source != oldValue { reloadSource() } }
    }
    @Published private(set) var profiles: [ChromeProfile] = []
    @Published var selectedProfileID: String? {
        didSet { if selectedProfileID != oldValue, source == .chromeProfile { loadProfileBookmarks() } }
    }
    @Published private(set) var fileURL: URL?
    @Published private(set) var roots: [BookmarkNode] = []
    @Published private(set) var selected = Set<String>()
    @Published var folderTagMode: FolderTagMode = .nearestFolder
    @Published var extraTag = ""
    @Published var errorMessage: String?
    /// Vložený text s odkazy (zdroj „Text“) – parsuje se při každé změně.
    @Published var plainText = "" {
        didSet { if plainText != oldValue, source == .text { parseText() } }
    }
    /// Neprázdné řádky textu, ve kterých nebyla nalezena URL.
    @Published private(set) var skippedTextLines = 0

    /// ID složky → ID všech odkazů v jejím podstromu.
    private var leavesByFolder: [String: [String]] = [:]

    /// Znovu načte aktuální zdroj (profily Chrome, nebo vybraný HTML soubor).
    func reloadSource() {
        switch source {
        case .chromeProfile:
            reloadProfiles()
        case .htmlFile:
            if let fileURL {
                loadHTML(fileURL)
            } else {
                setRoots([])
                errorMessage = nil
            }
        case .text:
            parseText()
        }
    }

    // MARK: Profil Chrome

    private func reloadProfiles() {
        profiles = ChromeProfileLocator.profiles()
        if profiles.isEmpty {
            setRoots([])
            errorMessage = "Nenalezen žádný profil Chrome se záložkami v ~/Library/Application Support/Google/Chrome. "
                + "Pokud Chrome používáte, povolte aplikaci LinkLauncher přístup v Nastavení systému → Soukromí a zabezpečení, "
                + "nebo použijte import z HTML souboru."
            return
        }
        errorMessage = nil
        if let current = selectedProfileID, profiles.contains(where: { $0.id == current }) {
            loadProfileBookmarks()
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    private func loadProfileBookmarks() {
        guard let profile = profiles.first(where: { $0.id == selectedProfileID }) else {
            setRoots([])
            return
        }
        do {
            let data = try Data(contentsOf: profile.bookmarksURL)
            setRoots(try ChromeBookmarksParser.parse(data: data))
            errorMessage = roots.isEmpty ? "Profil neobsahuje žádné záložky." : nil
        } catch {
            setRoots([])
            errorMessage = "Záložky se nepodařilo načíst: \(error.localizedDescription)"
        }
    }

    // MARK: HTML soubor

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Vyberte HTML export záložek"
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadHTML(url)
    }

    func loadHTML(_ url: URL) {
        if source != .htmlFile {
            fileURL = url
            source = .htmlFile // didSet načte soubor
            return
        }
        fileURL = url
        do {
            setRoots(try BookmarksHTMLParser.parse(data: Data(contentsOf: url)))
            errorMessage = nil
        } catch {
            setRoots([])
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Text

    private func parseText() {
        let result = PlainTextBookmarksParser.parse(plainText)
        setRoots(result.roots)
        skippedTextLines = result.skippedLines
        errorMessage = nil
        // Vložené odkazy chce uživatel typicky všechny – předvybrat.
        selectAll()
    }

    func chooseTextFile() {
        let panel = NSOpenPanel()
        panel.title = "Vyberte textový soubor s odkazy"
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadText(url)
    }

    func loadText(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            errorMessage = BookmarksImportError.unreadable.localizedDescription
            return
        }
        if source != .text { source = .text }
        plainText = text
        parseText()
    }

    /// Přetažený soubor: HTML export → HTML zdroj, ostatní → text.
    func loadDropped(_ url: URL) {
        if ["html", "htm"].contains(url.pathExtension.lowercased()) {
            loadHTML(url)
        } else {
            loadText(url)
        }
    }

    // MARK: Výběr

    private func setRoots(_ newRoots: [BookmarkNode]) {
        selected.removeAll()
        leavesByFolder.removeAll()
        roots = newRoots
        for root in newRoots { indexLeaves(root) }
    }

    @discardableResult
    private func indexLeaves(_ node: BookmarkNode) -> [String] {
        guard node.isFolder else { return [node.id] }
        let leaves = node.children.flatMap { indexLeaves($0) }
        leavesByFolder[node.id] = leaves
        return leaves
    }

    func state(of node: BookmarkNode) -> CheckState {
        guard node.isFolder else { return selected.contains(node.id) ? .on : .off }
        let leaves = leavesByFolder[node.id] ?? []
        guard !leaves.isEmpty else { return .off }
        let count = leaves.reduce(0) { $0 + (selected.contains($1) ? 1 : 0) }
        if count == 0 { return .off }
        return count == leaves.count ? .on : .mixed
    }

    /// Klik na zaškrtávátko – u složky (od)vybere všechny potomky.
    func toggle(_ node: BookmarkNode) {
        let ids = node.isFolder ? (leavesByFolder[node.id] ?? []) : [node.id]
        if state(of: node) == .on {
            selected.subtract(ids)
        } else {
            selected.formUnion(ids)
        }
    }

    func selectAll() {
        selected = Set(roots.flatMap(\.allBookmarks).map(\.id))
    }

    func selectNone() {
        selected.removeAll()
    }

    var selectedCount: Int { selected.count }

    /// Provede import a vrátí souhrn.
    func performImport(into store: LinkStore, favicons: FaviconStore) -> String {
        var options = ChromeImportOptions()
        options.folderTagMode = folderTagMode
        options.extraTag = extraTag
        let plan = ChromeImportPlanner.plan(
            roots: roots,
            selectedIDs: selected,
            options: options,
            existingURLs: store.links.map(\.url)
        )
        store.add(plan.links)
        favicons.prefetch(plan.links.map(\.url))
        fetchMissingTitles(plan.links, store: store)
        selected.removeAll()

        var summary = "Přidáno: \(plan.links.count), přeskočeno: \(plan.skipped)"
        var details: [String] = []
        if plan.skippedDuplicates > 0 { details.append("duplicitní URL: \(plan.skippedDuplicates)") }
        if plan.skippedUnsupported > 0 { details.append("nepodporované adresy: \(plan.skippedUnsupported)") }
        if !details.isEmpty { summary += " (\(details.joined(separator: ", ")))" }
        return summary
    }

    /// Odkazům bez názvu (typicky z textu) postupně načte `<title>` ze stránky.
    private func fetchMissingTitles(_ links: [Link], store: LinkStore) {
        let untitled = links.filter { $0.title.isEmpty }.prefix(100)
        guard !untitled.isEmpty else { return }
        Task { [store] in
            for link in untitled {
                if let title = await TitleFetcher.fetchTitle(for: link.url) {
                    store.setFetchedTitle(title, for: link.id, ifCurrentTitle: "")
                }
            }
        }
    }
}

@MainActor
struct BookmarksImportView: View {
    @ObservedObject var store: LinkStore
    let favicons: FaviconStore
    @StateObject private var model = BookmarksImportModel()
    @State private var summary: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Zdroj:", selection: $model.source) {
                ForEach(ImportSource.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            switch model.source {
            case .chromeProfile:
                HStack {
                    Picker("Profil:", selection: $model.selectedProfileID) {
                        ForEach(model.profiles) { profile in
                            Text(profile.displayName == profile.directoryName
                                 ? profile.displayName
                                 : "\(profile.displayName) (\(profile.directoryName))")
                                .tag(Optional(profile.id))
                        }
                    }
                    .frame(maxWidth: 360)
                    .disabled(model.profiles.isEmpty)
                    Button {
                        model.reloadSource()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Znovu načíst profily a záložky")
                    Spacer()
                }
            case .htmlFile:
                HStack {
                    Button("Vybrat soubor…") { model.chooseFile() }
                    if let url = model.fileURL {
                        Label(url.lastPathComponent, systemImage: "doc.text")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            case .text:
                textInput
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }

            if model.roots.isEmpty {
                switch model.source {
                case .htmlFile: instructions
                case .chromeProfile: Spacer(minLength: 240)
                case .text: Spacer(minLength: 120)
                }
            } else {
                List(model.roots, children: \.optionalChildren) { node in
                    BookmarkRow(node: node, state: model.state(of: node)) {
                        model.toggle(node)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: model.source == .text ? 160 : 240)

                HStack {
                    Button("Vybrat vše") { model.selectAll() }
                    Button("Zrušit výběr") { model.selectNone() }
                    Spacer()
                    Text("Vybráno: \(linksCountText(model.selectedCount))")
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                Picker("Názvy složek jako štítky:", selection: $model.folderTagMode) {
                    ForEach(FolderTagMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                TextField("Štítek pro všechny importované:", text: $model.extraTag, prompt: Text("např. chrome"))
            }

            HStack {
                Text("Duplicitní URL (již uložené) se přeskočí.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Importovat") {
                    summary = model.performImport(into: store, favicons: favicons)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedCount == 0)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { model.reloadSource() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.isFileURL }) else { return false }
            model.loadDropped(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .alert("Import dokončen", isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })) {
            Button("OK") { summary = nil }
        } message: {
            Text(summary ?? "")
        }
    }

    private var textInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Jeden odkaz na řádek, štítky jako #štítek.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Načíst ze souboru…") { model.chooseTextFile() }
            }
            TextEditor(text: $model.plainText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 130)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(alignment: .topLeading) {
                    if model.plainText.isEmpty {
                        Text(Self.textPlaceholder)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            if model.skippedTextLines > 0 {
                Text("Řádky bez URL (přeskočí se): \(model.skippedTextLines)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let textPlaceholder = """
    https://jira.example.com Jira #práce #pm
    Wiki | https://wiki.example.com | práce, dokumentace
    - [GitHub](https://github.com) #vývoj
    # Doma            ← nadpis = složka
    https://example.com/recepty Recepty
    """

    private var instructions: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Vyberte nebo sem přetáhněte HTML export záložek")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Chrome: Záložky a seznamy → Správce záložek (⌥⌘B) → ⋮ → Exportovat záložky")
                Text("Safari: Soubor → Exportovat → Záložky…")
                Text("Firefox: Záložky → Spravovat záložky → Import a záloha → Exportovat do HTML")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 240)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: 2, dash: [6]))
        )
    }
}

@MainActor
struct BookmarkRow: View {
    let node: BookmarkNode
    let state: CheckState
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Image(systemName: state.symbol)
                    .foregroundStyle(state == .off ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color.accentColor))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            if node.isFolder {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(node.name.isEmpty ? "Bez názvu" : node.name)
                Text("\(node.allBookmarks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(node.name.isEmpty ? (node.url ?? "") : node.name)
                    .lineLimit(1)
                Text(URLTools.displayDomain(node.url ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}
