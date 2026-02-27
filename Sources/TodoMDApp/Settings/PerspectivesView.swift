import SwiftUI

private enum PerspectiveRuleGroup {
    case all
    case any
    case none

    var title: String {
        switch self {
        case .all:
            return "All (AND)"
        case .any:
            return "Any (OR)"
        case .none:
            return "Exclude (NOT)"
        }
    }
}

struct PerspectivesView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var editingPerspective: PerspectiveDefinition?

    var body: some View {
        List {
            if container.perspectives.isEmpty {
                ContentUnavailableView(
                    "No Perspectives",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Create saved filters with AND / OR / NOT rules.")
                )
            } else {
                ForEach(container.perspectives) { perspective in
                    Button {
                        editingPerspective = perspective
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(perspective.name)
                                .font(.headline)
                            Text(summary(for: perspective))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        let perspective = container.perspectives[index]
                        container.deletePerspective(id: perspective.id)
                    }
                }
                .onMove { source, destination in
                    container.movePerspectives(from: source, to: destination)
                }
            }
        }
        .navigationTitle("Perspectives")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingPerspective = PerspectiveDefinition(name: "")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("perspectives.addButton")
            }
        }
        .sheet(item: $editingPerspective) { perspective in
            NavigationStack {
                PerspectiveEditorView(initialPerspective: perspective) { saved in
                    container.savePerspective(saved)
                    editingPerspective = nil
                }
            }
        }
    }

    private func summary(for perspective: PerspectiveDefinition) -> String {
        let all = perspective.allRules.count
        let any = perspective.anyRules.count
        let none = perspective.noneRules.count
        return "AND: \(all) · OR: \(any) · NOT: \(none)"
    }
}

private struct PerspectiveEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let initialPerspective: PerspectiveDefinition
    let onSave: (PerspectiveDefinition) -> Void

    @State private var name: String
    @State private var allRules: [PerspectiveRule]
    @State private var anyRules: [PerspectiveRule]
    @State private var noneRules: [PerspectiveRule]

    init(initialPerspective: PerspectiveDefinition, onSave: @escaping (PerspectiveDefinition) -> Void) {
        self.initialPerspective = initialPerspective
        self.onSave = onSave
        _name = State(initialValue: initialPerspective.name)
        _allRules = State(initialValue: initialPerspective.allRules)
        _anyRules = State(initialValue: initialPerspective.anyRules)
        _noneRules = State(initialValue: initialPerspective.noneRules)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Perspective name", text: $name)
                    .accessibilityIdentifier("perspectives.nameField")
            }

            rulesSection(group: .all, rules: $allRules)
            rulesSection(group: .any, rules: $anyRules)
            rulesSection(group: .none, rules: $noneRules)
        }
        .navigationTitle("Edit Perspective")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        PerspectiveDefinition(
                            id: initialPerspective.id,
                            name: name,
                            allRules: allRules,
                            anyRules: anyRules,
                            noneRules: noneRules
                        )
                    )
                }
                .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let all = allRules + anyRules + noneRules
        return all.allSatisfy { rule in
            if !requiresValue(rule.operator) {
                return true
            }
            return !rule.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @ViewBuilder
    private func rulesSection(group: PerspectiveRuleGroup, rules: Binding<[PerspectiveRule]>) -> some View {
        Section(group.title) {
            if rules.wrappedValue.isEmpty {
                Text("No rules")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rules) { $rule in
                    PerspectiveRuleEditor(rule: $rule)
                }
                .onDelete { offsets in
                    rules.wrappedValue.remove(atOffsets: offsets)
                }
            }

            Button {
                rules.wrappedValue.append(
                    PerspectiveRule(
                        field: .status,
                        operator: .equals,
                        value: TaskStatus.todo.rawValue
                    )
                )
            } label: {
                Label("Add Rule", systemImage: "plus.circle")
            }
        }
    }

    private func requiresValue(_ operatorValue: PerspectiveOperator) -> Bool {
        switch operatorValue {
        case .equals, .contains:
            return true
        default:
            return false
        }
    }
}

private struct PerspectiveRuleEditor: View {
    @Binding var rule: PerspectiveRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Field", selection: $rule.field) {
                ForEach(PerspectiveField.allCases, id: \.self) { field in
                    Text(fieldLabel(field)).tag(field)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: rule.field) { _, newField in
                let supported = operators(for: newField)
                if !supported.contains(rule.operator), let first = supported.first {
                    rule.operator = first
                }
            }

            Picker("Operator", selection: $rule.operator) {
                ForEach(operators(for: rule.field), id: \.self) { op in
                    Text(operatorLabel(op)).tag(op)
                }
            }
            .pickerStyle(.menu)

            if requiresValue(rule.operator) {
                if rule.field == .status {
                    Picker("Value", selection: $rule.value) {
                        ForEach(TaskStatus.allCases, id: \.rawValue) { status in
                            Text(status.rawValue).tag(status.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } else if rule.field == .priority {
                    Picker("Value", selection: $rule.value) {
                        ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                            Text(priority.rawValue).tag(priority.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    TextField(valuePlaceholder(for: rule.field), text: $rule.value)
                        .textInputAutocapitalization(.never)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func operators(for field: PerspectiveField) -> [PerspectiveOperator] {
        switch field {
        case .status, .priority:
            return [.equals, .isSet, .isNotSet]
        case .area, .project, .tags, .source:
            return [.equals, .contains, .isSet, .isNotSet]
        case .flagged:
            return [.isTrue, .isFalse]
        case .due, .scheduled, .defer:
            return [.isSet, .isNotSet, .beforeToday, .onToday, .afterToday, .equals]
        }
    }

    private func requiresValue(_ operatorValue: PerspectiveOperator) -> Bool {
        switch operatorValue {
        case .equals, .contains:
            return true
        default:
            return false
        }
    }

    private func fieldLabel(_ field: PerspectiveField) -> String {
        switch field {
        case .status:
            return "Status"
        case .due:
            return "Due"
        case .scheduled:
            return "Scheduled"
        case .defer:
            return "Defer"
        case .priority:
            return "Priority"
        case .flagged:
            return "Flagged"
        case .area:
            return "Area"
        case .project:
            return "Project"
        case .tags:
            return "Tags"
        case .source:
            return "Source"
        }
    }

    private func operatorLabel(_ op: PerspectiveOperator) -> String {
        switch op {
        case .equals:
            return "Equals"
        case .contains:
            return "Contains"
        case .isSet:
            return "Set"
        case .isNotSet:
            return "Not Set"
        case .beforeToday:
            return "< Today"
        case .onToday:
            return "Today"
        case .afterToday:
            return "> Today"
        case .isTrue:
            return "True"
        case .isFalse:
            return "False"
        }
    }

    private func valuePlaceholder(for field: PerspectiveField) -> String {
        switch field {
        case .status:
            return "todo"
        case .priority:
            return "high"
        case .area:
            return "Work"
        case .project:
            return "Roadmap"
        case .tags:
            return "home"
        case .source:
            return "shortcut"
        case .due, .scheduled, .defer:
            return "YYYY-MM-DD"
        case .flagged:
            return "true"
        }
    }
}
