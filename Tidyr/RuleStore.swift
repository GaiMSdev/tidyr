import Foundation
import Observation

@Observable
class RuleStore {
    var plainRules: [PlainTextRule] = []
    var ifThenRules: [IfThenRule] = []

    private let saveURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tidyr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rules.json")
    }()

    init() { load() }

    var totalCount: Int { plainRules.count + ifThenRules.count }

    // Returns a formatted string ready to inject into the analysis prompt, or nil if no rules.
    var promptText: String? {
        var lines: [String] = []
        for rule in plainRules {
            let t = rule.text.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { lines.append("- \(t)") }
        }
        for rule in ifThenRules where !rule.conditionValue.isEmpty && !rule.actionValue.isEmpty {
            lines.append("- IF file \(rule.conditionField.rawValue) \"\(rule.conditionValue)\" THEN \(rule.action.rawValue) \"\(rule.actionValue)\"")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    func save() {
        struct Payload: Codable {
            var plainRules: [PlainTextRule]
            var ifThenRules: [IfThenRule]
        }
        try? JSONEncoder()
            .encode(Payload(plainRules: plainRules, ifThenRules: ifThenRules))
            .write(to: saveURL)
    }

    private func load() {
        struct Payload: Codable {
            var plainRules: [PlainTextRule]
            var ifThenRules: [IfThenRule]
        }
        guard
            let data = try? Data(contentsOf: saveURL),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        plainRules = payload.plainRules
        ifThenRules = payload.ifThenRules
    }
}
