import SwiftUI

struct AnalysisView: View {
    let source: Source
    let response: AnalysisResponse
    @Binding var selection: SuggestionSelection
    let onApprove: () -> Void
    let onBack: () -> Void

    var approvedCount: Int { selection.approved.count }

    private var groups: [SuggestionGroup] {
        var orderedKeys: [String] = []
        var buckets: [String: [Suggestion]] = [:]
        var ungrouped: [Suggestion] = []

        for suggestion in response.suggestions {
            let key: String?
            switch suggestion.type {
            case .createFolder: key = suggestion.folderName
            case .move:         key = suggestion.destination
            case .rename:       key = nil
            }

            if let key = key, !key.isEmpty {
                if buckets[key] == nil { orderedKeys.append(key) }
                buckets[key, default: []].append(suggestion)
            } else {
                ungrouped.append(suggestion)
            }
        }

        var result = orderedKeys.map { key in
            SuggestionGroup(id: key, title: key, suggestions: buckets[key] ?? [])
        }
        if !ungrouped.isEmpty {
            result.append(SuggestionGroup(id: "_other", title: "Other changes", suggestions: ungrouped))
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                // Summary banner as first row
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    Text(response.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.blue.opacity(0.06))
                .listRowSeparator(.hidden)

                if response.suggestions.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.green)
                        Text("Already well organized!")
                            .font(.title2).fontWeight(.medium)
                        Text("The AI didn't find anything worth changing.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(groups) { group in
                        if group.suggestions.count > 1 {
                            groupHeader(for: group)
                        }
                        ForEach(group.suggestions) { suggestion in
                            SuggestionRow(
                                suggestion: suggestion,
                                isApproved: selection.isApproved(suggestion.id),
                                onToggle: { selection.toggle(suggestion.id) }
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
            .padding(.bottom, 56)

            // Bottom action bar
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("Back to files") { onBack() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if approvedCount > 0 {
                        Button("Apply \(approvedCount) change\(approvedCount == 1 ? "" : "s")") {
                            onApprove()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Text("Select suggestions to approve them")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .navigationTitle(source.name)
        .navigationSubtitle("AI Suggestions")
        .toolbar {
            if !response.suggestions.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Clear") { selection.clear() }
                        .buttonStyle(.bordered)
                        .disabled(selection.approved.isEmpty)
                    Button("Approve All") { selection.approveAll(response.suggestions) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func groupHeader(for group: SuggestionGroup) -> some View {
        let allApproved = selection.allApproved(group.suggestions)

        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .font(.callout)
            Text(group.title)
                .fontWeight(.semibold)
                .font(.subheadline)
            Text("(\(group.suggestions.count))")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            Button(allApproved ? "Deselect all" : "Select all") {
                if allApproved {
                    selection.deselect(group.suggestions)
                } else {
                    selection.approve(group.suggestions)
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .listRowSeparator(.hidden)
    }
}

struct SuggestionGroup: Identifiable {
    let id: String
    let title: String
    let suggestions: [Suggestion]
}

struct SuggestionRow: View {
    let suggestion: Suggestion
    let isApproved: Bool
    let onToggle: () -> Void

    var iconColor: Color {
        switch suggestion.type {
        case .createFolder: return .blue
        case .move:         return .orange
        case .rename:       return .purple
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.description)
                    .fontWeight(.medium)
                Text(suggestion.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isApproved ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isApproved ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}

struct AnalyzingView: View {
    let folderName: String
    let command: String?

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)

            if let cmd = command {
                Text("Working on your request…")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("\"\(cmd)\"")
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else {
                Text("Analyzing \"\(folderName)\"…")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Gemini is reading your files and thinking of the best way to organize them.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
