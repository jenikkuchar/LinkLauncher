import SwiftUI

/// Liquid Glass (macOS 26+) s náhradním vzhledem pro starší systémy.
/// Kód se dá sestavit i ve starším Xcode (bez SDK macOS 26) – pak se použije jen náhrada.
extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: Color
    ) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(shape.fill(fallback))
        }
        #else
        self.background(shape.fill(fallback))
        #endif
    }
}

/// Zvýraznění vybraného řádku launcheru – tónované sklo, které se mezi řádky posouvá.
@MainActor
struct SelectionHighlight: View {
    var body: some View {
        Color.clear
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                tint: Color.accentColor,
                fallback: Color.accentColor
            )
    }
}
