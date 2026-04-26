import Foundation

struct AnalysisService {

    static func analyze(folder: URL, apiKey: String, command: String? = nil, rules: String? = nil, isObsidianVault: Bool = false, plexLibraryType: PlexLibraryType? = nil) async throws -> AnalysisResponse {
        let contents = readFolder(folder)
        let prompt   = buildPrompt(folderName: folder.lastPathComponent, contents: contents, command: command, rules: rules, isObsidianVault: isObsidianVault, plexLibraryType: plexLibraryType)
        let rawJSON  = try await GeminiService.send(prompt: prompt, apiKey: apiKey)
        return try parseResponse(rawJSON)
    }

    private static func readFolder(_ url: URL) -> [String] {
        let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        return (items ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                return isDir ? "\(item.lastPathComponent)/" : item.lastPathComponent
            }
    }

    private static func buildPrompt(folderName: String, contents: [String], command: String? = nil, rules: String? = nil, isObsidianVault: Bool = false, plexLibraryType: PlexLibraryType? = nil) -> String {
        let itemList = contents.isEmpty
            ? "(empty folder)"
            : contents.map { "  - \($0)" }.joined(separator: "\n")

        let task: String
        if let cmd = command {
            task = "The user has a specific request: \"\(cmd)\". Focus your suggestions on fulfilling this request. You may include closely related improvements, but always prioritize what the user asked for."
        } else {
            task = "Analyze this folder and suggest how to improve its overall structure."
        }

        let rulesSection: String
        if let rules = rules {
            rulesSection = "\n\nThe user has set up these organization rules — always follow them when making suggestions:\n\(rules)"
        } else {
            rulesSection = ""
        }

        let plexSection: String
        if let plex = plexLibraryType {
            plexSection = "\n\n" + plex.namingConvention
        } else {
            plexSection = ""
        }

        let vaultSection = isObsidianVault ? """


        This folder is an Obsidian vault. Obsidian stores knowledge as plain Markdown (.md) files connected by [[wikilinks]]. Tidyr automatically repairs wikilinks after moves and renames, so broken links are not a concern — but follow these rules anyway:
        - You MAY suggest renaming .md files when the current name is genuinely confusing or inconsistent, but be conservative — only rename when the benefit is clear.
        - Moving .md files into subfolders is safe. Only suggest it when there is a clear thematic grouping (10+ notes on the same topic).
        - Non-.md files (images, PDFs, audio, video) are attachments. If there is no dedicated attachments folder yet, suggest creating one and moving loose attachments into it.
        - The .obsidian/ folder is vault configuration — never touch it.
        - .canvas files are Obsidian canvas diagrams — never move or rename them.
        - If you see folders named "Templates", "Daily Notes", "Attachments", or "Archive", treat them as intentional Obsidian structure — do not suggest reorganizing their contents unless the user asked.
        - Prefer folder-level organization over individual file moves when possible.
        """ : ""

        return """
        You are an expert file organizer. \(task)\(rulesSection)\(plexSection)\(vaultSection)

        Folder name: "\(folderName)"
        Contents (\(contents.count) items):
        \(itemList)

        Return ONLY a valid JSON object — no markdown, no explanation, just the JSON. Use this exact structure:
        {
          "summary": "2-3 sentences: what you found and your overall strategy",
          "suggestions": [
            {
              "id": 1,
              "type": "create_folder",
              "description": "Create a Finance folder",
              "reason": "Group all financial documents together",
              "folderName": "Finance",
              "fileName": null,
              "destination": null,
              "newName": null
            },
            {
              "id": 2,
              "type": "move",
              "description": "Move receipt.pdf into Finance",
              "reason": "It is a financial document",
              "folderName": null,
              "fileName": "receipt.pdf",
              "destination": "Finance",
              "newName": null
            },
            {
              "id": 3,
              "type": "rename",
              "description": "Rename IMG_001.jpg to vacation_photo.jpg",
              "reason": "More descriptive name",
              "folderName": null,
              "fileName": "IMG_001.jpg",
              "destination": null,
              "newName": "vacation_photo.jpg"
            }
          ]
        }

        Rules:
        - Always suggest create_folder BEFORE any move that uses that folder
        - Maximum 12 suggestions
        - Only suggest changes that genuinely improve organization
        - If already well-organized, say so in summary and return an empty suggestions array
        - Only reference files and folders that appear in the contents list above

        File type notes — read carefully before grouping by extension:
        - .torrent files are small pointer files for download clients. They are NOT media. Group them with downloads or torrents, never with videos or music.
        - .iso, .dmg, .pkg, .exe, .msi are installers or disk images, not regular documents.
        - .crdownload, .part, .download, .tmp are unfinished or temporary downloads — keep them separate from finished files.
        - .alias and .lnk are shortcuts pointing to other files, not the files themselves.
        - .zip, .rar, .7z, .tar, .gz are archives. Keep them as archives unless the filename clearly indicates what's inside.
        - Look at the full filename, not just the extension. A "screenshot_2025.png" and a "logo.png" probably belong in different places.
        """
    }

    private static func parseResponse(_ raw: String) throws -> AnalysisResponse {
        // Gemini sometimes wraps JSON in markdown code fences — strip them
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        }
        if cleaned.hasSuffix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropLast().joined(separator: "\n")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { throw AnalysisError.badJSON }
        do {
            return try JSONDecoder().decode(AnalysisResponse.self, from: data)
        } catch {
            throw AnalysisError.parseFailure(raw)
        }
    }
}

enum AnalysisError: LocalizedError {
    case badJSON
    case parseFailure(String)
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .badJSON:         return "Could not read the AI's response."
        case .parseFailure:    return "The AI returned an unexpected format. Try analyzing again."
        case .noAPIKey:        return "No API key found. Please add one in Settings (⚙)."
        }
    }
}
