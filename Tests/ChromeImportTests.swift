import XCTest
@testable import LinkLauncher

final class ChromeImportTests: XCTestCase {
    private let bookmarksJSON = """
    {
      "checksum": "abc",
      "roots": {
        "bookmark_bar": {
          "children": [
            { "id": "10", "name": "GitHub", "type": "url", "url": "https://github.com/" },
            {
              "id": "20", "name": "Práce", "type": "folder",
              "children": [
                { "id": "21", "name": "Jira", "type": "url", "url": "https://example.atlassian.net" },
                {
                  "id": "30", "name": "Interní Nástroje", "type": "folder",
                  "children": [
                    { "id": "31", "name": "Wiki", "type": "url", "url": "https://wiki.example.com" },
                    { "id": "32", "name": "Bookmarklet", "type": "url", "url": "javascript:alert(1)" }
                  ]
                }
              ]
            }
          ],
          "id": "1", "name": "Panel záložek", "type": "folder"
        },
        "other": {
          "children": [
            { "id": "40", "name": "Jira znovu", "type": "url", "url": "https://example.atlassian.net/" }
          ],
          "id": "2", "name": "Ostatní záložky", "type": "folder"
        },
        "synced": { "children": [], "id": "3", "name": "Mobilní záložky", "type": "folder" }
      },
      "version": 1
    }
    """

    private func roots() throws -> [BookmarkNode] {
        try ChromeBookmarksParser.parse(data: Data(bookmarksJSON.utf8))
    }

    func testParsesTree() throws {
        let roots = try roots()
        XCTAssertEqual(roots.map(\.name), ["Panel záložek", "Ostatní záložky"]) // prázdný „synced“ vynechán
        XCTAssertTrue(roots.allSatisfy(\.isRoot))
        let bar = roots[0]
        XCTAssertEqual(bar.children.map(\.name), ["GitHub", "Práce"])
        XCTAssertFalse(bar.children[0].isFolder)
        XCTAssertEqual(bar.children[0].url, "https://github.com/")
        XCTAssertTrue(bar.children[1].isFolder)
        XCTAssertEqual(bar.children[1].children[1].children.map(\.id), ["31", "32"])
        XCTAssertEqual(bar.allBookmarks.count, 4)
    }

    func testInvalidFileThrows() {
        XCTAssertThrowsError(try ChromeBookmarksParser.parse(data: Data("{}".utf8)))
        XCTAssertThrowsError(try ChromeBookmarksParser.parse(data: Data("nonsense".utf8)))
    }

    func testProfileNamesFromLocalState() {
        let json = """
        { "profile": { "info_cache": {
            "Default": { "name": "Osobní" },
            "Profile 1": { "name": "Práce" }
        } } }
        """
        XCTAssertEqual(ChromeProfileLocator.profileNames(fromLocalState: Data(json.utf8)), ["Default": "Osobní", "Profile 1": "Práce"])
        XCTAssertEqual(ChromeProfileLocator.profileNames(fromLocalState: Data("[]".utf8)), [:])
    }

    func testProfilesDiscovery() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        for profile in ["Default", "Profile 2", "Profile 10", "System Profile", "Profile 3"] {
            let p = dir.appendingPathComponent(profile)
            try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
            if profile != "Profile 3" {
                try Data(bookmarksJSON.utf8).write(to: p.appendingPathComponent("Bookmarks"))
            }
        }
        try Data(#"{"profile":{"info_cache":{"Profile 2":{"name":"Práce"}}}}"#.utf8)
            .write(to: dir.appendingPathComponent("Local State"))

        let profiles = ChromeProfileLocator.profiles(in: dir)
        XCTAssertEqual(profiles.map(\.directoryName), ["Default", "Profile 2", "Profile 10"])
        XCTAssertEqual(profiles.map(\.displayName), ["Default", "Práce", "Profile 10"])
    }

    func testImportNearestFolderTags() throws {
        let roots = try roots()
        let all = Set(roots.flatMap(\.allBookmarks).map(\.id))
        let plan = ChromeImportPlanner.plan(roots: roots, selectedIDs: all, options: ChromeImportOptions(), existingURLs: [])
        XCTAssertEqual(plan.links.map(\.title), ["GitHub", "Jira", "Wiki"])
        XCTAssertEqual(plan.links.map(\.tags), [[], ["práce"], ["interní-nástroje"]])
        XCTAssertEqual(plan.skippedDuplicates, 1) // „Jira znovu“ – stejná URL s lomítkem
        XCTAssertEqual(plan.skippedUnsupported, 1) // javascript:
        XCTAssertEqual(plan.skipped, 2)
    }

    func testImportFullPathAndExtraTag() throws {
        let roots = try roots()
        var options = ChromeImportOptions()
        options.folderTagMode = .fullPath
        options.extraTag = "Chrome"
        let plan = ChromeImportPlanner.plan(roots: roots, selectedIDs: ["31", "10"], options: options, existingURLs: [])
        XCTAssertEqual(plan.links.map(\.title), ["GitHub", "Wiki"])
        XCTAssertEqual(plan.links.map(\.tags), [["chrome"], ["práce", "interní-nástroje", "chrome"]])
    }

    func testImportWithoutFolderTags() throws {
        var options = ChromeImportOptions()
        options.folderTagMode = .none
        let plan = ChromeImportPlanner.plan(roots: try roots(), selectedIDs: ["21"], options: options, existingURLs: [])
        XCTAssertEqual(plan.links.first?.tags, [])
    }

    func testImportSkipsExistingURLs() throws {
        let plan = ChromeImportPlanner.plan(
            roots: try roots(),
            selectedIDs: ["10", "21"],
            options: ChromeImportOptions(),
            existingURLs: ["https://www.github.com"]
        )
        XCTAssertEqual(plan.links.map(\.title), ["Jira"])
        XCTAssertEqual(plan.skippedDuplicates, 1)
    }

    func testOnlySelectedImported() throws {
        let plan = ChromeImportPlanner.plan(roots: try roots(), selectedIDs: [], options: ChromeImportOptions(), existingURLs: [])
        XCTAssertTrue(plan.links.isEmpty)
        XCTAssertEqual(plan.skipped, 0)
    }
}
