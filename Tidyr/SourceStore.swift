import AppKit
import Observation

enum DetailMode {
    case fileList
    case analyzing(String?)
    case suggestions(AnalysisResponse)
    case applying
    case undoing
    case done
    case error(String)
}

@Observable
class SourceStore {
    var sources: [Source] = []
    var filesInView: [URL] = []
    var detailMode: DetailMode = .fileList
    var suggestionSelection = SuggestionSelection()
    var history: [ChangeSession] = []

    var lastSession: ChangeSession? { history.first }
    private(set) var lastAnalysisCommand: String? = nil
    private(set) var lastAnalysisRules: String? = nil
    private(set) var lastApplySkipped: [String] = []
    private(set) var lastRepairResult: ObsidianLinkRepairer.RepairResult?
    private(set) var lastPlexSynced: Bool? = nil

    private static let appSupportURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tidyr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let historyURL = SourceStore.appSupportURL.appendingPathComponent("history.json")
    private let sourcesURL = SourceStore.appSupportURL.appendingPathComponent("sources.json")

    init() {
        loadSources()
        loadHistory()
    }

    // MARK: - Folder management

    func removeSource(_ source: Source) {
        sources.removeAll { $0.id == source.id }
        saveSources()
    }

    func addFolder() -> Source? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to organize with Tidyr"
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        if let existing = sources.first(where: { $0.url == url }) { return existing }

