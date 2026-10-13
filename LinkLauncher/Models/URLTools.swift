import Foundation

enum URLTools {
    /// Doplní `https://`, pokud chybí schéma, a ověří, že jde o platnou URL.
    /// Vrací `nil` pro neplatný vstup.
    static func normalize(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: { $0.isWhitespace }) else { return nil }
        if !hasScheme(s) {
            s = "https://" + s
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "https" {
            guard let host = url.host, !host.isEmpty else { return nil }
            // Vyžadovat tečku nebo localhost, aby "jira" nebylo platnou URL.
            guard host.contains(".") || host == "localhost" || host.contains(":") else { return nil }
        }
        return s
    }

    /// Zda řetězec vypadá jako URL (pro předvyplnění z dotazu launcheru).
    static func looksLikeURL(_ input: String) -> Bool {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: { $0.isWhitespace }), !s.hasPrefix("#") else { return false }
        if hasScheme(s) { return normalize(s) != nil }
        return s.contains(".") && normalize(s) != nil && !s.hasSuffix(".")
    }

    static func hasScheme(_ s: String) -> Bool {
        guard let colon = s.firstIndex(of: ":") else { return false }
        let scheme = s[s.startIndex..<colon]
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return false }
        let rest = s[s.index(after: colon)...]
        // "localhost:8080" není schéma – za dvojtečkou následují číslice.
        if rest.first?.isNumber == true { return false }
        return true
    }

    /// Klíč pro detekci duplicit: bez schématu, `www.`, koncového lomítka, malá písmena v hostu.
    static func duplicateKey(_ urlString: String) -> String {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "://") {
            s = String(s[range.upperBound...])
        }
        // Host na malá písmena (cesta může být case-sensitive).
        let hostEnd = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? s.endIndex
        var host = s[s.startIndex..<hostEnd].lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var rest = String(s[hostEnd...])
        if rest.hasSuffix("#") { rest.removeLast() }
        while rest.hasSuffix("/") { rest.removeLast() }
        return host + rest
    }

    /// Host bez `www.` pro zobrazení.
    static func displayDomain(_ urlString: String) -> String {
        guard let host = host(of: urlString) else { return urlString }
        return host
    }

    static func host(of urlString: String) -> String? {
        guard let url = URL(string: urlString), var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
