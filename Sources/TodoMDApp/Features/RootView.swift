import SwiftUI

private struct DeferDateTarget: Identifiable {
    let path: String
    var id: String { path }
}

private struct BuiltInRulesTarget: Identifiable {
    let view: BuiltInView
    var id: String { view.rawValue }
}

private struct ResolvedBottomNavigationSection: Identifiable {
    let id: String
    let view: ViewIdentifier
}

private struct ProjectColorChoice: Identifiable {
    let hex: String
    let name: String
    var id: String { hex }
}

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.editMode) private var editMode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingQuickEntry = false
    @State private var navigationPath = NavigationPath()
    @State private var universalSearchText = ""
    @State private var browseProjectName = ""
    @State private var browseProjectFirstTaskTitle = ""
    @State private var pathsCompleting: Set<String> = []
    @State private var pathsSlidingOut: Set<String> = []
    @State private var completionAnimationTasks: [String: Task<Void, Never>] = [:]
    @State private var pendingDeletePath: String?
    @State private var pendingDeletePerspective: PerspectiveDefinition?
    @State private var deferDateTarget: DeferDateTarget?
    @State private var deferDateValue = Date()
    @State private var editingPerspective: PerspectiveDefinition?
    @State private var builtInRulesTarget: BuiltInRulesTarget?
    @AppStorage(BottomNavigationSettings.sectionsKey) private var bottomNavigationSectionsRawValue = BottomNavigationSettings.defaultSectionsRawValue
    @AppStorage("settings_pomodoro_enabled") private var pomodoroEnabled = false

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
                .safeAreaInset(edge: .bottom) {
                    if shouldShowBottomNavigationBar {
                        compactBottomNavigationBar
                    }
                }
            .navigationDestination(for: String.self) { path in
                TaskDetailView(path: path)
            }
            .navigationTitle(navigationTitle())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if horizontalSizeClass == .compact {
                        Button {
                            applyFilter(.browse)
                        } label: {
                            Image(systemName: "square.grid.2x2")
                        }
                    }
                }

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
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("root.settingsButton")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if shouldShowFloatingAddButton {
                    floatingAddButton
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
            .sheet(item: $editingPerspective) { perspective in
                NavigationStack {
                    PerspectiveEditorSheet(initialPerspective: perspective) { saved in
                        container.savePerspective(saved)
                        editingPerspective = nil
                    }
                }
            }
            .sheet(item: $builtInRulesTarget) { target in
                NavigationStack {
                    BuiltInPerspectiveRulesView(
                        perspective: container.builtInPerspectiveDefinition(for: target.view),
                        onDuplicate: {
                            let duplicate = container.duplicateBuiltInPerspective(target.view)
                            editingPerspective = duplicate
                        }
                    )
                }
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
            .alert(
                "Perspectives Warning",
                isPresented: Binding(
                    get: { container.perspectivesWarningMessage != nil },
                    set: { isPresented in
                        if !isPresented { container.perspectivesWarningMessage = nil }
                    }
                ),
                actions: {
                    Button("OK", role: .cancel) {
                        container.perspectivesWarningMessage = nil
                    }
                },
                message: {
                    Text(container.perspectivesWarningMessage ?? "")
                }
            )
            .onChange(of: container.navigationTaskPath) { _, newPath in
                guard let newPath else { return }
                navigationPath.append(newPath)
                container.clearPendingNavigationPath()
            }
            .onChange(of: container.shouldPresentQuickEntry) { _, shouldPresent in
                guard shouldPresent else { return }
                showingQuickEntry = true
                container.clearQuickEntryRequest()
            }
            .onAppear {
                if let pending = container.navigationTaskPath {
                    navigationPath.append(pending)
                    container.clearPendingNavigationPath()
                }
                if container.shouldPresentQuickEntry {
                    showingQuickEntry = true
                    container.clearQuickEntryRequest()
                }
            }
            .onDisappear {
                completionAnimationTasks.values.forEach { $0.cancel() }
                completionAnimationTasks.removeAll()
            }
            .onChange(of: pomodoroEnabled) { _, isEnabled in
                guard !isEnabled, container.selectedView == .builtIn(.pomodoro) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    container.selectedView = .builtIn(.inbox)
                }
            }
            .onChange(of: container.selectedView) { _, selectedView in
                if !selectedView.isBrowse {
                    universalSearchText = ""
                }
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("Browse") {
                navButton(view: .browse, label: "Browse", icon: "square.grid.2x2")
            }

            Section("Views") {
                builtInNavButton(.inbox, label: "Inbox", icon: "tray")
                builtInNavButton(.myTasks, label: "My Tasks", icon: "person")
                builtInNavButton(.delegated, label: "Delegated", icon: "person.2")
                builtInNavButton(.today, label: "Today", icon: "sun.max")
                builtInNavButton(.upcoming, label: "Upcoming", icon: "calendar")
                builtInNavButton(.anytime, label: "Anytime", icon: "list.bullet")
                builtInNavButton(.someday, label: "Someday", icon: "clock")
                builtInNavButton(.flagged, label: "Flagged", icon: "flag")
            }

            if !container.perspectives.isEmpty {
                Section("Perspectives") {
                    ForEach(container.perspectives) { perspective in
                        navButton(
                            view: container.perspectiveViewIdentifier(for: perspective.id),
                            label: perspective.name,
                            icon: perspective.icon,
                            tintHex: perspective.color
                        )
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
                }
            }

            let groupedAreas = container.projectsByArea()
            if !groupedAreas.isEmpty {
                Section("Areas") {
                    ForEach(groupedAreas, id: \.area) { group in
                        navButton(view: .area(group.area), label: group.area, icon: "square.grid.2x2")
                        ForEach(group.projects, id: \.self) { project in
                            navButton(
                                view: .project(project),
                                label: project,
                                icon: "folder",
                                isIndented: true,
                                tintHex: container.projectColorHex(for: project)
                            )
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
        let searchQuery = universalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if container.selectedView.isBrowse {
            browseContent(query: searchQuery)
                .searchable(
                    text: $universalSearchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search tasks, sections, tags"
                )
        } else if container.selectedView == .builtIn(.upcoming) {
            UpcomingCalendarView(sections: container.calendarUpcomingSections)
        } else if container.selectedView == .builtIn(.pomodoro) {
            PomodoroTimerView()
        } else {
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
                            if container.isCalendarConnected {
                                Section {
                                    TodayCalendarCard(events: container.calendarTodayEvents)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 10, trailing: 10))
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                            }

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
                                guard container.canManuallyReorderSelectedView() else { return }
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
    }

    private var browseSectionScreen: some View {
        List {
            Section("New Project") {
                TextField("Project name", text: $browseProjectName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                TextField("First task title (optional)", text: $browseProjectFirstTaskTitle)
                    .textInputAutocapitalization(.sentences)

                Button("Create Project") {
                    createProjectFromBrowse()
                }
                .disabled(browseProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Projects are created from tasks. This adds a starter task to the new project.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondaryColor)
            }

            let tags = container.availableTags()
            if tags.isEmpty {
                Section("Tags") {
                    Text("No tags yet")
                        .foregroundStyle(theme.textSecondaryColor)
                }
            } else {
                Section("Tags") {
                    ForEach(tags, id: \.self) { tag in
                        browseFilterButton(view: .tag(tag), label: "#\(tag)", icon: "number")
                    }
                }
            }

            let projects = container.allProjects()
            if projects.isEmpty {
                Section("Projects") {
                    Text("No projects yet")
                        .foregroundStyle(theme.textSecondaryColor)
                }
            } else {
                Section("Projects") {
                    ForEach(projects, id: \.self) { project in
                        HStack(spacing: 8) {
                            browseFilterButton(
                                view: .project(project),
                                label: project,
                                icon: "folder",
                                tintHex: container.projectColorHex(for: project)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            projectColorMenu(for: project)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func browseContent(query: String) -> some View {
        if query.isEmpty {
            browseSectionScreen
        } else {
            universalSearchContent(query: query)
        }
    }

    @ViewBuilder
    private func universalSearchContent(query: String) -> some View {
        let tasks = container.searchRecords(query: query)
        let tags = container.availableTags().filter { matchesQuery($0, query: query) }
        let areas = container.availableAreas().filter { matchesQuery($0, query: query) }
        let projects = container.allProjects().filter { matchesQuery($0, query: query) }
        let perspectives = container.perspectives.filter { matchesQuery($0.name, query: query) }
        let builtInViews: [(label: String, view: ViewIdentifier, icon: String)] = [
            ("Browse", .browse, "square.grid.2x2"),
            ("Inbox", .builtIn(.inbox), "tray"),
            ("My Tasks", .builtIn(.myTasks), "person"),
            ("Delegated", .builtIn(.delegated), "person.2"),
            ("Today", .builtIn(.today), "sun.max"),
            ("Upcoming", .builtIn(.upcoming), "calendar"),
            ("Anytime", .builtIn(.anytime), "list.bullet"),
            ("Someday", .builtIn(.someday), "clock"),
            ("Flagged", .builtIn(.flagged), "flag")
        ].filter { matchesQuery($0.label, query: query) }

        if tasks.isEmpty && tags.isEmpty && areas.isEmpty && projects.isEmpty && builtInViews.isEmpty && perspectives.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No matches for \"\(query)\"")
            )
        } else {
            List {
                if !builtInViews.isEmpty {
                    Section("Sections") {
                        ForEach(builtInViews, id: \.view.rawValue) { item in
                            if case .builtIn(let builtInView) = item.view {
                                builtInBrowseFilterButton(builtInView, label: item.label, icon: item.icon)
                            } else {
                                browseFilterButton(view: item.view, label: item.label, icon: item.icon)
                            }
                        }
                    }
                }

                if !perspectives.isEmpty {
                    Section("Perspectives") {
                        ForEach(perspectives) { perspective in
                            browseFilterButton(
                                view: container.perspectiveViewIdentifier(for: perspective.id),
                                label: perspective.name,
                                icon: perspective.icon,
                                tintHex: perspective.color
                            )
                        }
                    }
                }

                if !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags, id: \.self) { tag in
                            browseFilterButton(view: .tag(tag), label: "#\(tag)", icon: "number")
                        }
                    }
                }

                if !areas.isEmpty {
                    Section("Areas") {
                        ForEach(areas, id: \.self) { area in
                            browseFilterButton(view: .area(area), label: area, icon: "square.grid.2x2")
                        }
                    }
                }

                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects, id: \.self) { project in
                            browseFilterButton(
                                view: .project(project),
                                label: project,
                                icon: "folder",
                                tintHex: container.projectColorHex(for: project)
                            )
                        }
                    }
                }

                if !tasks.isEmpty {
                    Section("Tasks") {
                        ForEach(tasks) { record in
                            taskRowItem(record)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private var projectColorChoices: [ProjectColorChoice] {
        [
            ProjectColorChoice(hex: "E53935", name: "Red"),
            ProjectColorChoice(hex: "FB8C00", name: "Orange"),
            ProjectColorChoice(hex: "FDD835", name: "Yellow"),
            ProjectColorChoice(hex: "43A047", name: "Green"),
            ProjectColorChoice(hex: "00ACC1", name: "Teal"),
            ProjectColorChoice(hex: "1E88E5", name: "Blue"),
            ProjectColorChoice(hex: "5E35B1", name: "Purple"),
            ProjectColorChoice(hex: "6D4C41", name: "Brown"),
            ProjectColorChoice(hex: "546E7A", name: "Slate")
        ]
    }

    private func projectColorMenu(for project: String) -> some View {
        let currentHex = container.projectColorHex(for: project)

        return Menu {
            Button {
                container.setProjectColor(project: project, hex: nil)
            } label: {
                HStack {
                    Image(systemName: currentHex == nil ? "checkmark.circle.fill" : "circle")
                    Text("No Color")
                }
            }

            ForEach(projectColorChoices) { choice in
                Button {
                    container.setProjectColor(project: project, hex: choice.hex)
                } label: {
                    HStack {
                        Circle()
                            .fill(color(forHex: choice.hex) ?? theme.textSecondaryColor)
                            .frame(width: 10, height: 10)
                        Text(choice.name)
                        if currentHex == choice.hex {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Group {
                if let tint = color(forHex: currentHex) {
                    Circle()
                        .fill(tint)
                } else {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(theme.textSecondaryColor)
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Set color for \(project)")
    }

    private func browseFilterButton(view: ViewIdentifier, label: String, icon: String, tintHex: String? = nil) -> some View {
        let tint = color(forHex: tintHex)
        return Button {
            applyFilter(view)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(container.selectedView == view ? (tint ?? theme.accentColor) : (tint ?? theme.textSecondaryColor))
                Text(label)
                Spacer()
                if container.selectedView == view {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func builtInBrowseFilterButton(_ builtInView: BuiltInView, label: String, icon: String) -> some View {
        browseFilterButton(view: .builtIn(builtInView), label: label, icon: icon)
            .contextMenu {
                Button("View Rules") {
                    builtInRulesTarget = BuiltInRulesTarget(view: builtInView)
                }
            }
    }

    private var shouldShowBottomNavigationBar: Bool {
        horizontalSizeClass == .compact && !resolvedBottomNavigationSections.isEmpty
    }

    private var resolvedBottomNavigationSections: [ResolvedBottomNavigationSection] {
        var resolved = BottomNavigationSettings.decodeSections(bottomNavigationSectionsRawValue)
            .compactMap { section -> ResolvedBottomNavigationSection? in
                let view = section.viewIdentifier
                if case .builtIn(.pomodoro) = view, !pomodoroEnabled {
                    return nil
                }
                if case .custom = view, perspective(for: view) == nil, !view.isBrowse {
                    return nil
                }
                return ResolvedBottomNavigationSection(id: section.id, view: view)
            }

        if !resolved.contains(where: { $0.view.isBrowse }) {
            if resolved.count >= BottomNavigationSettings.maxSections {
                _ = resolved.popLast()
            }
            resolved.append(ResolvedBottomNavigationSection(id: "browse", view: .browse))
        }

        return resolved
    }

    private var compactBottomNavigationBar: some View {
        HStack(spacing: 4) {
            ForEach(resolvedBottomNavigationSections) { section in
                let item = bottomNavigationItem(for: section.view)
                Button {
                    applyFilter(section.view)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(
                        container.selectedView == section.view
                            ? (color(forHex: item.tintHex) ?? theme.accentColor)
                            : theme.textSecondaryColor
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(theme.surfaceColor.opacity(0.96))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func bottomNavigationItem(for view: ViewIdentifier) -> (title: String, icon: String, tintHex: String?) {
        switch view {
        case .builtIn(let builtIn):
            switch builtIn {
            case .inbox:
                return ("Inbox", "tray", nil)
            case .myTasks:
                return ("My Tasks", "person", nil)
            case .delegated:
                return ("Delegated", "person.2", nil)
            case .today:
                return ("Today", "sun.max", nil)
            case .upcoming:
                return ("Upcoming", "calendar", nil)
            case .anytime:
                return ("Anytime", "list.bullet", nil)
            case .someday:
                return ("Someday", "clock", nil)
            case .flagged:
                return ("Flagged", "flag", nil)
            case .pomodoro:
                return ("Pomodoro", "timer", nil)
            }
        case .area(let area):
            return (area, "square.grid.2x2", nil)
        case .project(let project):
            return (project, "folder", container.projectColorHex(for: project))
        case .tag(let tag):
            return ("#\(tag)", "number", nil)
        case .custom(let rawValue):
            if view.isBrowse {
                return ("Browse", "square.grid.2x2", nil)
            }
            if let perspective = perspective(for: view) {
                return (perspective.name, perspective.icon, perspective.color)
            }
            return (rawValue, "square.grid.2x2", nil)
        }
    }

    private func perspective(for view: ViewIdentifier) -> PerspectiveDefinition? {
        guard case .custom(let rawID) = view else { return nil }
        let prefix = "perspective:"
        guard rawID.hasPrefix(prefix) else { return nil }
        let id = String(rawID.dropFirst(prefix.count))
        guard !id.isEmpty else { return nil }
        return container.perspectives.first(where: { $0.id == id })
    }

    private var floatingAddButton: some View {
        Button {
            showingQuickEntry = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 56, height: 56)
                .background(Circle().fill(theme.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        }
        .accessibilityIdentifier("root.quickAddButton")
        .padding(.trailing, 20)
        .padding(.bottom, shouldShowBottomNavigationBar ? 76 : 16)
    }

    private var shouldShowFloatingAddButton: Bool {
        navigationPath.isEmpty
    }

    private func navigationTitle() -> String {
        if container.selectedView.isBrowse {
            return "Browse"
        }
        return titleForCurrentView()
    }

    private func matchesQuery(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func createProjectFromBrowse() {
        let trimmedProjectName = browseProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectName.isEmpty else { return }

        if let existingProject = container.allProjects().first(where: {
            $0.compare(trimmedProjectName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            browseProjectName = ""
            browseProjectFirstTaskTitle = ""
            applyFilter(.project(existingProject))
            return
        }

        let trimmedTaskTitle = browseProjectFirstTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let starterTaskTitle = trimmedTaskTitle.isEmpty ? "Plan \(trimmedProjectName)" : trimmedTaskTitle
        container.createTask(title: starterTaskTitle, naturalDate: nil, project: trimmedProjectName)
        browseProjectName = ""
        browseProjectFirstTaskTitle = ""
        applyFilter(.project(trimmedProjectName))
    }

    private func applyFilter(_ view: ViewIdentifier) {
        withAnimation(.easeInOut(duration: 0.2)) {
            container.selectedView = view
        }
        universalSearchText = ""
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
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
        let isDone = record.document.frontmatter.status == .done
        let quickProjects = container.recentProjects(limit: 3, excluding: record.document.frontmatter.project)
        let isCompleting = pathsCompleting.contains(path)
        let isSlidingOut = pathsSlidingOut.contains(path)
        return TaskRow(
            record: record,
            isCompleting: isCompleting || isSlidingOut
        )
        .accessibilityIdentifier("taskRow.\(record.document.frontmatter.title)")
        .accessibilityHint("Swipe right to mark complete. Long press for quick actions.")
        .contentShape(Rectangle())
        .onTapGesture {
            guard editMode?.wrappedValue.isEditing != true else { return }
            navigationPath.append(record.identity.path)
        }
        .contextMenu {
            Menu("Quick Settings") {
                Menu("Change Due Date") {
                    Button("+1 Hour") {
                        _ = container.offsetDueDate(path: record.identity.path, component: .hour, value: 1)
                    }
                    Button("+1 Day") {
                        _ = container.offsetDueDate(path: record.identity.path, component: .day, value: 1)
                    }
                    Button("+1 Week") {
                        _ = container.offsetDueDate(path: record.identity.path, component: .weekOfYear, value: 1)
                    }
                }

                Menu("Add to Project") {
                    if quickProjects.isEmpty {
                        Button("No Recent Projects") {}
                            .disabled(true)
                    } else {
                        ForEach(quickProjects, id: \.self) { project in
                            Button(project) {
                                _ = container.moveTask(
                                    path: record.identity.path,
                                    area: record.document.frontmatter.area,
                                    project: project
                                )
                            }
                        }
                    }
                }
            }

            Divider()

            if !isDone {
                Button("Mark Done") {
                    completeWithAnimation(path: record.identity.path)
                }
            }

            Button("Defer to Tomorrow") {
                _ = container.deferToTomorrow(path: record.identity.path)
            }

            Button("Set Date") {
                deferDateValue = dateValue(for: record.document.frontmatter.defer) ?? Date()
                deferDateTarget = DeferDateTarget(path: record.identity.path)
            }

            Button(record.document.frontmatter.isBlocked ? "Unblock" : "Block") {
                _ = container.setBlocked(path: record.identity.path, blockedBy: record.document.frontmatter.isBlocked ? nil : .manual)
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                _ = container.setBlocked(path: record.identity.path, blockedBy: .manual)
            } label: {
                Label("Block", systemImage: "lock.fill")
            }
            .tint(.orange)

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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isDone {
                Button {
                    completeWithAnimation(path: record.identity.path)
                } label: {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
        .opacity(isSlidingOut ? 0.0 : (isCompleting ? 0.86 : 1.0))
        .offset(x: isSlidingOut ? 700 : 0)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: pathsCompleting)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: pathsSlidingOut)
    }

    private func navButton(
        view: ViewIdentifier,
        label: String,
        icon: String,
        isIndented: Bool = false,
        tintHex: String? = nil
    ) -> some View {
        let tint = color(forHex: tintHex)
        return Button {
            applyFilter(view)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(container.selectedView == view ? (tint ?? theme.accentColor) : (tint ?? theme.textSecondaryColor))
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

    private func builtInNavButton(_ builtInView: BuiltInView, label: String, icon: String) -> some View {
        navButton(view: .builtIn(builtInView), label: label, icon: icon)
            .contextMenu {
                Button("View Rules") {
                    builtInRulesTarget = BuiltInRulesTarget(view: builtInView)
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

    private func titleForCurrentView() -> String {
        switch container.selectedView {
        case .builtIn(let view):
            switch view {
            case .inbox:
                return "Inbox"
            case .myTasks:
                return "My Tasks"
            case .delegated:
                return "Delegated"
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
            case .pomodoro:
                return "Pomodoro"
            }
        case .area(let area):
            return area
        case .project(let project):
            return project
        case .tag(let tag):
            return "#\(tag)"
        case .custom(let id):
            if ViewIdentifier.custom(id).isBrowse {
                return "Browse"
            }
            if let perspectiveName = container.perspectiveName(for: .custom(id)) {
                return perspectiveName
            }
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
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        let frontmatter = record.document.frontmatter

        HStack(spacing: 0) {
            Rectangle()
                .fill(projectBarColor(for: frontmatter))
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(frontmatter.title)
                        .font(.system(.title3, design: .rounded).weight(.regular))
                        .foregroundStyle(theme.textPrimaryColor)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let dueText = dueDisplayText(for: frontmatter) {
                        Text(dueText)
                            .font(.system(.title3, design: .rounded).weight(.regular))
                            .foregroundStyle(theme.textSecondaryColor)
                            .lineLimit(1)
                    }
                }

                if let recurrenceText = recurrenceDisplayText(for: frontmatter) {
                    Text(recurrenceText)
                        .font(.system(.title3, design: .rounded).weight(.regular))
                        .foregroundStyle(theme.textSecondaryColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(theme.surfaceColor.opacity(0.88))
        .opacity(isCompleting ? 0.9 : 1.0)
    }

    private func projectBarColor(for frontmatter: TaskFrontmatterV1) -> Color {
        guard let project = frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines),
              !project.isEmpty else {
            return theme.textSecondaryColor.opacity(0.35)
        }
        return color(forHex: container.projectColorHex(for: project))
            ?? theme.textSecondaryColor.opacity(0.35)
    }

    private func dueDisplayText(for frontmatter: TaskFrontmatterV1) -> String? {
        guard let due = frontmatter.due else { return nil }
        guard let dueDate = date(from: due, time: frontmatter.dueTime) else { return due.isoString }
        let calendar = Calendar.current

        if let dueTime = frontmatter.dueTime, calendar.isDateInToday(dueDate) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: dueDate, relativeTo: Date())
        }

        if calendar.isDateInToday(dueDate) { return "Today" }
        if calendar.isDateInTomorrow(dueDate) { return "Tomorrow" }

        if let oneWeekFromNow = calendar.date(byAdding: .day, value: 7, to: Date()),
           dueDate < oneWeekFromNow {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEE")
            return formatter.string(from: dueDate)
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: dueDate)
    }

    private func recurrenceDisplayText(for frontmatter: TaskFrontmatterV1) -> String? {
        let recurrence = frontmatter.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !recurrence.isEmpty else { return nil }

        if recurrence.uppercased().contains("FREQ="),
           let parsed = try? RecurrenceRule.parse(recurrence) {
            let base: String
            switch parsed.frequency {
            case .daily:
                base = parsed.interval == 1 ? "Every day" : "Every \(parsed.interval) days"
            case .weekly:
                let weekdayText = weekdayDisplayNames(for: parsed.byDay)
                if parsed.interval == 1 {
                    base = weekdayText.isEmpty ? "Every week" : "Every week on \(weekdayText)"
                } else {
                    base = weekdayText.isEmpty ? "Every \(parsed.interval) weeks" : "Every \(parsed.interval) weeks on \(weekdayText)"
                }
            case .monthly:
                if let dueDay = frontmatter.due?.day {
                    let dayText = ordinal(dueDay)
                    base = parsed.interval == 1 ? "Every month on the \(dayText)" : "Every \(parsed.interval) months on the \(dayText)"
                } else {
                    base = parsed.interval == 1 ? "Every month" : "Every \(parsed.interval) months"
                }
            case .yearly:
                base = parsed.interval == 1 ? "Every year" : "Every \(parsed.interval) years"
            }

            if let dueTime = frontmatter.dueTime {
                return "\(base) at \(formattedTime(dueTime))"
            }
            return base
        }

        return recurrence
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

    private func date(from localDate: LocalDate, time localTime: LocalTime?) -> Date? {
        var components = DateComponents()
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        components.hour = localTime?.hour ?? 12
        components.minute = localTime?.minute ?? 0
        components.second = 0
        components.calendar = .current
        return Calendar.current.date(from: components)
    }

    private func formattedTime(_ localTime: LocalTime) -> String {
        var components = DateComponents()
        components.hour = localTime.hour
        components.minute = localTime.minute
        components.second = 0
        components.calendar = .current
        guard let date = Calendar.current.date(from: components) else { return localTime.isoString }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func weekdayDisplayNames(for byDay: [String]) -> String {
        let names = byDay.compactMap { token -> String? in
            switch token {
            case "MO": return "Mon"
            case "TU": return "Tue"
            case "WE": return "Wed"
            case "TH": return "Thu"
            case "FR": return "Fri"
            case "SA": return "Sat"
            case "SU": return "Sun"
            default: return nil
            }
        }
        return names.joined(separator: ", ")
    }

    private func ordinal(_ day: Int) -> String {
        let mod100 = day % 100
        let suffix: String
        if (11...13).contains(mod100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}
