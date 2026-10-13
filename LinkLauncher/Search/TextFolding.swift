import Foundation

enum TextFolding {
    /// Převede text na malá písmena bez diakritiky (`Čeština` → `cestina`).
    static func fold(_ s: String) -> String {
        // Rychlá cesta pro čisté ASCII (většina URL).
        if s.utf8.allSatisfy({ $0 < 0x80 }) { return s.lowercased() }
        return s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    static func scalars(_ s: String) -> [Unicode.Scalar] {
        Array(fold(s).unicodeScalars)
    }

    /// URL bez schématu a `www.` – aby `https` nezvyšovalo shody.
    static func foldURL(_ url: String) -> [Unicode.Scalar] {
        var s = url
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if s.lowercased().hasPrefix("www.") { s.removeFirst(4) }
        return scalars(s)
    }
}
