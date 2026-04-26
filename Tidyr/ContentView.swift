import SwiftUI

enum SidebarItem: Hashable {
    case source(Source)
    case rules
    case history
}

struct ContentView: View {
    @State private var store = SourceStore()
    @State private var ruleStore = RuleStore()
    @State private var selection: SidebarItem?
    @State private var showSettings = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @State private var safetyAlert: PendingAnalysis?
    @State private var conflictsBeforeApply: [String] = []
    @State private var showConflictAlert = false
    @State private var pendingApplySource: Source?

    struct PendingAnalysis: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let isDanger: Bool
        let source: Source
        let command: String?
        let rules: String?
    }

    private var selectedSource: Source? {
        if case .source(let s) = selection { return s }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                selection: $selection,
                showSettings: $showSettings,
                onAddFolder: addFolder,
                ruleCount: ruleStore.totalCount,
                historyCount: store.history.count
            )
        } detail: {
            detailContent
        }
        .frame(minWidth: 700, minHeight: 450)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showWelcome, onDismiss: {
            hasSeenWelcome = true
        }) {
            WelcomeView(isPresented: $showWelcome)
        }
        .confirmationDialog(
            "\(conflictsBeforeApply.count) item\(conflictsBeforeApply.count == 1 ? "" : "s") already exist at the destination",
            isPresented: $showConflictAlert,
            titleVisibility: .visible
        ) {
            Button("Skip conflicts, apply the rest") {
                if let s = pendingApplySource {
                    Task { await store.applyChanges(source: s) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let list = conflictsBeforeApply.prefix(4).joined(separator: "\n")
            let extra = conflictsBeforeApply.count > 4 ? "\n+ \(conflictsBeforeApply.count - 4) more" : ""
            Text("These will be skipped automatically:\n\(list)\(extra)")
        }
        .sheet(item: $safetyAlert) { pending in
            SafetyWarningView(
                title: pending.title,
                detail: pending.detail,
                isDanger: pending.isDanger,
                onProceed: {
                    safetyAlert = nil
                    Task { await store.analyze(source: pending.source, command: pending.command, rules: pending.rules) }
                },
                onCancel: { safetyAlert = nil }
            )
        }
        .onAppear {
            if !hasSeenWelcome { showWelcome = true }
        }
    }

    private func addFolder() {
        if let newSource = store.addFolder() {
            selection = .source(newSource)
            store.loadFiles(for: newSource)
        }
    }

    private func requestAnalysis(for source: Source, command: String? = nil) {
        let rules = ruleStore.promptText
        switch SafetyChecker.check(folder: source.url) {
        case .safe:
            Task { await store.analyze(source: source, command: command, rules: rules) }
        case .warning(let title, let detail):
            safetyAlert = PendingAnalysis(title: title, detail: detail, isDanger: false, source: source, command: command, rules: rules)
        case .danger(let title, let detail):
            safetyAlert = PendingAnalysis(title: title, detail: detail, isDanger: true, source: source, command: command, rules: rules)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if case .rules = selection {
            RulesView(ruleStore: ruleStore)
        } else if case .history = selection {
            HistoryView(store: store)
        } else if let source = selectedSource {
            switch store.detailMode {
            case .fileList:
                FileListView(
                    source: source,
                    files: store.filesInView,
                    ruleCount: ruleStore.totalCount,
                    canUndo: store.lastSession?.sourceURL == source.url,
                    showSettings: { showSettings = true },
                    onCommand: { command in
                        requestAnalysis(for: source, command: command)
                    },
                    onRefresh: { store.loadFiles(for: source) },
                    onUndo: { Task { await store.undoLastSession(source: source) } }
                )
            case .analyzing(let command):
                AnalyzingView(folderName: source.name, command: command)
            case .suggestions(let response):
                AnalysisView(
                    source: source,
                    response: response,
                    selection: $store.suggestionSelection,
                    onApprove: {
                        let conflicts = store.conflictsInApproved(source: source, response: response)
                        if conflicts.isEmpty {
                            Task { await store.applyChanges(source: source) }
                        } else {
                            conflictsBeforeApply = conflicts
                            pendingApplySource = source
                            showConflictAlert = true
                        }
                    },
                    onBack: { store.loadFiles(for: source) }
                )
            case .applying:
                ApplyingView(folderName: source.name)
            case .undoing:
                UndoingView()
            case .done:
                DoneView(
                    folderName: source.name,
                    canUndo: store.lastSession != nil,
                    skipped: store.lastApplySkipped,
                    repairResult: store.lastRepairResult,
                    plexSynced: store.lastPlexSynced,
                    onUndo: { Task { await store.undoLastSession(source: source) } },
                    onBack: { store.loadFiles(for: source) }
                )
            case .error(let message):
                ErrorView(
                    message: message,
                    onRetry: { Task { await store.retryLastAnalysis(source: source) } },
                    onBack: { store.loadFiles(for: source) }
                )
            }
        } else {
            EmptyStateView(
                hasSources: !store.sources.isEmpty,
                hasAPIKey: KeychainHelper.hasKey,
                onAddFolder: addFolder,
                onOpenSettings: { showSettings = true }
            )
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    var store: SourceStore
    @Binding var selection: SidebarItem?
    @Binding var showSettings: Bool
    let onAddFolder: () -> Void
    let ruleCount: Int
    let historyCount: Int

    var body: some View {
        List(selection: $selection) {
            Section("Folders") {
                if store.sources.isEmpty {
                    Button(action: onAddFolder) {
                        Label("Add a folder…", systemImage: "folder.badge.plus")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(store.sources) { source in
                        SidebarSourceRow(
                            source: source,
                            isSelected: selection == .source(source),
                            onRemove: {
                                if selection == .source(source) { selection = nil }
                                store.removeSource(source)
                            }
                        )
                        .tag(SidebarItem.source(source))
                    }
                }
            }

            Section("Organize") {
                Label {
                    Text("Rules")
                } icon: {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.purple)
                }
                .tag(SidebarItem.rules)
                .badge(ruleCount)
                .contentShape(Rectangle())
                .onTapGesture { selection = .rules }

                Label {
                    Text("History")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                }
                .tag(SidebarItem.history)
                .badge(historyCount)
                .contentShape(Rectangle())
                .onTapGesture { selection = .history }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Tidyr")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarActionBar(onAddFolder: onAddFolder, onSettings: { showSettings = true })
        }
        .onChange(of: selection) { _, newItem in
            if case .source(let source) = newItem {
                store.loadFiles(for: source)
            }
        }
    }
}

struct SidebarActionBar: View {
    let onAddFolder: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button(action: onAddFolder) {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("Add a folder to organize")

                Button(action: onSettings) {
                    Image(systemName: "gear")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

struct SidebarSourceRow: View {
    let source: Source
    let isSelected: Bool
    let onRemove: () -> Void
    @State private var confirmTrash = false
    @State private var trashBlocked = false

    var body: some View {
        Label {
            Text(source.name)
        } icon: {
            if source.isObsidianVault {
                Image(systemName: "diamond.fill").foregroundStyle(.purple)
            } else if let plex = source.plexLibraryType {
                Image(systemName: plex.sidebarIcon).foregroundStyle(.orange)
            } else {
                Image(systemName: "folder").foregroundStyle(.primary)
            }
        }
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([source.url])
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }

            Divider()

            Button {
                onRemove()
            } label: {
                Label("Remove from Tidyr", systemImage: "minus.circle")
            }

            Button(role: .destructive) {
                switch SafetyChecker.check(folder: source.url) {
                case .danger:
                    trashBlocked = true
                default:
                    confirmTrash = true
                }
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Move \"\(source.name)\" to Trash?",
            isPresented: $confirmTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                onRemove()
                try? FileManager.default.trashItem(at: source.url, resultingItemURL: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move the folder and all its contents to the Trash.")
        }
        .alert("Can't Move to Trash", isPresented: $trashBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This folder is protected and cannot be moved to the Trash from Tidyr.")
        }
    }
}

// MARK: - File list

struct FileListView: View {
    let source: Source
    let files: [URL]
    let ruleCount: Int
    let canUndo: Bool
    let showSettings: () -> Void
    let onCommand: (String?) -> Void
    let onRefresh: () -> Void
    let onUndo: () -> Void
    @State private var commandText = ""
    @State private var isDropTargeted = false
    @State private var dropErrorMessage: String?

    private var hasKey: Bool { KeychainHelper.hasKey }

    private func createNewFolder() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Enter a name for the new folder:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let dest = source.url.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
        onRefresh()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List(files, id: \.self) { file in
                FileRow(url: file, onDelete: onRefresh)
            }
            .listStyle(.plain)
            .padding(.bottom, hasKey ? 44 : 0)

            if hasKey {
                VStack(spacing: 0) {
                    if ruleCount > 0 {
                        Divider()
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s") active")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.06))
                    }
                    Divider()
                    CommandBar(text: $commandText, onSubmit: onCommand)
                }
                .background(.regularMaterial)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                    guard let data,
                          let srcURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let dest = source.url.appendingPathComponent(srcURL.lastPathComponent)
                    do {
                        try FileManager.default.copyItem(at: srcURL, to: dest)
                    } catch {
                        DispatchQueue.main.async {
                            dropErrorMessage = "\"\(srcURL.lastPathComponent)\" could not be copied: \(error.localizedDescription)"
                        }
                    }
                    DispatchQueue.main.async { onRefresh() }
                }
            }
            return true
        }
        .alert("Could Not Copy File", isPresented: .init(
            get: { dropErrorMessage != nil },
            set: { if !$0 { dropErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { dropErrorMessage = nil }
        } message: {
            Text(dropErrorMessage ?? "")
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(source.name)
        .navigationSubtitle("\(files.count) item\(files.count == 1 ? "" : "s")")
        .toolbar {
            if canUndo {
                ToolbarItem(placement: .automatic) {
                    Button(action: onUndo) {
                        Label("Undo", systemImage: "arrow.uturn.backward.circle")
                    }
                    .help("Undo the last session's changes to this folder")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    createNewFolder()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .help("Create a new folder here")
            }

            ToolbarItem(placement: .primaryAction) {
                if hasKey {
                    Button("Analyze") { onCommand(nil) }
                        .buttonStyle(.borderedProminent)
                        .help("Let AI suggest how to organize this folder")
                } else {
                    Button("Set Up AI Key", action: showSettings)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct CommandBar: View {
    @Binding var text: String
    let onSubmit: (String?) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.callout)
                TextField("Ask AI to organize, or press Return to analyze everything…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($isFocused)
                    .onSubmit { submit() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            )

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
            .animation(.easeInOut(duration: 0.1), value: text.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(trimmed.isEmpty ? nil : trimmed)
        text = ""
    }
}

struct FileRow: View {
    let url: URL
    let onDelete: () -> Void
    @State private var confirmTrash = false
    @State private var confirmDelete = false

    private var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    var body: some View {
        Label(url.lastPathComponent, systemImage: fileIcon)
            .padding(.vertical, 2)
            .onDrag { NSItemProvider(object: url as NSURL) }
            .contextMenu {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Divider()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.clipboard")
                }

                Divider()

                Button(role: .destructive) {
                    confirmTrash = true
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Permanently", systemImage: "trash.slash")
                }
            }
            .confirmationDialog(
                "Move \"\(url.lastPathComponent)\" to Trash?",
                isPresented: $confirmTrash,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will move the \(isDirectory ? "folder" : "file") to the Trash. You can restore it from there if needed.")
            }
            .confirmationDialog(
                "Permanently delete \"\(url.lastPathComponent)\"?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    try? FileManager.default.removeItem(at: url)
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the \(isDirectory ? "folder" : "file"). This cannot be undone.")
            }
    }

    private var fileIcon: String {
        if isDirectory { return "folder" }
        switch url.pathExtension.lowercased() {
        case "pdf":                       return "doc.richtext"
        case "jpg", "jpeg", "png", "gif",
             "heic", "webp":             return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "md":                        return "note.text"
        case "txt":                       return "doc.text"
        case "zip", "tar", "gz", "rar":  return "archivebox"
        default:                          return "doc"
        }
    }
}

// MARK: - Empty / Error states

struct EmptyStateView: View {
    let hasSources: Bool
    let hasAPIKey: Bool
    let onAddFolder: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: hasSources ? "hand.tap.fill" : "sparkles.rectangle.stack.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text(hasSources ? "Choose a folder to get started" : "Welcome to Tidyr")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text(descriptionText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            VStack(alignment: .leading, spacing: 12) {
                NextStepRow(
                    number: "1",
                    title: hasAPIKey ? "Add a folder" : "Set up your AI key",
                    detail: hasAPIKey
                        ? "Choose the folder, vault, or messy downloads area you want Tidyr to review."
                        : "Paste your Gemini API key in Settings so Tidyr can analyze your files."
                )
                NextStepRow(
                    number: "2",
                    title: hasAPIKey ? "Ask in plain language" : "Add a folder",
                    detail: hasAPIKey
                        ? "Try requests like \"sort receipts by year\" or \"group notes by topic.\""
                        : "After the key is saved, add a folder you want help organizing."
                )
                NextStepRow(
                    number: "3",
                    title: "Review before anything changes",
                    detail: "Tidyr shows suggestions first. Nothing is moved until you approve it."
                )
            }
            .padding(20)
            .frame(maxWidth: 540)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))

            HStack(spacing: 12) {
                if !hasAPIKey {
                    Button("Set Up AI Key", action: onOpenSettings)
                        .buttonStyle(.bordered)
                }
                Button(hasSources ? "Pick Another Folder" : "Add Your First Folder", action: onAddFolder)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var descriptionText: String {
        if hasSources {
            return "Select a folder from the left to see its files, then tell Tidyr how you want it organized."
        }
        return "Tidyr helps you organize files with AI, but keeps you in control by showing every suggested change before it happens."
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: (() -> Void)?
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.title2).fontWeight(.medium)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            HStack(spacing: 12) {
                Button("← Back to files", action: onBack)
                    .buttonStyle(.borderless)
                if let onRetry {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ApplyingView: View {
    let folderName: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Applying changes to \"\(folderName)\"…")
                .font(.title3)
                .fontWeight(.medium)
            Text("Tidyr is updating your folder based on the approved suggestions.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DoneView: View {
    let folderName: String
    let canUndo: Bool
    let skipped: [String]
    let repairResult: ObsidianLinkRepairer.RepairResult?
    let plexSynced: Bool?
    let onUndo: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: skipped.isEmpty ? "checkmark.circle.fill" : "checkmark.circle.trianglebadge.exclamationmark.fill")
                .font(.system(size: 52))
                .foregroundStyle(skipped.isEmpty ? .green : .orange)
            Text("Done organizing \(folderName)")
                .font(.title2)
                .fontWeight(.medium)
            VStack(spacing: 6) {
                if skipped.isEmpty {
                    Text("Your approved changes have been applied.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(skipped.count) item\(skipped.count == 1 ? " was" : "s were") skipped — a file already exists at the destination.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                if let r = repairResult, r.linksRepaired > 0 {
                    Label(
                        "\(r.linksRepaired) wikilink\(r.linksRepaired == 1 ? "" : "s") updated across \(r.filesModified) note\(r.filesModified == 1 ? "" : "s").",
                        systemImage: "link"
                    )
                    .font(.callout)
                    .foregroundStyle(.purple)
                }
                if let synced = plexSynced {
                    Label(
                        synced ? "Plex library scan triggered." : "Plex was unreachable — scan manually in Plex.",
                        systemImage: synced ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(synced ? .orange : .secondary)
                }
            }
            HStack(spacing: 12) {
                if canUndo {
                    Button("Undo changes", action: onUndo)
                        .buttonStyle(.bordered)
                }
                Button("Back to files", action: onBack)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UndoingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Putting things back...")
                .font(.title3)
                .fontWeight(.medium)
            Text("Moving files back to where they were.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NextStepRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.blue, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    ContentView()
}
