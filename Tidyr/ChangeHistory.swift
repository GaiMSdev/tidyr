import Foundation

// A single file operation that can be reversed
enum UndoOperation: Codable {
    case moved(originalURL: URL, movedToURL: URL)
    case renamed(originalURL: URL, renamedToURL: URL)
    case createdFolder(URL)
}

// One complete round of approved changes
struct ChangeSession: Identifiable, Codable {
    let id: UUID
    let date: Date
    let folderName: String
    let sourceURL: URL?       // nil in sessions saved before this field was added
    let operations: [UndoOperation]

    init(id: UUID, date: Date, folderName: String, sourceURL: URL? = nil, operations: [UndoOperation]) {
        self.id = id; self.date = date; self.folderName = folderName
        self.sourceURL = sourceURL; self.operations = operations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,    forKey: .id)
        date       = try c.decode(Date.self,    forKey: .date)
        folderName = try c.decode(String.self,  forKey: .folderName)
        sourceURL  = try c.decodeIfPresent(URL.self, forKey: .sourceURL)
        operations = try c.decode([UndoOperation].self, forKey: .operations)
    }

    var count: Int { operations.filter { if case .createdFolder = $0 { return false }; return true }.count }

    var changeSummary: String {
        let moves   = operations.filter { if case .moved       = $0 { return true }; return false }.count
        let renames = operations.filter { if case .renamed     = $0 { return true }; return false }.count
        let folders = operations.filter { if case .createdFolder = $0 { return true }; return false }.count

        var parts: [String] = []
        if moves   > 0 { parts.append("\(moves) move\(moves == 1 ? "" : "s")") }
        if renames > 0 { parts.append("\(renames) rename\(renames == 1 ? "" : "s")") }
        if folders > 0 { parts.append("\(folders) folder\(folders == 1 ? "" : "s") created") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }

    var formattedDate: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "h:mm a"
        } else if cal.isDateInYesterday(date) {
            f.dateFormat = "'Yesterday at' h:mm a"
        } else {
            f.dateFormat = "MMM d 'at' h:mm a"
        }
        return f.string(from: date)
    }
}
