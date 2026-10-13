import SwiftUI

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
final class ChromeImportModel: ObservableObject {
    @Published private(set) var profiles: [ChromeProfile] = []
    @Published var selectedProfileID: String? {
        didSet { if selectedProfileID != oldValue { loadBookmarks() } }
    }
    @Published private(set) var roots: [BookmarkNode] = []
    @Published private(set) var selected = Set<String>()
    @Published var folderTagMode: FolderTagMode = .nearestFolder
    @Published var extraTag = ""
    @Published var errorMessage: String?

    /// ID složky → ID všech odkazů v jejím podstromu.
    private var leavesByFolder: [String: [String]] = [:]

    func reloadProfiles() {
        profiles = ChromeProfileLocator.profiles()
        if profiles.isEmpty {
            roots = []
            errorMessage = "Nenalezen žádný profil Chrome se záložkami v ~/Library/Application Support/Google/Chrome."
            return
        }
        errorMessage = nil
        if let current = selectedProfileID, profiles.contains(where: { $0.id == current }) {
            loadBookmarks()
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    private func loadBookmarks() {
        selected.removeAll()
        leavesByFolder.removeAll()
        guard let profile = profiles.first(where: { $0.id == selectedProfileID }) else {
            roots = []
            return
        }
        do {
            let data = try Data(contentsOf: profile.bookmarksURL)
            roots = try ChromeBookmarksParser.parse(data: data)
            errorMessage = roots.isEmpty ? "Profil neobsahuje žádné záložky." : nil
            for root in roots { indexLeaves(root) }
        } catch {
            roots = []
            errorMessage = "Záložky se nepodařilo načíst: \(error.localizedDescription)"
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
        selected = Set(roots.flatMap { leavesByFolder[$0.id] ?? [] })
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
struct ChromeImportView: View {
    @ObservedObject var store: LinkStore
    let favicons: FaviconStore
    @StateObject private var model = ChromeImportModel()
    @State private var summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    model.reloadProfiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Znovu načíst profily a záložky")
                Spacer()
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }

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
        .onAppear { model.reloadProfiles() }
        .alert("Import dokončen", isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })) {
            Button("OK") { summary = nil }
        } message: {
            Text(summary ?? "")
        }
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
