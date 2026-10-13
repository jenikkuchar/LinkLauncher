import SwiftUI

/// Okno „Spravovat odkazy“: sidebar se štítky + tabulka odkazů.
@MainActor
struct ManagerView: View {
    @ObservedObject var store: LinkStore
    let favicons: FaviconStore
    @ObservedObject var state: ManagerState
    let onImport: () -> Void

    @State private var sidebarSelection: SidebarItem? = .all
    @State private var selection = Set<Link.ID>()
    @State private var sortOrder = [KeyPathComparator(\Link.title, comparator: .localizedStandard)]
    @State private var searchText = ""
    @State private var confirmDelete = false
    @State private var tagSheet: TagSheet?
    @State private var tagToDelete: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            table
        }
        .frame(minWidth: 760, minHeight: 420)
        .sheet(item: $state.editorRequest) { request in
            LinkEditorView(mode: request.mode, store: store, favicons: favicons) {
                state.editorRequest = nil
            }
        }
        .sheet(item: $tagSheet) { sheet in
            TagSheetView(sheet: sheet, store: store, selection: selection) { newSidebarTag in
                if let newSidebarTag { sidebarSelection = .tag(newSidebarTag) }
                tagSheet = nil
            }
        }
        .confirmationDialog(
            "Smazat \(linksCountText(selection.count))?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Smazat", role: .destructive) {
                store.delete(ids: selection)
                selection.removeAll()
            }
        } message: {
            Text("Tuto akci nelze vrátit.")
        }
        .confirmationDialog(
            "Smazat štítek „\(tagToDelete ?? "")“?",
            isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Smazat štítek", role: .destructive) {
                if let tag = tagToDelete {
                    store.deleteTag(tag)
                    if sidebarSelection == .tag(tag) { sidebarSelection = .all }
                }
                tagToDelete = nil
            }
        } message: {
            Text("Štítek se odebere ze všech odkazů. Odkazy zůstanou zachovány.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        let tagCounts = store.tagCounts
        return List(selection: $sidebarSelection) {
            Section {
                Label("Vše", systemImage: "tray.full")
                    .badge(store.links.count)
                    .tag(SidebarItem.all)
                Label("Bez štítku", systemImage: "tag.slash")
                    .badge(store.links.filter { $0.tags.isEmpty }.count)
                    .tag(SidebarItem.untagged)
            }
            Section("Štítky") {
                ForEach(tagCounts, id: \.tag) { item in
                    Label(item.tag, systemImage: "tag")
                        .badge(item.count)
                        .tag(SidebarItem.tag(item.tag))
                        .contextMenu {
                            Button("Přejmenovat…") { tagSheet = .rename(item.tag) }
                            Button("Sloučit do…") { tagSheet = .merge(item.tag) }
                            Divider()
                            Button("Smazat štítek…", role: .destructive) { tagToDelete = item.tag }
                        }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .onChange(of: store.links) { _, _ in
            // Štítek mohl zmizet (smazání, přejmenování, ruční úprava souboru).
            if case .tag(let tag) = sidebarSelection, !store.links.contains(where: { $0.tags.contains(tag) }) {
                sidebarSelection = .all
            }
            let ids = Set(store.links.map(\.id))
            selection = selection.filter(ids.contains)
        }
    }

    // MARK: - Tabulka

    private var displayedLinks: [Link] {
        var result = store.links
        switch sidebarSelection ?? .all {
        case .all: break
        case .untagged: result = result.filter { $0.tags.isEmpty }
        case .tag(let tag): result = result.filter { $0.tags.contains(tag) }
        }
        let terms = searchText.split(whereSeparator: { $0.isWhitespace }).map { TextFolding.fold(String($0)) }
        if !terms.isEmpty {
            result = result.filter { link in
                let haystack = TextFolding.fold(link.title + " " + link.url + " " + link.tags.joined(separator: " "))
                return terms.allSatisfy { haystack.contains($0) }
            }
        }
        return result.sorted(using: sortOrder)
    }

    private var table: some View {
        Table(displayedLinks, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Název", value: \.title) { link in
                HStack(spacing: 6) {
                    FaviconCell(url: link.url, favicons: favicons)
                    Text(link.displayTitle)
                        .foregroundStyle(link.title.isEmpty ? Color.secondary : Color.primary)
                }
            }
            .width(min: 160, ideal: 240)
            TableColumn("URL", value: \.url) { link in
                Text(link.url)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
            }
            .width(min: 160, ideal: 280)
            TableColumn("Štítky", value: \.tagsSortKey) { link in
                HStack(spacing: 4) {
                    ForEach(link.tags, id: \.self) { TagChip(tag: $0) }
                }
            }
            .width(min: 100, ideal: 180)
            TableColumn("Naposledy otevřeno", value: \.lastOpenedSortKey) { link in
                if let date = link.lastOpenedAt {
                    Text(date, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                        .help(date.formatted(date: .long, time: .shortened))
                } else {
                    Text("–").foregroundStyle(.tertiary)
                }
            }
            .width(min: 110, ideal: 140)
        }
        .contextMenu(forSelectionType: Link.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            if let id = ids.first { state.editorRequest = EditorRequest(mode: .edit(id)) }
        }
        .onDeleteCommand {
            if !selection.isEmpty { confirmDelete = true }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Hledat odkazy")
        .toolbar { toolbar }
        .navigationTitle(navigationTitle)
        .navigationSubtitle(linksCountText(displayedLinks.count))
    }

    private var navigationTitle: String {
        switch sidebarSelection ?? .all {
        case .all: return "Vše"
        case .untagged: return "Bez štítku"
        case .tag(let tag): return "#\(tag)"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.editorRequest = EditorRequest(mode: .new(prefillURL: nil))
            } label: {
                Label("Přidat odkaz", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Přidat odkaz (⌘N)")

            Button {
                if let id = selection.first { state.editorRequest = EditorRequest(mode: .edit(id)) }
            } label: {
                Label("Upravit", systemImage: "pencil")
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(selection.count != 1)
            .help("Upravit vybraný odkaz (⌘E)")

            tagMenu(for: selection)
                .disabled(selection.isEmpty)

            Button {
                confirmDelete = true
            } label: {
                Label("Smazat", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
            .help("Smazat vybrané odkazy")

            Button(action: onImport) {
                Label("Importovat záložky", systemImage: "square.and.arrow.down")
            }
            .help("Importovat záložky z HTML exportu (Chrome, Safari, Firefox)")
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<Link.ID>) -> some View {
        if ids.count == 1, let id = ids.first, let link = store.link(withID: id) {
            Button("Otevřít v prohlížeči") {
                if let url = URL(string: link.url) {
                    NSWorkspace.shared.open(url)
                    store.recordOpen(id)
                }
            }
            Button("Kopírovat URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url, forType: .string)
            }
            Button("Upravit…") { state.editorRequest = EditorRequest(mode: .edit(id)) }
            Divider()
        }
        if !ids.isEmpty {
            tagMenu(for: ids)
            Divider()
            Button("Smazat \(linksCountText(ids.count))…", role: .destructive) {
                selection = ids
                confirmDelete = true
            }
        }
    }

    /// Všechny existující štítky s fajfkou u přiřazených; kliknutí štítek přidá/odebere.
    /// U více odkazů, kde štítek má jen část, je uveden počet a kliknutí ho přidá všem.
    private func tagMenu(for ids: Set<Link.ID>) -> some View {
        let selectedLinks = store.links.filter { ids.contains($0.id) }
        let allTags = store.allTags
        return Menu {
            ForEach(allTags, id: \.self) { tag in
                let count = selectedLinks.filter { $0.tags.contains(tag) }.count
                let isOn = !selectedLinks.isEmpty && count == selectedLinks.count
                Toggle(isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        if newValue {
                            store.addTag(tag, to: ids)
                        } else {
                            store.removeTag(tag, from: ids)
                        }
                    }
                )) {
                    if count > 0 && !isOn {
                        Text("\(tag)  (\(count) z \(selectedLinks.count))")
                    } else {
                        Text(tag)
                    }
                }
            }
            if !allTags.isEmpty {
                Divider()
            }
            Button("Nový štítek…") {
                selection = ids
                tagSheet = .addToSelection
            }
        } label: {
            Label("Štítky", systemImage: "tag")
        }
        .help("Přiřadit nebo odebrat štítky vybraným odkazům")
    }
}

/// Favicon v buňce tabulky (načítá se líně při zobrazení řádku).
@MainActor
struct FaviconCell: View {
    let url: String
    @ObservedObject var favicons: FaviconStore

    var body: some View {
        FaviconView(image: URLTools.host(of: url).flatMap { favicons.image(forHost: $0) }, size: 16)
            .task(id: url) { await favicons.load(for: url) }
    }
}
