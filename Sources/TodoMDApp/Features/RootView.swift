import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct DeferDateTarget: Identifiable {
    let path: String
    var id: String { path }
}

private struct BuiltInRulesTarget: Identifiable {
    let view: BuiltInView
    var id: String { view.rawValue }
}

private enum CompactRootTab: String, Hashable, CaseIterable, Identifiable {
    case inbox
    case today
    case upcoming
    case areas
    case logbook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .today:
            return "Today"
        case .upcoming:
            return "Upcoming"
        case .areas:
            return "Areas"
        case .logbook:
            return "Logbook"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox:
            return "tray"
        case .today:
            return "star"
        case .upcoming:
            return "calendar"
        case .areas:
            return "square.grid.2x2"
        case .logbook:
            return "checkmark.circle"
        }
    }
}

private struct ProjectColorChoice: Identifiable {
    let hex: String
    let name: String
    var id: String { hex }
}

private enum InlineTaskPanel: Equatable {
    case date
    case destination
    case tags
}

private struct InlineTaskDraft: Equatable {
    var title = ""
    var dueDate: Date?
    var area: String?
    var project: String?
    var tagsText = ""
    var flagged = false

    var normalizedTags: [String] {
        let delimiters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        var seen = Set<String>()
        let tokens = tagsText
            .split(whereSeparator: { scalar in
                scalar.unicodeScalars.contains { delimiters.contains($0) }
            })
            .map { token -> String in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("#") {
                    return String(trimmed.dropFirst())
                }
                return trimmed
            }

        return tokens.compactMap { token in
            let normalized = token
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }
}

private struct SectionHeaderView: View {
    let title: String
    let count: Int?
    @EnvironmentObject private var theme: ThemeManager

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack {
            Text(displayText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondaryColor)
                .textCase(nil)
                .tracking(0.4)
            Spacer()
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
        .padding(.leading, 20)
    }

    private var displayText: String {
        let upper = title.uppercased()
        if let count {
            return "\(upper)  \(count)"
        }
        return upper
    }
}

private struct RootViewSearchableModifier: ViewModifier {
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
#if os(iOS)
        content.searchable(
            text: $text,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: prompt
        )
#else
        content.searchable(text: $text, prompt: prompt)
#endif
    }
}

private struct RootViewInsetGroupedListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.plain)
    }
}

private struct RootViewWordsAutocapitalization: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.textInputAutocapitalization(.words)
#else
        content
#endif
    }
}

private struct RootViewNeverAutocapitalization: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.textInputAutocapitalization(.never)
#else
        content
