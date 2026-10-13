import Foundation

/// Frecency = frekvence × čerstvost. Každé otevření má váhu, která s věkem
/// posledního otevření klesá (poločas 14 dní). Nikdy neotevřené odkazy mají 0.
enum Frecency {
    static let halfLifeDays = 14.0

    static func score(openCount: Int, lastOpenedAt: Date?, now: Date = Date()) -> Double {
        guard openCount > 0, let last = lastOpenedAt else { return 0 }
        let ageDays = max(0, now.timeIntervalSince(last) / 86_400)
        let recency = pow(0.5, ageDays / halfLifeDays)
        // Logaritmus frekvence, aby staré často otevírané odkazy úplně nepřebily čerstvé.
        return (1 + log2(Double(openCount))) * (0.1 + 0.9 * recency)
    }

    static func score(_ link: Link, now: Date = Date()) -> Double {
        score(openCount: link.openCount, lastOpenedAt: link.lastOpenedAt, now: now)
    }
}
