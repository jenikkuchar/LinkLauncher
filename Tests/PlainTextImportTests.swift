import XCTest
@testable import LinkLauncher

final class PlainTextImportTests: XCTestCase {
    private func line(_ s: String) -> PlainTextBookmarksParser.ParsedLine? {
        PlainTextBookmarksParser.parseLine(s)
    }

    func testURLWithTitleAndHashTags() {
        XCTAssertEqual(
            line("https://jira.example.com Jira projekt #Práce #pm"),
            .init(title: "Jira projekt", url: "https://jira.example.com", tags: ["práce", "pm"])
        )
        XCTAssertEqual(
            line("Jira – https://jira.example.com #práce"),
            .init(title: "Jira", url: "https://jira.example.com", tags: ["práce"])
        )
    }

    func testURLOnlyAndWithoutScheme() {
        XCTAssertEqual(line("https://example.com/a?b=1"), .init(title: "", url: "https://example.com/a?b=1", tags: []))
        XCTAssertEqual(line("github.com/apple"), .init(title: "", url: "https://github.com/apple", tags: []))
        XCTAssertEqual(line("<https://example.com>,"), .init(title: "", url: "https://example.com", tags: []))
    }

    func testColumns() {
        XCTAssertEqual(
            line("Jira | https://jira.example.com | práce, pm"),
            .init(title: "Jira", url: "https://jira.example.com", tags: ["práce", "pm"])
        )
        XCTAssertEqual(
            line("https://jira.example.com\tJira\tpráce pm"),
            .init(title: "Jira", url: "https://jira.example.com", tags: ["práce", "pm"])
        )
    }

    func testMarkdownLinkAndBullets() {
        XCTAssertEqual(
            line("- [Jira board](https://jira.example.com/board) #práce"),
            .init(title: "Jira board", url: "https://jira.example.com/board", tags: ["práce"])
        )
        XCTAssertEqual(
            line("2. Wiki https://wiki.example.com"),
            .init(title: "Wiki", url: "https://wiki.example.com", tags: [])
        )
    }

    func testLinesWithoutURL() {
        XCTAssertNil(line("Jen poznámka bez odkazu, např. v1.2"))
        XCTAssertNil(line("#práce #pm"))
    }

    func testSectionsAndSkippedLines() throws {
        let text = """
        // Moje odkazy
        https://github.com GitHub #vývoj

        # Práce
        Jira | https://jira.example.com | pm
        ## Interní Nástroje
        https://wiki.example.com Wiki
        Nástroje:
        https://ci.example.com CI
        Monitoring:
        https://grafana.example.com Grafana
        # Doma
        https://example.com/recepty Recepty #jídlo
        tohle není odkaz
        """
        let result = PlainTextBookmarksParser.parse(text)
        XCTAssertEqual(result.skippedLines, 1)
        XCTAssertEqual(result.linkCount, 6)

        let root = try XCTUnwrap(result.roots.first)
        XCTAssertTrue(root.isRoot)
        XCTAssertEqual(root.children.map(\.name), ["GitHub", "Práce", "Doma"])
        let prace = root.children[1]
        XCTAssertEqual(prace.children.map(\.name), ["Jira", "Interní Nástroje"])
        let tools = prace.children[1]
        XCTAssertEqual(tools.children.map(\.name), ["Wiki", "Nástroje", "Monitoring"])
        XCTAssertEqual(tools.children[1].children.map(\.name), ["CI"])
        XCTAssertEqual(tools.children[2].children.map(\.name), ["Grafana"])
    }

    func testImportPlanCombinesFolderAndLineTags() throws {
        let text = """
        # Práce
        Jira | https://jira.example.com | pm
        https://github.com GitHub #vývoj #práce
        """
        let roots = PlainTextBookmarksParser.parse(text).roots
        let all = Set(roots.flatMap(\.allBookmarks).map(\.id))
        var options = ChromeImportOptions()
        options.extraTag = "import"
        let plan = ChromeImportPlanner.plan(roots: roots, selectedIDs: all, options: options, existingURLs: [])
        XCTAssertEqual(plan.links.map(\.title), ["Jira", "GitHub"])
        XCTAssertEqual(plan.links.map(\.tags), [["práce", "pm", "import"], ["práce", "vývoj", "import"]])
    }

    func testEmptyText() {
        let result = PlainTextBookmarksParser.parse("\n  \n// nic\n")
        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertEqual(result.skippedLines, 0)
    }
}
