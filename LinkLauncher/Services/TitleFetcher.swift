import Foundation

/// Asynchronně načte `<title>` stránky (s timeoutem).
enum TitleFetcher {
    static func fetchTitle(for urlString: String, timeout: TimeInterval = 6) async -> String? {
        guard let html = await fetchHTML(urlString, timeout: timeout) else { return nil }
        return HTMLTitleParser.title(in: html)
    }

    static func fetchHTML(_ urlString: String, timeout: TimeInterval) async -> String? {
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) LinkLauncher", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            // Stačí začátek dokumentu.
            let head = data.prefix(512 * 1024)
            return String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()
}
