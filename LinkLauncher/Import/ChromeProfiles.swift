import Foundation

struct ChromeProfile: Identifiable, Hashable {
    /// Název složky profilu (`Default`, `Profile 1`, …).
    let directoryName: String
    /// Jméno profilu z `Local State`.
    let displayName: String
    let bookmarksURL: URL

    var id: String { directoryName }
}

enum ChromeProfileLocator {
    static var defaultChromeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    /// Najde profily, které mají soubor `Bookmarks`.
    static func profiles(in chromeDirectory: URL = defaultChromeDirectory) -> [ChromeProfile] {
        let fm = FileManager.default
        var names: [String: String] = [:]
        if let data = try? Data(contentsOf: chromeDirectory.appendingPathComponent("Local State")) {
            names = profileNames(fromLocalState: data)
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: chromeDirectory.path) else { return [] }
        let dirs = entries.filter { $0 == "Default" || $0.hasPrefix("Profile ") }
        return dirs.compactMap { dir -> ChromeProfile? in
            let bookmarks = chromeDirectory.appendingPathComponent(dir).appendingPathComponent("Bookmarks")
            guard fm.fileExists(atPath: bookmarks.path) else { return nil }
            return ChromeProfile(directoryName: dir, displayName: names[dir] ?? dir, bookmarksURL: bookmarks)
        }
        .sorted { sortKey($0.directoryName) < sortKey($1.directoryName) }
    }

    /// Vrátí mapu `složka profilu → jméno` z JSONu `Local State`.
    static func profileNames(fromLocalState data: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any]
        else { return [:] }
        var result: [String: String] = [:]
        for (dir, value) in cache {
            if let info = value as? [String: Any], let name = info["name"] as? String, !name.isEmpty {
                result[dir] = name
            }
        }
        return result
    }

    /// `Default` první, pak `Profile N` podle čísla.
    private static func sortKey(_ dir: String) -> Int {
        if dir == "Default" { return -1 }
        return Int(dir.dropFirst("Profile ".count)) ?? Int.max
    }
}
