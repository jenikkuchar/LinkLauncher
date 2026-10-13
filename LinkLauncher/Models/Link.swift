import Foundation

/// Jeden uložený odkaz.
struct Link: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var url: String
    var tags: [String]
    var createdAt: Date
    var lastOpenedAt: Date?
    var openCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        tags: [String] = [],
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        openCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.tags = Tag.normalizeList(tags)
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.openCount = openCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, url, tags, createdAt, lastOpenedAt, openCount
    }

    /// Tolerantní dekódování – soubor se může upravovat ručně, chybějící pole dostanou výchozí hodnoty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        tags = Tag.normalizeList(try c.decodeIfPresent([String].self, forKey: .tags) ?? [])
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        openCount = try c.decodeIfPresent(Int.self, forKey: .openCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(url, forKey: .url)
        try c.encode(tags, forKey: .tags)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try c.encode(openCount, forKey: .openCount)
    }

    /// Doména pro zobrazení (bez `www.`).
    var domain: String { URLTools.displayDomain(url) }

    /// Název pro zobrazení – když chybí, použije se doména.
    var displayTitle: String { title.isEmpty ? domain : title }
}

/// Kořen souboru `links.json`.
struct LinkDatabase: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var links: [Link]

    init(version: Int = LinkDatabase.currentVersion, links: [Link]) {
        self.version = version
        self.links = links
    }

    private enum CodingKeys: String, CodingKey { case version, links }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? LinkDatabase.currentVersion
        links = try c.decodeIfPresent([Link].self, forKey: .links) ?? []
    }
}
