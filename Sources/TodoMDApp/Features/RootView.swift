import SwiftUI

private struct DeferDateTarget: Identifiable {
    let path: String
    var id: String { path }
}

private struct QuickEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @AppStorage("settings_quick_entry_default_view") private var quickEntryDefaultView = BuiltInView.inbox.rawValue

    @State private var title = ""
    @State private var dateText = ""
    @State private var tagsText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("quickEntry.titleField")
                TextField("Date phrase (optional)", text: $dateText)
                    .accessibilityIdentifier("quickEntry.dateField")
                TextField("Tags (comma separated)", text: $tagsText)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("quickEntry.tagsField")
            }
            .accessibilityIdentifier("quickEntry.form")
            .navigationTitle("Quick Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("quickEntry.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTitle.isEmpty else { return }
                        let trimmedDateText = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let tags = tagsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        let defaultView = BuiltInView(rawValue: quickEntryDefaultView)
                        container.createTask(
                            title: trimmedTitle,
                            naturalDate: trimmedDateText.isEmpty ? nil : trimmedDateText,
                            tags: tags,
                            defaultView: defaultView
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("quickEntry.addButton")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.editMode) private var editMode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingQuickEntry = false
    @State private var navigationPath = NavigationPath()
    @State private var pathsCompleting: Set<String> = []
    @State private var pathsSlidingOut: Set<String> = []
    @State private var completionAnimationTasks: [String: Task<Void, Never>] = [:]
    @State private var pendingDeletePath: String?
    @State private var deferDateTarget: DeferDateTarget?
    @State private var deferDateValue = Date()

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                detailPane
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailPane
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: container.selectedView)
        .background(theme.backgroundColor.ignoresSafeArea())
    }

    private var detailPane: some View {
        NavigationStack(path: $navigationPath) {
            mainContent
                .navigationDestination(for: String.self) { path in
                    TaskDetailView(path: path)
                }
                .navigationTitle(titleForCurrentView())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }

                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            DebugView()
                        } label: {
                            Image(systemName: "ladybug")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingQuickEntry = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("root.quickAddButton")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityIdentifier("root.settingsButton")
                    }
                }
                .refreshable {
                    container.refresh()
                }
                .sheet(isPresented: $showingQuickEntry) {
                    QuickEntrySheet()
                }
                .sheet(item: $deferDateTarget) { target in
                    deferDateSheet(target: target)
                }
                .alert(
                    "High Ingestion Volume",
                    isPresented: Binding(
                        get: { container.rateLimitAlertMessage != nil },
                        set: { isPresented in
                            if !isPresented { container.rateLimitAlertMessage = nil }
                        }
                    ),
                    actions: {
                        Button("OK", role: .cancel) { container.rateLimitAlertMessage = nil }
                    },
                    message: {
                        Text(container.rateLimitAlertMessage ?? "")
                    }
                )
                .alert(
                    "Delete Task",
                    isPresented: Binding(
                        get: { pendingDeletePath != nil },
                        set: { isPresented in
                            if !isPresented { pendingDeletePath = nil }
                        }
                    ),
                    actions: {
                        Button("Delete", role: .destructive) {
                            if let pendingDeletePath {
                                _ = container.deleteTask(path: pendingDeletePath)
                                self.pendingDeletePath = nil
                            }
                        }
                        Button("Cancel", role: .cancel) {
                            pendingDeletePath = nil
                        }
                    },
                    message: {
                        Text("This removes the task markdown file.")
                    }
                )
                .alert(
                    "Link Error",
                    isPresented: Binding(
                        get: { container.urlRoutingErrorMessage != nil },
                        set: { isPresented in
                            if !isPresented { container.urlRoutingErrorMessage = nil }
                        }
                    ),
                    actions: {
                        Button("OK", role: .cancel) {
                            container.urlRoutingErrorMessage = nil
                        }
                    },
                    message: {
                        Text(container.urlRoutingErrorMessage ?? "")
                    }
                )
                .onChange(of: container.navigationTaskPath) { _, newPath in
                    guard let newPath else { return }
                    navigationPath.append(newPath)
                    container.clearPendingNavigationPath()
                }
                .onAppear {
                    if let pending = container.navigationTaskPath {
                        navigationPath.append(pending)
                        container.clearPendingNavigationPath()
                    }
                }
                .onDisappear {
                    completionAnimationTasks.values.forEach { $0.cancel() }
                    completionAnimationTasks.removeAll()
                }
        }
    }

    private var sidebar: some View {
        List {
            Section("Views") {
                navButton(view: .builtIn(.inbox), label: "Inbox", icon: "tray")
                navButton(view: .builtIn(.today), label: "Today", icon: "sun.max")
                navButton(view: .builtIn(.upcoming), label: "Upcoming", icon: "calendar")
                navButton(view: .builtIn(.anytime), label: "Anytime", icon: "list.bullet")
                navButton(view: .builtIn(.someday), label: "Someday", icon: "clock")
                navButton(view: .builtIn(.flagged), label: "Flagged", icon: "flag")
            }

            let groupedAreas = container.projectsByArea()
            if !groupedAreas.isEmpty {
                Section("Areas") {
                    ForEach(groupedAreas, id: \.area) { group in
                        navButton(view: .area(group.area), label: group.area, icon: "square.grid.2x2")
                        ForEach(group.projects, id: \.self) { project in
                            navButton(view: .project(project), label: project, icon: "folder", isIndented: true)
                        }
                    }
                }
            }

            let tags = container.availableTags()
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.self) { tag in
                        navButton(view: .tag(tag), label: tag, icon: "number")
                    }
                }
            }

            if !container.conflicts.isEmpty {
                Section {
                    NavigationLink {
                        ConflictResolutionView()
                    } label: {
                        Label("Resolve \(container.conflicts.count) conflict(s)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !container.diagnostics.isEmpty {
                Section {
                    NavigationLink {
                        UnparseableFilesView()
                    } label: {
                        Label("Review \(container.diagnostics.count) unparseable file(s)", systemImage: "doc.badge.gearshape")
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .navigationTitle("todo.md")
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingQuickEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("root.quickAddButton")
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("root.settingsButton")
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        let records = container.filteredRecords()

        if records.isEmpty {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing in \(titleForCurrentView()) right now.")
                )

                if !container.diagnostics.isEmpty {
                    VStack(spacing: 6) {
                        Text("\(container.diagnostics.count) file(s) could not be parsed.")
                            .font(.footnote)
                            .foregroundStyle(theme.textSecondaryColor)
                        NavigationLink("Review Unparseable Files") {
                            UnparseableFilesView()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            List {
                if container.selectedView == .builtIn(.today) {
                    if editMode?.wrappedValue.isEditing == true {
                        Section("Today") {
                            ForEach(records) { record in
                                taskRowItem(record)
                            }
                            .onMove { source, destination in
                                var reordered = records
                                reordered.move(fromOffsets: source, toOffset: destination)
                                container.saveManualOrder(filenames: reordered.map { $0.identity.filename })
                            }
                        }
                    } else {
                        ForEach(container.todaySections()) { section in
                            Section(section.group.rawValue) {
                                ForEach(section.records) { record in
                                    taskRowItem(record)
                                }
                            }
                        }
                    }
                } else if container.selectedView == .builtIn(.upcoming) {
                    ForEach(container.upcomingSections()) { section in
                        Section(formattedDate(section.date)) {
                            ForEach(section.records) { record in
                                taskRowItem(record)
                            }
                        }
                    }
                } else {
                    Section(titleForCurrentView()) {
                        ForEach(records) { record in
                            taskRowItem(record)
                        }
                        .onMove { source, destination in
                            var reordered = records
                            reordered.move(fromOffsets: source, toOffset: destination)
                            container.saveManualOrder(filenames: reordered.map { $0.identity.filename })
                        }
                    }
                }
            }
            .id(container.selectedView.rawValue)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }


    private func deferDateSheet(target: DeferDateTarget) -> some View {
        NavigationStack {
            Form {
                DatePicker("Defer until", selection: $deferDateValue, displayedComponents: .date)

                Button("Clear Date", role: .destructive) {
                    _ = container.setDefer(path: target.path, date: nil)
                    deferDateTarget = nil
                }
            }
            .navigationTitle("Set Date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { deferDateTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = container.setDefer(path: target.path, date: deferDateValue)
                        deferDateTarget = nil
                    }
                }
            }
        }
    }

    private func completeWithAnimation(path: String) {
        guard !pathsCompleting.contains(path),
              !pathsSlidingOut.contains(path),
              completionAnimationTasks[path] == nil else { return }

        let task = Task { @MainActor in
            defer { completionAnimationTasks[path] = nil }

            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                _ = pathsCompleting.insert(path)
            }

            do { try await Task.sleep(nanoseconds: 120_000_000) } catch {
                resetCompletionAnimationState(path: path)
                return
            }

            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                _ = pathsSlidingOut.insert(path)
            }

            do { try await Task.sleep(nanoseconds: 160_000_000) } catch {
                resetCompletionAnimationState(path: path)
                return
            }

            container.complete(path: path)

            do { try await Task.sleep(nanoseconds: 280_000_000) } catch {
                resetCompletionAnimationState(path: path)
                return
            }

            withAnimation(.easeOut(duration: 0.16)) {
                resetCompletionAnimationState(path: path)
            }
        }

        completionAnimationTasks[path] = task
    }

    private func resetCompletionAnimationState(path: String) {
        _ = pathsCompleting.remove(path)
        _ = pathsSlidingOut.remove(path)
    }

    private func taskRowItem(_ record: TaskRecord) -> some View {
        let path = record.identity.path
        let isCompleting = pathsCompleting.contains(path)
        let isSlidingOut = pathsSlidingOut.contains(path)
        return NavigationLink(value: record.identity.path) {
            TaskRow(record: record, isCompleting: isCompleting || isSlidingOut)
        }
        .accessibilityIdentifier("taskRow.\(record.document.frontmatter.title)")
        .contextMenu {
            Button("Complete") {
                completeWithAnimation(path: record.identity.path)
            }

            Button("Defer to Tomorrow") {
                _ = container.deferToTomorrow(path: record.identity.path)
            }

            Button("Set Date") {
                deferDateValue = dateValue(for: record.document.frontmatter.defer) ?? Date()
                deferDateTarget = DeferDateTarget(path: record.identity.path)
            }

            Menu("Priority") {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Button(priority.rawValue.capitalized) {
                        _ = container.setPriority(path: record.identity.path, priority: priority)
                    }
                }
            }

            Menu("Move to Project") {
                Button("Move to Inbox") {
                    _ = container.moveTask(path: record.identity.path, area: nil, project: nil)
                }
                ForEach(container.projectsByArea(), id: \.area) { group in
                    Menu(group.area) {
                        Button("Area Only") {
                            _ = container.moveTask(path: record.identity.path, area: group.area, project: nil)
                        }
                        ForEach(group.projects, id: \.self) { project in
                            Button(project) {
                                _ = container.moveTask(path: record.identity.path, area: group.area, project: project)
                            }
                        }
                    }
                }
            }

            Button(record.document.frontmatter.flagged ? "Remove Flag" : "Flag") {
                _ = container.toggleFlag(path: record.identity.path)
            }

            Button("Delete", role: .destructive) {
                pendingDeletePath = record.identity.path
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                completeWithAnimation(path: record.identity.path)
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                deferDateValue = dateValue(for: record.document.frontmatter.defer) ?? Date()
                deferDateTarget = DeferDateTarget(path: record.identity.path)
            } label: {
                Label("Set Date", systemImage: "calendar")
            }
            .tint(.indigo)

            Button {
                _ = container.deferToTomorrow(path: record.identity.path)
            } label: {
                Label("Tomorrow", systemImage: "arrow.turn.down.right")
            }
            .tint(.blue)
        }
        .opacity(isSlidingOut ? 0.0 : (isCompleting ? 0.86 : 1.0))
        .offset(x: isSlidingOut ? 700 : 0)
        .listRowBackground(theme.surfaceColor.opacity(0.78))
        .listRowSeparator(.hidden)
        .shadow(
            color: (editMode?.wrappedValue.isEditing ?? false) ? .black.opacity(0.06) : .clear,
            radius: (editMode?.wrappedValue.isEditing ?? false) ? 4 : 0,
            x: 0,
            y: 2
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: pathsCompleting)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: pathsSlidingOut)
    }

    private func navButton(view: ViewIdentifier, label: String, icon: String, isIndented: Bool = false) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                container.selectedView = view
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(container.selectedView == view ? theme.accentColor : theme.textSecondaryColor)
                Text(label)
                Spacer()
                if container.selectedView == view {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentColor)
                }
            }
            .padding(.leading, isIndented ? 20 : 0)
        }
        .buttonStyle(.plain)
    }

    private func titleForCurrentView() -> String {
        switch container.selectedView {
        case .builtIn(let view):
            switch view {
            case .inbox:
                return "Inbox"
            case .today:
                return "Today"
            case .upcoming:
                return "Upcoming"
            case .anytime:
                return "Anytime"
            case .someday:
                return "Someday"
            case .flagged:
                return "Flagged"
            }
        case .area(let area):
            return area
        case .project(let project):
            return project
        case .tag(let tag):
            return "#\(tag)"
        case .custom(let id):
            return id
        }
    }

    private func dateValue(for localDate: LocalDate?) -> Date? {
        guard let localDate else { return nil }
        var components = DateComponents()
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        return Calendar.current.date(from: components)
    }

    private func formattedDate(_ localDate: LocalDate) -> String {
        var components = DateComponents()
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        guard let date = Calendar.current.date(from: components) else {
            return localDate.isoString
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct TaskRow: View {
    let record: TaskRecord
    let isCompleting: Bool
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        let frontmatter = record.document.frontmatter

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                completionIndicator(isDone: frontmatter.status == .done)

                VStack(alignment: .leading, spacing: 2) {
                    Text(frontmatter.title)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(theme.textPrimaryColor)
                        .lineLimit(1)

                    if let description = frontmatter.description, !description.isEmpty {
                        Text(description)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(theme.textSecondaryColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if frontmatter.flagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                }
            }

            metadata(frontmatter)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func completionIndicator(isDone: Bool) -> some View {
        let showFilled = isDone || isCompleting

        ZStack {
            Circle()
                .stroke(showFilled ? Color.clear : theme.textSecondaryColor, lineWidth: 1.5)

            Circle()
                .fill(theme.accentColor)
                .scaleEffect(showFilled ? 1.0 : 0.01)
                .opacity(showFilled ? 1.0 : 0.0)

            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(showFilled ? (isCompleting ? 0.84 : 1.0) : 0.7)
                .opacity(showFilled ? 1.0 : 0.0)
        }
        .frame(width: 20, height: 20)
        .scaleEffect(isCompleting ? 0.84 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: showFilled)
        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: isCompleting)
    }

    @ViewBuilder
    private func metadata(_ frontmatter: TaskFrontmatterV1) -> some View {
        HStack(spacing: 8) {
            if let due = frontmatter.due {
                Label("Due \(due.isoString)", systemImage: "calendar.badge.clock")
                    .foregroundStyle(theme.textSecondaryColor)
            }

            if let scheduled = frontmatter.scheduled {
                Label("Planned \(scheduled.isoString)", systemImage: "calendar")
                    .foregroundStyle(theme.textSecondaryColor)
            }

            if let project = frontmatter.project {
                Text(project)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.textSecondaryColor.opacity(0.15)))
                    .foregroundStyle(theme.textPrimaryColor)
            }

            if frontmatter.priority != .none {
                Text(frontmatter.priority.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(priorityColor(frontmatter.priority).opacity(0.2)))
                    .foregroundStyle(priorityColor(frontmatter.priority))
            }

            if let estimate = frontmatter.estimatedMinutes {
                Label("\(estimate)m", systemImage: "clock")
                    .foregroundStyle(theme.textSecondaryColor)
            }

            if let deferDate = frontmatter.defer,
               deferDate > LocalDate.today(in: .current) {
                Label("Deferred \(deferDate.isoString)", systemImage: "hourglass")
                    .foregroundStyle(theme.textSecondaryColor)
            }

            if frontmatter.source != "user" {
                Label(frontmatter.source, systemImage: "tray.and.arrow.down")
                    .foregroundStyle(theme.textSecondaryColor)
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        theme.priorityColor(priority)
    }
}
