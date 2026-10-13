import XCTest
@testable import LinkLauncher

final class BookmarksHTMLImportTests: XCTestCase {
    private let bookmarksHTML = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <!-- This is an automatically generated file.
         It will be read and overwritten.
         DO NOT EDIT! -->
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
        <DT><H3 ADD_DATE="1700000000" LAST_MODIFIED="1700000001" PERSONAL_TOOLBAR_FOLDER="true">Panel záložek</H3>
        <DL><p>
            <DT><A HREF="https://github.com/" ADD_DATE="1700000000" ICON="data:image/png;base64,iVBORw0KGgo=">GitHub</A>
            <DT><H3 ADD_DATE="1700000000">Práce</H3>
            <DL><p>
                <DT><A HREF="https://example.atlassian.net">Jira</A>
                <DT><H3>Interní Nástroje</H3>
                <DL><p>
                    <DT><A HREF="https://wiki.example.com/?a=1&amp;b=2">Wiki &amp; dokumentace</A>
                    <DT><A HREF="javascript:alert(1)">Bookmarklet</A>
                </DL><p>
            </DL><p>
        </DL><p>
        <DT><A HREF="https://example.atlassian.net/">Jira znovu</A>
    </DL><p>
    """

    private func roots() throws -> [BookmarkNode] {
        try BookmarksHTMLParser.parse(data: Data(bookmarksHTML.utf8))
    }

    private func id(of name: String, in roots: [BookmarkNode]) -> String {
        func find(_ node: BookmarkNode) -> String? {
            if node.name == name { return node.id }
            return node.children.lazy.compactMap(find).first
        }
        return roots.lazy.compactMap(find).first!
    }

    func testParsesTree() throws {
        let roots = try roots()
        XCTAssertEqual(roots.count, 1)
        let root = roots[0]
        XCTAssertTrue(root.isRoot)
        XCTAssertEqual(root.children.map(\.name), ["Panel záložek", "Jira znovu"])
        let bar = root.children[0]
        XCTAssertTrue(bar.isRoot) // panel záložek se nepoužívá jako štítek
        XCTAssertEqual(bar.children.map(\.name), ["GitHub", "Práce"])
        XCTAssertFalse(bar.children[0].isFolder)
        XCTAssertEqual(bar.children[0].url, "https://github.com/")
        let prace = bar.children[1]
        XCTAssertTrue(prace.isFolder)
        XCTAssertFalse(prace.isRoot)
        let tools = prace.children[1]
        XCTAssertEqual(tools.name, "Interní Nástroje")
        XCTAssertEqual(tools.children.map(\.name), ["Wiki & dokumentace", "Bookmarklet"])
        XCTAssertEqual(tools.children[0].url, "https://wiki.example.com/?a=1&b=2")
        XCTAssertEqual(root.allBookmarks.count, 5)
        XCTAssertEqual(Set(root.allBookmarks.map(\.id)).count, 5)
    }

    func testParsesLowercaseAndSafariStyle() throws {
        let html = """
        <dl><dt><h3 folded>Oblíbené</h3>
        <dl><dt><a href='https://apple.com'>Apple</a></dl>
        <dt><a href="https://example.com">Bez složky</a></dl>
        """
        let root = try BookmarksHTMLParser.parse(html: html)[0]
        XCTAssertEqual(root.children.map(\.name), ["Oblíbené", "Bez složky"])
        XCTAssertEqual(root.children[0].children.first?.url, "https://apple.com")
    }

    func testInvalidFileThrows() {
        XCTAssertThrowsError(try BookmarksHTMLParser.parse(data: Data("{}".utf8)))
        XCTAssertThrowsError(try BookmarksHTMLParser.parse(data: Data("<html><body>Ahoj</body></html>".utf8)))
        XCTAssertThrowsError(try BookmarksHTMLParser.parse(data: Data("<DL></DL>".utf8)))
    }

    func testHTMLImportUsesFolderTags() throws {
        let roots = try roots()
        let all = Set(roots.flatMap(\.allBookmarks).map(\.id))
        let plan = ChromeImportPlanner.plan(roots: roots, selectedIDs: all, options: ChromeImportOptions(), existingURLs: [])
        XCTAssertEqual(plan.links.map(\.title), ["GitHub", "Jira", "Wiki & dokumentace"])
        XCTAssertEqual(plan.links.map(\.tags), [[], ["práce"], ["interní-nástroje"]])
        XCTAssertEqual(plan.skippedDuplicates, 1)
        XCTAssertEqual(plan.skippedUnsupported, 1)
    }
}
