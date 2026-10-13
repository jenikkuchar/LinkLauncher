import XCTest
@testable import LinkLauncher

final class LauncherModelTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LauncherModelTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    @MainActor
    private func makeModel() -> LauncherModel {
        let store = LinkStore(directory: dir)
        store.load(createSampleIfMissing: false)
        store.add([
            Link(title: "Jira", url: "https://jira.example.com", tags: ["práce", "pm"]),
            Link(title: "Wiki", url: "https://wiki.example.com", tags: ["práce"]),
            Link(title: "Recepty", url: "https://recepty.example.com", tags: ["doma"]),
        ])
        let model = LauncherModel(store: store)
        model.isActive = true
        model.prepareForShow()
        return model
    }

    @MainActor
    func testTabOpensPickerAndAppliesTag() {
        let model = makeModel()
        XCTAssertEqual(model.results.count, 3)

        model.handleTab()
        XCTAssertTrue(model.isTagPickerOpen)
        XCTAssertEqual(model.pickerTags.map(\.tag), ["práce", "doma", "pm"]) // podle počtu, pak abecedně
        XCTAssertEqual(Set(model.results.map(\.title)), ["Jira", "Wiki"])    // náhled pro zvýrazněný štítek

        model.movePicker(by: 1)
        XCTAssertEqual(model.highlightedPickerTag, "doma")
        XCTAssertEqual(model.results.map(\.title), ["Recepty"])

        model.movePicker(by: -1)
        model.handleTab()
        XCTAssertFalse(model.isTagPickerOpen)
        XCTAssertEqual(model.activeTags, ["práce"])
        XCTAssertEqual(Set(model.results.map(\.title)), ["Jira", "Wiki"])

        model.query = "jira"
        XCTAssertEqual(model.results.map(\.title), ["Jira"])
    }

    @MainActor
    func testTypingFiltersPicker() {
        let model = makeModel()
        model.handleTab()
        model.query = "dom"
        XCTAssertEqual(model.pickerTags.map(\.tag), ["doma"])
        model.applyHighlightedTag()
        XCTAssertEqual(model.activeTags, ["doma"])
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.results.map(\.title), ["Recepty"])
    }

    @MainActor
    func testBackspaceRemovesLastTagAndEscapeClosesPicker() {
        let model = makeModel()
        model.handleTab()
        model.applyHighlightedTag()
        model.handleTab()
        XCTAssertFalse(model.pickerTags.map(\.tag).contains("práce")) // už použitý štítek se nenabízí
        model.closeTagPicker()
        XCTAssertFalse(model.isTagPickerOpen)
        XCTAssertEqual(model.activeTags, ["práce"])

        XCTAssertTrue(model.removeLastActiveTag())
        XCTAssertEqual(model.activeTags, [])
        XCTAssertEqual(model.results.count, 3)
        XCTAssertFalse(model.removeLastActiveTag())
    }

    @MainActor
    func testTabCompletesHashTagFirst() {
        let model = makeModel()
        model.query = "#pr"
        model.handleTab()
        XCTAssertFalse(model.isTagPickerOpen)
        XCTAssertEqual(model.query, "#práce ")
    }
}
