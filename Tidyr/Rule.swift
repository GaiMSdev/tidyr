import Foundation

struct PlainTextRule: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
}

enum ConditionField: String, CaseIterable, Codable {
    case nameContains   = "name contains"
    case nameStartsWith = "name starts with"
    case extensionIs    = "extension is"
}

enum RuleAction: String, CaseIterable, Codable {
    case moveToFolder     = "move to folder"
    case renameWithPrefix = "add prefix"
}

struct IfThenRule: Identifiable, Codable, Equatable {
    let id: UUID
    var conditionField: ConditionField
    var conditionValue: String
    var action: RuleAction
    var actionValue: String
}
