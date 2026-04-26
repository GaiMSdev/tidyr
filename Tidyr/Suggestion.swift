import Foundation

struct Suggestion: Identifiable, Codable {
    let id: Int
    let type: ActionType
    let description: String
    let reason: String
    let folderName: String?
    let fileName: String?
    let destination: String?
    let newName: String?

    enum ActionType: String, Codable {
        case createFolder = "create_folder"
        case move         = "move"
        case rename       = "rename"
    }

    var icon: String {
        switch type {
        case .createFolder: return "folder.badge.plus"
        case .move:         return "arrow.right.circle.fill"
        case .rename:       return "pencil.circle.fill"
        }
    }
}

struct AnalysisResponse: Codable {
    let summary: String
    let suggestions: [Suggestion]
}

struct SuggestionSelection {
    var approved: Set<Int> = []

    mutating func toggle(_ id: Int) {
        if approved.contains(id) { approved.remove(id) }
        else { approved.insert(id) }
    }

    mutating func approveAll(_ suggestions: [Suggestion]) {
        approved = Set(suggestions.map(\.id))
    }

    mutating func approve(_ suggestions: [Suggestion]) {
        approved.formUnion(suggestions.map(\.id))
    }

    mutating func deselect(_ suggestions: [Suggestion]) {
        approved.subtract(suggestions.map(\.id))
    }

    mutating func clear() { approved.removeAll() }

    func isApproved(_ id: Int) -> Bool { approved.contains(id) }

    func allApproved(_ suggestions: [Suggestion]) -> Bool {
        !suggestions.isEmpty && suggestions.allSatisfy { approved.contains($0.id) }
    }
}
