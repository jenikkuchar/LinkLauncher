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

@MainActor
final class BookmarksImportModel: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var roots: [BookmarkNode] = []
    @Published private(set) var selected = Set<String>()
    @Published var folderTagMode: FolderTagMode = .nearestFolder
    @Published var extraTag = ""
    @Published var errorMessage: String?

    /// ID složky → ID všech odkazů v jejím podstromu.
    private var leavesByFolder: [String: [String]] = [:]

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
        load(url)
    }

    func load(_ url: URL) {
        selected.removeAll()
        leavesByFolder.removeAll()
        fileURL = url
        do {
            let data = try Data(contentsOf: url)
            roots = try BookmarksHTMLParser.parse(data: data)
            errorMessage = nil
            for root in roots { indexLeaves(root) }
        } catch {
            roots = []
            errorMessage = error.localizedDescription
        }
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
        selected.removeAll()

        var summary = "Přidáno: \(plan.links.count), přeskočeno: \(plan.skipped)"
        var details: [String] = []
        if plan.skippedDuplicates > 0 { details.append("duplicitní URL: \(plan.skippedDuplicates)") }
        if plan.skippedUnsupported > 0 { details.append("nepodporované adresy: \(plan.skippedUnsupported)") }
        if !details.isEmpty { summary += " (\(details.joined(separator: ", ")))" }
        return summary
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

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }

            if model.roots.isEmpty {
                instructions
            } else {
                List(model.roots, children: \.optionalChildren) { node in
                    BookmarkRow(node: node, state: model.state(of: node)) {
                        model.toggle(node)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 240)

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
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.isFileURL }) else { return false }
            model.load(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .alert("Import dokončen", isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })) {
            Button("OK") { summary = nil }
        } message: {
            Text(summary ?? "")
        }
    }

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