        let source = Source(name: url.lastPathComponent, url: url)
        sources.append(source)
        saveSources()
        detectPlex(for: source)
        return source
    }

    private func detectPlex(for source: Source) {
        guard PlexLibraryDetector.isInstalled else { return }
        Task { @MainActor in
            guard let section = await PlexLibraryDetector.detectSection(for: source.url) else { return }
            guard let idx = sources.firstIndex(where: { $0.id == source.id }) else { return }
            sources[idx].plexSectionId = section.id
            sources[idx].plexLibraryType = section.type
            saveSources()
        }
    }

    func loadFiles(for source: Source) {
        detailMode = .fileList
        suggestionSelection.clear()
        let contents = try? FileManager.default.contentsOfDirectory(
            at: source.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        filesInView = (contents ?? []).sorted {
            $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased()
        }
    }

    // MARK: - Analysis

    func analyze(source: Source, command: String? = nil, rules: String? = nil) async {
        guard let apiKey = KeychainHelper.load() else {
            detailMode = .error(AnalysisError.noAPIKey.localizedDescription)
            return
        }
        if filesInView.count > 500 {
            detailMode = .error("This folder has \(filesInView.count) items — Tidyr works best with 500 or fewer. Try selecting a subfolder instead.")
            return
        }
        lastAnalysisCommand = command
        lastAnalysisRules = rules
        detailMode = .analyzing(command)
        suggestionSelection.clear()
        do {
            let response = try await AnalysisService.analyze(
                folder: source.url,
                apiKey: apiKey,
                command: command,
                rules: rules,
                isObsidianVault: source.isObsidianVault,
                plexLibraryType: source.plexLibraryType
            )
            detailMode = .suggestions(response)
        } catch {
            detailMode = .error(error.localizedDescription)
        }
    }

    func retryLastAnalysis(source: Source) async {
        await analyze(source: source, command: lastAnalysisCommand, rules: lastAnalysisRules)
    }

    // MARK: - Apply changes

    func applyChanges(source: Source) async {
        guard case .suggestions(let response) = detailMode else { return }
        let approved = response.suggestions.filter { suggestionSelection.isApproved($0.id) }
        detailMode = .applying
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.apply(suggestions: approved, in: source.url)
            }.value
            lastApplySkipped = result.skipped
            lastRepairResult = nil
            lastPlexSynced = nil
            if !result.operations.isEmpty {
                if source.isObsidianVault {
                    lastRepairResult = try? ObsidianLinkRepairer.repair(
                        vaultURL: source.url, operations: result.operations
                    )
                }
                if let sectionId = source.plexSectionId {
                    lastPlexSynced = await PlexSyncService.refresh(sectionId: sectionId)
                }
                let session = ChangeSession(
                    id: UUID(),
                    date: Date(),
                    folderName: source.name,
                    sourceURL: source.url,
                    operations: result.operations
                )
                history.insert(session, at: 0)
                saveHistory()
            }
            detailMode = .done
        } catch {
            detailMode = .error(error.localizedDescription)
        }
    }

    // MARK: - Undo

    // Used by DoneView — manages detailMode transitions
    func undoLastSession(source: Source) async {
        guard let session = history.first else { return }
        detailMode = .undoing
        do {
            try await undoSession(session)
            loadFiles(for: source)
        } catch {
            detailMode = .error("Could not undo all changes: \(error.localizedDescription)")
        }
    }

    // Used by HistoryView — pure undo without detailMode side-effects
    func undoSession(_ session: ChangeSession) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.reverse(session.operations)
        }.value
        if let vaultURL = session.sourceURL,
           sources.first(where: { $0.url == vaultURL })?.isObsidianVault == true {
            try? ObsidianLinkRepairer.reverseRepair(vaultURL: vaultURL, operations: session.operations)
        }
        history.removeAll { $0.id == session.id }
        saveHistory()
    }

    // MARK: - File operations

    private static func apply(
        suggestions: [Suggestion],
        in folderURL: URL
    ) throws -> (operations: [UndoOperation], skipped: [String]) {
        let fm = FileManager.default
        var completed: [UndoOperation] = []
        var skipped: [String] = []

        for suggestion in suggestions {
            switch suggestion.type {
            case .createFolder:
                guard let folderName = suggestion.folderName, !folderName.isEmpty else { continue }
                let dest = folderURL.appendingPathComponent(folderName, isDirectory: true)
                let existed = fm.fileExists(atPath: dest.path)
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                if !existed { completed.append(.createdFolder(dest)) }

            case .move:
                guard
                    let fileName = suggestion.fileName, !fileName.isEmpty,
                    let destination = suggestion.destination, !destination.isEmpty
                else { continue }

                let src = folderURL.appendingPathComponent(fileName)
                let destFolder = folderURL.appendingPathComponent(destination, isDirectory: true)
                let dest = destFolder.appendingPathComponent(src.lastPathComponent)

                let folderExisted = fm.fileExists(atPath: destFolder.path)
                try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
                if !folderExisted { completed.append(.createdFolder(destFolder)) }

                guard !fm.fileExists(atPath: dest.path) else {
                    skipped.append("\(fileName) (already exists in \(destination))")
                    continue
                }
                try fm.moveItem(at: src, to: dest)
                completed.append(.moved(originalURL: src, movedToURL: dest))

            case .rename:
                guard
                    let fileName = suggestion.fileName, !fileName.isEmpty,
                    let newName = suggestion.newName, !newName.isEmpty
                else { continue }

                let src = folderURL.appendingPathComponent(fileName)
                let dest = src.deletingLastPathComponent().appendingPathComponent(newName)

                guard !fm.fileExists(atPath: dest.path) else {
                    skipped.append("\(fileName) → \(newName) (name already taken)")
                    continue
                }
                try fm.moveItem(at: src, to: dest)
                completed.append(.renamed(originalURL: src, renamedToURL: dest))
            }
        }

        return (completed, skipped)
    }

    private static func reverse(_ operations: [UndoOperation]) throws {
        let fm = FileManager.default
        for operation in operations.reversed() {
            switch operation {
            case .moved(let originalURL, let movedToURL):
                try fm.moveItem(at: movedToURL, to: originalURL)

            case .renamed(let originalURL, let renamedToURL):
                try fm.moveItem(at: renamedToURL, to: originalURL)

            case .createdFolder(let url):
                let contents = try? fm.contentsOfDirectory(atPath: url.path)
                if contents?.isEmpty == true {
                    try fm.removeItem(at: url)
                }
            }
        }
    }

    // MARK: - Conflict pre-check

    func conflictsInApproved(source: Source, response: AnalysisResponse) -> [String] {
        let fm = FileManager.default
        let approved = response.suggestions.filter { suggestionSelection.isApproved($0.id) }
        var conflicts: [String] = []
        for s in approved {
            switch s.type {
            case .move:
                guard let file = s.fileName, let dest = s.destination else { continue }
                let path = source.url.appendingPathComponent(dest).appendingPathComponent(file).path
                if fm.fileExists(atPath: path) { conflicts.append("\(file) → \(dest)/") }
            case .rename:
                guard let file = s.fileName, let newName = s.newName else { continue }
                let path = source.url.appendingPathComponent(newName).path
                if fm.fileExists(atPath: path) { conflicts.append("\(file) → \(newName)") }
            case .createFolder:
                break
            }
        }
        return conflicts
    }

    // MARK: - Persistence

    private func saveSources() {
        try? JSONEncoder().encode(sources).write(to: sourcesURL)
    }

    private func loadSources() {
        guard
            let data = try? Data(contentsOf: sourcesURL),
            let loaded = try? JSONDecoder().decode([Source].self, from: data)
        else { return }
        sources = loaded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        if history.count > 100 { history = Array(history.prefix(100)) }
        try? JSONEncoder().encode(history).write(to: historyURL)
    }

    private func loadHistory() {
        guard
            let data = try? Data(contentsOf: historyURL),
            let loaded = try? JSONDecoder().decode([ChangeSession].self, from: data)
        else { return }
        history = Array(loaded.prefix(100))
    }
}

