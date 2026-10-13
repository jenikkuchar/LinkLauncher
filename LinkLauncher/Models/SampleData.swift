import Foundation

enum SampleData {
    static var links: [Link] {
        [
            Link(title: "GitHub", url: "https://github.com", tags: ["vývoj"]),
            Link(title: "Apple Developer dokumentace", url: "https://developer.apple.com/documentation", tags: ["vývoj", "apple"]),
            Link(title: "Swift Forums", url: "https://forums.swift.org", tags: ["vývoj"]),
            Link(title: "Česká televize", url: "https://www.ceskatelevize.cz", tags: ["zprávy"]),
            Link(title: "Počasí – ČHMÚ", url: "https://www.chmi.cz", tags: ["počasí"]),
        ]
    }
}
