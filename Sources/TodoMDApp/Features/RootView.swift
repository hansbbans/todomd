import SwiftUI

private struct DeferDateTarget: Identifiable {
    let path: String
    var id: String { path }
}

private struct BuiltInRulesTarget: Identifiable {
    let view: BuiltInView
    var id: String { view.rawValue }
}

private enum RootScreenPage: Hashable {
    case filters
    case tasks
}

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.editMode) private var editMode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingQuickEntry = false
    @State private var navigationPath = NavigationPath()
    @State private var rootScreenPage: RootScreenPage = .tasks
    @State private var universalSearchText = ""
    @State private var pathsCompleting: Set<String> = []
    @State private var pathsSlidingOut: Set<String> = []
    @State private var completionAnimationTasks: [String: Task<Void, Never>] = [:]
    @State private var pendingDeletePath: String?
    @State private var pendingDeletePerspective: PerspectiveDefinition?
    @State private var deferDateTarget: DeferDateTarget?
    @State private var deferDateValue = Date()
    @State private var editingPerspective: PerspectiveDefinition?
    @State private var builtInRulesTarget: BuiltInRulesTarget?

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
            TabView(selection: $rootScreenPage) {
                filterBrowserScreen
                    .tag(RootScreenPage.filters)

                mainContent
                    .tag(RootScreenPage.tasks)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationDestination(for: String.self) { path in
                TaskDetailView(path: path)
            }
            .navigationTitle(navigationTitle())
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
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("root.settingsButton")
                }
            }
            .searchable(
                text: $universalSearchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search tasks, sections, tags"
            )
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
            .onChange(of: universalSearchText) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rootScreenPage = .tasks
                }
            }
            .onAppear {
                rootScreenPage = .tasks
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
                builtInNavButton(.inbox, label: "Inbox", icon: "tray")
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
        if !searchQuery.isEmpty {
            universalSearchContent(query: searchQuery)
        } else if container.selectedView == .builtIn(.upcoming) {
            UpcomingCalendarView(sections: container.calendarUpcomingSections)
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

    private var filterBrowserScreen: some View {
        List {
            Section("Sections") {
                builtInBrowseFilterButton(.inbox, label: "Inbox", icon: "tray")
                builtInBrowseFilterButton(.today, label: "Today", icon: "sun.max")
                builtInBrowseFilterButton(.upcoming, label: "Upcoming", icon: "calendar")
                builtInBrowseFilterButton(.anytime, label: "Anytime", icon: "list.bullet")
            }

            if !container.perspectives.isEmpty {
                Section("Perspectives") {
                    ForEach(container.perspectives) { perspective in
                        browseFilterButton(
                            view: container.perspectiveViewIdentifier(for: perspective.id),
                            label: perspective.name,
                            icon: perspective.icon,
                            tintHex: perspective.color
                        )
                    }
                }
            }

            Section("Filters") {
                NavigationLink {
                    PerspectivesView()
                } label: {
                    Label("Manage Perspectives", systemImage: "slider.horizontal.3")
                }
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
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func universalSearchContent(query: String) -> some View {
        let tasks = container.searchRecords(query: query)
        let tags = container.availableTags().filter { matchesQuery($0, query: query) }
        let areas = container.availableAreas().filter { matchesQuery($0, query: query) }
        let projects = container.allProjects().filter { matchesQuery($0, query: query) }
        let perspectives = container.perspectives.filter { matchesQuery($0.name, query: query) }
        let builtInViews: [(label: String, view: ViewIdentifier, icon: String)] = [
            ("Inbox", .builtIn(.inbox), "tray"),
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
                            browseFilterButton(view: .project(project), label: project, icon: "folder")
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
        .padding(.bottom, 16)
    }

    private var shouldShowFloatingAddButton: Bool {
        navigationPath.isEmpty && rootScreenPage == .tasks
    }

    private func navigationTitle() -> String {
        let query = universalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return "Search"
        }
        if rootScreenPage == .filters {
            return "Browse"
        }
        return titleForCurrentView()
    }

    private func matchesQuery(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func applyFilter(_ view: ViewIdentifier) {
        withAnimation(.easeInOut(duration: 0.2)) {
            container.selectedView = view
            rootScreenPage = .tasks
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
        let isCompleting = pathsCompleting.contains(path)
        let isSlidingOut = pathsSlidingOut.contains(path)
        return TaskRow(
            record: record,
            isCompleting: isCompleting || isSlidingOut,
            onCompletionTap: {
                guard record.document.frontmatter.status != .done else { return }
                completeWithAnimation(path: record.identity.path)
            }
        )
        .accessibilityIdentifier("taskRow.\(record.document.frontmatter.title)")
        .contentShape(Rectangle())
        .onTapGesture {
            guard editMode?.wrappedValue.isEditing != true else { return }
            navigationPath.append(record.identity.path)
        }
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
    let onCompletionTap: () -> Void
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

        Button {
            onCompletionTap()
        } label: {
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
        }
        .frame(width: 20, height: 20)
        .scaleEffect(isCompleting ? 0.84 : 1.0)
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: showFilled)
        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: isCompleting)
    }

    @ViewBuilder
    private func metadata(_ frontmatter: TaskFrontmatterV1) -> some View {
        HStack(spacing: 8) {
            if let due = frontmatter.due {
                Label(dueLabel(for: frontmatter, due: due), systemImage: "calendar.badge.clock")
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

    private func dueLabel(for frontmatter: TaskFrontmatterV1, due: LocalDate) -> String {
        if let dueTime = frontmatter.dueTime {
            return "Due \(due.isoString) \(dueTime.isoString)"
        }
        return "Due \(due.isoString)"
    }
}
