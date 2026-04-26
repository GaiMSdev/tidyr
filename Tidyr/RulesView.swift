import SwiftUI

struct RulesView: View {
    @Bindable var ruleStore: RuleStore
    @State private var newRuleText = ""
    @FocusState private var newRuleFocused: Bool

    var body: some View {
        List {
            Section {
                ForEach(ruleStore.plainRules) { rule in
                    PlainRuleRow(rule: rule) {
                        ruleStore.plainRules.removeAll { $0.id == rule.id }
                        ruleStore.save()
                    }
                }

                HStack(spacing: 8) {
                    TextField("e.g. always put receipts in Finance", text: $newRuleText)
                        .textFieldStyle(.plain)
                        .focused($newRuleFocused)
                        .onSubmit { addPlainRule() }
                    Button("Add") { addPlainRule() }
                        .buttonStyle(.bordered)
                        .disabled(newRuleText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Plain-language rules")
            } footer: {
                Text("Describe what you want in plain English. Tidyr passes these to the AI on every analysis.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($ruleStore.ifThenRules) { $rule in
                    IfThenRuleRow(rule: $rule) {
                        ruleStore.ifThenRules.removeAll { $0.id == rule.id }
                        ruleStore.save()
                    } onSave: {
                        ruleStore.save()
                    }
                }

                Button {
                    ruleStore.ifThenRules.append(IfThenRule(
                        id: UUID(),
                        conditionField: .nameContains,
                        conditionValue: "",
                        action: .moveToFolder,
                        actionValue: ""
                    ))
                    ruleStore.save()
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, 2)
            } header: {
                Text("If–then rules")
            } footer: {
                Text("Precise rules with conditions and actions. These are always applied when analyzing a folder.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .navigationTitle("Rules")
        .navigationSubtitle(subtitleText)
    }

    private var subtitleText: String {
        let n = ruleStore.totalCount
        return n == 0 ? "No rules yet" : "\(n) rule\(n == 1 ? "" : "s")"
    }

    private func addPlainRule() {
        let trimmed = newRuleText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ruleStore.plainRules.append(PlainTextRule(id: UUID(), text: trimmed))
        ruleStore.save()
        newRuleText = ""
    }
}

// MARK: - Plain rule row

private struct PlainRuleRow: View {
    let rule: PlainTextRule
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "text.quote")
                .foregroundStyle(.blue)
                .font(.callout)
                .frame(width: 20)
            Text(rule.text)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Delete rule")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - If-then rule row

private struct IfThenRuleRow: View {
    @Binding var rule: IfThenRule
    let onDelete: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("IF")
                .font(.callout).fontWeight(.medium)
                .foregroundStyle(.secondary)

            Picker("", selection: $rule.conditionField) {
                ForEach(ConditionField.allCases, id: \.self) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: rule.conditionField) { onSave() }

            TextField("value", text: $rule.conditionValue)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 80, maxWidth: 130)
                .onChange(of: rule.conditionValue) { onSave() }

            Text("THEN")
                .font(.callout).fontWeight(.medium)
                .foregroundStyle(.secondary)

            Picker("", selection: $rule.action) {
                ForEach(RuleAction.allCases, id: \.self) { action in
                    Text(action.rawValue).tag(action)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: rule.action) { onSave() }

            TextField(actionPlaceholder, text: $rule.actionValue)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 80, maxWidth: 130)
                .onChange(of: rule.actionValue) { onSave() }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Delete rule")
        }
        .padding(.vertical, 2)
    }

    private var actionPlaceholder: String {
        switch rule.action {
        case .moveToFolder:     return "folder name"
        case .renameWithPrefix: return "prefix text"
        }
    }
}

#Preview {
    let store = RuleStore()
    store.plainRules = [
        PlainTextRule(id: UUID(), text: "always put receipts in Finance"),
        PlainTextRule(id: UUID(), text: "group notes by topic"),
    ]
    store.ifThenRules = [
        IfThenRule(id: UUID(), conditionField: .nameContains, conditionValue: "invoice", action: .moveToFolder, actionValue: "Invoices"),
    ]
    return RulesView(ruleStore: store)
        .frame(width: 600, height: 500)
}
