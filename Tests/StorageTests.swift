import XCTest
@testable import LinkLauncher

final class StorageTests: XCTestCase {
    func testRoundTripIsReadableAndSorted() throws {
        let link = Link(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Jira",
            url: "https://example.atlassian.net/a/b",
            tags: ["práce", "pm"],
            createdAt: Date(timeIntervalSince1970: 1_791_885_600),
            lastOpenedAt: nil,
            openCount: 3
        )
        let data = try LinkDatabaseCodec.encode(LinkDatabase(links: [link]))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"url\" : \"https://example.atlassian.net/a/b\""), text) // bez escapovaných lomítek
        XCTAssertTrue(text.contains("\"createdAt\" : \"2026-10-13T10:00:00Z\""), text)
        XCTAssertFalse(text.contains("lastOpenedAt"))
        XCTAssertTrue(text.hasSuffix("\n"))
        // Seřazené klíče
        let keys = ["createdAt", "id", "openCount", "tags", "title", "url"].compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        XCTAssertEqual(keys, keys.sorted())

        let decoded = try LinkDatabaseCodec.decode(data)
        XCTAssertEqual(decoded.links, [link])
        XCTAssertEqual(decoded.version, 1)
    }

    func testTagColorsRoundTrip() throws {
        let db = LinkDatabase(links: [Link(title: "A", url: "https://a.example.com", tags: ["práce"])],
                              tagColors: ["práce": "blue"])
        let data = try LinkDatabaseCodec.encode(db)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"tagColors\""))
        let decoded = try LinkDatabaseCodec.decode(data)
        XCTAssertEqual(decoded.tagColors, ["práce": "blue"])
        XCTAssertEqual(decoded.tagColors.tagColor(for: "práce"), .blue)
        XCTAssertNil(["x": "neexistujici"].tagColor(for: "x"))

        // Bez barev se pole nezapisuje vůbec.
        let plain = try LinkDatabaseCodec.encode(LinkDatabase(links: []))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("tagColors"))
    }

    func testTagColorKeysAreNormalized() throws {
        let json = ##"{ "links": [], "tagColors": { "#Práce": "green", " ": "red" } }"##
        let db = try LinkDatabaseCodec.decode(Data(json.utf8))
        XCTAssertEqual(db.tagColors, ["práce": "green"])
    }

    func testLenientDecodingOfHandEditedFile() throws {
        let json = """
        { "links": [
            { "title": "Ručně", "url": "https://example.com", "tags": ["#Práce", "práce", " PM "] },
            { "url": "https://x.example.com", "lastOpenedAt": "2026-10-13T10:00:00.123Z" }
        ] }
        """
        let db = try LinkDatabaseCodec.decode(Data(json.utf8))
        XCTAssertEqual(db.version, 1)
        XCTAssertEqual(db.links.count, 2)
        XCTAssertEqual(db.links[0].tags, ["práce", "pm"])
        XCTAssertEqual(db.links[0].openCount, 0)
        XCTAssertEqual(db.links[1].title, "")
        XCTAssertNotNil(db.links[1].lastOpenedAt)
    }

    func testInvalidJSONThrowsWithDescription() {
        XCTAssertThrowsError(try LinkDatabaseCodec.decode(Data("{ \"links\": [ { \"title\": 1 } ] }".utf8))) { error in
            XCTAssertFalse(LinkDatabaseCodec.describe(error).isEmpty)
        }
        XCTAssertThrowsError(try LinkDatabaseCodec.decode(Data("{ nope".utf8)))
    }

    func testURLNormalization() {
        XCTAssertEqual(URLTools.normalize("example.com"), "https://example.com")
        XCTAssertEqual(URLTools.normalize("  http://example.com/x "), "http://example.com/x")
        XCTAssertEqual(URLTools.normalize("localhost:8080/app"), "https://localhost:8080/app")
        XCTAssertNil(URLTools.normalize("jira"))
        XCTAssertNil(URLTools.normalize("není url"))
        XCTAssertNil(URLTools.normalize(""))
        XCTAssertTrue(URLTools.looksLikeURL("github.com/apple"))
        XCTAssertFalse(URLTools.looksLikeURL("jira"))
        XCTAssertFalse(URLTools.looksLikeURL("#práce"))
    }

    func testDuplicateKey() {
        XCTAssertEqual(URLTools.duplicateKey("https://www.Example.com/"), URLTools.duplicateKey("http://example.com"))
        XCTAssertNotEqual(URLTools.duplicateKey("https://example.com/A"), URLTools.duplicateKey("https://example.com/a"))
        XCTAssertEqual(URLTools.displayDomain("https://www.github.com/apple"), "github.com")
    }

    func testTagNormalization() {
        XCTAssertEqual(Tag.normalize("  #Interní Nástroje "), "interní-nástroje")
        XCTAssertEqual(Tag.normalizeList(["A", "a", "", "#b"]), ["a", "b"])
    }

    func testHTMLTitleParsing() {
        XCTAssertEqual(HTMLTitleParser.title(in: "<html><head><TITLE lang=cs>\n  Jira &amp; Confluence &#8211; Přehled\n</title>"), "Jira & Confluence – Přehled")
        XCTAssertNil(HTMLTitleParser.title(in: "<html><title></title>"))
        XCTAssertEqual(HTMLTitleParser.iconHref(in: #"<link rel="stylesheet" href="a.css"><link rel="shortcut icon" href="/fav.ico">"#), "/fav.ico")
        XCTAssertEqual(HTMLTitleParser.iconHref(in: #"<link data-href="x" href='/i.png' rel=icon>"#), "/i.png")
    }
}
