import Foundation

/// Čitelný JSON formát `links.json` (pretty-printed, seřazené klíče, ISO 8601 data).
enum LinkDatabaseCodec {
    static func encode(_ database: LinkDatabase) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(formatter.string(from: date))
        }
        var data = try encoder.encode(database)
        data.append(0x0A) // koncový řádek kvůli gitu
        return data
    }

    static func decode(_ data: Data) throws -> LinkDatabase {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = formatter.date(from: s) ?? fractionalFormatter.date(from: s) ?? dateOnlyFormatter.date(from: s) {
                return d
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Neplatné datum: \(s)")
        }
        return try decoder.decode(LinkDatabase.self, from: data)
    }

    /// Čitelný popis chyby dekódování (s cestou ke chybnému poli).
    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        func path(_ ctx: DecodingError.Context) -> String {
            let p = ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return p.isEmpty ? "" : " (\(p))"
        }
        switch error {
        case .dataCorrupted(let ctx):
            if let underlying = ctx.underlyingError as NSError? {
                return "Neplatný JSON: \(underlying.userInfo[NSDebugDescriptionErrorKey] as? String ?? underlying.localizedDescription)"
            }
            return "\(ctx.debugDescription)\(path(ctx))"
        case .keyNotFound(let key, let ctx):
            return "Chybí pole „\(key.stringValue)“\(path(ctx))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "\(ctx.debugDescription)\(path(ctx))"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dateOnlyFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
