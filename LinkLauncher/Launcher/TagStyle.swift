import SwiftUI

extension TagColor {
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        }
    }
}

/// Barvy štítků pro celé UI (launcher, správa, nastavení) – vkládá se v kořenových view.
private struct TagColorsKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

extension EnvironmentValues {
    var tagColors: [String: String] {
        get { self[TagColorsKey.self] }
        set { self[TagColorsKey.self] = newValue }
    }
}

/// Barevné kolečko pro výběr barvy štítku (nastavení).
@MainActor
struct TagColorSwatch: View {
    let color: TagColor?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let color {
                    Circle().fill(color.color)
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    Image(systemName: "slash.circle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-3)
                    if color != nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 16, height: 16)
            .padding(3)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color?.label ?? "Bez barvy")
    }
}

/// Řádek nastavení barvy jednoho štítku.
@MainActor
struct TagColorRow: View {
    let tag: String
    let count: Int
    let selected: TagColor?
    let onSelect: (TagColor?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            TagChip(tag: tag)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                TagColorSwatch(color: nil, isSelected: selected == nil) { onSelect(nil) }
                ForEach(TagColor.allCases) { color in
                    TagColorSwatch(color: color, isSelected: selected == color) { onSelect(color) }
                }
            }
        }
    }
}
