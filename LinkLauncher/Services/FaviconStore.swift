import AppKit

/// Cache faviconů v `~/Library/Caches/LinkLauncher/favicons`. Vše asynchronně –
/// launcher zobrazí, co je v paměti, a ikony doplní, až budou k dispozici.
@MainActor
final class FaviconStore: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]

    let directory: URL
    private var inFlight = Set<String>()
    private var failed = Set<String>()
    private static let retryFailedAfter: TimeInterval = 7 * 86_400
    private static let iconSize = 32

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LinkLauncher/favicons", isDirectory: true)) {
        self.directory = directory
    }

    func image(forHost host: String) -> NSImage? {
        images[host]
    }

    /// Zajistí načtení faviconu pro odkaz (z disku, případně stažením). Nikdy neblokuje.
    func load(for urlString: String) async {
        guard let host = URLTools.host(of: urlString) else { return }
        guard images[host] == nil, !inFlight.contains(host), !failed.contains(host) else { return }
        inFlight.insert(host)
        defer { inFlight.remove(host) }

        let file = fileURL(for: host)
        let marker = failureMarkerURL(for: host)
        let cached: Data? = await Task.detached(priority: .utility) {
            try? Data(contentsOf: file)
        }.value
        if let cached, let image = NSImage(data: cached) {
            images[host] = image
            return
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: marker.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.retryFailedAfter {
            failed.insert(host)
            return
        }

        guard let png = await download(pageURL: urlString, host: host),
              let image = NSImage(data: png) else {
            failed.insert(host)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Data().write(to: marker)
            return
        }
        images[host] = image
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? png.write(to: file, options: .atomic)
        try? FileManager.default.removeItem(at: marker)
    }

    /// Přednačte favicony pro nové odkazy (např. po přidání nebo importu).
    func prefetch(_ urls: [String]) {
        var seenHosts = Set<String>()
        let unique = urls.filter { url in
            guard let host = URLTools.host(of: url) else { return false }
            return seenHosts.insert(host).inserted
        }
        Task {
            for url in unique.prefix(200) { await load(for: url) }
        }
    }

    private func download(pageURL: String, host: String) async -> Data? {
        var candidates: [URL] = []
        if let page = URL(string: pageURL),
           let html = await TitleFetcher.fetchHTML(pageURL, timeout: 5),
           let href = HTMLTitleParser.iconHref(in: html),
           let iconURL = URL(string: href, relativeTo: page)?.absoluteURL {
            candidates.append(iconURL)
        }
        if let page = URL(string: pageURL), let scheme = page.scheme, let pageHost = page.host,
           let fallback = URL(string: "\(scheme)://\(pageHost)/favicon.ico") {
            candidates.append(fallback)
        }
        for url in candidates {
            guard let result = try? await TitleFetcher.session.data(from: url) else { continue }
            if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { continue }
            if let png = Self.normalizedPNG(from: result.0) { return png }
        }
        return nil
    }

    /// Zmenší ikonu na 32×32 PNG (šetří paměť i disk).
    static func normalizedPNG(from data: Data) -> Data? {
        guard let image = NSImage(data: data), image.isValid, image.size.width >= 1, image.size.height >= 1 else { return nil }
        let size = iconSize
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func fileURL(for host: String) -> URL {
        directory.appendingPathComponent(safeName(host) + ".png")
    }

    private func failureMarkerURL(for host: String) -> URL {
        directory.appendingPathComponent(safeName(host) + ".none")
    }

    private func safeName(_ host: String) -> String {
        host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? String($0) : "_" }.joined()
    }
}
