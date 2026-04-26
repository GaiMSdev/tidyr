import SwiftUI

struct HistoryView: View {
    var store: SourceStore
    @State private var undoingID: UUID?
    @State private var errorMessage: String?

    private var grouped: [(label: String, sessions: [ChangeSession])] {
        let cal = Calendar.current
        var today:     [ChangeSession] = []
        var yesterday: [ChangeSession] = []
        var older:     [ChangeSession] = []

        for session in store.history {
            if cal.isDateInToday(session.date)     { today.append(session) }
            else if cal.isDateInYesterday(session.date) { yesterday.append(session) }
            else                                   { older.append(session) }
        }

        var result: [(String, [ChangeSession])] = []
        if !today.isEmpty     { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !older.isEmpty     { result.append(("Earlier", older)) }
        return result
    }

    var body: some View {
        Group {
            if store.history.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(grouped, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.sessions) { session in
                                SessionRow(
                                    session: session,
                                    isUndoing: undoingID == session.id,
                                    onUndo: { performUndo(session) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("History")
        .navigationSubtitle(store.history.isEmpty ? "No sessions" : "\(store.history.count) session\(store.history.count == 1 ? "" : "s")")
        .toolbar {
            if !store.history.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All") { store.clearHistory() }
                        .foregroundStyle(.red)
                        .help("Remove all history entries")
                }
            }
        }
        .alert("Undo failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 8) {
                Text("No history yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Every time you approve changes, a session is saved here so you can review or undo it later.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func performUndo(_ session: ChangeSession) {
        undoingID = session.id
        Task {
            do {
                try await store.undoSession(session)
            } catch {
                errorMessage = error.localizedDescription
            }
            undoingID = nil
        }
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: ChangeSession
    let isUndoing: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Folder icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(session.folderName)
                    .fontWeight(.semibold)
                Text(session.changeSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right side: time + undo button
            VStack(alignment: .trailing, spacing: 6) {
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if isUndoing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Undoing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    let store = SourceStore()
    store.history = [
        ChangeSession(
            id: UUID(), date: Date(),
            folderName: "Downloads",
            operations: [
                .moved(originalURL: URL(fileURLWithPath: "/Downloads/a.pdf"),
                       movedToURL: URL(fileURLWithPath: "/Downloads/Docs/a.pdf")),
                .moved(originalURL: URL(fileURLWithPath: "/Downloads/b.jpg"),
                       movedToURL: URL(fileURLWithPath: "/Downloads/Photos/b.jpg")),
                .createdFolder(URL(fileURLWithPath: "/Downloads/Docs")),
            ]
        ),
        ChangeSession(
            id: UUID(), date: Date().addingTimeInterval(-86400),
            folderName: "Desktop",
            operations: [
                .renamed(originalURL: URL(fileURLWithPath: "/Desktop/IMG_001.jpg"),
                         renamedToURL: URL(fileURLWithPath: "/Desktop/vacation.jpg")),
            ]
        ),
    ]
    return HistoryView(store: store)
        .frame(width: 600, height: 500)
}
