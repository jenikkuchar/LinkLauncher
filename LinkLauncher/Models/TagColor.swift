import Foundation

/// Barva štítku (paleta jako u štítků ve Finderu). V `links.json` se ukládá jako název (`"blue"`).
enum TagColor: String, CaseIterable, Identifiable, Codable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "Červená"
        case .orange: return "Oranžová"
        case .yellow: return "Žlutá"
        case .green: return "Zelená"
        case .mint: return "Mátová"
        case .teal: return "Tyrkysová"
        case .blue: return "Modrá"
        case .indigo: return "Indigová"
        case .purple: return "Fialová"
        case .pink: return "Růžová"
        case .brown: return "Hnědá"
        case .gray: return "Šedá"
        }
    }
}

extension Dictionary where Key == String, Value == String {
    /// Barva štítku z mapy `tagColors` (neznámé názvy barev se ignorují).
    func tagColor(for tag: String) -> TagColor? {
        self[tag].flatMap(TagColor.init(rawValue:))
    }
}