#endif
    }
}

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingQuickEntry = false
    @State private var navigationPath = NavigationPath()
    @State private var inboxNavigationPath = NavigationPath()
    @State private var todayNavigationPath = NavigationPath()
    @State private var upcomingNavigationPath = NavigationPath()
    @State private var areasNavigationPath = NavigationPath()
    @State private var logbookNavigationPath = NavigationPath()
    @State private var compactSelectedTab: CompactRootTab = .inbox
    @State private var universalSearchText = ""
    @State private var showingCreateProjectSheet = false
    @State private var newProjectName = ""
    @State private var newProjectColorHex = "1E88E5"
    @State private var newProjectIconSymbol = "folder"
    @State private var isCreatingTask = false
    @State private var compactComposerContentVisible = false
    @State private var inlineTaskDraft = InlineTaskDraft()
    @State private var expandedInlineTaskPanel: InlineTaskPanel?
    @State private var inlineComposerTransitionTask: Task<Void, Never>?
    @State private var showingProjectSettingsSheet = false
    @State private var editingProjectOriginalName = ""
    @State private var editingProjectName = ""
    @State private var editingProjectColorHex: String?
    @State private var editingProjectIconSymbol = "folder"
    @State private var pathsCompleting: Set<String> = []
    @State private var pathsSlidingOut: Set<String> = []
    @State private var completionAnimationTasks: [String: Task<Void, Never>] = [:]
    @State private var pendingDeletePath: String?
    @State private var pendingDeletePerspective: PerspectiveDefinition?
    @State private var deferDateTarget: DeferDateTarget?
    @State private var deferDateValue = Date()
    @State private var swipeAddProjectPath: String?
    @State private var editingPerspective: PerspectiveDefinition?
    @State private var builtInRulesTarget: BuiltInRulesTarget?
    @State private var inboxTriageMode = false
    @State private var inboxTriageSkippedPaths: Set<String> = []
    @State private var inboxTriagePinnedPath: String?
    @FocusState private var inlineTaskFocused: Bool
    @Namespace private var compactQuickAddNamespace
    @AppStorage("settings_pomodoro_enabled") private var pomodoroEnabled = false

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactRootPane
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailPane(path: $navigationPath) {
                        mainContent
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: container.selectedView)
        .background(theme.backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $showingQuickEntry) {
            QuickEntrySheet()
        }
        .sheet(isPresented: $showingCreateProjectSheet) {
            NavigationStack {
                createProjectSheet
            }
        }
        .sheet(isPresented: $showingProjectSettingsSheet) {
            NavigationStack {
                projectSettingsSheet
            }
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
        .confirmationDialog(
            "Add to Project",
            isPresented: Binding(
                get: { swipeAddProjectPath != nil },
                set: { isPresented in
                    if !isPresented { swipeAddProjectPath = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            let projects = container.allProjects()
            if projects.isEmpty {
                Button("No Projects") {}
                    .disabled(true)
            } else {
                ForEach(projects, id: \.self) { project in
                    Button(project) {
                        guard let path = swipeAddProjectPath else { return }
                        _ = container.addToProject(path: path, project: project)
                        swipeAddProjectPath = nil
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                swipeAddProjectPath = nil
            }
        }
        .onChange(of: container.navigationTaskPath) { _, newPath in
            guard let newPath else { return }
            cancelInlineTaskComposer()
            appendToActiveNavigationPath(newPath)
            container.clearPendingNavigationPath()
        }
        .onChange(of: container.shouldPresentQuickEntry) { _, shouldPresent in
            guard shouldPresent else { return }
            presentQuickEntryFromCurrentContext()
            container.clearQuickEntryRequest()
        }
        .onAppear {
            if horizontalSizeClass == .compact {
                syncCompactSelectedTab()
            }
            if let pending = container.navigationTaskPath {
                appendToActiveNavigationPath(pending)
                container.clearPendingNavigationPath()
            }
            if container.shouldPresentQuickEntry {
                presentQuickEntryFromCurrentContext()
                container.clearQuickEntryRequest()
            }
        }
        .onDisappear {
            cancelInlineTaskComposer()
            inlineComposerTransitionTask?.cancel()
            inlineComposerTransitionTask = nil
            completionAnimationTasks.values.forEach { $0.cancel() }
            completionAnimationTasks.removeAll()
        }
        .onChange(of: pomodoroEnabled) { _, isEnabled in
            guard !isEnabled, container.selectedView == .builtIn(.pomodoro) else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                container.selectedView = horizontalSizeClass == .compact ? .browse : .builtIn(.inbox)
            }
        }
        .onChange(of: container.selectedView) { _, selectedView in
            if !selectedView.isBrowse {
                universalSearchText = ""
            }
            if selectedView != .builtIn(.inbox) {
                resetInboxTriageMode()
            }
            if horizontalSizeClass == .compact {
                syncCompactSelectedTab()
            }
            cancelInlineTaskComposer()
        }
        .onChange(of: compactSelectedTab) { _, newTab in
            guard horizontalSizeClass == .compact else { return }
            guard compactRootTab(for: container.selectedView) != newTab else { return }
            selectCompactTab(newTab)
        }
        .onChange(of: activeNavigationDepth) { _, count in
            if count > 0 {
                cancelInlineTaskComposer()
            }
        }
    }

    private var isEditing: Bool {
#if os(iOS)
        editMode?.wrappedValue.isEditing == true
#else
        false
#endif
    }

    private var compactRootPane: some View {
        compactTabView
    }

    private var compactTabView: some View {
        TabView(selection: $compactSelectedTab) {
            ForEach(CompactRootTab.allCases) { tab in
                compactTabScene(tab)
            }
        }
        .tint(theme.accentColor)
    }

    private func compactTabScene(_ tab: CompactRootTab) -> AnyView {
        AnyView(
            detailPane(path: navigationPathBinding(for: tab)) {
                detailContent(for: tab)
            }
            .tabItem {
                Label(tab.title, systemImage: tab.systemImage)
            }
            .tag(tab)
            .accessibilityIdentifier("root.tab.\(tab.rawValue)")
        )
    }

    private var activeCompactTab: CompactRootTab {
        horizontalSizeClass == .compact ? compactSelectedTab : compactRootTab(for: container.selectedView)
    }

    private func navigationPathBinding(for tab: CompactRootTab) -> Binding<NavigationPath> {
        switch tab {
        case .inbox:
            return $inboxNavigationPath
        case .today:
            return $todayNavigationPath
        case .upcoming:
            return $upcomingNavigationPath
        case .areas:
            return $areasNavigationPath
        case .logbook:
            return $logbookNavigationPath
        }
    }

    private var activeNavigationPathBinding: Binding<NavigationPath> {
        if horizontalSizeClass == .compact {
            return navigationPathBinding(for: activeCompactTab)
        }
        return $navigationPath
    }

    private var activeNavigationDepth: Int {
        activeNavigationPathBinding.wrappedValue.count
    }

    private var isAtActiveNavigationRoot: Bool {
        activeNavigationPathBinding.wrappedValue.isEmpty
    }

    private func appendToActiveNavigationPath(_ path: String) {
        var updatedPath = activeNavigationPathBinding.wrappedValue
        updatedPath.append(path)
        activeNavigationPathBinding.wrappedValue = updatedPath
    }

    private func detailPane<Content: View>(
        path: Binding<NavigationPath>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: path) {
            detailPaneContent(content: content)
        }
    }

    private func detailPaneContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .navigationDestination(for: String.self) { path in
                TaskDetailView(path: path)
            }
            .navigationTitle(navigationTitle())
            .toolbar {
                detailToolbar
            }
            .safeAreaInset(edge: .bottom) {
                if shouldReserveFloatingAddButtonSpace {
                    Color.clear
                        .frame(height: 92)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if shouldShowFloatingAddButton {
                    floatingAddButton
                        .padding(.trailing, 24)
                        .padding(.bottom, 18)
                }
            }
            .overlay {
                if shouldShowCompactInlineTaskComposer {
                    compactInlineTaskComposerOverlay
                }
            }
            .refreshable {
                container.refresh()
            }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .appTrailingAction) {
            if shouldShowToolbarInlineTaskButton {
                Button {
                    triggerInlineTaskComposer()
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.regular))
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("root.inlineAddButton")
            }
        }

        ToolbarItem(placement: .appTrailingAction) {
            if container.selectedView == .builtIn(.inbox), isAtActiveNavigationRoot {
                Button {
                    toggleInboxTriageMode()
                } label: {
                    Label(inboxTriageMode ? "List" : "Triage", systemImage: inboxTriageMode ? "list.bullet" : "rectangle.stack")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .accessibilityIdentifier("root.triageToggle")
            }
        }

        ToolbarItem(placement: .appTrailingAction) {
            if horizontalSizeClass != .compact {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("root.settingsButton")
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("Areas") {
                navButton(view: .browse, label: "Areas", icon: "square.grid.2x2")
            }

            Section("Views") {
                builtInNavButton(.inbox, label: "Inbox", icon: "tray")
                    .keyboardShortcut("1", modifiers: .command)
                builtInNavButton(.myTasks, label: "My Tasks", icon: "person")
                    .keyboardShortcut("2", modifiers: .command)
                builtInNavButton(.delegated, label: "Delegated", icon: "person.2")
                    .keyboardShortcut("3", modifiers: .command)
                builtInNavButton(.today, label: "Today", icon: "star")
                    .keyboardShortcut("4", modifiers: .command)
                builtInNavButton(.upcoming, label: "Upcoming", icon: "calendar")
                    .keyboardShortcut("5", modifiers: .command)
                builtInNavButton(.logbook, label: "Logbook", icon: "checkmark.circle")
                builtInNavButton(.review, label: "Review", icon: "checklist")
                builtInNavButton(.anytime, label: "Anytime", icon: "list.bullet")
                builtInNavButton(.someday, label: "Someday", icon: "clock")
                builtInNavButton(.flagged, label: "Flagged", icon: "flag")
                if pomodoroEnabled {
                    builtInNavButton(.pomodoro, label: "Pomodoro", icon: "timer")
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
                                icon: container.projectIconSymbol(for: project),
                                isIndented: true,
                                tintHex: container.projectColorHex(for: project),
                                fallbackIcon: "folder"
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
            ToolbarItem(placement: .appTrailingAction) {
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
                .modifier(
                    RootViewSearchableModifier(
                        text: $universalSearchText,
                        prompt: "Search tasks, areas, projects, tags"
                    )
                )
        } else if container.selectedView == .builtIn(.upcoming) {
            UpcomingCalendarView(sections: container.upcomingAgendaSections())
        } else if container.selectedView == .builtIn(.review) {
            weeklyReviewContent()
        } else if container.selectedView == .builtIn(.pomodoro) {
            PomodoroTimerView()
        } else {
            let records = container.filteredRecords()

            if container.selectedView == .builtIn(.inbox), inboxTriageMode {
                InboxTriageView(
                    records: records,
                    skippedPaths: $inboxTriageSkippedPaths,
                    pinnedPath: $inboxTriagePinnedPath,
                    onExit: { resetInboxTriageMode() },
                    onOpenDetail: { path in
                        appendToActiveNavigationPath(path)
                    }
                )
            } else if records.isEmpty, shouldRenderInlineTaskComposerInList {
                List {
                    inlineTaskComposerListRow
                }
                .id("\(container.selectedView.rawValue)-inline-empty")
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.backgroundColor)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if records.isEmpty {
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
                        if shouldRenderInlineTaskComposerInList {
                            inlineTaskComposerListRow
                        }
                        if isEditing {
                            ForEach(records) { record in
                                taskRowItem(record)
                            }
                            .onMove { source, destination in
                                var reordered = records
                                reordered.move(fromOffsets: source, toOffset: destination)
                                container.saveManualOrder(filenames: reordered.map { $0.identity.filename })
                            }
                        } else {
                            if container.isCalendarConnected {
                                Section {
                                    TodayCalendarCard(events: container.calendarTodayEvents)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 8)
                                        .padding(.bottom, 14)
                                        .listRowInsets(EdgeInsets())
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                            }

                            ForEach(container.todaySections()) { section in
                                Section {
                                    ForEach(section.records) { record in
                                        taskRowItem(record)
                                    }
                                } header: {
                                    SectionHeaderView(section.group.rawValue, count: section.records.count)
                                }
                            }
                        }
                    } else {
                        if shouldRenderInlineTaskComposerInList {
                            inlineTaskComposerListRow
                        }
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
                .id(container.selectedView.rawValue)
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.backgroundColor)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var inlineTaskComposerListRow: some View {
        HStack(alignment: .top, spacing: 12) {
            TaskCheckbox(
                isCompleted: false,
                isDashed: false,
                tint: theme.accentColor,
                isInteractive: false,
                onTap: {}
            )
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                TextField("New Task", text: $inlineTaskDraft.title)
                    .font(.body)
                    .foregroundStyle(theme.textPrimaryColor)
                    .focused($inlineTaskFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("inlineTask.titleField")
                    .onSubmit {
                        commitInlineTaskComposer()
                    }

                inlineTaskAccessoryBar

                if let expandedInlineTaskPanel {
                    inlineTaskExpandedPanel(expandedInlineTaskPanel)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .transition(.asymmetric(
            insertion: .push(from: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var compactInlineTaskComposerOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelInlineTaskComposer()
                }

            compactInlineTaskComposerCard
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .transition(
            .asymmetric(
                insertion: .offset(x: 34, y: 144)
                    .combined(with: .scale(scale: 0.92, anchor: .bottomTrailing))
                    .combined(with: .opacity),
                removal: .offset(x: 28, y: 120)
                    .combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
                    .combined(with: .opacity)
            )
        )
        .zIndex(3)
    }

    private var compactInlineTaskComposerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                CompactComposerCheckbox(strokeColor: compactComposerCheckboxColor)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("New To-Do", text: $inlineTaskDraft.title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(compactComposerPrimaryTextColor)
                        .focused($inlineTaskFocused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("inlineTask.titleField")
                        .onSubmit {
                            commitInlineTaskComposer()
                        }

                    Text("Notes")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(compactComposerSecondaryTextColor)
                }

                Spacer(minLength: 0)
            }

            compactInlineTaskAccessoryBar

            if let expandedInlineTaskPanel {
                inlineTaskExpandedPanel(expandedInlineTaskPanel)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: expandedInlineTaskPanel == nil ? 134 : nil, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .opacity(compactComposerContentVisible ? 1 : 0.001)
        .offset(y: compactComposerContentVisible ? 0 : 10)
        .scaleEffect(compactComposerContentVisible ? 1 : 0.978, anchor: .bottomTrailing)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(compactComposerBackgroundColor)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                compactComposerHighlightColor,
                                compactComposerLowlightColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.045),
                                .clear,
                                .black.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(compactComposerBorderColor, lineWidth: 1)
            }
            .matchedGeometryEffect(
                id: "compactQuickAddShell",
                in: compactQuickAddNamespace,
                properties: .frame,
                anchor: .bottomTrailing
            )
            .shadow(color: .black.opacity(0.34), radius: 28, x: 0, y: 16)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        )
        .animation(.easeOut(duration: 0.18), value: compactComposerContentVisible)
    }

    private var inlineTaskAccessoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                QuickAddChip(
                    icon: "calendar",
                    label: inlineTaskDateLabel,
                    isSet: inlineTaskDraft.dueDate != nil,
                    tint: theme.accentColor
                ) {
                    toggleInlineTaskPanel(.date)
                }

                QuickAddChip(
                    icon: "tray",
                    label: inlineTaskDestinationLabel,
                    isSet: inlineTaskDraft.project != nil || inlineTaskDraft.area != nil,
                    tint: theme.accentColor
                ) {
                    toggleInlineTaskPanel(.destination)
                }

                QuickAddChip(
                    icon: "tag",
                    label: inlineTaskTagsLabel,
                    isSet: !inlineTaskDraft.normalizedTags.isEmpty,
                    tint: theme.accentColor
                ) {
                    toggleInlineTaskPanel(.tags)
                }

                QuickAddChip(
                    icon: "flag",
                    label: "Flag",
                    isSet: inlineTaskDraft.flagged,
                    tint: theme.flaggedColor
                ) {
                    inlineTaskDraft.flagged.toggle()
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var compactInlineDueTint: Color {
        if inlineTaskDraft.dueDate != nil {
            return compactComposerTodayTint
        }
        return compactComposerIconColor
    }

    private var compactComposerBackgroundColor: Color {
        Color(.sRGB, red: 0.1059, green: 0.1294, blue: 0.1569, opacity: 0.985)
    }

    private var compactComposerHighlightColor: Color {
        Color(.sRGB, red: 0.1333, green: 0.1569, blue: 0.1882, opacity: 0.94)
    }

    private var compactComposerLowlightColor: Color {
        Color(.sRGB, red: 0.0941, green: 0.1137, blue: 0.1373, opacity: 0.98)
    }

    private var compactComposerBorderColor: Color {
        Color.white.opacity(0.045)
    }

    private var compactComposerPrimaryTextColor: Color {
        Color.white.opacity(0.92)
    }

    private var compactComposerSecondaryTextColor: Color {
        Color.white.opacity(0.34)
    }

    private var compactComposerIconColor: Color {
        Color.white.opacity(0.42)
    }

    private var compactComposerIconActiveColor: Color {
        compactComposerPrimaryTextColor
    }

    private var compactComposerTodayTint: Color {
        Color(.sRGB, red: 0.949, green: 0.784, blue: 0.192, opacity: 1)
    }

    private var compactComposerFlagTint: Color {
        Color(.sRGB, red: 0.969, green: 0.604, blue: 0.22, opacity: 1)
    }

    private var compactComposerCheckboxColor: Color {
        Color.white.opacity(0.48)
    }

    private var compactInlineTaskAccessoryBar: some View {
        HStack(alignment: .center, spacing: 14) {
            CompactInlineLeadingButton(
                icon: "star.fill",
                label: inlineTaskDateLabel,
                tint: compactInlineDueTint
            ) {
                toggleInlineTaskPanel(.date)
            }

            Spacer(minLength: 0)

            CompactQuickAddIconButton(
                icon: "tag",
                tint: compactComposerIconActiveColor,
                inactiveTint: compactComposerIconColor,
                isActive: !inlineTaskDraft.normalizedTags.isEmpty
            ) {
                toggleInlineTaskPanel(.tags)
            }

            CompactQuickAddIconButton(
                icon: "list.bullet",
                tint: compactComposerIconActiveColor,
                inactiveTint: compactComposerIconColor,
                isActive: inlineTaskDraft.project != nil || inlineTaskDraft.area != nil
            ) {
                toggleInlineTaskPanel(.destination)
            }

            CompactQuickAddIconButton(
                icon: "flag",
                tint: compactComposerFlagTint,
                inactiveTint: compactComposerIconColor,
                isActive: inlineTaskDraft.flagged
            ) {
                inlineTaskDraft.flagged.toggle()
            }
        }
    }

    @ViewBuilder
    private func inlineTaskExpandedPanel(_ panel: InlineTaskPanel) -> some View {
        switch panel {
        case .date:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    InlineTaskOptionButton(
                        title: "Today",
                        isSelected: inlineTaskDraft.dueDate.map(Calendar.current.isDateInToday) == true,
                        tint: theme.accentColor
                    ) {
                        inlineTaskDraft.dueDate = Calendar.current.startOfDay(for: Date())
                    }

                    InlineTaskOptionButton(
                        title: "Tomorrow",
                        isSelected: inlineTaskDraft.dueDate.map(Calendar.current.isDateInTomorrow) == true,
                        tint: theme.accentColor
                    ) {
                        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return }
                        inlineTaskDraft.dueDate = Calendar.current.startOfDay(for: tomorrow)
                    }

                    InlineTaskOptionButton(
                        title: "Next Week",
                        isSelected: false,
                        tint: theme.accentColor
                    ) {
                        guard let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date()) else { return }
                        inlineTaskDraft.dueDate = Calendar.current.startOfDay(for: nextWeek)
                    }

                    InlineTaskOptionButton(
                        title: "No Date",
                        isSelected: inlineTaskDraft.dueDate == nil,
                        tint: theme.textSecondaryColor
                    ) {
                        inlineTaskDraft.dueDate = nil
                    }
                }
            }

        case .destination:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    InlineTaskOptionButton(
                        title: "Inbox",
                        isSelected: inlineTaskDraft.project == nil && inlineTaskDraft.area == nil,
                        tint: theme.accentColor
                    ) {
                        inlineTaskDraft.project = nil
                        inlineTaskDraft.area = nil
                    }

                    if let currentArea = defaultInlineTaskDraft(for: container.selectedView).area {
                        InlineTaskOptionButton(
                            title: currentArea,
                            isSelected: inlineTaskDraft.area == currentArea && inlineTaskDraft.project == nil,
                            tint: theme.accentColor
                        ) {
                            inlineTaskDraft.area = currentArea
                            inlineTaskDraft.project = nil
                        }
                    }

                    ForEach(container.recentProjects(limit: 6, excluding: inlineTaskDraft.project), id: \.self) { project in
                        InlineTaskOptionButton(
                            title: project,
                            isSelected: inlineTaskDraft.project == project,
                            tint: theme.accentColor
                        ) {
                            inlineTaskDraft.project = project
                            inlineTaskDraft.area = nil
                        }
                    }
                }
            }

        case .tags:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Tags", text: $inlineTaskDraft.tagsText)
                    .font(.footnote)
                    .modifier(RootViewNeverAutocapitalization())
                    .autocorrectionDisabled()

                if !inlineTaskSuggestedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(inlineTaskSuggestedTags, id: \.self) { tag in
                                InlineTaskOptionButton(
                                    title: "#\(tag)",
                                    isSelected: inlineTaskDraft.normalizedTags.contains(tag),
                                    tint: theme.accentColor
                                ) {
                                    appendInlineTag(tag)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var inlineTaskDateLabel: String {
        guard let dueDate = inlineTaskDraft.dueDate else { return "Date" }
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        }
        if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var inlineTaskDestinationLabel: String {
        if let project = inlineTaskDraft.project {
            return project
        }
        if let area = inlineTaskDraft.area {
            return area
        }
        return "Inbox"
    }

    private var inlineTaskTagsLabel: String {
        let tags = inlineTaskDraft.normalizedTags
        if tags.isEmpty {
            return "Tags"
        }
        if tags.count == 1, let first = tags.first {
            return "#\(first)"
        }
        return "\(tags.count) Tags"
    }

    private var inlineTaskSuggestedTags: [String] {
        let existing = Set(inlineTaskDraft.normalizedTags)
        return container.availableTags()
            .filter { !existing.contains($0) }
            .prefix(6)
            .map { $0 }
    }

    private func toggleInlineTaskPanel(_ panel: InlineTaskPanel) {
        if expandedInlineTaskPanel == panel {
            expandedInlineTaskPanel = nil
        } else {
            expandedInlineTaskPanel = panel
        }
    }

    private func appendInlineTag(_ tag: String) {
        let currentTags = inlineTaskDraft.normalizedTags
        guard !currentTags.contains(tag) else { return }
        let updatedTags = currentTags + [tag]
        inlineTaskDraft.tagsText = updatedTags.map { "#\($0)" }.joined(separator: " ")
    }

    private var browseSectionScreen: some View {
        List {
            if horizontalSizeClass == .compact {
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("root.settingsButton")
                }
            }

            Section("Lists") {
                builtInBrowseFilterButton(.myTasks, label: "My Tasks", icon: "person")
                builtInBrowseFilterButton(.delegated, label: "Delegated", icon: "person.2")
                builtInBrowseFilterButton(.anytime, label: "Anytime", icon: "list.bullet")
                builtInBrowseFilterButton(.someday, label: "Someday", icon: "clock")
                builtInBrowseFilterButton(.flagged, label: "Flagged", icon: "flag")
                builtInBrowseFilterButton(.review, label: "Review", icon: "checklist")
                if pomodoroEnabled {
                    builtInBrowseFilterButton(.pomodoro, label: "Pomodoro", icon: "timer")
                }
            }

            let areas = container.availableAreas()
            Section("Areas") {
                if areas.isEmpty {
                    Text("No areas yet")
                        .foregroundStyle(theme.textSecondaryColor)
                } else {
                    ForEach(areas, id: \.self) { area in
                        browseFilterButton(view: .area(area), label: area, icon: "square.grid.2x2")
                    }
                }
            }

            let projects = container.allProjects()
            Section {
                if projects.isEmpty {
                    Text("No projects yet")
                        .foregroundStyle(theme.textSecondaryColor)
                } else {
                    ForEach(projects, id: \.self) { project in
                        HStack(spacing: 8) {
                            browseFilterButton(
                                view: .project(project),
                                label: project,
                                icon: container.projectIconSymbol(for: project),
                                tintHex: container.projectColorHex(for: project),
                                fallbackIcon: "folder"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                openProjectSettings(for: project)
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(theme.textSecondaryColor)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit \(project)")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        newProjectName = ""
                        newProjectColorHex = "1E88E5"
                        newProjectIconSymbol = "folder"
                        showingCreateProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create Project")
                }
            }

            Section {
                if container.perspectives.isEmpty {
                    Text("No perspectives yet")
                        .foregroundStyle(theme.textSecondaryColor)
                } else {
                    ForEach(container.perspectives) { perspective in
                        HStack(spacing: 8) {
                            browseFilterButton(
                                view: container.perspectiveViewIdentifier(for: perspective.id),
                                label: perspective.name,
                                icon: perspective.icon,
                                tintHex: perspective.color,
                                fallbackIcon: "list.bullet"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
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

                            Button {
                                editingPerspective = perspective
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(theme.textSecondaryColor)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit \(perspective.name)")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Perspectives")
                    Spacer()
                    Button {
                        editingPerspective = PerspectiveDefinition()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create Perspective")
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
        .modifier(RootViewInsetGroupedListStyle())
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
        let builtInViews: [(label: String, view: ViewIdentifier, icon: String)] = {
            var views: [(label: String, view: ViewIdentifier, icon: String)] = [
                ("Areas", .browse, "square.grid.2x2"),
                ("Inbox", .builtIn(.inbox), "tray"),
                ("My Tasks", .builtIn(.myTasks), "person"),
                ("Delegated", .builtIn(.delegated), "person.2"),
                ("Today", .builtIn(.today), "star"),
                ("Upcoming", .builtIn(.upcoming), "calendar"),
                ("Logbook", .builtIn(.logbook), "checkmark.circle"),
                ("Review", .builtIn(.review), "checklist"),
                ("Anytime", .builtIn(.anytime), "list.bullet"),
                ("Someday", .builtIn(.someday), "clock"),
                ("Flagged", .builtIn(.flagged), "flag")
            ]
            if pomodoroEnabled {
                views.append(("Pomodoro", .builtIn(.pomodoro), "timer"))
            }
            return views.filter { matchesQuery($0.label, query: query) }
        }()

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
                                tintHex: perspective.color,
                                fallbackIcon: "list.bullet"
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
                                icon: container.projectIconSymbol(for: project),
                                tintHex: container.projectColorHex(for: project),
                                fallbackIcon: "folder"
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
            .modifier(RootViewInsetGroupedListStyle())
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

    private var createProjectSheet: some View {
        Form {
            Section("Name") {
                TextField("Project name", text: $newProjectName)
                    .modifier(RootViewWordsAutocapitalization())
                    .autocorrectionDisabled()
            }

            Section("Icon") {
                AppIconPickerLink(
                    label: "Icon",
                    title: "Project Icon",
                    fallbackSymbol: "folder",
                    tint: color(forHex: newProjectColorHex) ?? theme.accentColor,
                    selection: $newProjectIconSymbol
                )
            }

            Section("Color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
                    ForEach(projectColorChoices) { choice in
                        Button {
                            newProjectColorHex = choice.hex
                        } label: {
                            Circle()
                                .fill(color(forHex: choice.hex) ?? theme.textSecondaryColor)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if newProjectColorHex == choice.hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.name)
                    }
                }
            }
        }
        .navigationTitle("New Project")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    showingCreateProjectSheet = false
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    createProjectFromSheet()
                }
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var projectSettingsSheet: some View {
        Form {
            Section("Name") {
                TextField("Project name", text: $editingProjectName)
                    .modifier(RootViewWordsAutocapitalization())
                    .autocorrectionDisabled()
            }

            Section("Icon") {
                AppIconPickerLink(
                    label: "Icon",
                    title: "Project Icon",
                    fallbackSymbol: "folder",
                    tint: color(forHex: editingProjectColorHex) ?? theme.accentColor,
                    selection: $editingProjectIconSymbol
                )
            }

            Section("Color") {
                Button {
                    editingProjectColorHex = nil
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: editingProjectColorHex == nil ? "checkmark.circle.fill" : "circle")
                        Text("No Color")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
                    ForEach(projectColorChoices) { choice in
                        Button {
                            editingProjectColorHex = choice.hex
                        } label: {
                            Circle()
                                .fill(color(forHex: choice.hex) ?? theme.textSecondaryColor)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if editingProjectColorHex == choice.hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.name)
                    }
                }
            }
        }
        .navigationTitle("Project Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    showingProjectSettingsSheet = false
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveProjectSettings()
                }
                .disabled(editingProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func browseFilterButton(
        view: ViewIdentifier,
        label: String,
        icon: String,
        tintHex: String? = nil,
        fallbackIcon: String? = nil
    ) -> some View {
        let tint = color(forHex: tintHex)
        let resolvedFallback = fallbackIcon ?? (icon.isEmpty ? "questionmark.circle" : icon)
        return Button {
            applyFilter(view)
        } label: {
            HStack(spacing: 10) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: resolvedFallback,
                    pointSize: 17,
                    weight: .semibold,
                    tint: container.selectedView == view ? (tint ?? theme.accentColor) : (tint ?? theme.textSecondaryColor)
                )
                .frame(width: 20, height: 20)
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
                if builtInView != .review {
                    Button("View Rules") {
                        builtInRulesTarget = BuiltInRulesTarget(view: builtInView)
                    }
                }
            }
    }

    @ViewBuilder
    private func detailContent(for compactTab: CompactRootTab?) -> some View {
        if let compactTab, compactRootTab(for: container.selectedView) != compactTab {
            Color.clear
        } else {
            mainContent
        }
    }

    private func compactRootTab(for view: ViewIdentifier) -> CompactRootTab {
        switch view {
        case .builtIn(.inbox):
            return .inbox
        case .builtIn(.today):
            return .today
        case .builtIn(.upcoming):
            return .upcoming
        case .builtIn(.logbook):
            return .logbook
        default:
            return .areas
        }
    }

    private func rootView(for tab: CompactRootTab, currentView: ViewIdentifier? = nil) -> ViewIdentifier {
        let currentView = currentView ?? container.selectedView
        switch tab {
        case .inbox:
            return .builtIn(.inbox)
        case .today:
            return .builtIn(.today)
        case .upcoming:
            return .builtIn(.upcoming)
        case .areas:
            return compactRootTab(for: currentView) == .areas ? currentView : .browse
        case .logbook:
            return .builtIn(.logbook)
        }
    }

    private func selectCompactTab(_ tab: CompactRootTab) {
        let targetView = rootView(for: tab)
        applyFilter(targetView)
    }

    private func syncCompactSelectedTab() {
        let resolvedTab = compactRootTab(for: container.selectedView)
        guard compactSelectedTab != resolvedTab else { return }
        compactSelectedTab = resolvedTab
    }

    private func perspective(for view: ViewIdentifier) -> PerspectiveDefinition? {
        guard case .custom(let rawID) = view else { return nil }
        let prefix = "perspective:"
        guard rawID.hasPrefix(prefix) else { return nil }
        let id = String(rawID.dropFirst(prefix.count))
        guard !id.isEmpty else { return nil }
        return container.perspectives.first(where: { $0.id == id })
    }

    private var shouldShowInlineTaskButton: Bool {
        isAtActiveNavigationRoot && canCreateInlineTask(in: container.selectedView) && !inboxTriageMode
    }

    private var shouldShowToolbarInlineTaskButton: Bool {
        horizontalSizeClass != .compact && shouldShowInlineTaskButton
    }

    private var shouldShowFloatingAddButton: Bool {
        horizontalSizeClass == .compact && shouldShowInlineTaskButton && !isCreatingTask
    }

    private var shouldReserveFloatingAddButtonSpace: Bool {
        shouldShowFloatingAddButton
    }

    private var shouldRenderInlineTaskComposer: Bool {
        isCreatingTask && shouldShowInlineTaskButton
    }

    private var shouldRenderInlineTaskComposerInList: Bool {
        shouldRenderInlineTaskComposer && horizontalSizeClass != .compact
    }

    private var shouldShowCompactInlineTaskComposer: Bool {
        shouldRenderInlineTaskComposer && horizontalSizeClass == .compact
    }

    private var compactComposerOpenAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.84, blendDuration: 0.12)
    }

    private var compactComposerCloseAnimation: Animation {
        .spring(response: 0.24, dampingFraction: 0.94, blendDuration: 0.1)
    }

    private var floatingAddButton: some View {
        Button {
            triggerInlineTaskComposer()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(theme.accentColor)
                    .matchedGeometryEffect(
                        id: "compactQuickAddShell",
                        in: compactQuickAddNamespace,
                        properties: .frame,
                        anchor: .bottomTrailing
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    }

                Image(systemName: "plus")
                    .font(.system(size: 31, weight: .light))
                    .foregroundStyle(.white)
            }
            .frame(width: 68, height: 68)
            .shadow(color: theme.accentColor.opacity(0.3), radius: 20, x: 0, y: 10)
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("Add Task")
        .accessibilityIdentifier("root.inlineAddButton")
        .transition(.scale(scale: 0.86, anchor: .bottomTrailing).combined(with: .opacity))
    }

    private func canCreateInlineTask(in view: ViewIdentifier) -> Bool {
        switch view {
        case .builtIn(.review), .builtIn(.upcoming), .builtIn(.logbook), .builtIn(.pomodoro):
            return false
        case .custom(let rawValue):
            return rawValue != ViewIdentifier.browseRawValue
        default:
            return !view.isBrowse
        }
    }

    private func presentQuickEntryFromCurrentContext() {
        if shouldShowInlineTaskButton {
            triggerInlineTaskComposer()
        } else {
            showingQuickEntry = true
        }
    }

    private func triggerInlineTaskComposer() {
        guard shouldShowInlineTaskButton else {
            showingQuickEntry = true
            return
        }
        inlineComposerTransitionTask?.cancel()
        inlineComposerTransitionTask = nil
        if isCreatingTask {
            inlineTaskFocused = true
            return
        }

        inlineTaskDraft = defaultInlineTaskDraft(for: container.selectedView)
        expandedInlineTaskPanel = nil
        compactComposerContentVisible = horizontalSizeClass != .compact
        withAnimation(compactComposerOpenAnimation) {
            isCreatingTask = true
        }

        if horizontalSizeClass == .compact {
            inlineComposerTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 55_000_000)
                withAnimation(.easeOut(duration: 0.18)) {
                    compactComposerContentVisible = true
                }
                inlineComposerTransitionTask = nil
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            inlineTaskFocused = isCreatingTask
        }
    }

    private func cancelInlineTaskComposer() {
        guard isCreatingTask else { return }
        inlineComposerTransitionTask?.cancel()
        inlineComposerTransitionTask = nil
        if horizontalSizeClass == .compact {
            withAnimation(.easeOut(duration: 0.12)) {
                compactComposerContentVisible = false
            }
            inlineComposerTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(compactComposerCloseAnimation) {
                    isCreatingTask = false
                }
                inlineTaskDraft = InlineTaskDraft()
                inlineComposerTransitionTask = nil
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                isCreatingTask = false
            }
            inlineTaskDraft = InlineTaskDraft()
        }
        inlineTaskFocused = false
        expandedInlineTaskPanel = nil
    }

    private func commitInlineTaskComposer() {
        let trimmedTitle = inlineTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            cancelInlineTaskComposer()
            return
        }

        let defaultDraft = defaultInlineTaskDraft(for: container.selectedView)
        let explicitDue: LocalDate?
        if inlineTaskDraft.dueDate == defaultDraft.dueDate {
            explicitDue = nil
        } else {
            explicitDue = inlineTaskDraft.dueDate.map(localDate(from:))
        }
        let defaultView: BuiltInView? = {
            if case .builtIn(let builtInView) = container.selectedView {
                return builtInView
            }
            return nil
        }()

        let created = container.createTask(
            fromQuickEntryText: trimmedTitle,
            explicitDue: explicitDue,
            priority: nil,
            flagged: inlineTaskDraft.flagged,
            tags: inlineTaskDraft.normalizedTags,
            area: inlineTaskDraft.area,
            project: inlineTaskDraft.project,
            defaultView: defaultView
        )
        if !created {
            container.createTask(
                title: trimmedTitle,
                naturalDate: nil,
                tags: inlineTaskDraft.normalizedTags,
                explicitDue: explicitDue,
                priorityOverride: nil,
                flagged: inlineTaskDraft.flagged,
                area: inlineTaskDraft.area,
                project: inlineTaskDraft.project,
                source: "user",
                defaultView: defaultView
            )
        }

        cancelInlineTaskComposer()
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
    }

    private func defaultInlineTaskDraft(for view: ViewIdentifier) -> InlineTaskDraft {
        var draft = InlineTaskDraft()
        switch view {
        case .builtIn(.today):
            draft.dueDate = Calendar.current.startOfDay(for: Date())
        case .area(let area):
            draft.area = area
        case .project(let project):
            draft.project = project
        case .tag(let tag):
            draft.tagsText = "#\(tag)"
        default:
            break
        }
        return draft
    }

    private func localDate(from date: Date) -> LocalDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (try? LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )) ?? .epoch
    }

    private func navigationTitle() -> String {
        if container.selectedView.isBrowse {
            return "Areas"
        }
        return titleForCurrentView()
    }

    private func matchesQuery(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func createProjectFromSheet() {
        let trimmedProjectName = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectName.isEmpty else { return }
        guard let created = container.createProject(
            name: trimmedProjectName,
            colorHex: newProjectColorHex,
            iconSymbol: newProjectIconSymbol
        ) else { return }

        newProjectName = ""
        newProjectColorHex = "1E88E5"
        newProjectIconSymbol = "folder"
        showingCreateProjectSheet = false
        applyFilter(.project(created))
    }

    private func openProjectSettings(for project: String) {
        editingProjectOriginalName = project
        editingProjectName = project
        editingProjectColorHex = container.projectColorHex(for: project)
        editingProjectIconSymbol = container.projectIconSymbol(for: project)
        showingProjectSettingsSheet = true
    }

    private func saveProjectSettings() {
        let trimmedName = editingProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let updatedProject = container.updateProject(
            originalName: editingProjectOriginalName,
            newName: trimmedName,
            colorHex: editingProjectColorHex,
            iconSymbol: editingProjectIconSymbol
        ) else { return }

        showingProjectSettingsSheet = false
        if case .project = container.selectedView {
            applyFilter(.project(updatedProject))
        }
    }

    private func applyFilter(_ view: ViewIdentifier) {
        withAnimation(.easeInOut(duration: 0.18)) {
            container.selectedView = view
        }
        universalSearchText = ""
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }

    private func toggleInboxTriageMode() {
        if inboxTriageMode {
            resetInboxTriageMode()
            return
        }
        inboxTriageSkippedPaths.removeAll()
        inboxTriagePinnedPath = container.filteredRecords().first?.identity.path
        inboxTriageMode = true
    }

    private func resetInboxTriageMode() {
        inboxTriageMode = false
        inboxTriageSkippedPaths.removeAll()
        inboxTriagePinnedPath = nil
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

            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                _ = pathsCompleting.insert(path)
            }

            do { try await Task.sleep(nanoseconds: 450_000_000) } catch {
                resetCompletionAnimationState(path: path)
                return
            }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                _ = pathsSlidingOut.insert(path)
            }

#if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif

            do { try await Task.sleep(nanoseconds: 350_000_000) } catch {
                resetCompletionAnimationState(path: path)
                return
            }

            container.complete(path: path)

            do { try await Task.sleep(nanoseconds: 120_000_000) } catch {
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
            isCompleting: isCompleting || isSlidingOut,
            onComplete: { completeWithAnimation(path: path) }
        )
        .accessibilityIdentifier("taskRow.\(record.document.frontmatter.title)")
        .accessibilityHint("Swipe right for quick actions. Swipe left to complete. Long press for more options.")
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing else { return }
            cancelInlineTaskComposer()
            appendToActiveNavigationPath(record.identity.path)
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
                                _ = container.addToProject(path: record.identity.path, project: project)
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
                _ = container.setDefer(path: record.identity.path, date: Date())
            } label: {
                Label("Today", systemImage: "sun.max.fill")
            }
            .tint(.blue)

            Button {
                swipeAddProjectPath = record.identity.path
            } label: {
                Label("Add to Project", systemImage: "folder.badge.plus")
            }
            .tint(.teal)
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
        .opacity(isSlidingOut ? 0.0 : 1.0)
        .offset(y: isSlidingOut ? -8 : 0)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pathsCompleting)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pathsSlidingOut)
    }

    private func navButton(
        view: ViewIdentifier,
        label: String,
        icon: String,
        isIndented: Bool = false,
        tintHex: String? = nil,
        fallbackIcon: String? = nil
    ) -> some View {
        let tint = color(forHex: tintHex)
        let resolvedFallback = fallbackIcon ?? (icon.isEmpty ? "questionmark.circle" : icon)
        return Button {
            applyFilter(view)
        } label: {
            HStack(spacing: 10) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: resolvedFallback,
                    pointSize: 17,
                    weight: .semibold,
                    tint: container.selectedView == view ? (tint ?? theme.accentColor) : (tint ?? theme.textSecondaryColor)
                )
                .frame(width: 20, height: 20)
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
                if builtInView != .review {
                    Button("View Rules") {
                        builtInRulesTarget = BuiltInRulesTarget(view: builtInView)
                    }
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
            case .logbook:
                return "Logbook"
            case .review:
                return "Review"
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
                return "Areas"
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

extension RootView {
    @ViewBuilder
    private func weeklyReviewContent() -> some View {
        let sections = container.weeklyReviewSections()

        if sections.isEmpty {
            ContentUnavailableView(
                "Review Is Clear",
                systemImage: "checkmark.circle",
                description: Text("Nothing is stale, overdue, deferred into someday, or missing a next action.")
            )
        } else {
            List {
                ForEach(sections) { section in
                    Section {
                        switch section.kind {
                        case .projectsWithoutNextAction:
                            ForEach(section.projects) { summary in
                                reviewProjectRow(summary)
                            }
                        case .overdue, .stale, .someday:
                            ForEach(section.records) { record in
                                taskRowItem(record)
                            }
                        }
                    } header: {
                        SectionHeaderView(section.kind.title, count: section.count)
                    }
                }
            }
            .id(container.selectedView.rawValue)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.backgroundColor)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func reviewProjectRow(_ summary: WeeklyReviewProjectSummary) -> some View {
        Button {
            applyFilter(.project(summary.project))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                AppIconGlyph(
                    icon: container.projectIconSymbol(for: summary.project),
                    fallbackSymbol: "folder",
                    pointSize: 18,
                    weight: .semibold,
                    tint: color(forHex: container.projectColorHex(for: summary.project)) ?? theme.accentColor
                )
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.project)
                        .font(.body)
                        .foregroundStyle(theme.textPrimaryColor)
                        .lineLimit(2)

                    Text(reviewProjectSummaryText(summary))
                        .font(.caption)
                        .foregroundStyle(theme.textSecondaryColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func reviewProjectSummaryText(_ summary: WeeklyReviewProjectSummary) -> String {
        var parts = ["\(summary.taskCount) open"]
        if summary.blockedCount > 0 {
            parts.append("\(summary.blockedCount) blocked")
        }
        if summary.delegatedCount > 0 {
            parts.append("\(summary.delegatedCount) delegated")
        }
        if summary.deferredCount > 0 {
            parts.append("\(summary.deferredCount) deferred")
        }
        if summary.somedayCount > 0 {
            parts.append("\(summary.somedayCount) someday")
        }
        parts.append("no current next action")
        return parts.joined(separator: "  ·  ")
    }
}

private struct TaskRow: View {
    private struct MetadataSegment {
        let text: String
        let color: Color
    }

    let record: TaskRecord
    let isCompleting: Bool
    let onComplete: () -> Void
    @EnvironmentObject private var theme: ThemeManager

    private var completionAccessibilityIdentifier: String {
        "taskRow.complete.\(record.document.frontmatter.title)"
    }

    var body: some View {
        let frontmatter = record.document.frontmatter

        HStack(alignment: .top, spacing: 12) {
            TaskCheckbox(
                isCompleted: isCompleting || frontmatter.status == .done || frontmatter.status == .cancelled,
                isDashed: frontmatter.status == .inProgress && !isCompleting,
                tint: checkboxTint(for: frontmatter),
                accessibilityIdentifier: completionAccessibilityIdentifier,
                onTap: onComplete
            )
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(frontmatter.title)
                    .font(.body)
                    .fontWeight(.regular)
                    .foregroundStyle(isCompleting ? theme.textSecondaryColor : theme.textPrimaryColor)
                    .strikethrough(isCompleting, color: theme.textSecondaryColor)
                    .lineLimit(2)

                if let metadataText = metadataLine(frontmatter: frontmatter) {
                    metadataText
                        .font(.footnote)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if frontmatter.flagged {
                Image(systemName: "flag.fill")
                    .font(.footnote)
                    .foregroundStyle(theme.flaggedColor)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 13)
    }

    private func checkboxTint(for frontmatter: TaskFrontmatterV1) -> Color {
        if frontmatter.status == .cancelled {
            return theme.textSecondaryColor
        }
        return theme.accentColor
    }

    private func metadataLine(frontmatter: TaskFrontmatterV1) -> Text? {
        let segments = metadataSegments(for: frontmatter)
        guard let first = segments.first else { return nil }

        var combined = Text(first.text).foregroundColor(first.color)
        for segment in segments.dropFirst() {
            combined = combined + Text("  ·  ").foregroundColor(theme.textSecondaryColor)
            combined = combined + Text(segment.text).foregroundColor(segment.color)
        }
        return combined
    }

    private func metadataSegments(for frontmatter: TaskFrontmatterV1) -> [MetadataSegment] {
        var segments: [MetadataSegment] = []

        if let project = frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            segments.append(MetadataSegment(text: project, color: theme.textSecondaryColor))
        } else if let area = frontmatter.area?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !area.isEmpty {
            segments.append(MetadataSegment(text: area, color: theme.textSecondaryColor))
        }

        if let dueText = dueDisplayText(for: frontmatter) {
            segments.append(MetadataSegment(
                text: dueText,
                color: isOverdue(frontmatter) ? theme.overdueColor : theme.textSecondaryColor
            ))
        }

        if let completionText = completionDisplayText(for: frontmatter) {
            segments.append(MetadataSegment(text: completionText, color: theme.textSecondaryColor))
        }

        if let recurrenceText = recurrenceDisplayText(for: frontmatter) {
            segments.append(MetadataSegment(text: recurrenceText, color: theme.textSecondaryColor))
        }

        segments.append(contentsOf: frontmatter.tags.prefix(2).map {
            MetadataSegment(text: "#\($0)", color: theme.textSecondaryColor)
        })
        return segments
    }

    private func dueDisplayText(for frontmatter: TaskFrontmatterV1) -> String? {
        guard let due = frontmatter.due else { return nil }
        guard let dueDate = date(from: due, time: frontmatter.dueTime) else { return due.isoString }
        let calendar = Calendar.current

        if frontmatter.dueTime != nil, calendar.isDateInToday(dueDate) {
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

    private func isOverdue(_ frontmatter: TaskFrontmatterV1) -> Bool {
        guard let due = frontmatter.due,
              frontmatter.status != .done,
              frontmatter.status != .cancelled,
              let dueDate = date(from: due, time: frontmatter.dueTime) else {
            return false
        }

        if frontmatter.dueTime != nil {
            return dueDate < Date()
        }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: Date())
    }

    private func completionDisplayText(for frontmatter: TaskFrontmatterV1) -> String? {
        guard frontmatter.status == .done || frontmatter.status == .cancelled else { return nil }

        let prefix = frontmatter.status == .cancelled ? "Cancelled" : "Completed"
        guard let completed = frontmatter.completed else { return prefix }

        let calendar = Calendar.current
        if calendar.isDateInToday(completed) {
            return "\(prefix) Today"
        }
        if calendar.isDateInYesterday(completed) {
            return "\(prefix) Yesterday"
        }
        return "\(prefix) \(completed.formatted(date: .abbreviated, time: .omitted))"
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

private struct TaskCheckbox: View {
    let isCompleted: Bool
    let isDashed: Bool
    let tint: Color
    var isInteractive = true
    let accessibilityIdentifier: String?
    let onTap: () -> Void

    @State private var fillProgress: CGFloat

    init(
        isCompleted: Bool,
        isDashed: Bool,
        tint: Color,
        isInteractive: Bool = true,
        accessibilityIdentifier: String? = nil,
        onTap: @escaping () -> Void
    ) {
        self.isCompleted = isCompleted
        self.isDashed = isDashed
        self.tint = tint
        self.isInteractive = isInteractive
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
        _fillProgress = State(initialValue: isCompleted ? 1 : 0)
    }

    var body: some View {
        Group {
            if isInteractive {
                if let accessibilityIdentifier {
                    Button(action: handleTap) {
                        checkboxBody
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(accessibilityIdentifier)
                } else {
                    Button(action: handleTap) {
                        checkboxBody
                    }
                    .buttonStyle(.plain)
                }
            } else {
                checkboxBody
            }
        }
        .onChange(of: isCompleted) { _, completed in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                fillProgress = completed ? 1 : 0
            }
        }
    }

    private var checkboxBody: some View {
        ZStack {
            Circle()
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 1.5, dash: isDashed && !isCompleted ? [3, 2] : [])
                )
                .frame(width: 22, height: 22)

            Circle()
                .fill(tint)
                .frame(width: 22, height: 22)
                .scaleEffect(fillProgress)
                .opacity(fillProgress)

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .opacity(fillProgress)
        }
        .frame(width: 22, height: 22)
    }

    private func handleTap() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
        onTap()
    }
}

private struct QuickAddChip: View {
    let icon: String
    let label: String
    let isSet: Bool
    let tint: Color
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSet ? tint.opacity(0.15) : theme.surfaceColor)
            )
            .foregroundStyle(isSet ? tint : theme.textSecondaryColor)
        }
        .buttonStyle(.plain)
    }
}

private struct CompactInlineLeadingButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 16, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

private struct CompactQuickAddIconButton: View {
    let icon: String
    let tint: Color
    let inactiveTint: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(isActive ? tint : inactiveTint)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

private struct CompactComposerCheckbox: View {
    let strokeColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(strokeColor, lineWidth: 1.8)
            .frame(width: 18, height: 18)
    }
}

private struct InlineTaskOptionButton: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? tint.opacity(0.15) : theme.surfaceColor)
                )
                .foregroundStyle(isSelected ? tint : theme.textSecondaryColor)
        }
        .buttonStyle(.plain)
    }
}
