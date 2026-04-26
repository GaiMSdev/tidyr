import Foundation

enum PlexLibraryType: String, Codable {
    case movies
    case shows
    case music
    case photos
    case other

    init(plexType: String) {
        switch plexType {
        case "movie":  self = .movies
        case "show":   self = .shows
        case "artist": self = .music
        case "photo":  self = .photos
        default:       self = .other
        }
    }

    var displayName: String {
        switch self {
        case .movies: return "Plex Movie Library"
        case .shows:  return "Plex TV Library"
        case .music:  return "Plex Music Library"
        case .photos: return "Plex Photo Library"
        case .other:  return "Plex Library"
        }
    }

    var sidebarIcon: String {
        switch self {
        case .movies: return "film"
        case .shows:  return "tv"
        case .music:  return "music.note"
        case .photos: return "photo"
        case .other:  return "square.stack"
        }
    }

    // Naming convention AI prompt section
    var namingConvention: String {
        switch self {
        case .movies:
            return """
            This is a Plex Movie Library. Plex expects this exact naming format:
            - Each movie in its own folder: Movie Title (Year)/Movie Title (Year).ext
            - Year must be in parentheses: "Inception (2010)", not "Inception 2010" or "Inception.2010"
            - Multi-edition: Movie Title (Year) {edition-Director's Cut}/...
            Suggest renames that bring files closer to this convention. Never merge movie folders.
            """
        case .shows:
            return """
            This is a Plex TV Library. Plex expects this exact naming format:
            - Top-level: Show Name/Season XX/
            - Episode files: Show Name - SXXEXX - Episode Title.ext
            - Season folders must be: "Season 01", "Season 02" — never "S01" or "Series 1"
            Suggest renames that fix episode numbering or season folder names. Never merge show folders.
            """
        case .music:
            return """
            This is a Plex Music Library. Plex expects this structure:
            - Artist/Album (Year)/NN - Track Title.ext
            - Track numbers should be zero-padded: "01", "02", not "1", "2"
            Suggest renames that fix artist/album folder structure or track numbering.
            """
        case .photos, .other:
            return "This appears to be a Plex library. Prefer folder-level organization and do not rename files in ways that could confuse Plex's scanner."
        }
    }
}

struct PlexLibrarySection {
    let id: Int
    let title: String
    let type: PlexLibraryType
    let paths: [String]
}

struct PlexLibraryDetector {

    private static let baseURL = "http://localhost:32400"

    private static var tokenFileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plex Media Server/.LocalAdminToken")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: tokenFileURL.path)
    }

    static var localToken: String? {
        guard let raw = try? String(contentsOf: tokenFileURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Format is either "local-xxx" directly or "token=local-xxx"
        if trimmed.contains("=") {
            return trimmed.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    // Detect which Plex section (if any) owns the given folder
    static func detectSection(for folderURL: URL) async -> PlexLibrarySection? {
        guard let sections = try? await allSections() else { return nil }
        let target = folderURL.standardized.path
        return sections.first { section in
            section.paths.contains { path in
                target == path || target.hasPrefix(path + "/")
            }
        }
    }

    static func allSections() async throws -> [PlexLibrarySection] {
        guard let token = localToken else { return [] }
        guard var components = URLComponents(string: "\(baseURL)/library/sections") else { return [] }
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        return parseJSON(data)
    }

    private static func parseJSON(_ data: Data) -> [PlexLibrarySection] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let container = root["MediaContainer"] as? [String: Any],
            let directories = container["Directory"] as? [[String: Any]]
        else { return [] }

        return directories.compactMap { dir in
            // "key" can be Int or String depending on Plex version
            let id: Int
            if let n = dir["key"] as? Int { id = n }
            else if let s = dir["key"] as? String, let n = Int(s) { id = n }
            else { return nil }

            guard
                let typeStr = dir["type"] as? String,
                let title   = dir["title"] as? String
            else { return nil }

            let paths: [String]
            if let locations = dir["Location"] as? [[String: Any]] {
                paths = locations.compactMap { $0["path"] as? String }
            } else {
                paths = []
            }

            return PlexLibrarySection(
                id: id,
                title: title,
                type: PlexLibraryType(plexType: typeStr),
                paths: paths
            )
        }
    }
}
