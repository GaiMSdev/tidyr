import Foundation

struct Source: Identifiable, Codable {
    let id: UUID
    let name: String
    let url: URL
    var plexSectionId: Int?
    var plexLibraryType: PlexLibraryType?

    init(id: UUID = UUID(), name: String, url: URL,
         plexSectionId: Int? = nil, plexLibraryType: PlexLibraryType? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.plexSectionId = plexSectionId
        self.plexLibraryType = plexLibraryType
    }

    var isObsidianVault: Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".obsidian").path)
    }

    var isPlex: Bool { plexLibraryType != nil }
}

// Hash and equality based on id only so mutable plex fields don't affect identity
extension Source: Hashable {
    static func == (lhs: Source, rhs: Source) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
