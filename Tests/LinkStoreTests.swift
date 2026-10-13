import XCTest
@testable import LinkLauncher

final class LinkStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LinkStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    @MainActor
    func testCreatesFileWithSampleData() throws {
        let store = LinkStore(directory: dir)
        store.load()
        XCTAssertFalse(store.links.isEmpty)
        let db = try LinkDatabaseCodec.decode(Data(contentsOf: store.fileURL))
        XCTAssertEqual(db.links, store.links)
    }

    @MainActor
    func testExternalEditIsReloaded() throws {
        let store = LinkStore(directory: dir)
        store.load(createSampleIfMissing: false)
        XCTAssertTrue(store.links.isEmpty)

        let edited = LinkDatabase(links: [Link(title: "Ručně", url: "https://example.com")])
        try LinkDatabaseCodec.encode(edited).write(to: store.fileURL, options: .atomic)
        store.reloadFromDisk()
        XCTAssertEqual(store.links.map(\.title), ["Ručně"])
    }

    @MainActor
    func testBrokenFileIsNotOverwrittenAndBackedUp() throws {
        let store = LinkStore(directory: dir)
        store.load(createSampleIfMissing: false)
        store.add(Link(title: "A", url: "https://a.example.com"))

        let broken = Data("{ \"links\": [ oops".utf8)
        try broken.write(to: store.fileURL, options: .atomic)
        store.reloadFromDisk()

        XCTAssertNotNil(store.fileError)
        XCTAssertEqual(store.links.map(\.title), ["A"]) // poslední platná data zůstávají v paměti
        store.add(Link(title: "B", url: "https://b.example.com"))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), broken) // soubor nepřepsán

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("links.broken-") }
        XCTAssertEqual(backups.count, 1)

        // Po opravě souboru se změny znovu ukládají.
        try LinkDatabaseCodec.encode(LinkDatabase(links: [])).write(to: store.fileURL, options: .atomic)
        store.reloadFromDisk()
        XCTAssertNil(store.fileError)
        store.add(Link(title: "C", url: "https://c.example.com"))
        XCTAssertEqual(try LinkDatabaseCodec.decode(Data(contentsOf: store.fileURL)).links.map(\.title), ["C"])
    }

    @MainActor
    func testTagOperations() {
        let store = LinkStore(directory: dir)
        store.load(createSampleIfMissing: false)
        let a = Link(title: "A", url: "https://a.example.com", tags: ["prace", "pm"])
        let b = Link(title: "B", url: "https://b.example.com", tags: ["práce"])
        store.add([a, b])

        store.mergeTag("prace", into: "práce")
        XCTAssertEqual(store.link(withID: a.id)?.tags, ["práce", "pm"])
        XCTAssertEqual(store.tagCounts.first { $0.tag == "práce" }?.count, 2)

        store.renameTag("pm", to: "Projekty")
        XCTAssertEqual(store.link(withID: a.id)?.tags, ["práce", "projekty"])

        store.addTag("chrome", to: [a.id, b.id])
        XCTAssertEqual(store.link(withID: b.id)?.tags, ["práce", "chrome"])

        store.removeTag("práce", from: [b.id])
        XCTAssertEqual(store.link(withID: b.id)?.tags, ["chrome"])

        store.deleteTag("chrome")
        XCTAssertEqual(store.link(withID: a.id)?.tags, ["práce", "projekty"])
        XCTAssertEqual(store.link(withID: b.id)?.tags, [])
    }

    @MainActor
    func testRecordOpenAndMerge() {
        let store = LinkStore(directory: dir)
        store.load(createSampleIfMissing: false)
        let a = Link(title: "A", url: "https://a.example.com")
        store.add(a)
        store.recordOpen(a.id)
        XCTAssertEqual(store.link(withID: a.id)?.openCount, 1)
        XCTAssertNotNil(store.link(withID: a.id)?.lastOpenedAt)

        let result = store.merge([Link(title: "dup", url: "http://www.a.example.com/"), Link(title: "B", url: "https://b.example.com")])
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertNotNil(store.duplicate(of: "a.example.com"))
    }
}
