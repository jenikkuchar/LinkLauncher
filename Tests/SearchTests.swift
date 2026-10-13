import XCTest
@testable import LinkLauncher

final class SearchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func link(_ title: String, _ url: String, tags: [String] = [], opened: Int = 0, daysAgo: Double? = nil) -> Link {
        Link(
            title: title,
            url: url,
            tags: tags,
            createdAt: now.addingTimeInterval(-86_400 * 100),
            lastOpenedAt: daysAgo.map { now.addingTimeInterval(-86_400 * $0) },
            openCount: opened
        )
    }

    // MARK: Diakritika a velikost písmen

    func testFoldingRemovesDiacriticsAndCase() {
        XCTAssertEqual(TextFolding.fold("Čeština"), "cestina")
        XCTAssertEqual(TextFolding.fold("ŽLUŤOUČKÝ kůň"), "zlutoucky kun")
    }

    func testSearchIgnoresDiacritics() {
        let engine = SearchEngine(links: [
            link("Čeština pro cizince", "https://cestina.example.com"),
            link("Angličtina", "https://english.example.com"),
        ])
        XCTAssertEqual(engine.search("cestina", now: now).map(\.title), ["Čeština pro cizince"])
        XCTAssertEqual(engine.search("ČEŠTINA", now: now).map(\.title), ["Čeština pro cizince"])
        XCTAssertEqual(engine.search("anglictina", now: now).map(\.title), ["Angličtina"])
    }

    func testDiacriticsInQueryMatchPlainText() {
        let engine = SearchEngine(links: [link("Cestovani", "https://a.example.com")])
        XCTAssertEqual(engine.search("cěstování", now: now).count, 1)
    }

    // MARK: Fuzzy

    func testFuzzySubsequenceMatches() {
        let engine = SearchEngine(links: [
            link("Google Drive", "https://drive.google.com"),
            link("Kalendář", "https://calendar.example.com"),
        ])
        XCTAssertEqual(engine.search("gdrv", now: now).map(\.title), ["Google Drive"])
    }

    func testAllTermsMustMatch() {
        let engine = SearchEngine(links: [
            link("Jira projekt A", "https://a.atlassian.net"),
            link("Jira projekt B", "https://b.atlassian.net"),
        ])
        XCTAssertEqual(engine.search("jira b", now: now).first?.title, "Jira projekt B")
        XCTAssertTrue(engine.search("jira zzz", now: now).isEmpty)
    }

    func testMatchesURLAndTags() {
        let engine = SearchEngine(links: [
            link("Tracker", "https://example.atlassian.net", tags: ["pm"]),
        ])
        XCTAssertEqual(engine.search("atlassian", now: now).count, 1)
        XCTAssertEqual(engine.search("pm", now: now).count, 1)
    }

    func testSchemeDoesNotMatch() {
        let engine = SearchEngine(links: [link("Example", "https://example.com")])
        XCTAssertTrue(engine.search("https", now: now).isEmpty)
    }

    // MARK: Řazení

    func testTitleHasHighestWeight() {
        let engine = SearchEngine(links: [
            link("Něco jiného", "https://jira.example.com"),
            link("Moje", "https://example.com", tags: ["jira"]),
            link("Jira", "https://tracker.example.com"),
        ])
        XCTAssertEqual(engine.search("jira", now: now).map(\.title), ["Jira", "Moje", "Něco jiného"])
    }

    func testPrefixBeatsSubstringBeatsFuzzy() {
        let engine = SearchEngine(links: [
            link("Xabc", "https://1.example.com"),
            link("a-b-c", "https://2.example.com"),
            link("Abc dokumentace", "https://3.example.com"),
        ])
        XCTAssertEqual(engine.search("abc", now: now).map(\.title), ["Abc dokumentace", "Xabc", "a-b-c"])
    }

    func testEqualScoreSortedByOpenCount() {
        let engine = SearchEngine(links: [
            link("Docs", "https://a.example.com", opened: 1, daysAgo: 1),
            link("Docs", "https://b.example.com", opened: 5, daysAgo: 60),
            link("Docs", "https://c.example.com"),
        ])
        XCTAssertEqual(engine.search("docs", now: now).map(\.url), [
            "https://b.example.com", "https://a.example.com", "https://c.example.com",
        ])
    }

    func testEmptyQuerySortedByOpenCount() {
        let engine = SearchEngine(links: [
            link("Nikdy", "https://a.example.com"),
            link("Často dávno", "https://b.example.com", opened: 20, daysAgo: 120),
            link("Včera", "https://c.example.com", opened: 3, daysAgo: 1),
        ])
        XCTAssertEqual(engine.search("", now: now).map(\.title), ["Často dávno", "Včera", "Nikdy"])
    }

    func testSameOpenCountPrefersRecentlyOpened() {
        let engine = SearchEngine(links: [
            link("Dávno", "https://a.example.com", opened: 2, daysAgo: 30),
            link("Nedávno", "https://b.example.com", opened: 2, daysAgo: 1),
        ])
        XCTAssertEqual(engine.search("", now: now).map(\.title), ["Nedávno", "Dávno"])
    }

    func testMatchScoreStillBeatsOpenCount() {
        let engine = SearchEngine(links: [
            link("Moje Jira", "https://a.example.com", opened: 50, daysAgo: 1),
            link("Jira", "https://b.example.com"),
        ])
        XCTAssertEqual(engine.search("jira", now: now).first?.title, "Jira")
    }

    // MARK: #štítky

    func testTagFilter() {
        let engine = SearchEngine(links: [
            link("Jira práce", "https://work.atlassian.net", tags: ["práce", "pm"]),
            link("Jira doma", "https://home.atlassian.net", tags: ["doma"]),
            link("Wiki", "https://wiki.example.com", tags: ["práce"]),
        ])
        XCTAssertEqual(engine.search("#práce jira", now: now).map(\.title), ["Jira práce"])
        XCTAssertEqual(engine.search("#prace jira", now: now).map(\.title), ["Jira práce"])
        XCTAssertEqual(Set(engine.search("#práce ", now: now).map(\.title)), ["Jira práce", "Wiki"])
    }

    func testMultipleTagsAreAND() {
        let engine = SearchEngine(links: [
            link("A", "https://a.example.com", tags: ["práce", "pm"]),
            link("B", "https://b.example.com", tags: ["práce"]),
            link("C", "https://c.example.com", tags: ["pm"]),
        ])
        XCTAssertEqual(engine.search("#práce #pm ", now: now).map(\.title), ["A"])
        XCTAssertEqual(engine.search("#pm #práce", now: now).map(\.title), ["A"])
    }

    func testCompletedTagIsExactMatch() {
        let engine = SearchEngine(links: [
            link("A", "https://a.example.com", tags: ["pm"]),
            link("B", "https://b.example.com", tags: ["pmo"]),
        ])
        XCTAssertEqual(engine.search("#pm a", now: now).map(\.title), ["A"])
        XCTAssertEqual(engine.search("#pm ", now: now).map(\.title), ["A"])
    }

    func testPendingTagFiltersByPrefix() {
        let engine = SearchEngine(links: [
            link("A", "https://a.example.com", tags: ["práce"]),
            link("B", "https://b.example.com", tags: ["doma"]),
        ])
        XCTAssertEqual(engine.search("#pr", now: now).map(\.title), ["A"])
        XCTAssertEqual(engine.search("#", now: now).count, 2)
    }

    func testQueryParser() {
        let q = QueryParser.parse("#Práce  Jíra #pm ")
        XCTAssertEqual(q.terms, ["jira"])
        XCTAssertEqual(q.tagFilters, ["prace", "pm"])
        XCTAssertNil(q.pendingTagPrefix)

        let pending = QueryParser.parse("jira #pr")
        XCTAssertEqual(pending.terms, ["jira"])
        XCTAssertEqual(pending.tagFilters, [])
        XCTAssertEqual(pending.pendingTagPrefix, "pr")
    }

    func testTagSuggestions() {
        let engine = SearchEngine(links: [
            link("A", "https://a.example.com", tags: ["práce", "projekty"]),
            link("B", "https://b.example.com", tags: ["práce", "doma"]),
            link("C", "https://c.example.com", tags: ["sport"]),
        ])
        XCTAssertEqual(engine.tagSuggestions(for: QueryParser.parse("#pr")), ["práce", "projekty"])
        XCTAssertEqual(engine.tagSuggestions(for: QueryParser.parse("#práce #p")), ["projekty", "sport"])
        XCTAssertEqual(engine.tagSuggestions(for: QueryParser.parse("#or")), ["sport"])
        XCTAssertEqual(engine.tagSuggestions(for: QueryParser.parse("#pr ")), [])
        XCTAssertEqual(QueryParser.completeTag(in: "jira #pr", with: "práce"), "jira #práce ")
    }

    // MARK: Výkon

    func testPerformanceWith5000Links() {
        let words = ["alfa", "beta", "gama", "delta", "projekt", "dokumentace", "tabulka", "přehled", "účet", "server"]
        var links: [Link] = []
        for i in 0..<5_000 {
            let title = "\(words[i % 10]) \(words[(i / 10) % 10]) \(i)"
            links.append(link(title, "https://host\(i).example.com/path/\(words[(i / 7) % 10])", tags: [words[i % 7]], opened: i % 5, daysAgo: Double(i % 40)))
        }
        let engine = SearchEngine(links: links)
        let start = Date()
        for query in ["a", "al", "alf", "alfa", "alfa p", "alfa pr", "#beta do", "xyz", "dkmn", ""] {
            _ = engine.search(query, now: now, limit: 100)
        }
        let perQuery = Date().timeIntervalSince(start) / 10
        // Debug build na CI je pomalejší – rezerva; v Release je to jednotky ms.
        XCTAssertLessThan(perQuery, 0.1)
    }
}
