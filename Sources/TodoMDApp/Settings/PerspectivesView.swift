import SwiftUI
import UniformTypeIdentifiers

struct PerspectivesView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var editingPerspective: PerspectiveDefinition?
    @State private var pendingDeletePerspective: PerspectiveDefinition?

    var body: some View {
        List {
            if container.perspectives.isEmpty {
                ContentUnavailableView(
                    "No Perspectives",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Create saved filters with nested AND / OR / NOT rules.")
                )
            } else {
                ForEach(container.perspectives) { perspective in
                    Button {
                        editingPerspective = perspective
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: perspective.icon)
                                .foregroundStyle(color(forHex: perspective.color) ?? .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(perspective.name)
                                    .font(.headline)
                                Text(summary(for: perspective))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") {
                            editingPerspective = perspective
                        }
                        Button("Duplicate") {
                            editingPerspective = container.duplicatePerspective(id: perspective.id)
                        }
                        Button("Delete", role: .destructive) {
                            pendingDeletePerspective = perspective
                        }
                    }
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
                    editingPerspective = PerspectiveDefinition()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("perspectives.addButton")
            }
        }
        .alert(
            "Delete Perspective",
            isPresented: Binding(
                get: { pendingDeletePerspective != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletePerspective = nil }
                }
            ),
            actions: {
                Button("Delete", role: .destructive) {
                    if let pendingDeletePerspective {
                        container.deletePerspective(id: pendingDeletePerspective.id)
                        self.pendingDeletePerspective = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletePerspective = nil
                }
            },
            message: {
                Text("Delete '\(pendingDeletePerspective?.name ?? "")'? This cannot be undone.")
            }
        )
        .sheet(item: $editingPerspective) { perspective in
            NavigationStack {
                PerspectiveEditorSheet(initialPerspective: perspective) { saved in
                    container.savePerspective(saved)
                    editingPerspective = nil
                }
            }
        }
    }

    private func summary(for perspective: PerspectiveDefinition) -> String {
        let ruleCount = countRules(in: perspective.effectiveRules)
        let groupCount = countGroups(in: perspective.effectiveRules)
        return "\(ruleCount) rule\(ruleCount == 1 ? "" : "s") · \(groupCount) group\(groupCount == 1 ? "" : "s")"
    }

    private func countRules(in group: PerspectiveRuleGroup) -> Int {
        group.conditions.reduce(into: 0) { count, condition in
            switch condition {
            case .rule:
                count += 1
            case .group(let subgroup):
                count += countRules(in: subgroup)
            }
        }
    }

    private func countGroups(in group: PerspectiveRuleGroup) -> Int {
        1 + group.conditions.reduce(into: 0) { count, condition in
            if case .group(let subgroup) = condition {
                count += countGroups(in: subgroup)
            }
        }
    }

    private func color(forHex hex: String?) -> Color? {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

struct PerspectiveEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialPerspective: PerspectiveDefinition
    let onSave: (PerspectiveDefinition) -> Void

    @State private var name: String
    @State private var icon: String
    @State private var color: String?
    @State private var sortField: PerspectiveSortField
    @State private var groupBy: PerspectiveGroupBy
    @State private var layout: PerspectiveLayout
    @State private var rootRules: PerspectiveRuleGroup
    @StateObject private var dragState = PerspectiveRuleDragState()

    private let iconChoices = ["list.bullet", "briefcase", "house", "star", "heart", "bolt", "clock", "tag", "flag", "checkmark.circle"]
    private let colorChoices: [(name: String, hex: String?)] = [
        ("Default", nil),
        ("Blue", "#4A90D9"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Red", "#FF3B30"),
        ("Pink", "#FF2D55"),
        ("Teal", "#30B0C7"),
        ("Gray", "#8E8E93")
    ]
    private let sortChoices: [PerspectiveSortField] = [.due, .scheduled, .defer, .priority, .estimatedMinutes, .title, .created, .modified, .completed, .flagged, .manual]
    private let groupChoices: [PerspectiveGroupBy] = [.none, .area, .project, .tag, .tags, .priority, .due, .scheduled, .defer, .flagged, .source]
    private let layoutChoices: [PerspectiveLayout] = [.default, .comfortable, .compact, .detailed]

    init(initialPerspective: PerspectiveDefinition, onSave: @escaping (PerspectiveDefinition) -> Void) {
        self.initialPerspective = initialPerspective
        self.onSave = onSave
        _name = State(initialValue: initialPerspective.name)
        _icon = State(initialValue: initialPerspective.icon)
        _color = State(initialValue: initialPerspective.color)
        _sortField = State(initialValue: initialPerspective.sort.field)
        _groupBy = State(initialValue: initialPerspective.groupBy)
        _layout = State(initialValue: initialPerspective.layout)
        _rootRules = State(initialValue: initialPerspective.effectiveRules)
    }

    var body: some View {
        Form {
            Section("General") {
                TextField("Perspective name", text: $name)
                    .onChange(of: name) { _, newValue in
                        if newValue.count > 100 {
                            name = String(newValue.prefix(100))
                        }
                    }
                    .accessibilityIdentifier("perspectives.nameField")

                Picker("Icon", selection: $icon) {
                    ForEach(iconChoices, id: \.self) { symbol in
                        Label(symbol, systemImage: symbol).tag(symbol)
                    }
                }

                Picker("Color", selection: Binding(
                    get: { color ?? "" },
                    set: { color = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(colorChoices, id: \.name) { choice in
                        HStack {
                            Circle()
                                .fill(color(forHex: choice.hex) ?? .accentColor)
                                .frame(width: 12, height: 12)
                            Text(choice.name)
                        }
                        .tag(choice.hex ?? "")
                    }
                }
            }

            Section("Structure") {
                Picker("Sort", selection: $sortField) {
                    ForEach(sortChoices, id: \.self) { field in
                        Text(sortLabel(field)).tag(field)
                    }
                }
                Picker("Group By", selection: $groupBy) {
                    ForEach(groupChoices, id: \.self) { value in
                        Text(groupLabel(value)).tag(value)
                    }
                }
                Picker("Layout", selection: $layout) {
                    ForEach(layoutChoices, id: \.self) { value in
                        Text(layoutLabel(value)).tag(value)
                    }
                }
            }

            Section("Rules") {
                PerspectiveRuleGroupEditor(
                    group: $rootRules,
                    rootGroup: $rootRules,
                    depth: 0,
                    dragState: dragState
                )
            }
        }
        .navigationTitle("Edit Perspective")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var updated = initialPerspective
                    updated.name = name
                    updated.icon = icon
                    updated.color = color
                    updated.sort = PerspectiveSort(field: sortField, direction: .asc)
                    updated.groupBy = groupBy
                    updated.layout = layout
                    updated.rules = rootRules
                    let legacy = extractLegacyRules(from: rootRules)
                    updated.allRules = legacy.all
                    updated.anyRules = legacy.any
                    updated.noneRules = legacy.none
                    onSave(updated)
                }
                .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func extractLegacyRules(from group: PerspectiveRuleGroup) -> (all: [PerspectiveRule], any: [PerspectiveRule], none: [PerspectiveRule]) {
        guard group.operator == .and else { return ([], [], []) }

        var allRules: [PerspectiveRule] = []
        var anyRules: [PerspectiveRule] = []
        var noneRules: [PerspectiveRule] = []

        for condition in group.conditions {
            switch condition {
            case .rule(let rule):
                allRules.append(rule)
            case .group(let subgroup):
                let rules = subgroup.conditions.compactMap { condition -> PerspectiveRule? in
                    if case .rule(let rule) = condition { return rule }
                    return nil
                }
                if rules.count != subgroup.conditions.count { continue }
                switch subgroup.operator {
                case .or:
                    anyRules.append(contentsOf: rules)
                case .not:
                    noneRules.append(contentsOf: rules)
                default:
                    break
                }
            }
        }

        return (allRules, anyRules, noneRules)
    }

    private func sortLabel(_ value: PerspectiveSortField) -> String {
        switch value {
        case .due: return "Due Date"
        case .scheduled: return "Scheduled Date"
        case .defer: return "Defer Date"
        case .priority: return "Priority"
        case .estimatedMinutes: return "Estimated Time"
        case .title: return "Title"
        case .created: return "Created Date"
        case .modified: return "Modified Date"
        case .completed: return "Completed Date"
        case .flagged: return "Flagged"
        case .manual: return "Manual"
        case .unknown(let value): return value
        }
    }

    private func groupLabel(_ value: PerspectiveGroupBy) -> String {
        switch value {
        case .none: return "None"
        case .area: return "Area"
        case .project: return "Project"
        case .tag: return "Tag"
        case .tags: return "Tags"
        case .priority: return "Priority"
        case .due: return "Due Date"
        case .scheduled: return "Scheduled Date"
        case .defer: return "Defer Date"
        case .flagged: return "Flagged"
        case .source: return "Source"
        case .unknown(let value): return value
        }
    }

    private func layoutLabel(_ value: PerspectiveLayout) -> String {
        switch value {
        case .default: return "Default"
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
        case .detailed: return "Detailed"
        case .unknown(let value): return value
        }
    }

    private func color(forHex hex: String?) -> Color? {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

struct BuiltInPerspectiveRulesView: View {
    @Environment(\.dismiss) private var dismiss

    let perspective: PerspectiveDefinition
    let onDuplicate: () -> Void

    var body: some View {
        List {
            Section("Rules") {
                PerspectiveRuleGroupReadonlyView(group: perspective.effectiveRules, depth: 0)
            }
            Section {
                Button("Duplicate as Custom Perspective") {
                    onDuplicate()
                    dismiss()
                }
            }
        }
        .navigationTitle("\(perspective.name) Rules")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}

private struct PerspectiveRuleGroupReadonlyView: View {
    let group: PerspectiveRuleGroup
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(groupTitle(group.operator))
                .font(.subheadline.weight(.semibold))
            ForEach(group.conditions, id: \.id) { condition in
                switch condition {
                case .rule(let rule):
                    Text("• \(ruleDescription(rule))")
                        .font(.subheadline)
                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                case .group(let subgroup):
                    PerspectiveRuleGroupReadonlyView(group: subgroup, depth: depth + 1)
                        .padding(.leading, 14)
                }
            }
        }
    }

    private func groupTitle(_ op: PerspectiveLogicalOperator) -> String {
        switch op {
        case .and: return "All of the following"
        case .or: return "Any of the following"
        case .not: return "None of the following"
        case .unknown(let raw): return raw
        }
    }

    private func ruleDescription(_ rule: PerspectiveRule) -> String {
        "\(fieldLabel(rule.field)) \(operatorLabel(rule.operator)) \(rule.stringValue)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fieldLabel(_ field: PerspectiveField) -> String {
        switch field {
        case .status: return "status"
        case .due: return "due date"
        case .scheduled: return "scheduled date"
        case .defer: return "defer date"
        case .priority: return "priority"
        case .flagged: return "flagged"
        case .area: return "area"
        case .project: return "project"
        case .tags: return "tags"
        case .source: return "source"
        case .title: return "title"
        case .body: return "body"
        case .created: return "created date"
        case .completed: return "completed date"
        case .modified: return "modified date"
        case .estimatedMinutes: return "estimated time"
        case .recurrence: return "recurrence"
        case .unknown(let value): return value
        }
    }

    private func operatorLabel(_ op: PerspectiveOperator) -> String {
        switch op {
        case .equals: return "equals"
        case .notEquals: return "does not equal"
        case .in: return "is in"
        case .contains: return "contains"
        case .containsAny: return "contains any of"
        case .containsAll: return "contains all of"
        case .isSet, .isNotNil: return "is set"
        case .isNotSet, .isNil: return "is not set"
        case .beforeToday: return "is before today"
        case .onToday: return "is on today"
        case .afterToday: return "is after today"
        case .before: return "is before"
        case .after: return "is after"
        case .on: return "is on"
        case .onOrBefore: return "is on or before"
        case .between: return "is between"
        case .lessThan: return "is less than"
        case .greaterThan: return "is greater than"
        case .stringContains: return "text contains"
        case .isTrue: return "is true"
        case .isFalse: return "is false"
        case .inPast: return "is in past"
        case .inNext: return "is in next"
        case .unknown(let value): return value
        }
    }
}

private final class PerspectiveRuleDragState: ObservableObject {
    @Published var draggedConditionID: String?
}

private struct PerspectiveRuleGroupEditor: View {
    @Binding var group: PerspectiveRuleGroup
    @Binding var rootGroup: PerspectiveRuleGroup
    let depth: Int
    let dragState: PerspectiveRuleDragState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Operator", selection: $group.operator) {
                    Text("All").tag(PerspectiveLogicalOperator.and)
                    Text("Any").tag(PerspectiveLogicalOperator.or)
                    Text("None").tag(PerspectiveLogicalOperator.not)
                }
                .pickerStyle(.segmented)

                Toggle("On", isOn: $group.isEnabled)
                    .labelsHidden()
            }

            ForEach(Array(group.conditions.enumerated()), id: \.element.id) { index, condition in
                conditionRow(condition: condition, at: index)
                    .onDrag {
                        dragState.draggedConditionID = condition.id
                        return NSItemProvider(object: condition.id as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: PerspectiveConditionDropDelegate(
                            rootGroup: $rootGroup,
                            dragState: dragState,
                            destinationGroupID: group.id,
                            destinationConditionID: condition.id
                        )
                    )
            }

            dropTarget
                .onDrop(
                    of: [UTType.text],
                    delegate: PerspectiveConditionDropDelegate(
                        rootGroup: $rootGroup,
                        dragState: dragState,
                        destinationGroupID: group.id,
                        destinationConditionID: nil
                    )
                )

            if !group.conditions.isEmpty {
                Text("Drag rules or groups to reorder or move across groups.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Button {
                    group.conditions.append(
                        .rule(PerspectiveRule(
                            field: .status,
                            operator: .in,
                            jsonValue: .array([.string(TaskStatus.todo.rawValue), .string(TaskStatus.inProgress.rawValue)])
                        ))
                    )
                } label: {
                    Label("Add Rule", systemImage: "plus.circle")
                }

                Button {
                    group.conditions.append(.group(PerspectiveRuleGroup(operator: .and, conditions: [])))
                } label: {
                    Label("Add Group", systemImage: "square.stack.3d.up")
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func conditionRow(condition: PerspectiveCondition, at index: Int) -> some View {
        switch condition {
        case .rule:
            VStack(alignment: .leading, spacing: 6) {
                PerspectiveRuleEditor(rule: ruleBinding(at: index))
                HStack(spacing: 14) {
                    Button("Up") { moveCondition(from: index, delta: -1) }
                        .disabled(index == 0)
                    Button("Down") { moveCondition(from: index, delta: 1) }
                        .disabled(index >= group.conditions.count - 1)
                    Button(ruleEnabled(at: index) ? "Turn Off" : "Turn On") {
                        toggleRuleEnabled(at: index)
                    }
                    Button("Delete", role: .destructive) {
                        group.conditions.remove(at: index)
                    }
                }
                .font(.caption)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
        case .group:
            VStack(alignment: .leading, spacing: 8) {
                PerspectiveRuleGroupEditor(
                    group: groupBinding(at: index),
                    rootGroup: $rootGroup,
                    depth: depth + 1,
                    dragState: dragState
                )
                HStack(spacing: 14) {
                    Button("Up") { moveCondition(from: index, delta: -1) }
                        .disabled(index == 0)
                    Button("Down") { moveCondition(from: index, delta: 1) }
                        .disabled(index >= group.conditions.count - 1)
                    Button("Delete Group", role: .destructive) {
                        group.conditions.remove(at: index)
                    }
                }
                .font(.caption)
            }
            .padding(.leading, 12)
        }
    }

    private var dropTarget: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            .foregroundStyle(.tertiary)
            .frame(height: 26)
            .overlay {
                Text("Drop Here")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
    }

    private func ruleBinding(at index: Int) -> Binding<PerspectiveRule> {
        Binding(
            get: {
                guard index < group.conditions.count,
                      case .rule(let rule) = group.conditions[index] else {
                    return PerspectiveRule(field: .status, operator: .equals, value: TaskStatus.todo.rawValue)
                }
                return rule
            },
            set: { newRule in
                guard index < group.conditions.count else { return }
                group.conditions[index] = .rule(newRule)
            }
        )
    }

    private func groupBinding(at index: Int) -> Binding<PerspectiveRuleGroup> {
        Binding(
            get: {
                guard index < group.conditions.count,
                      case .group(let subgroup) = group.conditions[index] else {
                    return PerspectiveRuleGroup(operator: .and, conditions: [])
                }
                return subgroup
            },
            set: { newGroup in
                guard index < group.conditions.count else { return }
                group.conditions[index] = .group(newGroup)
            }
        )
    }

    private func moveCondition(from index: Int, delta: Int) {
        let target = index + delta
        guard index >= 0, index < group.conditions.count,
              target >= 0, target < group.conditions.count else {
            return
        }
        let item = group.conditions.remove(at: index)
        group.conditions.insert(item, at: target)
    }

    private func ruleEnabled(at index: Int) -> Bool {
        guard index < group.conditions.count,
              case .rule(let rule) = group.conditions[index] else {
            return true
        }
        return rule.isEnabled
    }

    private func toggleRuleEnabled(at index: Int) {
        guard index < group.conditions.count,
              case .rule(var rule) = group.conditions[index] else {
            return
        }
        rule.isEnabled.toggle()
        group.conditions[index] = .rule(rule)
    }
}

private struct PerspectiveConditionDropDelegate: DropDelegate {
    @Binding var rootGroup: PerspectiveRuleGroup
    let dragState: PerspectiveRuleDragState
    let destinationGroupID: String
    let destinationConditionID: String?

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedConditionID = dragState.draggedConditionID else { return false }
        guard draggedConditionID != destinationConditionID else {
            dragState.draggedConditionID = nil
            return true
        }

        var workingRoot = rootGroup
        let originalRoot = workingRoot

        guard let draggedCondition = Self.removeCondition(withID: draggedConditionID, from: &workingRoot) else {
            dragState.draggedConditionID = nil
            return false
        }

        if case .group(let draggedGroup) = draggedCondition,
           Self.groupContains(groupID: destinationGroupID, in: draggedGroup) {
            rootGroup = originalRoot
            dragState.draggedConditionID = nil
            return false
        }

        let inserted = Self.insertCondition(
            draggedCondition,
            into: &workingRoot,
            destinationGroupID: destinationGroupID,
            beforeConditionID: destinationConditionID
        )
        guard inserted else {
            rootGroup = originalRoot
            dragState.draggedConditionID = nil
            return false
        }

        rootGroup = workingRoot
        dragState.draggedConditionID = nil
        return true
    }

    private static func removeCondition(withID conditionID: String, from group: inout PerspectiveRuleGroup) -> PerspectiveCondition? {
        if let directIndex = group.conditions.firstIndex(where: { $0.id == conditionID }) {
            return group.conditions.remove(at: directIndex)
        }

        for index in group.conditions.indices {
            guard case .group(var subgroup) = group.conditions[index] else { continue }
            if let removed = removeCondition(withID: conditionID, from: &subgroup) {
                group.conditions[index] = .group(subgroup)
                return removed
            }
        }

        return nil
    }

    private static func insertCondition(
        _ condition: PerspectiveCondition,
        into group: inout PerspectiveRuleGroup,
        destinationGroupID: String,
        beforeConditionID: String?
    ) -> Bool {
        if group.id == destinationGroupID {
            if let beforeConditionID,
               let destinationIndex = group.conditions.firstIndex(where: { $0.id == beforeConditionID }) {
                group.conditions.insert(condition, at: destinationIndex)
            } else {
                group.conditions.append(condition)
            }
            return true
        }

        for index in group.conditions.indices {
            guard case .group(var subgroup) = group.conditions[index] else { continue }
            if insertCondition(
                condition,
                into: &subgroup,
                destinationGroupID: destinationGroupID,
                beforeConditionID: beforeConditionID
            ) {
                group.conditions[index] = .group(subgroup)
                return true
            }
        }
        return false
    }

    private static func groupContains(groupID: String, in group: PerspectiveRuleGroup) -> Bool {
        if group.id == groupID {
            return true
        }
        for condition in group.conditions {
            guard case .group(let subgroup) = condition else { continue }
            if groupContains(groupID: groupID, in: subgroup) {
                return true
            }
        }
        return false
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
                if rule.field == .status, rule.operator == .equals {
                    Picker("Value", selection: Binding(
                        get: { TaskStatus(rawValue: rule.stringValue) != nil ? rule.stringValue : TaskStatus.todo.rawValue },
                        set: { rule.value = .string($0) }
                    )) {
                        ForEach(TaskStatus.allCases, id: \.rawValue) { status in
                            Text(status.rawValue).tag(status.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } else if rule.field == .priority, rule.operator == .equals {
                    Picker("Value", selection: Binding(
                        get: { TaskPriority(rawValue: rule.stringValue) != nil ? rule.stringValue : TaskPriority.none.rawValue },
                        set: { rule.value = .string($0) }
                    )) {
                        ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                            Text(priority.rawValue).tag(priority.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    TextField(valuePlaceholder(for: rule.field), text: Binding(
                        get: { rule.stringValue },
                        set: { newValue in
                            if [.containsAny, .containsAll, .in].contains(rule.operator) {
                                let values = newValue
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                                    .map(JSONValue.string)
                                rule.value = .array(values)
                            } else {
                                rule.stringValue = newValue
                            }
                        }
                    ))
                    .textInputAutocapitalization(.never)
                }
            }
        }
    }

    private func operators(for field: PerspectiveField) -> [PerspectiveOperator] {
        switch field {
        case .status, .priority:
            return [.equals, .in, .isSet, .isNotSet]
        case .area, .project, .source, .title, .body, .recurrence:
            return [.equals, .contains, .stringContains, .isSet, .isNotSet]
        case .tags:
            return [.contains, .containsAny, .containsAll, .isSet, .isNotSet]
        case .flagged:
            return [.isTrue, .isFalse]
        case .due, .scheduled, .defer, .created, .completed, .modified:
            return [.isSet, .isNotSet, .beforeToday, .onToday, .afterToday, .on, .before, .after, .onOrBefore, .between]
        case .estimatedMinutes:
            return [.isSet, .isNotSet, .lessThan, .greaterThan, .equals]
        case .unknown:
            return [.equals, .contains, .isSet, .isNotSet]
        }
    }

    private func requiresValue(_ operatorValue: PerspectiveOperator) -> Bool {
        switch operatorValue {
        case .equals, .notEquals, .in, .contains, .containsAny, .containsAll, .stringContains, .before, .after, .on, .onOrBefore, .between, .lessThan, .greaterThan, .inPast, .inNext:
            return true
        default:
            return false
        }
    }

    private func fieldLabel(_ field: PerspectiveField) -> String {
        switch field {
        case .status: return "Status"
        case .due: return "Due"
        case .scheduled: return "Scheduled"
        case .defer: return "Defer"
        case .priority: return "Priority"
        case .flagged: return "Flagged"
        case .area: return "Area"
        case .project: return "Project"
        case .tags: return "Tags"
        case .source: return "Source"
        case .title: return "Title"
        case .body: return "Body"
        case .created: return "Created"
        case .completed: return "Completed"
        case .modified: return "Modified"
        case .estimatedMinutes: return "Estimated Time"
        case .recurrence: return "Repeating"
        case .unknown(let value): return value
        }
    }

    private func operatorLabel(_ op: PerspectiveOperator) -> String {
        switch op {
        case .equals: return "Equals"
        case .notEquals: return "Not Equals"
        case .in: return "In"
        case .contains: return "Contains"
        case .containsAny: return "Contains Any"
        case .containsAll: return "Contains All"
        case .isSet: return "Set"
        case .isNotSet: return "Not Set"
        case .isNil: return "Is Nil"
        case .isNotNil: return "Is Not Nil"
        case .beforeToday: return "< Today"
        case .onToday: return "Today"
        case .afterToday: return "> Today"
        case .before: return "Before"
        case .after: return "After"
        case .on: return "On"
        case .onOrBefore: return "On or Before"
        case .between: return "Between"
        case .lessThan: return "Less Than"
        case .greaterThan: return "Greater Than"
        case .stringContains: return "Text Contains"
        case .isTrue: return "True"
        case .isFalse: return "False"
        case .inPast: return "In Past Range"
        case .inNext: return "In Next Range"
        case .unknown(let value): return value
        }
    }

    private func valuePlaceholder(for field: PerspectiveField) -> String {
        switch field {
        case .status: return "todo,in-progress"
        case .priority: return "high"
        case .area: return "Work"
        case .project: return "Roadmap"
        case .tags: return "home,call"
        case .source: return "shortcut"
        case .due, .scheduled, .defer, .created, .completed, .modified: return "YYYY-MM-DD"
        case .flagged: return "true"
        case .title, .body: return "contains text"
        case .estimatedMinutes: return "15"
        case .recurrence: return "every week"
        case .unknown: return "value"
        }
    }
}
