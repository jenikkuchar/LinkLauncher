import Foundation
import Combine

/// Drží odkazy v paměti, ukládá je do `links.json` a sleduje změny souboru na disku.
@MainActor
final class LinkStore: ObservableObject {
    @Published private(set) var links: [Link] = []
    /// Chyba při čtení/zápisu souboru (zobrazuje se uživateli).
    @Published private(set) var fileError: String?

    let fileURL: URL
    var directoryURL: URL { fileURL.deletingLastPathComponent() }

    /// Obsah souboru, jak ho naposledy známe (načtený nebo zapsaný) – pro ignorování vlastních zápisů.
    private var lastKnownData: Data?
    /// Soubor na disku je poškozený – nepřepisovat ho, dokud ho uživatel neopraví.
    private var isFileBroken = false
    private var lastBackedUpData: Data?
    private var watcher: DirectoryWatcher?

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkLauncher", isDirectory: true)
    }

    init(directory: URL = LinkStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("links.json")
    }

    // MARK: - Načítání a ukládání

    /// Načte soubor; pokud neexistuje, vytvoří ho s ukázkovými daty.
    func load(createSampleIfMissing: Bool = true) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            fileError = "Nelze vytvořit složku s daty: \(error.localizedDescription)"
            return
        }
        if !fm.fileExists(atPath: fileURL.path) {
            links = createSampleIfMissing ? SampleData.links : []
            save()
            return
        }
        reloadFromDisk(force: true)
    }

    /// Znovu načte soubor, pokud se změnil od posledního čtení/zápisu.
    func reloadFromDisk(force: Bool = false) {
        guard let data = try? Data(contentsOf: fileURL) else { return } // smazaný soubor – nic neměnit
        if !force, data == lastKnownData { return }
        lastKnownData = data
        do {
            let db = try LinkDatabaseCodec.decode(data)
            isFileBroken = false
            fileError = nil
            if db.links != links { links = db.links }
        } catch {
            isFileBroken = true
            let backup = makeBackup(of: data)
            var message = "Soubor links.json se nepodařilo načíst: \(LinkDatabaseCodec.describe(error))."
            if let backup { message += "\nZáloha: \(backup.lastPathComponent)" }
            message += "\nDokud soubor neopravíte, změny se neukládají."
            fileError = message
        }
    }

    func save() {
        guard !isFileBroken else { return }
        do {
            let data = try LinkDatabaseCodec.encode(LinkDatabase(links: links))
            guard data != lastKnownData else { return }
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastKnownData = data
            if fileError != nil { fileError = nil }
        } catch {
            fileError = "Nepodařilo se uložit links.json: \(error.localizedDescription)"
        }
    }

    private func makeBackup(of data: Data) -> URL? {
        guard data != lastBackedUpData else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directoryURL.appendingPathComponent("links.broken-\(formatter.string(from: Date())).json")
        do {
            try data.write(to: url, options: .atomic)
            lastBackedUpData = data
            return url
        } catch {
            return nil
        }
    }

    func startWatching() {
        guard watcher == nil else { return }
        watcher = DirectoryWatcher(url: directoryURL) { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadFromDisk()
            }
        }
    }

    // MARK: - Dotazy

    func link(withID id: Link.ID) -> Link? {
        links.first { $0.id == id }
    }

    /// Existující odkaz se stejnou URL (pro upozornění na duplicitu).
    func duplicate(of url: String, excluding id: Link.ID? = nil) -> Link? {
        let key = URLTools.duplicateKey(url)
        return links.first { $0.id != id && URLTools.duplicateKey($0.url) == key }
    }

    /// Všechny štítky s počty, seřazené abecedně.
    var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for link in links {
            for tag in link.tags { counts[tag, default: 0] += 1 }
        }
        return counts.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    var allTags: [String] { tagCounts.map(\.tag) }

    // MARK: - Úpravy

    func add(_ link: Link) {
        links.append(link)
        save()
    }

    func add(_ newLinks: [Link]) {
        guard !newLinks.isEmpty else { return }
        links.append(contentsOf: newLinks)
        save()
    }

    func update(_ link: Link) {
        guard let i = links.firstIndex(where: { $0.id == link.id }) else { return }
        var updated = link
        updated.tags = Tag.normalizeList(link.tags)
        links[i] = updated
        save()
    }

    /// Doplní název načtený z webu, pokud ho mezitím uživatel nezměnil.
    func setFetchedTitle(_ title: String, for id: Link.ID, ifCurrentTitle expected: String) {
        guard let i = links.firstIndex(where: { $0.id == id }), links[i].title == expected else { return }
        links[i].title = title
        save()
    }

    func delete(ids: Set<Link.ID>) {
        guard !ids.isEmpty else { return }
        links.removeAll { ids.contains($0.id) }
        save()
    }

    func recordOpen(_ id: Link.ID, at date: Date = Date()) {
        guard let i = links.firstIndex(where: { $0.id == id }) else { return }
        links[i].openCount += 1
        links[i].lastOpenedAt = date
        save()
    }

    func replaceAll(with newLinks: [Link]) {
        links = newLinks
        save()
    }

    /// Přidá odkazy, jejichž URL ještě neexistuje. Vrací (přidáno, přeskočeno).
    @discardableResult
    func merge(_ newLinks: [Link]) -> (added: Int, skipped: Int) {
        var keys = Set(links.map { URLTools.duplicateKey($0.url) })
        var existingIDs = Set(links.map(\.id))
        var toAdd: [Link] = []
        for var link in newLinks {
            guard keys.insert(URLTools.duplicateKey(link.url)).inserted else { continue }
            if !existingIDs.insert(link.id).inserted { link.id = UUID() }
            toAdd.append(link)
        }
        add(toAdd)
        return (toAdd.count, newLinks.count - toAdd.count)
    }

    // MARK: - Štítky

    func renameTag(_ old: String, to new: String) {
        let newTag = Tag.normalize(new)
        guard !newTag.isEmpty, newTag != old else { return }
        mutateTags { tags in
            guard let i = tags.firstIndex(of: old) else { return }
            tags[i] = newTag
        }
    }

    func deleteTag(_ tag: String) {
        mutateTags { $0.removeAll { $0 == tag } }
    }

    /// Sloučí štítek `source` do `target` (source zmizí).
    func mergeTag(_ source: String, into target: String) {
        renameTag(source, to: target)
    }

    func addTag(_ tag: String, to ids: Set<Link.ID>) {
        let tag = Tag.normalize(tag)
        guard !tag.isEmpty else { return }
        mutateTags(ids: ids) { tags in
            if !tags.contains(tag) { tags.append(tag) }
        }
    }

    func removeTag(_ tag: String, from ids: Set<Link.ID>) {
        mutateTags(ids: ids) { $0.removeAll { $0 == tag } }
    }

    private func mutateTags(ids: Set<Link.ID>? = nil, _ body: (inout [String]) -> Void) {
        var changed = false
        var newLinks = links
        for i in newLinks.indices {
            if let ids, !ids.contains(newLinks[i].id) { continue }
            var tags = newLinks[i].tags
            body(&tags)
            tags = Tag.normalizeList(tags)
            if tags != newLinks[i].tags {
                newLinks[i].tags = tags
                changed = true
            }
        }
        guard changed else { return }
        links = newLinks
        save()
    }
}
