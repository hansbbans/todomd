import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct DeferDateTarget: Identifiable {
    let path: String
    var id: String { path }
}

private struct ExpandedTaskDateTarget: Identifiable {
    let path: String
    let initialDate: Date?
    let initialRecurrence: String?

    var id: String { path }
}

private struct PersistedExpandedTaskDateState: Equatable {
    let date: Date?
    let recurrence: String?
}

private struct ExpandedTaskTagsTarget: Identifiable {
    let path: String
    let initialTags: [String]

    var id: String { path }
}

private struct ExpandedTaskMoveTarget: Identifiable {
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
    case areas
    case customPrimary
    case customSecondary

    var id: String { rawValue }
}

private struct ProjectColorChoice: Identifiable {
    let hex: String
    let name: String
    var id: String { hex }
}

private enum ProjectSheetMode: Identifiable, Equatable {
    case create
    case duplicate(sourceProject: String)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .duplicate(let sourceProject):
            return "duplicate:\(sourceProject)"
        }
    }
}

private struct MainViewHeroConfiguration {
    let title: String
    let symbolName: String
    let iconColor: Color
}

#if canImport(UIKit)
private struct CompactTabBarImageConfigurator: UIViewRepresentable {
    let choices: [CompactTabChoice]

    final class ProbeView: UIView {
        var choices: [CompactTabChoice] = []
        private var pendingApplyWorkItem: DispatchWorkItem?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleApply()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            scheduleApply()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleApply()
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func scheduleApply() {
            pendingApplyWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.applyTabBarItemsIfPossible()
            }
            pendingApplyWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.applyTabBarItemsIfPossible()
            }
        }

        func applyTabBarItemsIfPossible() {
            guard let tabBar = findTabBar(in: window),
                  let items = tabBar.items,
                  items.count >= choices.count else {
                return
            }

            for (index, choice) in choices.enumerated() {
                let item = items[index]
                item.title = choice.title
                item.accessibilityIdentifier = choice.accessibilityIdentifier

                guard !choice.iconToken.isEmoji,
                      let image = CompactTabBarImageConfigurator.symbolImage(for: choice) else {
                    continue
                }

                let templatedImage = image.withRenderingMode(.alwaysTemplate)
                item.image = templatedImage
                item.selectedImage = templatedImage
            }

            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
        }

        private func findTabBar(in rootView: UIView?) -> UITabBar? {
            guard let rootView else { return nil }
            if let tabBar = rootView as? UITabBar {
                return tabBar
            }

            for subview in rootView.subviews {
                if let tabBar = findTabBar(in: subview) {
                    return tabBar
                }
            }

            return nil
        }
    }

    func makeUIView(context: Context) -> UIView {
        ProbeView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let probeView = uiView as? ProbeView else {
            return
        }
        probeView.choices = choices
        probeView.scheduleApply()
    }

    private static func symbolImage(for choice: CompactTabChoice) -> UIImage? {
        let preferredNames: [String]
        if choice.view.isBrowse {
            preferredNames = [
                CompactTabChoiceCatalog.compactTabBarSymbolName(for: choice),
                "square.grid.2x2.fill",
                "square.grid.3x3.fill",
                "square.grid.2x2",
                "square.grid.3x3",
                "list.bullet"
            ]
        } else {
            preferredNames = [
                CompactTabChoiceCatalog.compactTabBarSymbolName(for: choice),
                choice.iconToken.symbolName
            ]
        }

        for name in preferredNames {
            if let image = UIImage(systemName: name) {
                return image
            }
        }
        return nil
    }
}
#endif

private enum InlineTaskPanel: Equatable {
    case destination
    case tags
}

private enum InlineTaskComposerSuggestionKind {
    case project
    case tag

    var title: String {
        switch self {
        case .project:
            return "Projects"
        case .tag:
            return "Tags"
        }
    }

    var systemImage: String {
        switch self {
        case .project:
            return "tray"
        case .tag:
            return "tag"
        }
    }
}

private struct InlineTaskComposerSuggestionContext {
    let kind: InlineTaskComposerSuggestionKind
    let query: String
    let suggestions: [String]
}

private struct InlineTaskDraft: Equatable {
    var title = ""
    var description = ""
    var dueDate: Date?
    var dueTime = NotificationTimePreference().date(on: Date())
    var hasDueTime = false
    var recurrence = ""
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

private struct RootViewInsetGroupedListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.plain)
    }
}

#if os(iOS)
private enum RootPullToSearchCoordinateSpace {
    static let name = "rootPullToSearchScrollArea"
}

private struct RootPullToSearchTopOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

private struct RootPullToSearchTopMarker: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RootPullToSearchTopOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(RootPullToSearchCoordinateSpace.name)).minY
                )
            }
        }
    }
}
#endif

private struct RootPullToSearchIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: CGFloat
    let isVisible: Bool
    let isArmed: Bool

    private var activationProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1.2)
    }

    private var progressAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return .interactiveSpring(response: 0.18, dampingFraction: 0.84, blendDuration: 0.08)
    }

    private var armedAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return .spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0.1)
    }

    var body: some View {
        let panelScale = 0.82 + (clampedProgress * 0.18)
        let iconScale = 0.84 + (clampedProgress * 0.22)
        let panelOpacity = isVisible ? min(1, 0.12 + (activationProgress * 1.28)) : 0
        let verticalOffset = max(-18, 18 - (clampedProgress * 24))

        VStack(spacing: 7) {
            RootPullToSearchMagnifyingGlass(
                progress: activationProgress,
                isArmed: isArmed
            )
            .frame(width: 28, height: 28)
            .scaleEffect(iconScale)

            Text(isArmed ? "Release to search" : "Pull to search")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .opacity(activationProgress > 0.2 ? 1 : activationProgress / 0.2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(isArmed ? 0.18 : 0.08), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.22), radius: 16, y: 10)
        .scaleEffect(panelScale)
        .offset(y: verticalOffset)
        .opacity(panelOpacity)
        .animation(progressAnimation, value: progress)
        .animation(armedAnimation, value: isArmed)
        .accessibilityHidden(true)
    }
}

private struct RootPullToSearchMagnifyingGlass: View {
    let progress: CGFloat
    let isArmed: Bool

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var tint: Color {
        Color(red: 0.24, green: 0.74, blue: 0.98)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lensDiameter = size * 0.62
            let lensStrokeWidth = max(2.2, size * 0.085)
            let lensInset = lensStrokeWidth * 0.8
            let handleWidth = max(4.5, size * 0.15)
            let handleHeight = size * 0.3
            let handleFillHeight = max(handleWidth, handleHeight * max(clampedProgress, 0.12))
            let lensFillHeight = max(0, (lensDiameter - (lensInset * 2)) * clampedProgress)

            VStack(spacing: -(lensStrokeWidth * 0.45)) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.07 + (clampedProgress * 0.08)))

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.98),
                                    Color(red: 0.56, green: 0.9, blue: 1.0)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .padding(lensInset)
                        .mask(alignment: .bottom) {
                            Rectangle()
                                .frame(height: lensFillHeight)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }

                    Circle()
                        .strokeBorder(Color.white.opacity(isArmed ? 0.98 : 0.72), lineWidth: lensStrokeWidth)
                }
                .frame(width: lensDiameter, height: lensDiameter)

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.46 + (clampedProgress * 0.32)))
                    .frame(width: handleWidth, height: handleHeight)
                    .overlay(alignment: .top) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.8),
                                        tint
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: handleWidth, height: handleFillHeight)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotationEffect(.degrees(-45))
            .shadow(color: tint.opacity(isArmed ? 0.24 : 0.14 * clampedProgress), radius: isArmed ? 10 : 6)
        }
    }
}

private struct RootPullToSearchGestureModifier: ViewModifier {
    let isEnabled: Bool
    let onTrigger: () -> Void

#if os(iOS)
    @State private var pullDistance: CGFloat = 0
    @State private var isArmed = false
    @State private var isListAtTop = true
    @State private var dragStartedAtTop = false
    @State private var isTrackingDrag = false

    private let activationDistance: CGFloat = 96
    private let topOffsetTolerance: CGFloat = 12
    private let maxHorizontalDrift: CGFloat = 140
#endif

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .coordinateSpace(name: RootPullToSearchCoordinateSpace.name)
            .onPreferenceChange(RootPullToSearchTopOffsetPreferenceKey.self) { minY in
                guard let minY else { return }
                isListAtTop = minY >= -topOffsetTolerance
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 14, coordinateSpace: .global)
                    .onChanged { value in
                        if !isTrackingDrag {
                            isTrackingDrag = true
                            dragStartedAtTop = isListAtTop
                        }

                        guard isEnabled, dragStartedAtTop else {
                            resetIndicator(animated: true)
                            return
                        }

                        let verticalPull = max(0, value.translation.height)
                        guard verticalPull > 0,
                              abs(value.translation.width) < maxHorizontalDrift else {
                            resetIndicator(animated: true)
                            return
                        }

                        pullDistance = verticalPull
                        isArmed = verticalPull >= activationDistance
                    }
                    .onEnded { value in
                        let shouldTrigger = isEnabled &&
                            dragStartedAtTop &&
                            value.translation.height >= activationDistance &&
                            abs(value.translation.width) < maxHorizontalDrift

                        resetGestureState(animated: true)

                        guard shouldTrigger else { return }
                        onTrigger()
                    }
            )
            .overlay(alignment: .top) {
                RootPullToSearchIndicator(
                    progress: pullDistance / activationDistance,
                    isVisible: isEnabled && pullDistance > 0,
                    isArmed: isArmed
                )
                .padding(.top, 8)
                .allowsHitTesting(false)
            }
#else
        content
#endif
    }

#if os(iOS)
    private func resetGestureState(animated: Bool) {
        dragStartedAtTop = false
        isTrackingDrag = false
        resetIndicator(animated: animated)
    }

    private func resetIndicator(animated: Bool) {
        if animated {
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.84, blendDuration: 0.08)) {
                pullDistance = 0
                isArmed = false
            }
        } else {
            pullDistance = 0
            isArmed = false
        }
    }
#endif
}

private struct RootNavigationTitleModifier: ViewModifier {
    let title: String
    let useInlineDisplayMode: Bool

    func body(content: Content) -> some View {
#if os(iOS)
        if useInlineDisplayMode {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
                .navigationTitle(title)
        }
#else
        content
            .navigationTitle(title)
#endif
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingQuickEntry = false
    @State private var navigationPath = NavigationPath()
    @State private var inboxNavigationPath = NavigationPath()
    @State private var todayNavigationPath = NavigationPath()
    @State private var customPrimaryNavigationPath = NavigationPath()
    @State private var areasNavigationPath = NavigationPath()
    @State private var customSecondaryNavigationPath = NavigationPath()
    @State private var compactSelectedTab: CompactRootTab = .inbox
    @State private var universalSearchText = ""
    @State private var isRootSearchPresented = false
    @State private var quickFindStore = QuickFindStore()
    @State private var activeProjectSheetMode: ProjectSheetMode?
    @State private var newProjectName = ""
    @State private var newProjectColorHex = "1E88E5"
    @State private var newProjectIconSymbol = "folder"
    @State private var pendingProjectDuplicationSourceName: String?
    @State private var isCreatingTask = false
    @State private var compactComposerContentVisible = false
    @State private var inlineTaskDraft = InlineTaskDraft()
    @State private var expandedInlineTaskPanel: InlineTaskPanel?
    @State private var showingInlineTaskDateModal = false
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
    @State private var expandedTaskPath: String?
    @State private var expandedTaskDateTarget: ExpandedTaskDateTarget?
    @State private var expandedTaskTagsTarget: ExpandedTaskTagsTarget?
    @State private var expandedTaskMoveTarget: ExpandedTaskMoveTarget?
    @State private var pendingExpandedTaskPath: String?
    @State private var expandedTaskScrollTask: Task<Void, Never>?
    @State private var inlineComposerScrollTask: Task<Void, Never>?
    @State private var swipeAddProjectPath: String?
    @State private var editingPerspective: PerspectiveDefinition?
    @State private var builtInRulesTarget: BuiltInRulesTarget?
    @State private var inboxTriageMode = false
    @State private var inboxTriageSkippedPaths: Set<String> = []
    @State private var inboxTriagePinnedPath: String?
    @State private var inlineAutoDatePhrase: String?
    @State private var inlineTaskTitleMutationInFlight = false
    @State private var showingInlineVoiceRamble = false
    @FocusState private var inlineTaskFocused: Bool
    @Namespace private var compactQuickAddNamespace
    @AppStorage(CompactTabSettings.leadingViewKey) private var compactPrimaryTabRawValue = CompactTabSettings.defaultLeadingView.rawValue
    @AppStorage(CompactTabSettings.trailingViewKey) private var compactSecondaryTabRawValue = CompactTabSettings.defaultTrailingView.rawValue
    @AppStorage("settings_pomodoro_enabled") private var pomodoroEnabled = false

    private var rootScaffold: some View {
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
    }

    private var inlineTaskComposerScrollID: String {
        "inlineTask.composerRow"
    }

    var body: some View {
        rootLifecycleView
    }

    private var rootPresentedView: some View {
        rootScaffold
            .background(theme.backgroundColor.ignoresSafeArea())
            .overlay {
                if usesFloatingExpandedTaskDateModal, let target = expandedTaskDateTarget {
                    expandedTaskDateModalOverlay(target: target)
                }
            }
            .sheet(isPresented: $showingQuickEntry) {
                QuickEntrySheet()
            }
            .overlay {
                if isRootSearchPresented {
                    ZStack(alignment: .top) {
                        Color.clear
                            .ignoresSafeArea()
                            .onTapGesture { dismissRootSearch() }

                        GeometryReader { geo in
                            QuickFindCard(
                                query: $universalSearchText,
                                store: quickFindStore,
                                maxHeight: geo.size.height * 0.55,
                                onDismiss: { dismissRootSearch() },
                                onSelectRecent: { item in
                                    switch item.destination {
                                    case .view(let raw):
                                        dismissRootSearch()
                                        let view = ViewIdentifier(rawValue: raw)
                                        guard container.selectedView != view else { return }
                                        applyFilter(view)
                                    case .task(let path):
                                        dismissRootSearch()
                                        DispatchQueue.main.async { openFullTaskEditor(path: path) }
                                    }
                                },
                                resultsContent: { query in
                                    AnyView(rootSearchResultsContent(query: query))
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 60)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: -12).combined(with: .opacity),
                            removal: .offset(y: -12).combined(with: .opacity)
                        )
                    )
                }
            }
            .sheet(isPresented: $showingInlineVoiceRamble) {
                VoiceRambleSheet(
                    fallbackDue: inlineTaskDraft.dueDate.map(localDate(from:)),
                    fallbackDueTime: nil,
                    fallbackPriority: nil,
                    fallbackFlagged: inlineTaskDraft.flagged,
                    fallbackTags: inlineTaskDraft.normalizedTags,
                    fallbackArea: inlineTaskDraft.area,
                    fallbackProject: inlineTaskDraft.project,
                    defaultView: currentBuiltInView,
                    onTasksCreated: {
                        showingInlineVoiceRamble = false
                        cancelInlineTaskComposer()
                    }
                )
            }
            .sheet(isPresented: $showingInlineTaskDateModal) {
                InlineTaskDateEditorSheet(
                    hasDate: inlineTaskHasDueDateBinding,
                    date: inlineTaskDueDateBinding,
                    hasTime: inlineTaskHasDueTimeBinding,
                    time: inlineTaskDueTimeBinding,
                    recurrence: inlineTaskRecurrenceBinding
                ) {
                    dismissInlineTaskDateEditor(animated: false)
                }
            }
            .sheet(item: $activeProjectSheetMode) { mode in
                NavigationStack {
                    createProjectSheet(mode: mode)
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
            .sheet(item: regularExpandedTaskDateTarget) { target in
                expandedTaskDateSheet(target: target)
            }
            .sheet(item: $expandedTaskTagsTarget) { target in
                expandedTaskTagsSheet(target: target)
            }
            .sheet(item: $expandedTaskMoveTarget) { target in
                expandedTaskMoveSheet(target: target)
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
    }

    private var rootAlertedView: some View {
        rootPresentedView
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
                            if expandedTaskPath == pendingDeletePath {
                                expandedTaskPath = nil
                            }
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
    }

    private var rootLifecycleView: some View {
        rootAlertedView
            .onChange(of: container.navigationTaskPath) { _, newPath in
                guard let newPath else { return }
                cancelInlineTaskComposer()
                expandedTaskPath = nil
                appendToActiveNavigationPath(newPath)
                container.clearPendingNavigationPath()
            }
            .onChange(of: container.shouldPresentQuickEntry) { _, shouldPresent in
                guard shouldPresent else { return }
                presentQuickEntryFromCurrentContext()
                container.clearQuickEntryRequest()
            }
            .onAppear {
                normalizeCompactTabSettingsIfNeeded()
                if horizontalSizeClass == .compact {
                    syncCompactSelectedTab()
                }
                refreshInboxRemindersIfVisible()
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
                expandedTaskPath = nil
                inlineComposerTransitionTask?.cancel()
                inlineComposerTransitionTask = nil
                completionAnimationTasks.values.forEach { $0.cancel() }
                completionAnimationTasks.removeAll()
            }
            .onChange(of: showingProjectSettingsSheet) { _, isPresented in
                guard !isPresented, let sourceProject = pendingProjectDuplicationSourceName else { return }
                pendingProjectDuplicationSourceName = nil
                prepareProjectSheetForDuplication(from: sourceProject)
            }
            .onChange(of: pomodoroEnabled) { _, isEnabled in
                normalizeCompactTabSettingsIfNeeded()
                guard !isEnabled, container.selectedView == .builtIn(.pomodoro) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    container.selectedView = horizontalSizeClass == .compact ? .browse : .builtIn(.inbox)
                }
            }
            .onChange(of: container.perspectives) { _, _ in
                normalizeCompactTabSettingsIfNeeded()
                if horizontalSizeClass == .compact {
                    syncCompactSelectedTab()
                }
            }
            .onChange(of: compactPrimaryTabRawValue) { _, _ in
                normalizeCompactTabSettingsIfNeeded()
                if horizontalSizeClass == .compact {
                    syncCompactSelectedTab()
                }
            }
            .onChange(of: compactSecondaryTabRawValue) { _, _ in
                normalizeCompactTabSettingsIfNeeded()
                if horizontalSizeClass == .compact {
                    syncCompactSelectedTab()
                }
            }
            .onChange(of: container.selectedView) { _, selectedView in
                dismissRootSearch()
                if selectedView != .builtIn(.inbox) {
                    resetInboxTriageMode()
                } else {
                    refreshInboxRemindersIfVisible()
                }
                if horizontalSizeClass == .compact {
                    syncCompactSelectedTab()
                }
                expandedTaskPath = nil
                cancelInlineTaskComposer()
            }
#if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refreshInboxRemindersIfVisible()
            }
#endif
            .onChange(of: compactSelectedTab) { _, newTab in
                guard horizontalSizeClass == .compact else { return }
                guard compactRootTab(for: container.selectedView) != newTab else { return }
                selectCompactTab(newTab)
            }
            .onChange(of: activeNavigationDepth) { _, count in
                if count > 0 {
                    expandedTaskPath = nil
                    cancelInlineTaskComposer()
                    dismissRootSearch()
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
        Group {
            if #available(iOS 18.0, macOS 15.0, *) {
                compactTabViewNative
            } else {
                compactTabViewLegacy
            }
        }
#if canImport(UIKit)
        .background(
            CompactTabBarImageConfigurator(
                choices: CompactRootTab.allCases.map(compactTabChoice(for:))
            )
        )
#endif
        .tint(theme.accentColor)
    }

    private var compactTabViewLegacy: some View {
        TabView(selection: $compactSelectedTab) {
            ForEach(CompactRootTab.allCases) { tab in
                compactTabScene(tab)
            }
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    private var compactTabViewNative: some View {
        TabView(selection: $compactSelectedTab) {
            compactTabItemsNative
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    @TabContentBuilder<CompactRootTab>
    private var compactTabItemsNative: some TabContent<CompactRootTab> {
        ForEach(CompactRootTab.allCases) { tab in
            let choice = compactTabChoice(for: tab)

            if choice.iconToken.isEmoji {
                Tab(value: tab) {
                    compactTabContent(for: tab)
                        .accessibilityIdentifier(choice.accessibilityIdentifier)
                } label: {
                    compactTabItemLabel(choice: choice)
                }
            } else {
                Tab(
                    choice.title,
                    systemImage: CompactTabChoiceCatalog.compactTabBarSymbolName(for: choice),
                    value: tab
                ) {
                    compactTabContent(for: tab)
                        .accessibilityIdentifier(choice.accessibilityIdentifier)
                }
            }
        }
    }

    private var compactPerspectiveViews: [ViewIdentifier] {
        container.perspectives.map { container.perspectiveViewIdentifier(for: $0.id) }
    }

    private var compactCustomViews: (primary: ViewIdentifier, secondary: ViewIdentifier) {
        CompactTabSettings.normalizedCustomViews(
            leadingRawValue: compactPrimaryTabRawValue,
            trailingRawValue: compactSecondaryTabRawValue,
            pomodoroEnabled: pomodoroEnabled,
            additionalViews: compactPerspectiveViews
        )
    }

    private var compactPrimaryView: ViewIdentifier {
        compactCustomViews.primary
    }

    private var compactSecondaryView: ViewIdentifier {
        compactCustomViews.secondary
    }

    private func compactTabChoice(for tab: CompactRootTab) -> CompactTabChoice {
        let view: ViewIdentifier = switch tab {
        case .inbox:
            .builtIn(.inbox)
        case .today:
            .builtIn(.today)
        case .customPrimary:
            compactPrimaryView
        case .areas:
            .browse
        case .customSecondary:
            compactSecondaryView
        }

        return CompactTabChoiceCatalog.choice(for: view, perspectives: container.perspectives)
    }

    private func compactTabScene(_ tab: CompactRootTab) -> AnyView {
        let choice = compactTabChoice(for: tab)
        return AnyView(
            compactTabContent(for: tab)
            .tabItem {
                compactTabItemLabel(choice: choice)
            }
            .tag(tab)
            .accessibilityIdentifier(choice.accessibilityIdentifier)
        )
    }

    private func compactTabContent(for tab: CompactRootTab) -> some View {
        detailPane(path: navigationPathBinding(for: tab)) {
            detailContent(for: tab)
        }
    }

    @ViewBuilder
    private func compactTabItemLabel(choice: CompactTabChoice) -> some View {
        if choice.iconToken.isEmoji {
            Label {
                Text(choice.title)
            } icon: {
                Text(choice.iconToken.storageValue)
            }
            .accessibilityLabel(choice.title)
        } else {
            Label(choice.title, systemImage: CompactTabChoiceCatalog.compactTabBarSymbolName(for: choice))
        }
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
        case .customPrimary:
            return $customPrimaryNavigationPath
        case .areas:
            return $areasNavigationPath
        case .customSecondary:
            return $customSecondaryNavigationPath
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
            .modifier(
                RootNavigationTitleModifier(
                    title: navigationTitle(),
                    useInlineDisplayMode: usesInContentHeroHeader
                )
            )
            .toolbar {
                detailToolbar
            }
            .safeAreaInset(edge: .bottom) {
                if shouldShowExpandedTaskBottomBar {
                    expandedTaskBottomBar
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if shouldReserveFloatingAddButtonSpace {
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
            .animation(.spring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.12), value: shouldShowExpandedTaskBottomBar)
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .appTrailingAction) {
            if shouldShowToolbarInlineTaskButton {
                Button {
                    triggerInlineTaskComposer()
                } label: {
                    Image(systemName: isCreatingTask ? "xmark" : "plus")
                        .font(.title3.weight(.regular))
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel(isCreatingTask ? "Close Task Entry" : "Add Task")
                .accessibilityIdentifier("root.inlineAddButton")
            }
        }

        ToolbarItem(placement: .appTrailingAction) {
            if horizontalSizeClass != .compact {
                NavigationLink {
                    SettingsView(quickFindStore: quickFindStore)
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
                navButton(view: .browse, label: "Browse", icon: "square.grid.2x2")
            }

            Section("Views") {
                builtInNavButton(
                    .inbox,
                    label: "Inbox",
                    icon: "tray",
                    isActive: container.selectedView == .builtIn(.inbox) && !inboxTriageMode
                )
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
                builtInNavButton(.anytime, label: "Anytime", icon: "list.bullet")
                builtInNavButton(.someday, label: "Someday", icon: "clock")
                builtInNavButton(.flagged, label: "Flagged", icon: "flag")
                if pomodoroEnabled {
                    builtInNavButton(.pomodoro, label: "Pomodoro", icon: "timer")
                }
            }

            Section("Workflows") {
                ForEach(RootWorkflowEntry.allCases) { workflow in
                    switch workflow {
                    case .inboxTriage:
                        workflowNavButton(
                            label: workflow.label,
                            icon: workflow.icon,
                            isActive: isInboxTriageActive,
                            accessibilityIdentifier: workflow.accessibilityIdentifier
                        ) {
                            toggleInboxTriageMode()
                        }
                    case .review:
                        builtInNavButton(
                            .review,
                            label: workflow.label,
                            icon: workflow.icon,
                            accessibilityIdentifier: workflow.accessibilityIdentifier
                        )
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
                                icon: container.projectIconSymbol(for: project),
                                isIndented: true,
                                tintHex: container.projectColorHex(for: project),
                                fallbackIcon: "folder"
                            )
                            .contextMenu {
                                projectContextMenu(for: project)
                            }
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
                    SettingsView(quickFindStore: quickFindStore)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("root.settingsButton")
            }
        }
    }

    private var mainContent: AnyView {
        if container.selectedView.isBrowse {
            return AnyView(
                browseContent()
                    .transition(rootScreenTransition)
            )
        }
        if container.selectedView == .builtIn(.upcoming) {
            return AnyView(
                UpcomingCalendarView(sections: container.upcomingAgendaSections()) { record in
                    taskRowItem(record)
                }
                .transition(rootScreenTransition)
            )
        }
        if container.selectedView == .builtIn(.review) {
            return AnyView(
                weeklyReviewContent()
                    .transition(rootScreenTransition)
            )
        }
        if container.selectedView == .builtIn(.pomodoro) {
            return AnyView(
                PomodoroTimerView(
                    header: currentMainHeroConfiguration.map { configuration in
                        AnyView(MainHeroHeader(
                            title: configuration.title,
                            symbolName: configuration.symbolName,
                            iconColor: configuration.iconColor
                        ))
                    }
                )
                .transition(rootScreenTransition)
            )
        }
        return AnyView(
            recordsMainContent(records: container.filteredRecords())
                .transition(rootScreenTransition)
        )
    }

    private func recordsMainContent(records: [TaskRecord]) -> AnyView {
        if container.selectedView == .builtIn(.inbox), inboxTriageMode {
            return AnyView(
                InboxTriageView(
                    records: records,
                    skippedPaths: $inboxTriageSkippedPaths,
                    pinnedPath: $inboxTriagePinnedPath,
                    onExit: { resetInboxTriageMode() },
                    onOpenDetail: { path in
                        appendToActiveNavigationPath(path)
                    }
                )
            )
        }
        if records.isEmpty, shouldRenderInlineTaskComposerInList {
            return AnyView(emptyInlineTaskComposerList)
        }
        if records.isEmpty {
            return emptyStateMainContent()
        }
        return AnyView(populatedRecordsMainContent(records: records))
    }

    private var emptyInlineTaskComposerList: some View {
        List {
            mainHeroListRow

            inlineTaskComposerListRow

            if container.selectedView == .builtIn(.inbox) {
                InboxRemindersImportPanel()
            }
            if container.selectedView == .builtIn(.today) {
                if container.isCalendarConnected {
                    todayCalendarCardListRow
                }
            }
        }
        .id("\(container.selectedView.rawValue)-inline-empty")
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.backgroundColor)
    }

    private func emptyStateMainContent() -> AnyView {
        if container.selectedView == .builtIn(.today) {
            return AnyView(todayEmptyStateContent)
        }
        if container.selectedView == .builtIn(.inbox) {
            return AnyView(inboxEmptyStateContent)
        }
        return AnyView(
            genericEmptyStateContent
        )
    }

    private var todayEmptyStateContent: some View {
        taskList(id: "\(container.selectedView.rawValue)-empty") {
            mainHeroListRow

            if container.isCalendarConnected {
                todayCalendarCardListRow
            }

            VStack(spacing: 12) {
                emptyTasksUnavailableView
                unparseableFilesSummary
            }
            .frame(maxWidth: .infinity)
            .padding(.top, container.isCalendarConnected ? 10 : 24)
            .padding(.bottom, 40)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var inboxEmptyStateContent: some View {
        taskList(id: "\(container.selectedView.rawValue)-empty") {
            mainHeroListRow
            InboxRemindersImportPanel()

            VStack(spacing: 12) {
                emptyTasksUnavailableView
                unparseableFilesSummary
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var genericEmptyStateContent: some View {
        taskList(id: "\(container.selectedView.rawValue)-empty") {
            mainHeroListRow

            VStack(spacing: 12) {
                emptyTasksUnavailableView
                unparseableFilesSummary
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var emptyTasksUnavailableView: some View {
        ContentUnavailableView(
            "No Tasks",
            systemImage: "checkmark.circle",
            description: Text("Nothing in \(titleForCurrentView()) right now.")
        )
    }

    @ViewBuilder
    private var unparseableFilesSummary: some View {
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

    private func populatedRecordsMainContent(records: [TaskRecord]) -> some View {
        taskList(id: container.selectedView.rawValue) {
            if container.selectedView == .builtIn(.today) {
                mainHeroListRow

                if isEditing {
                    if shouldRenderInlineTaskComposerInList {
                        inlineTaskComposerListRow
                    }
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
                        todayCalendarCardListRow
                    }

                    if shouldRenderInlineTaskComposerInList {
                        inlineTaskComposerListRow
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
                mainHeroListRow

                if container.selectedView == .builtIn(.inbox) {
                    InboxRemindersImportPanel()
                }
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
    }

    private var mainHeroListRow: some View {
        Group {
            if let configuration = currentMainHeroConfiguration {
                MainHeroHeader(
                    title: configuration.title,
                    symbolName: configuration.symbolName,
                    iconColor: configuration.iconColor
                )
            }
        }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, mainHeroBottomPadding)
#if os(iOS)
            .modifier(RootPullToSearchTopMarker())
#endif
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var mainHeroBottomPadding: CGFloat {
        if container.selectedView == .builtIn(.today), container.isCalendarConnected {
            return 4
        }
        return 12
    }

    private var rootScreenTransition: AnyTransition {
        .opacity
    }

    private var currentMainHeroConfiguration: MainViewHeroConfiguration? {
        switch container.selectedView {
        case .builtIn(.inbox):
            return MainViewHeroConfiguration(title: "Inbox", symbolName: "tray", iconColor: Color(red: 0.11, green: 0.60, blue: 0.98))
        case .builtIn(.today):
            return MainViewHeroConfiguration(title: "Today", symbolName: "star.fill", iconColor: Color(red: 0.89, green: 0.71, blue: 0.13))
        case .builtIn(.upcoming):
            return MainViewHeroConfiguration(title: "Upcoming", symbolName: "calendar", iconColor: Color(red: 1.0, green: 0.22, blue: 0.45))
        case .builtIn(.myTasks):
            return MainViewHeroConfiguration(title: "My Tasks", symbolName: "person", iconColor: theme.accentColor)
        case .builtIn(.delegated):
            return MainViewHeroConfiguration(title: "Delegated", symbolName: "person.2", iconColor: Color(red: 0.98, green: 0.61, blue: 0.22))
        case .builtIn(.logbook):
            return MainViewHeroConfiguration(title: "Logbook", symbolName: "checkmark.circle", iconColor: Color(red: 0.32, green: 0.79, blue: 0.53))
        case .builtIn(.review):
            return MainViewHeroConfiguration(title: "Review", symbolName: "checklist", iconColor: Color(red: 0.32, green: 0.77, blue: 0.83))
        case .builtIn(.anytime):
            return MainViewHeroConfiguration(title: "Anytime", symbolName: "list.bullet", iconColor: theme.accentColor)
        case .builtIn(.someday):
            return MainViewHeroConfiguration(title: "Someday", symbolName: "clock", iconColor: Color(red: 0.67, green: 0.57, blue: 0.98))
        case .builtIn(.flagged):
            return MainViewHeroConfiguration(title: "Flagged", symbolName: "flag.fill", iconColor: theme.flaggedColor)
        case .builtIn(.pomodoro):
            return MainViewHeroConfiguration(title: "Pomodoro", symbolName: "timer", iconColor: Color(red: 0.98, green: 0.42, blue: 0.31))
        case .area(let area):
            return MainViewHeroConfiguration(title: area, symbolName: "square.grid.2x2", iconColor: theme.accentColor)
        case .project(let project):
            return MainViewHeroConfiguration(
                title: project,
                symbolName: container.projectIconSymbol(for: project),
                iconColor: color(forHex: container.projectColorHex(for: project)) ?? theme.accentColor
            )
        case .tag(let tag):
            return MainViewHeroConfiguration(title: "#\(tag)", symbolName: "number", iconColor: theme.accentColor)
        case .custom(let id):
            if ViewIdentifier.custom(id).isBrowse {
                return MainViewHeroConfiguration(title: "Browse", symbolName: "square.grid.2x2", iconColor: theme.accentColor)
            }
            if let perspective = container.perspectiveDefinition(for: .custom(id)) {
                return MainViewHeroConfiguration(
                    title: perspective.name,
                    symbolName: perspective.icon,
                    iconColor: color(forHex: perspective.color) ?? theme.accentColor
                )
            }
            return MainViewHeroConfiguration(title: id, symbolName: "list.bullet", iconColor: theme.accentColor)
        }
    }

    private var todayCalendarCardListRow: some View {
        TodayCalendarCard(events: container.calendarTodayEvents)
            .padding(.horizontal, 24)
            .padding(.top, 2)
            .padding(.bottom, 14)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var inlineTaskComposerListRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TaskCheckbox(
                    isCompleted: false,
                    isDashed: false,
                    tint: theme.accentColor,
                    isInteractive: false,
                    onTap: {}
                )
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    inlineTaskExpandedTitleField
                    inlineTaskExpandedNotesField
                    inlineTaskComposerDetectedMetadata
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 14) {
                inlineTaskAccessoryBar

                if let expandedInlineTaskPanel {
                    inlineTaskExpandedPanel(expandedInlineTaskPanel)
                }
            }
            .padding(.leading, 34)
        }
        .padding(.leading, 16)
        .padding(.trailing, 17)
        .padding(.top, 17)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(inlineTaskComposerCardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.035 : 0.18),
                                    Color.clear,
                                    Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(inlineTaskComposerBorderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 28, y: 16)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.17 : 0.05), radius: 12, y: 5)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(inlineTaskComposerScrollID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inlineTask.row")
        .accessibilityValue("expanded")
        .transition(.asymmetric(
            insertion: .push(from: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var inlineTaskExpandedTitleField: some View {
        ZStack(alignment: .topLeading) {
            if inlineTaskDraft.title.isEmpty {
                Text("Task")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(theme.textTertiaryColor)
                    .padding(.top, 1)
            }

            TextField("", text: $inlineTaskDraft.title, axis: .vertical)
                .modifier(RootViewWordsAutocapitalization())
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(theme.textPrimaryColor)
                .focused($inlineTaskFocused)
                .lineLimit(1...3)
                .submitLabel(.done)
                .accessibilityIdentifier("inlineTask.titleField")
                .onChange(of: inlineTaskDraft.title) { _, newValue in
                    handleInlineTaskTitleChanged(newValue)
                }
                .onSubmit {
                    commitInlineTaskComposer()
                }
        }
    }

    private var inlineTaskExpandedNotesField: some View {
        ZStack(alignment: .topLeading) {
            if inlineTaskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Notes")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(inlineTaskComposerNotePlaceholderColor)
                    .padding(.top, 1)
            }

            TextField("", text: $inlineTaskDraft.description, axis: .vertical)
                .modifier(RootViewWordsAutocapitalization())
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(inlineTaskComposerNoteTextColor)
                .lineLimit(1...5)
                .accessibilityIdentifier("inlineTask.notesField")
        }
        .frame(minHeight: 86, alignment: .topLeading)
    }

    private var inlineTaskComposerCardGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.12, blue: 0.16),
                    Color(red: 0.08, green: 0.09, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                theme.surfaceColor.opacity(0.98),
                theme.backgroundColor.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var inlineTaskComposerBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : theme.textSecondaryColor.opacity(0.16)
    }

    private var inlineTaskComposerNoteTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.82) : theme.textSecondaryColor
    }

    private var inlineTaskComposerNotePlaceholderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.3) : theme.textSecondaryColor.opacity(0.7)
    }

    private var compactInlineTaskComposerOverlay: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        cancelInlineTaskComposer()
                    }

                compactInlineTaskComposerCard(
                    maxHeight: max(
                        220,
                        min(
                            geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom - 24,
                            520
                        )
                    )
                )
                .padding(.horizontal, 12)
                .padding(.bottom, max(10, geometry.safeAreaInsets.bottom + 4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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

    private func compactInlineTaskComposerCard(maxHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
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
                            .onChange(of: inlineTaskDraft.title) { _, newValue in
                                handleInlineTaskTitleChanged(newValue)
                            }
                            .onSubmit {
                                commitInlineTaskComposer()
                            }

                        Text("Notes")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(compactComposerSecondaryTextColor)
                    }

                    Spacer(minLength: 0)
                }

                inlineTaskComposerDetectedMetadata
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
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
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
        inlineTaskAccessoryBarLayout(
            dateActiveTint: theme.accentColor,
            activeTint: theme.accentColor,
            inactiveTint: inlineTaskAccessoryInactiveTint,
            flagTint: theme.flaggedColor
        )
    }

    private var inlineTaskAccessoryInactiveTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : theme.textSecondaryColor
    }

    private func inlineTaskAccessoryBarLayout(
        dateActiveTint: Color,
        activeTint: Color,
        inactiveTint: Color,
        flagTint: Color
    ) -> some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            inlineTaskDateAccessoryButton(activeTint: dateActiveTint, inactiveTint: inactiveTint)
            inlineTaskTagsAccessoryButton(activeTint: activeTint, inactiveTint: inactiveTint)
            inlineTaskProjectAccessoryMenu(activeTint: activeTint, inactiveTint: inactiveTint)
            inlineTaskFlagAccessoryButton(activeTint: flagTint, inactiveTint: inactiveTint)
        }
    }

    private func inlineTaskDateAccessoryButton(
        activeTint: Color,
        inactiveTint: Color
    ) -> some View {
        let isActive = inlineTaskDraft.dueDate != nil
        return Button {
            presentInlineTaskDateEditor()
        } label: {
            InlineTaskAccessoryIconLabel(
                systemImage: "calendar",
                tint: isActive ? activeTint : inactiveTint
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inlineTask.dateButton")
        .accessibilityLabel("Date")
        .accessibilityValue(inlineTaskDateLabel)
    }

    private func inlineTaskProjectAccessoryMenu(
        activeTint: Color,
        inactiveTint: Color
    ) -> some View {
        let isActive = inlineTaskDraft.project != nil || inlineTaskDraft.area != nil
        return Menu {
            inlineTaskProjectMenuContent
        } label: {
            InlineTaskAccessoryIconLabel(
                systemImage: "list.bullet",
                tint: isActive ? activeTint : inactiveTint
            )
        }
        .menuIndicator(.hidden)
        .accessibilityIdentifier("inlineTask.projectMenuButton")
        .accessibilityLabel("Project")
        .accessibilityValue(inlineTaskDestinationLabel)
    }

    private func inlineTaskTagsAccessoryButton(
        activeTint: Color,
        inactiveTint: Color
    ) -> some View {
        let isActive = !inlineTaskDraft.normalizedTags.isEmpty
        return Button {
            toggleInlineTaskPanel(.tags)
        } label: {
            InlineTaskAccessoryIconLabel(
                systemImage: isActive ? "tag.fill" : "tag",
                tint: isActive ? activeTint : inactiveTint
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inlineTask.tagsButton")
        .accessibilityLabel("Tags")
        .accessibilityValue(inlineTaskTagsLabel)
    }

    private func inlineTaskFlagAccessoryButton(
        activeTint: Color,
        inactiveTint: Color
    ) -> some View {
        let isActive = inlineTaskDraft.flagged
        return Button {
            inlineTaskDraft.flagged.toggle()
        } label: {
            InlineTaskAccessoryIconLabel(
                systemImage: isActive ? "flag.fill" : "flag",
                tint: isActive ? activeTint : inactiveTint
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inlineTask.flagButton")
        .accessibilityLabel("Flag")
        .accessibilityValue(isActive ? "On" : "Off")
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

    private var inlineComposerMetadataBackgroundColor: Color {
        horizontalSizeClass == .compact ? compactComposerBackgroundColor.opacity(0.98) : theme.surfaceColor
    }

    private var inlineComposerMetadataPrimaryTextColor: Color {
        horizontalSizeClass == .compact ? compactComposerPrimaryTextColor : theme.textPrimaryColor
    }

    private var inlineComposerMetadataSecondaryTextColor: Color {
        horizontalSizeClass == .compact ? compactComposerSecondaryTextColor : theme.textSecondaryColor
    }

    private var inlineComposerMetadataBorderColor: Color {
        horizontalSizeClass == .compact ? Color.white.opacity(0.08) : theme.textSecondaryColor.opacity(0.12)
    }

    private var compactInlineTaskAccessoryBar: some View {
        inlineTaskAccessoryBarLayout(
            dateActiveTint: compactInlineDueTint,
            activeTint: compactComposerIconActiveColor,
            inactiveTint: compactComposerIconColor,
            flagTint: compactComposerFlagTint
        )
    }

    @ViewBuilder
    private var inlineTaskComposerDetectedMetadata: some View {
        if inlineAutoDatePhrase != nil || inlineTaskComposerSuggestionContext != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let inlineAutoDatePhrase {
                    inlineTaskAutoDateChip(phrase: inlineAutoDatePhrase)
                }

                if let context = inlineTaskComposerSuggestionContext,
                   !context.suggestions.isEmpty {
                    inlineTaskSuggestionPanel(context)
                }
            }
        }
    }

    @ViewBuilder
    private func inlineTaskExpandedPanel(_ panel: InlineTaskPanel) -> some View {
        switch panel {
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
        let hasDueTime = inlineTaskDraft.hasDueTime
        let timeText = inlineTaskDraft.dueTime.formatted(date: .omitted, time: .shortened)
        let notificationTimePreference = NotificationTimePreference()
        if calendar.isDateInToday(dueDate) {
            if hasDueTime && notificationTimePreference.matches(inlineTaskDraft.dueTime, calendar: calendar) {
                return "Tonight"
            }
            if hasDueTime {
                return "Today \(timeText)"
            }
            return "Today"
        }
        if calendar.isDateInTomorrow(dueDate) {
            if hasDueTime {
                return "Tomorrow \(timeText)"
            }
            return "Tomorrow"
        }
        if hasDueTime {
            return "\(dueDate.formatted(date: .abbreviated, time: .omitted)) \(timeText)"
        }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var inlineTaskHasDueDateBinding: Binding<Bool> {
        Binding(
            get: { inlineTaskDraft.dueDate != nil },
            set: { hasDate in
                if hasDate {
                    if inlineTaskDraft.dueDate == nil {
                        setInlineTaskDueDate(Calendar.current.startOfDay(for: Date()))
                    }
                } else {
                    setInlineTaskDueDate(nil)
                }
            }
        )
    }

    private var inlineTaskDueDateBinding: Binding<Date> {
        Binding(
            get: { inlineTaskDraft.dueDate ?? Calendar.current.startOfDay(for: Date()) },
            set: { date in
                setInlineTaskDueDate(Calendar.current.startOfDay(for: date))
            }
        )
    }

    private var inlineTaskHasDueTimeBinding: Binding<Bool> {
        Binding(
            get: { inlineTaskDraft.dueDate != nil && inlineTaskDraft.hasDueTime },
            set: { hasDueTime in
                inlineTaskDraft.hasDueTime = hasDueTime && inlineTaskDraft.dueDate != nil
                inlineAutoDatePhrase = nil
            }
        )
    }

    private var inlineTaskDueTimeBinding: Binding<Date> {
        Binding(
            get: { inlineTaskDraft.dueTime },
            set: { time in
                inlineTaskDraft.dueTime = time
                inlineAutoDatePhrase = nil
            }
        )
    }

    private var inlineTaskRecurrenceBinding: Binding<String> {
        Binding(
            get: { inlineTaskDraft.recurrence },
            set: { recurrence in
                inlineTaskDraft.recurrence = recurrence
                inlineAutoDatePhrase = nil
            }
        )
    }

    @ViewBuilder
    private var inlineTaskProjectMenuContent: some View {
        Button {
            expandedInlineTaskPanel = nil
            inlineTaskDraft.project = nil
            inlineTaskDraft.area = nil
        } label: {
            inlineTaskProjectMenuRow(
                title: "Inbox",
                systemImage: "tray",
                isSelected: inlineTaskDraft.project == nil && inlineTaskDraft.area == nil
            )
        }

        let areas = inlineTaskAreaMenuOptions
        if !areas.isEmpty {
            Section("Areas") {
                ForEach(areas, id: \.self) { area in
                    Button {
                        expandedInlineTaskPanel = nil
                        inlineTaskDraft.area = area
                        inlineTaskDraft.project = nil
                    } label: {
                        inlineTaskProjectMenuRow(
                            title: area,
                            systemImage: "square.grid.2x2",
                            isSelected: inlineTaskDraft.area == area && inlineTaskDraft.project == nil
                        )
                    }
                }
            }
        }

        let projects = container.allProjects()
        if !projects.isEmpty {
            Section("Projects") {
                ForEach(projects, id: \.self) { project in
                    Button {
                        expandedInlineTaskPanel = nil
                        inlineTaskDraft.project = project
                        inlineTaskDraft.area = nil
                    } label: {
                        inlineTaskProjectMenuRow(
                            title: project,
                            systemImage: container.projectIconSymbol(for: project),
                            isSelected: inlineTaskDraft.project == project
                        )
                    }
                    .accessibilityIdentifier("inlineTask.projectMenuItem.\(project)")
                }
            }
        } else {
            Button("No projects yet") {}
                .disabled(true)
        }
    }

    private var inlineTaskAreaMenuOptions: [String] {
        let availableAreas = container.availableAreas()
        guard let currentArea = defaultInlineTaskDraft(for: container.selectedView).area,
              !availableAreas.contains(currentArea) else {
            return availableAreas
        }
        return [currentArea] + availableAreas
    }

    private func inlineTaskProjectMenuRow(
        title: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
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

    private var canCommitInlineTask: Bool {
        !inlineTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inlineTaskComposerSuggestionContext: InlineTaskComposerSuggestionContext? {
        let trimmedTitle = inlineTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmedTitle.split(whereSeparator: { $0.isWhitespace }).last.map(String.init),
              token.count >= 1 else {
            return nil
        }

        if token.hasPrefix("@") {
            let query = String(token.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            let suggestions: [String]
            if query.isEmpty {
                suggestions = container.recentProjects(limit: 6, excluding: inlineTaskDraft.project)
            } else {
                suggestions = Array(container.allProjects().filter { project in
                    matchesQuery(project, query: query)
                }.prefix(6))
            }

            guard !suggestions.isEmpty else { return nil }
            return InlineTaskComposerSuggestionContext(kind: .project, query: query, suggestions: suggestions)
        }

        if token.hasPrefix("#") {
            let query = String(token.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = Set(inlineTaskDraft.normalizedTags)
            let filtered = container.availableTags().filter { tag in
                !existing.contains(tag) && (query.isEmpty || matchesQuery(tag, query: query))
            }
            let suggestions = Array(filtered.prefix(8))
            guard !suggestions.isEmpty else { return nil }
            return InlineTaskComposerSuggestionContext(kind: .tag, query: query, suggestions: suggestions)
        }

        return nil
    }

    private func toggleInlineTaskPanel(_ panel: InlineTaskPanel) {
        showingInlineTaskDateModal = false
        if expandedInlineTaskPanel == panel {
            expandedInlineTaskPanel = nil
        } else {
            expandedInlineTaskPanel = panel
        }
    }

    private func presentInlineTaskDateEditor() {
        inlineTaskFocused = false
        expandedInlineTaskPanel = nil
        showingInlineTaskDateModal = true
    }

    private func dismissInlineTaskDateEditor(animated _: Bool) {
        showingInlineTaskDateModal = false
    }

    private func applyInlineDueDate(_ date: Date?, autoPhrase: String? = nil) {
        inlineTaskDraft.dueDate = date
        inlineTaskDraft.hasDueTime = false
        inlineTaskDraft.dueTime = NotificationTimePreference().date(on: date ?? Date())
        inlineAutoDatePhrase = autoPhrase
    }

    private func setInlineTaskDueDate(_ date: Date?) {
        let hadDueDate = inlineTaskDraft.dueDate != nil
        inlineTaskDraft.dueDate = date
        if let date {
            if !inlineTaskDraft.hasDueTime && !hadDueDate {
                inlineTaskDraft.dueTime = NotificationTimePreference().date(on: date)
            }
        } else {
            inlineTaskDraft.hasDueTime = false
            inlineTaskDraft.dueTime = NotificationTimePreference().date(on: Date())
        }
        inlineAutoDatePhrase = nil
    }

    private func appendInlineTag(_ tag: String) {
        let currentTags = inlineTaskDraft.normalizedTags
        guard !currentTags.contains(tag) else { return }
        let updatedTags = currentTags + [tag]
        inlineTaskDraft.tagsText = updatedTags.map { "#\($0)" }.joined(separator: " ")
    }

    private func inlineTaskAutoDateChip(phrase: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
            Text(phrase)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(inlineComposerMetadataPrimaryTextColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(horizontalSizeClass == .compact ? Color.white.opacity(0.12) : theme.backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(inlineComposerMetadataBorderColor, lineWidth: 1)
        )
    }

    private func inlineTaskSuggestionPanel(_ context: InlineTaskComposerSuggestionContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: context.kind.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(context.kind.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if !context.query.isEmpty {
                    Text(context.query)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(inlineComposerMetadataSecondaryTextColor)
                }
            }
            .foregroundStyle(inlineComposerMetadataPrimaryTextColor)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(context.suggestions, id: \.self) { suggestion in
                        Button {
                            applyInlineTaskSuggestion(kind: context.kind, suggestion: suggestion)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: context.kind.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(inlineComposerMetadataSecondaryTextColor)
                                Text(context.kind == .tag ? "#\(suggestion)" : suggestion)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(inlineComposerMetadataPrimaryTextColor)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(inlineComposerMetadataBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(inlineComposerMetadataBorderColor, lineWidth: 1)
        )
    }

    private func applyInlineTaskSuggestion(
        kind: InlineTaskComposerSuggestionKind,
        suggestion: String
    ) {
        inlineTaskDraft.title = titleWithoutTrailingSuggestionToken(from: inlineTaskDraft.title)
        switch kind {
        case .project:
            inlineTaskDraft.project = suggestion
            inlineTaskDraft.area = nil
        case .tag:
            appendInlineTag(suggestion)
        }
    }

    private var browseSectionScreen: some View {
        List {
            mainHeroListRow

            Section {
                Button {
                    presentRootSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("root.browse.searchButton")
            }

            Section {
                NavigationLink {
                    SettingsView(quickFindStore: quickFindStore)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("root.settingsButton")
            }

            let areas = container.availableAreas()
            let projects = container.allProjects()
            let perspectives = container.perspectives

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
                            .accessibilityIdentifier("project.edit.\(project)")
                        }
                        .contextMenu {
                            projectContextMenu(for: project)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        prepareProjectSheetForCreate()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create Project")
                }
            }

            ForEach(RootNavigationCatalog.browseDiscoverySectionOrder) { section in
                switch section {
                case .perspectives:
                    browsePerspectivesSection(perspectives: perspectives)
                case .workflows:
                    browseWorkflowsSection(areas: areas)
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
        .modifier(
            RootPullToSearchGestureModifier(
                isEnabled: shouldAllowPullToSearchGesture,
                onTrigger: {
                    Task { @MainActor in
                        presentRootSearch()
                    }
                }
            )
        )
    }

    @ViewBuilder
    private func browseContent() -> some View {
        browseSectionScreen
    }

    @ViewBuilder
    private func browsePerspectivesSection(perspectives: [PerspectiveDefinition]) -> some View {
        Section {
            ForEach(RootNavigationCatalog.browseBuiltInEntries(pomodoroEnabled: pomodoroEnabled)) { entry in
                if case .builtIn(let builtInView) = entry.view {
                    builtInBrowseFilterButton(
                        builtInView,
                        label: entry.label,
                        icon: entry.icon
                    )
                }
            }

            if !perspectives.isEmpty {
                ForEach(perspectives) { perspective in
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
    }

    @ViewBuilder
    private func browseWorkflowsSection(areas: [String]) -> some View {
        Section("Workflows") {
            ForEach(RootWorkflowEntry.allCases) { workflow in
                switch workflow {
                case .inboxTriage:
                    workflowBrowseButton(
                        label: workflow.label,
                        icon: workflow.icon,
                        isActive: isInboxTriageActive,
                        accessibilityIdentifier: workflow.accessibilityIdentifier
                    ) {
                        toggleInboxTriageMode()
                    }
                case .review:
                    builtInBrowseFilterButton(
                        .review,
                        label: workflow.label,
                        icon: workflow.icon,
                        accessibilityIdentifier: workflow.accessibilityIdentifier
                    )
                }
            }
            if !areas.isEmpty {
                ForEach(areas, id: \.self) { area in
                    browseFilterButton(view: .area(area), label: area, icon: "square.grid.2x2")
                }
            }
        }
    }

    @ViewBuilder
    private func rootSearchResultsContent(query: String) -> some View {
        let tasks = container.searchRecords(query: query)
        let tags = container.availableTags().filter { matchesQuery($0, query: query) }
        let areas = container.availableAreas().filter { matchesQuery($0, query: query) }
        let projects = container.allProjects().filter { matchesQuery($0, query: query) }
        let perspectives = container.perspectives.filter { matchesQuery($0.name, query: query) }
        let builtInViews = RootNavigationCatalog
            .searchableBuiltInEntries(pomodoroEnabled: pomodoroEnabled)
            .filter { matchesQuery($0.label, query: query) }
        let matchingWorkflows = RootWorkflowEntry.allCases.filter { matchesQuery($0.label, query: query) }

        if tasks.isEmpty
            && tags.isEmpty
            && areas.isEmpty
            && projects.isEmpty
            && builtInViews.isEmpty
            && perspectives.isEmpty
            && matchingWorkflows.isEmpty
        {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No matches for \"\(query)\"")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            if !builtInViews.isEmpty {
                Section("Sections") {
                    ForEach(builtInViews, id: \.view.rawValue) { item in
                        searchDestinationButton(
                            view: item.view,
                            label: item.label,
                            icon: item.icon
                        )
                    }
                }
            }

            if !perspectives.isEmpty {
                Section("Perspectives") {
                    ForEach(perspectives) { perspective in
                        searchDestinationButton(
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
                        searchDestinationButton(
                            view: .tag(tag),
                            label: "#\(tag)",
                            icon: "number"
                        )
                    }
                }
            }

            if !areas.isEmpty || !matchingWorkflows.isEmpty {
                Section("Workflows") {
                    ForEach(matchingWorkflows) { workflow in
                        switch workflow {
                        case .inboxTriage:
                            searchActionButton(
                                label: workflow.label,
                                icon: workflow.icon,
                                accessibilityIdentifier: workflow.searchAccessibilityIdentifier
                            ) {
                                toggleInboxTriageMode()
                            }
                        case .review:
                            if let view = workflow.destinationView {
                                searchDestinationButton(
                                    view: view,
                                    label: workflow.label,
                                    icon: workflow.icon
                                )
                            }
                        }
                    }
                    ForEach(areas, id: \.self) { area in
                        searchDestinationButton(
                            view: .area(area),
                            label: area,
                            icon: "square.grid.2x2"
                        )
                    }
                }
            }

            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects, id: \.self) { project in
                        searchDestinationButton(
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
                        searchTaskResultButton(record)
                    }
                }
            }
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

    private func projectSheetTitle(for mode: ProjectSheetMode) -> String {
        switch mode {
        case .create:
            return "New Project"
        case .duplicate:
            return "Duplicate Project"
        }
    }

    private func projectSheetConfirmationTitle(for mode: ProjectSheetMode) -> String {
        switch mode {
        case .create:
            return "Create"
        case .duplicate:
            return "Duplicate"
        }
    }

    private func projectSheetConfirmationAccessibilityIdentifier(for mode: ProjectSheetMode) -> String {
        switch mode {
        case .create:
            return "projectSheet.createButton"
        case .duplicate:
            return "projectSheet.duplicateButton"
        }
    }

    private func canSubmitProjectSheet(for mode: ProjectSheetMode) -> Bool {
        let trimmedName = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        guard case .duplicate(let sourceProject) = mode else { return true }

        let comparisonOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard trimmedName.compare(sourceProject, options: comparisonOptions) != .orderedSame else {
            return false
        }

        return !container.allProjects().contains(where: {
            $0.compare(trimmedName, options: comparisonOptions) == .orderedSame
                && $0.compare(sourceProject, options: comparisonOptions) != .orderedSame
        })
    }

    private func createProjectSheet(mode: ProjectSheetMode) -> some View {
        Form {
            Section("Name") {
                TextField("Project name", text: $newProjectName)
                    .modifier(RootViewWordsAutocapitalization())
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("projectSheet.nameField")
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
        .navigationTitle(projectSheetTitle(for: mode))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    resetProjectSheetState()
                    activeProjectSheetMode = nil
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(projectSheetConfirmationTitle(for: mode)) {
                    guard canSubmitProjectSheet(for: mode) else { return }
                    createProjectFromSheet(mode: mode)
                }
                .accessibilityIdentifier(projectSheetConfirmationAccessibilityIdentifier(for: mode))
            }
        }
    }

    private var projectSettingsSheet: some View {
        Form {
            Section("Name") {
                TextField("Project name", text: $editingProjectName)
                    .modifier(RootViewWordsAutocapitalization())
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("projectSettings.nameField")
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

            Section {
                Button("Duplicate Project") {
                    pendingProjectDuplicationSourceName = editingProjectOriginalName
                    showingProjectSettingsSheet = false
                }
                .accessibilityIdentifier("projectSettings.duplicateButton")
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

    @ViewBuilder
    private func projectContextMenu(for project: String) -> some View {
        Button("Edit") {
            openProjectSettings(for: project)
        }
        Button("Duplicate") {
            prepareProjectSheetForDuplication(from: project)
        }
    }

    private func browseFilterButton(
        view: ViewIdentifier,
        label: String,
        icon: String,
        tintHex: String? = nil,
        fallbackIcon: String? = nil,
        isActive: Bool? = nil,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        let tint = color(forHex: tintHex)
        let resolvedFallback = fallbackIcon ?? (icon.isEmpty ? "questionmark.circle" : icon)
        let isSelected = isActive ?? (container.selectedView == view)
        return Button {
            applyFilter(view)
        } label: {
            HStack(spacing: 10) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: resolvedFallback,
                    pointSize: 17,
                    weight: .semibold,
                    tint: isSelected ? (tint ?? theme.accentColor) : (tint ?? theme.textSecondaryColor)
                )
                .frame(width: 20, height: 20)
                Text(label)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "root.browse.\(view.rawValue)")
    }

    private func builtInBrowseFilterButton(
        _ builtInView: BuiltInView,
        label: String,
        icon: String,
        isActive: Bool? = nil,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        browseFilterButton(
            view: .builtIn(builtInView),
            label: label,
            icon: icon,
            isActive: isActive,
            accessibilityIdentifier: accessibilityIdentifier
        )
            .contextMenu {
                if builtInView != .review {
                    Button("View Rules") {
                        builtInRulesTarget = BuiltInRulesTarget(view: builtInView)
                    }
                }
            }
    }

    private func workflowBrowseButton(
        label: String,
        icon: String,
        isActive: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: icon,
                    pointSize: 17,
                    weight: .semibold,
                    tint: isActive ? theme.accentColor : theme.textSecondaryColor
                )
                .frame(width: 20, height: 20)
                Text(label)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func searchDestinationButton(
        view: ViewIdentifier,
        label: String,
        icon: String,
        tintHex: String? = nil,
        fallbackIcon: String? = nil
    ) -> some View {
        let tint = color(forHex: tintHex) ?? theme.accentColor
        let resolvedFallback = fallbackIcon ?? (icon.isEmpty ? "questionmark.circle" : icon)
        return Button {
            openSearchResult(view, label: label, icon: icon, tintHex: tintHex)
        } label: {
            HStack(spacing: 10) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: resolvedFallback,
                    pointSize: 17,
                    weight: .semibold,
                    tint: tint
                )
                .frame(width: 20, height: 20)

                Text(label)
                    .foregroundStyle(theme.textPrimaryColor)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)
            }
        }
        .buttonStyle(.plain)
    }

    private func searchActionButton(
        label: String,
        icon: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: icon,
                    pointSize: 17,
                    weight: .semibold,
                    tint: theme.accentColor
                )
                .frame(width: 20, height: 20)

                Text(label)
                    .foregroundStyle(theme.textPrimaryColor)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func searchTaskResultButton(_ record: TaskRecord) -> some View {
        let frontmatter = record.document.frontmatter
        let locationLabel = frontmatter.project ?? frontmatter.area ?? "Inbox"
        let tint = frontmatter.flagged ? theme.flaggedColor : theme.accentColor

        return Button {
            openSearchTaskResult(path: record.identity.path, label: frontmatter.title)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: frontmatter.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(frontmatter.status == .done ? Color.green : tint)

                    Text(frontmatter.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.textPrimaryColor)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Label(locationLabel, systemImage: frontmatter.project == nil ? "tray" : "folder")
                    if let due = frontmatter.due, let dueDate = dateFromLocalDate(due) {
                        Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let firstTag = frontmatter.tags.first {
                        Text("#\(firstTag)")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.textSecondaryColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("root.search.taskResult.\(frontmatter.title)")
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
        case let candidate where candidate == compactPrimaryView:
            return .customPrimary
        case let candidate where candidate == compactSecondaryView:
            return .customSecondary
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
        case .customPrimary:
            return compactPrimaryView
        case .areas:
            return compactRootTab(for: currentView) == .areas ? currentView : .browse
        case .customSecondary:
            return compactSecondaryView
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
        horizontalSizeClass == .compact && shouldShowInlineTaskButton && !isCreatingTask && expandedTaskPath == nil
    }

    private var shouldReserveFloatingAddButtonSpace: Bool {
        shouldShowFloatingAddButton
    }

    private var shouldRenderInlineTaskComposer: Bool {
        isCreatingTask && shouldShowInlineTaskButton
    }

    private var shouldRenderInlineTaskComposerInList: Bool {
        shouldRenderInlineTaskComposer
    }

    private var shouldShowCompactInlineTaskComposer: Bool {
        shouldRenderInlineTaskComposer && horizontalSizeClass == .compact
    }

    private var shouldShowExpandedTaskBottomBar: Bool {
        horizontalSizeClass == .compact && isAtActiveNavigationRoot && expandedTaskPath != nil
    }

    private var shouldAllowPullToSearchGesture: Bool {
        isAtActiveNavigationRoot && !inboxTriageMode && !isRootSearchPresented
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

    @ViewBuilder
    private var expandedTaskBottomBar: some View {
        if let path = expandedTaskPath {
            HStack(spacing: 0) {
                ExpandedTaskBottomBarPrimaryButton(
                    title: "Move",
                    systemImage: "arrow.right",
                    tint: Color.white.opacity(0.94),
                    action: {
                        showExpandedTaskMoveEditor(path: path)
                    }
                )

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 30)
                    .padding(.vertical, 10)

                ExpandedTaskBottomBarIconButton(
                    systemImage: "trash",
                    tint: Color.white.opacity(0.88),
                    action: {
                        expandedTaskPath = nil
                        pendingDeletePath = path
                    }
                )

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 30)
                    .padding(.vertical, 10)

                ExpandedTaskBottomBarIconButton(
                    systemImage: "ellipsis",
                    tint: Color.white.opacity(0.88),
                    action: {
                        openFullTaskEditor(path: path)
                    }
                )
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.31, green: 0.37, blue: 0.48).opacity(0.96),
                                Color(red: 0.24, green: 0.29, blue: 0.39).opacity(0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 22, y: 10)
            .accessibilityIdentifier("expandedTask.bottomBar")
        }
    }

    private func taskList<ID: Hashable, Content: View>(
        id: ID,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollViewReader { proxy in
            List {
                content()
            }
            .id(id)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.backgroundColor)
            .modifier(
                RootPullToSearchGestureModifier(
                    isEnabled: shouldAllowPullToSearchGesture,
                    onTrigger: {
                        Task { @MainActor in
                            presentRootSearch()
                        }
                    }
                )
            )
            .onChange(of: expandedTaskPath) { _, path in
                expandedTaskScrollTask?.cancel()
                guard let path else { return }
                scheduleExpandedTaskScroll(to: path, proxy: proxy)
            }
            .onChange(of: isCreatingTask) { _, isCreating in
                inlineComposerScrollTask?.cancel()
                guard isCreating, shouldRenderInlineTaskComposerInList else { return }
                scheduleInlineTaskComposerScroll(proxy: proxy)
            }
        }
    }

    private func scheduleExpandedTaskScroll(to path: String, proxy: ScrollViewProxy) {
        expandedTaskScrollTask?.cancel()

        let anchor: UnitPoint = horizontalSizeClass == .compact ? .center : .top
        expandedTaskScrollTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: horizontalSizeClass == .compact ? 90_000_000 : 60_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled, expandedTaskPath == path else { return }
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo(path, anchor: anchor)
            }

            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled, expandedTaskPath == path else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(path, anchor: anchor)
            }
        }
    }

    private func scheduleInlineTaskComposerScroll(proxy: ScrollViewProxy) {
        inlineComposerScrollTask?.cancel()

        inlineComposerScrollTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled, isCreatingTask, shouldRenderInlineTaskComposerInList else { return }
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo(inlineTaskComposerScrollID, anchor: .top)
            }
            inlineComposerScrollTask = nil
        }
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
            cancelInlineTaskComposer()
            return
        }

        inlineTaskDraft = defaultInlineTaskDraft(for: container.selectedView)
        expandedInlineTaskPanel = nil
        showingInlineTaskDateModal = false
        inlineAutoDatePhrase = nil
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
        showingInlineVoiceRamble = false
        showingInlineTaskDateModal = false
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
                inlineAutoDatePhrase = nil
                inlineComposerTransitionTask = nil
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                isCreatingTask = false
            }
            inlineTaskDraft = InlineTaskDraft()
            inlineAutoDatePhrase = nil
        }
        inlineTaskFocused = false
        expandedInlineTaskPanel = nil
    }

    private func handleInlineTaskTitleChanged(_ value: String) {
        guard !inlineTaskTitleMutationInFlight else { return }
        let parser = NaturalLanguageTaskParser(availableProjects: container.allProjects())
        guard let parsed = parser.parse(value),
              let due = parsed.due,
              parsed.dueTime == nil,
              let phrase = parsed.recognizedDatePhrase else {
            return
        }

        let currentTitle = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTitle.isEmpty else { return }

        inlineTaskTitleMutationInFlight = true
        if let parsedProject = parsed.project {
            inlineTaskDraft.project = parsedProject
            inlineTaskDraft.area = nil
        }
        if !parsed.tags.isEmpty {
            for tag in parsed.tags {
                appendInlineTag(tag)
            }
        }
        let loweredPhrase = phrase.lowercased()
        let chipPhrase = loweredPhrase.hasPrefix("due ")
            || loweredPhrase.hasPrefix("by ")
            || loweredPhrase.hasPrefix("on ")
            || loweredPhrase.hasPrefix("at ")
            ? loweredPhrase
            : "due \(loweredPhrase)"
        applyInlineDueDate(dateFromLocalDate(due), autoPhrase: chipPhrase)
        inlineTaskTitleMutationInFlight = false
    }

    private func commitInlineTaskComposer() {
        let trimmedTitle = inlineTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            cancelInlineTaskComposer()
            return
        }

        let defaultDraft = defaultInlineTaskDraft(for: container.selectedView)
        let explicitDue: LocalDate?
        let inlineDueTimeMatchesDefault = inlineTaskDraft.hasDueTime == defaultDraft.hasDueTime && (
            !inlineTaskDraft.hasDueTime ||
                Calendar.current.compare(inlineTaskDraft.dueTime, to: defaultDraft.dueTime, toGranularity: .minute) == .orderedSame
        )
        if inlineTaskDraft.dueDate == defaultDraft.dueDate, inlineDueTimeMatchesDefault {
            explicitDue = nil
        } else {
            explicitDue = inlineTaskDraft.dueDate.map(localDate(from:))
        }
        let explicitDueTime: LocalTime?
        if inlineTaskDraft.dueDate != nil, inlineTaskDraft.hasDueTime, explicitDue != nil {
            let components = Calendar.current.dateComponents([.hour, .minute], from: inlineTaskDraft.dueTime)
            explicitDueTime = (try? LocalTime(
                hour: components.hour ?? 0,
                minute: components.minute ?? 0
            )) ?? .midnight
        } else {
            explicitDueTime = nil
        }
        let defaultView: BuiltInView? = {
            if case .builtIn(let builtInView) = container.selectedView {
                return builtInView
            }
            return nil
        }()
        let explicitDescription: String? = {
            let trimmed = inlineTaskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let explicitRecurrence: String? = {
            let trimmed = inlineTaskDraft.recurrence.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        let created = container.createTask(
            fromQuickEntryText: trimmedTitle,
            explicitDue: explicitDue,
            explicitDueTime: explicitDueTime,
            explicitRecurrence: explicitRecurrence,
            priority: nil,
            flagged: inlineTaskDraft.flagged,
            tags: inlineTaskDraft.normalizedTags,
            area: inlineTaskDraft.area,
            project: inlineTaskDraft.project,
            description: explicitDescription,
            defaultView: defaultView
        )
        if !created {
            container.createTask(
                title: trimmedTitle,
                naturalDate: nil,
                tags: inlineTaskDraft.normalizedTags,
                explicitDue: explicitDue,
                explicitDueTime: explicitDueTime,
                explicitRecurrence: explicitRecurrence,
                priorityOverride: nil,
                flagged: inlineTaskDraft.flagged,
                area: inlineTaskDraft.area,
                project: inlineTaskDraft.project,
                description: explicitDescription,
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
        case .tag(let tag):
            draft.tagsText = "#\(tag)"
        default:
            break
        }
        if let inferredProject = container.inferredTaskProject(for: view) {
            draft.project = inferredProject
        }
        return draft
    }

    private var currentBuiltInView: BuiltInView? {
        if case .builtIn(let builtInView) = container.selectedView {
            return builtInView
        }
        return nil
    }

    private func titleWithoutTrailingSuggestionToken(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(whereSeparator: { $0.isWhitespace }).last.map(String.init),
              token.hasPrefix("@") || token.hasPrefix("#") else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.endIndex, offsetBy: -token.count)
        return trimmed[..<endIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dateFromLocalDate(_ localDate: LocalDate) -> Date? {
        var components = DateComponents()
        components.year = localDate.year
        components.month = localDate.month
        components.day = localDate.day
        return Calendar.current.date(from: components)
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
        if usesInContentHeroHeader {
            return ""
        }
        return titleForCurrentView()
    }

    private var usesInContentHeroHeader: Bool {
        true
    }

    private func matchesQuery(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func resetProjectSheetState() {
        newProjectName = ""
        newProjectColorHex = "1E88E5"
        newProjectIconSymbol = "folder"
    }

    private func prepareProjectSheetForCreate() {
        resetProjectSheetState()
        activeProjectSheetMode = .create
    }

    private func prepareProjectSheetForDuplication(from project: String) {
        newProjectName = container.suggestedDuplicateProjectName(for: project)
        newProjectColorHex = container.projectColorHex(for: project) ?? "1E88E5"
        newProjectIconSymbol = container.projectIconSymbol(for: project)
        activeProjectSheetMode = .duplicate(sourceProject: project)
    }

    private func createProjectFromSheet(mode: ProjectSheetMode) {
        let trimmedProjectName = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectName.isEmpty else { return }

        let created: String?
        if case .duplicate(let sourceProject) = mode {
            created = container.duplicateProject(
                originalName: sourceProject,
                newName: trimmedProjectName,
                colorHex: newProjectColorHex,
                iconSymbol: newProjectIconSymbol
            )
        } else {
            created = container.createProject(
                name: trimmedProjectName,
                colorHex: newProjectColorHex,
                iconSymbol: newProjectIconSymbol
            )
        }

        guard let created else { return }

        resetProjectSheetState()
        activeProjectSheetMode = nil
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
        if isRootSearchPresented {
            dismissRootSearch()
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            container.selectedView = view
        }
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }

    @MainActor
    private func presentRootSearch(resetQuery: Bool = true) {
        if resetQuery { universalSearchText = "" }
        withAnimation(.easeOut(duration: 0.22)) {
            isRootSearchPresented = true
        }
    }

    private func dismissRootSearch() {
        universalSearchText = ""
        withAnimation(.easeIn(duration: 0.18)) {
            isRootSearchPresented = false
        }
    }

    private func openSearchResult(
        _ view: ViewIdentifier,
        label: String,
        icon: String,
        tintHex: String? = nil
    ) {
        let item = RecentItem(label: label, icon: icon, tintHex: tintHex, destination: .view(view.rawValue))
        quickFindStore.record(item: item)
        dismissRootSearch()
        guard container.selectedView != view else { return }
        applyFilter(view)
    }

    private func openSearchTaskResult(path: String, label: String) {
        let item = RecentItem(label: label, icon: "doc.text", tintHex: nil, destination: .task(path))
        quickFindStore.record(item: item)
        dismissRootSearch()
        DispatchQueue.main.async {
            openFullTaskEditor(path: path)
        }
    }

    private var isInboxTriageActive: Bool {
        container.selectedView == .builtIn(.inbox) && inboxTriageMode
    }

    private func toggleInboxTriageMode() {
        dismissRootSearch()
        expandedTaskPath = nil
        pendingExpandedTaskPath = nil
        cancelInlineTaskComposer()

        if isInboxTriageActive {
            withAnimation(.easeInOut(duration: 0.18)) {
                resetInboxTriageMode()
            }
            return
        }

        if container.selectedView != .builtIn(.inbox) {
            applyFilter(.builtIn(.inbox))
        }

        inboxTriageSkippedPaths.removeAll()
        inboxTriagePinnedPath = container.filteredRecords().first?.identity.path
        withAnimation(.easeInOut(duration: 0.18)) {
            inboxTriageMode = true
        }
    }

    private func resetInboxTriageMode() {
        inboxTriageMode = false
        inboxTriageSkippedPaths.removeAll()
        inboxTriagePinnedPath = nil
    }

    private var usesFloatingExpandedTaskDateModal: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private var regularExpandedTaskDateTarget: Binding<ExpandedTaskDateTarget?> {
        Binding(
            get: { usesFloatingExpandedTaskDateModal ? nil : expandedTaskDateTarget },
            set: { expandedTaskDateTarget = $0 }
        )
    }

    @ViewBuilder
    private func expandedTaskDateModalOverlay(target: ExpandedTaskDateTarget) -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("expandedTaskDate.backdrop")
                    .onTapGesture {
                        dismissExpandedTaskDateEditor(animated: true)
                    }

                expandedTaskDateContent(target: target)
                    .frame(
                        width: min(proxy.size.width - 28, 430),
                        height: min(proxy.size.height - 48, 560)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(theme.backgroundColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(theme.textSecondaryColor.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: Color.black.opacity(0.32), radius: 30, y: 18)
                    .padding(.horizontal, 14)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityIdentifier("expandedTaskDate.modal")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(.smooth(duration: 0.22), value: expandedTaskDateTarget != nil)
    }

    private func dismissExpandedTaskDateEditor(animated: Bool) {
        if animated && usesFloatingExpandedTaskDateModal {
            withAnimation(.smooth(duration: 0.18)) {
                expandedTaskDateTarget = nil
            }
        } else {
            expandedTaskDateTarget = nil
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

    private func expandedTaskDateContent(target: ExpandedTaskDateTarget) -> some View {
        ExpandedTaskDateEditorSheet(initialDate: target.initialDate, initialRecurrence: target.initialRecurrence) { date, recurrence in
            _ = container.setDueAndRecurrence(path: target.path, date: date, recurrence: recurrence)
        } onDismiss: {
            dismissExpandedTaskDateEditor(animated: true)
        }
    }

    private func expandedTaskDateSheet(target: ExpandedTaskDateTarget) -> some View {
        let sheet = expandedTaskDateContent(target: target)

#if os(iOS)
        return sheet
            .presentationDetents([.fraction(0.64), .large])
            .presentationDragIndicator(.visible)
#else
        return sheet
#endif
    }

    private func expandedTaskTagsSheet(target: ExpandedTaskTagsTarget) -> some View {
        ExpandedTaskTagsEditorSheet(
            initialTags: target.initialTags,
            suggestedTags: container.availableTags()
        ) { tags in
            _ = container.setTags(path: target.path, tags: tags)
            expandedTaskTagsTarget = nil
        } onCancel: {
            expandedTaskTagsTarget = nil
        }
    }

    private func expandedTaskMoveSheet(target: ExpandedTaskMoveTarget) -> some View {
        let groupedAreas = container.projectsByArea()
        let groupedProjects = Set(groupedAreas.flatMap(\.projects))
        let ungroupedProjects = container.allProjects().filter { !groupedProjects.contains($0) }
        let currentFrontmatter = container.record(for: target.path)?.document.frontmatter

        return ExpandedTaskMoveEditorSheet(
            currentArea: currentFrontmatter?.area,
            currentProject: currentFrontmatter?.project,
            groupedAreas: groupedAreas,
            ungroupedProjects: ungroupedProjects
        ) { area, project in
            _ = container.moveTask(path: target.path, area: area, project: project)
            expandedTaskMoveTarget = nil
        } onCancel: {
            expandedTaskMoveTarget = nil
        }
    }

    private func completeWithAnimation(path: String) {
        guard !pathsCompleting.contains(path),
              !pathsSlidingOut.contains(path),
              completionAnimationTasks[path] == nil else { return }

        if expandedTaskPath == path {
            withAnimation(.easeInOut(duration: 0.18)) {
                expandedTaskPath = nil
            }
        }

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

    private var expandedTaskOpenAnimation: Animation {
        .smooth(duration: 0.26)
    }

    private var expandedTaskCloseAnimation: Animation {
        .smooth(duration: 0.18)
    }

    private func toggleExpandedTask(path: String) {
        guard !isEditing else { return }
        cancelInlineTaskComposer()

        if expandedTaskPath == path {
            pendingExpandedTaskPath = nil
            withAnimation(expandedTaskCloseAnimation) {
                expandedTaskPath = nil
            }
            return
        }

        guard expandedTaskPath != nil else {
            pendingExpandedTaskPath = path
            withAnimation(expandedTaskOpenAnimation) {
                expandedTaskPath = path
            }
            return
        }

        pendingExpandedTaskPath = path
        withAnimation(expandedTaskCloseAnimation) {
            expandedTaskPath = nil
        } completion: {
            guard pendingExpandedTaskPath == path else { return }
            withAnimation(expandedTaskOpenAnimation) {
                expandedTaskPath = path
            }
        }
    }

    private func showExpandedTaskDateEditor(for record: TaskRecord) {
        let target = ExpandedTaskDateTarget(
            path: record.identity.path,
            initialDate: dateValue(for: record.document.frontmatter.due),
            initialRecurrence: record.document.frontmatter.recurrence
        )

        if usesFloatingExpandedTaskDateModal {
            withAnimation(.smooth(duration: 0.22)) {
                expandedTaskDateTarget = target
            }
        } else {
            expandedTaskDateTarget = target
        }
    }

    private func showExpandedTaskTagsEditor(for record: TaskRecord) {
        expandedTaskTagsTarget = ExpandedTaskTagsTarget(
            path: record.identity.path,
            initialTags: record.document.frontmatter.tags
        )
    }

    private func showExpandedTaskMoveEditor(path: String) {
        expandedTaskMoveTarget = ExpandedTaskMoveTarget(path: path)
    }

    private func openFullTaskEditor(path: String) {
        pendingExpandedTaskPath = nil
        expandedTaskPath = nil
        appendToActiveNavigationPath(path)
    }

    private func saveExpandedTaskTextEdits(path: String, title: String, notes: String) {
        guard var editState = container.makeEditState(path: path) else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard editState.title != trimmedTitle || editState.subtitle != trimmedNotes else { return }

        editState.title = trimmedTitle
        editState.subtitle = trimmedNotes
        _ = container.updateTask(path: path, editState: editState)
    }

    private func taskRowItem(_ record: TaskRecord) -> some View {
        let path = record.identity.path
        let isDone = record.document.frontmatter.status == .done
        let quickProjects = container.recentProjects(limit: 3, excluding: record.document.frontmatter.project)
        let isCompleting = pathsCompleting.contains(path)
        let isSlidingOut = pathsSlidingOut.contains(path)
        return ExpandedTaskRow(
            record: record,
            isExpanded: expandedTaskPath == path,
            showsInlineFooter: horizontalSizeClass != .compact,
            isCompleting: isCompleting || isSlidingOut,
            onExpand: { toggleExpandedTask(path: path) },
            onComplete: { completeWithAnimation(path: path) },
            onSaveTextEdits: { title, notes in
                saveExpandedTaskTextEdits(path: path, title: title, notes: notes)
            },
            onCalendar: {
                showExpandedTaskDateEditor(for: record)
            },
            onTags: {
                showExpandedTaskTagsEditor(for: record)
            },
            onMore: {
                openFullTaskEditor(path: path)
            },
            onMove: {
                showExpandedTaskMoveEditor(path: path)
            },
            onDelete: {
                pendingExpandedTaskPath = nil
                expandedTaskPath = nil
                pendingDeletePath = path
            }
        )
        .id(path)
        .accessibilityIdentifier("taskRow.\(record.document.frontmatter.title)")
        .accessibilityValue(expandedTaskPath == path ? "expanded" : "collapsed")
        .accessibilityHint("Tap to expand. Swipe right for quick actions. Swipe left to complete. Long press for more options.")
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
        fallbackIcon: String? = nil,
        isActive: Bool? = nil,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        let tint = color(forHex: tintHex)
        let resolvedFallback = fallbackIcon ?? (icon.isEmpty ? "questionmark.circle" : icon)
        let isSelected = isActive ?? (container.selectedView == view)
        return Button {
            applyFilter(view)
        } label: {
            HStack(spacing: 10) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: resolvedFallback,
                    pointSize: 17,
                    weight: .semibold,
                    tint: isSelected ? (tint ?? theme.accentColor) : (tint ?? theme.textSecondaryColor)
                )
                .frame(width: 20, height: 20)
                Text(label)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentColor)
                }
            }
            .padding(.leading, isIndented ? 20 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "root.sidebar.\(view.rawValue)")
    }

    private func builtInNavButton(
        _ builtInView: BuiltInView,
        label: String,
        icon: String,
        isActive: Bool? = nil,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        navButton(
            view: .builtIn(builtInView),
            label: label,
            icon: icon,
            isActive: isActive,
            accessibilityIdentifier: accessibilityIdentifier
        )
            .contextMenu {
                if builtInView != .review {
                    Button("View Rules") {
                        builtInRulesTarget = BuiltInRulesTarget(view: builtInView)
                    }
                }
            }
    }

    private func workflowNavButton(
        label: String,
        icon: String,
        isActive: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: icon,
                    pointSize: 17,
                    weight: .semibold,
                    tint: isActive ? theme.accentColor : theme.textSecondaryColor
                )
                .frame(width: 20, height: 20)
                Text(label)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
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
            return view.displayTitle
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

    private func normalizeCompactTabSettingsIfNeeded() {
        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: compactPrimaryTabRawValue,
            trailingRawValue: compactSecondaryTabRawValue,
            pomodoroEnabled: pomodoroEnabled,
            additionalViews: compactPerspectiveViews
        )

        if compactPrimaryTabRawValue != normalized.primary.rawValue {
            compactPrimaryTabRawValue = normalized.primary.rawValue
        }
        if compactSecondaryTabRawValue != normalized.secondary.rawValue {
            compactSecondaryTabRawValue = normalized.secondary.rawValue
        }
    }
    private func refreshInboxRemindersIfVisible(forceListRefresh: Bool = false) {
        guard container.selectedView == .builtIn(.inbox) else { return }

        Task {
            if forceListRefresh {
                await container.refreshReminderLists()
            } else {
                await container.refreshReminderListsIfNeeded()
            }
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
            List {
                mainHeroListRow

                ContentUnavailableView(
                    "Review Is Clear",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing is stale, overdue, deferred into someday, or missing a next action.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 40)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .id(container.selectedView.rawValue)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.backgroundColor)
            .modifier(
                RootPullToSearchGestureModifier(
                    isEnabled: shouldAllowPullToSearchGesture,
                    onTrigger: {
                        Task { @MainActor in
                            presentRootSearch()
                        }
                    }
                )
            )
        } else {
            List {
                mainHeroListRow

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
            .modifier(
                RootPullToSearchGestureModifier(
                    isEnabled: shouldAllowPullToSearchGesture,
                    onTrigger: {
                        Task { @MainActor in
                            presentRootSearch()
                        }
                    }
                )
            )
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

private struct ExpandedTaskRow: View {
    private struct MetadataSegment {
        let text: String
        let color: Color
    }

    private enum Field: Hashable {
        case title
        case notes
    }

    let record: TaskRecord
    let isExpanded: Bool
    let showsInlineFooter: Bool
    let isCompleting: Bool
    let onExpand: () -> Void
    let onComplete: () -> Void
    let onSaveTextEdits: (String, String) -> Void
    let onCalendar: () -> Void
    let onTags: () -> Void
    let onMore: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var theme: ThemeManager
    @FocusState private var focusedField: Field?
    @State private var titleDraft: String
    @State private var notesDraft: String

    init(
        record: TaskRecord,
        isExpanded: Bool,
        showsInlineFooter: Bool,
        isCompleting: Bool,
        onExpand: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        onSaveTextEdits: @escaping (String, String) -> Void,
        onCalendar: @escaping () -> Void,
        onTags: @escaping () -> Void,
        onMore: @escaping () -> Void,
        onMove: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.record = record
        self.isExpanded = isExpanded
        self.showsInlineFooter = showsInlineFooter
        self.isCompleting = isCompleting
        self.onExpand = onExpand
        self.onComplete = onComplete
        self.onSaveTextEdits = onSaveTextEdits
        self.onCalendar = onCalendar
        self.onTags = onTags
        self.onMore = onMore
        self.onMove = onMove
        self.onDelete = onDelete
        _titleDraft = State(initialValue: record.document.frontmatter.title)
        _notesDraft = State(initialValue: record.document.frontmatter.description ?? "")
    }

    private var completionAccessibilityIdentifier: String {
        "taskRow.complete.\(record.document.frontmatter.title)"
    }

    var body: some View {
        let frontmatter = record.document.frontmatter

        VStack(alignment: .leading, spacing: isExpanded ? 17 : 0) {
            HStack(alignment: .top, spacing: 12) {
                TaskCheckbox(
                    isCompleted: isCompleting || frontmatter.status == .done || frontmatter.status == .cancelled,
                    isDashed: frontmatter.status == .inProgress && !isCompleting,
                    tint: checkboxTint(for: frontmatter),
                    accessibilityIdentifier: completionAccessibilityIdentifier,
                    onTap: onComplete
                )
                .padding(.top, isExpanded ? 4 : 2)

                VStack(alignment: .leading, spacing: isExpanded ? 8 : 3) {
                    if isExpanded {
                        expandedTextContent()
                    } else {
                        collapsedTextContent(frontmatter: frontmatter)
                    }
                }

                Spacer(minLength: 0)

                if !isExpanded, frontmatter.flagged {
                    Image(systemName: "flag.fill")
                        .font(.footnote)
                        .foregroundStyle(theme.flaggedColor)
                        .padding(.top, 2)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    expandedActionRow(frontmatter: frontmatter)
                        .padding(.leading, 34)

                    if showsInlineFooter {
                        Rectangle()
                            .fill(expandedDividerColor)
                            .frame(height: 1)
                            .padding(.leading, 34)
                            .padding(.trailing, 2)

                        expandedFooter
                            .padding(.leading, 34)
                    }
                }
                .transition(expandedSupplementaryTransition)
            }
        }
        .padding(.leading, isExpanded ? 16 : 20)
        .padding(.trailing, isExpanded ? 17 : 16)
        .padding(.top, isExpanded ? 17 : 13)
        .padding(.bottom, isExpanded ? 16 : 13)
        .background(expandedBackground)
        .overlay(expandedBorder)
        .shadow(color: isExpanded ? Color.black.opacity(colorScheme == .dark ? 0.3 : 0.12) : .clear, radius: 28, y: 16)
        .shadow(color: isExpanded ? Color.black.opacity(colorScheme == .dark ? 0.17 : 0.05) : .clear, radius: 12, y: 5)
        .padding(.horizontal, isExpanded ? 10 : 0)
        .padding(.vertical, isExpanded ? 7 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .zIndex(isExpanded ? 1 : 0)
        .onTapGesture {
            if !isExpanded {
                onExpand()
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                syncDraftsFromRecord()
            } else {
                focusedField = nil
                saveTextEdits(force: true)
            }
        }
        .onChange(of: focusedField) { _, field in
            if field == nil {
                saveTextEdits()
            }
        }
        .onChange(of: record.document.frontmatter.title) { _, _ in
            guard focusedField == nil else { return }
            syncDraftsFromRecord()
        }
        .onChange(of: record.document.frontmatter.description ?? "") { _, _ in
            guard focusedField == nil else { return }
            syncDraftsFromRecord()
        }
        .onDisappear {
            focusedField = nil
            saveTextEdits(force: true)
        }
        .animation(.smooth(duration: 0.26), value: isExpanded)
    }

    private func collapsedTextContent(frontmatter: TaskFrontmatterV1) -> some View {
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
    }

    private func expandedTextContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if titleDraft.isEmpty {
                    Text("Task")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(theme.textTertiaryColor)
                        .padding(.top, 1)
                }

                TextField("", text: $titleDraft, axis: .vertical)
                    .modifier(RootViewWordsAutocapitalization())
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(theme.textPrimaryColor)
                    .focused($focusedField, equals: .title)
                    .lineLimit(1...3)
                    .submitLabel(.done)
            }

            ZStack(alignment: .topLeading) {
                if notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Notes")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(expandedNotePlaceholderColor)
                        .padding(.top, 1)
                }

                TextField("", text: $notesDraft, axis: .vertical)
                    .modifier(RootViewWordsAutocapitalization())
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(expandedNoteTextColor)
                    .focused($focusedField, equals: .notes)
                    .lineLimit(1...5)
            }
            .frame(minHeight: 86, alignment: .topLeading)
        }
    }

    private func expandedActionRow(frontmatter: TaskFrontmatterV1) -> some View {
        HStack(spacing: 18) {
            if let dueLabel = dueDisplayText(for: frontmatter) {
                ExpandedTaskInlineChipButton(
                    title: dueLabel,
                    systemImage: "calendar",
                    tint: dueActionTint(for: frontmatter),
                    accessibilityLabel: "Edit due date",
                    action: presentCalendarEditor
                )

                Spacer(minLength: 0)

                ExpandedTaskInlineIconButton(
                    icon: "tag",
                    tint: frontmatter.tags.isEmpty ? theme.textSecondaryColor : theme.accentColor,
                    accessibilityLabel: "Edit tags",
                    action: presentTagsEditor
                )
            } else {
                Spacer(minLength: 0)

                ExpandedTaskInlineIconButton(
                    icon: "calendar",
                    tint: theme.textSecondaryColor,
                    accessibilityLabel: "Choose due date",
                    action: presentCalendarEditor
                )

                ExpandedTaskInlineIconButton(
                    icon: "tag",
                    tint: frontmatter.tags.isEmpty ? theme.textSecondaryColor : theme.accentColor,
                    accessibilityLabel: "Edit tags",
                    action: presentTagsEditor
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 10)
        .padding(.trailing, 6)
        .accessibilityIdentifier("expandedTask.actions.\(frontmatter.title)")
    }

    private var expandedFooter: some View {
        HStack(spacing: 0) {
            ExpandedTaskFooterButton(
                title: "Move",
                systemImage: "arrow.right",
                tint: expandedFooterPrimaryTextColor,
                action: presentMoveEditor
            )

            Rectangle()
                .fill(expandedFooterDividerColor)
                .frame(width: 1, height: 22)
                .padding(.vertical, 6)

            ExpandedTaskFooterButton(
                title: "Delete",
                systemImage: "trash",
                tint: expandedFooterPrimaryTextColor,
                action: handleDelete
            )

            Rectangle()
                .fill(expandedFooterDividerColor)
                .frame(width: 1, height: 22)
                .padding(.vertical, 6)

            ExpandedTaskFooterButton(
                title: "More",
                systemImage: "ellipsis",
                tint: expandedFooterPrimaryTextColor,
                action: openMoreDetails
            )
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(expandedFooterBarGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(expandedFooterBorderColor, lineWidth: 1)
        )
    }

    private var expandedBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(isExpanded ? expandedCardGradient : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
            .overlay {
                if isExpanded {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.035 : 0.18),
                                    Color.clear,
                                    Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
    }

    private var expandedBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(isExpanded ? expandedBorderColor : .clear, lineWidth: 1)
    }

    private var expandedCardGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.12, blue: 0.16),
                    Color(red: 0.08, green: 0.09, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                theme.surfaceColor.opacity(0.98),
                theme.backgroundColor.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var expandedBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : theme.textSecondaryColor.opacity(0.16)
    }

    private var expandedDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : theme.textSecondaryColor.opacity(0.09)
    }

    private var expandedSupplementaryTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 6).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func performExpandedAction(_ action: @escaping () -> Void) {
        guard focusedField != nil else {
            action()
            return
        }

        focusedField = nil
        DispatchQueue.main.async {
            action()
        }
    }

    private func presentCalendarEditor() {
        performExpandedAction(onCalendar)
    }

    private func presentTagsEditor() {
        performExpandedAction(onTags)
    }

    private func presentMoveEditor() {
        performExpandedAction(onMove)
    }

    private func openMoreDetails() {
        performExpandedAction(onMore)
    }

    private func handleDelete() {
        performExpandedAction(onDelete)
    }

    private var expandedNoteTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.82) : theme.textSecondaryColor
    }

    private var expandedNotePlaceholderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.3) : theme.textSecondaryColor.opacity(0.7)
    }

    private var expandedFooterPrimaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : theme.textPrimaryColor
    }

    private var expandedFooterBarGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.055),
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                theme.surfaceColor.opacity(0.92),
                theme.backgroundColor.opacity(0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var expandedFooterBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : theme.textSecondaryColor.opacity(0.12)
    }

    private var expandedFooterDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : theme.textSecondaryColor.opacity(0.12)
    }

    private func syncDraftsFromRecord() {
        titleDraft = record.document.frontmatter.title
        notesDraft = record.document.frontmatter.description ?? ""
    }

    private func saveTextEdits(force: Bool = false) {
        guard force || isExpanded else { return }
        onSaveTextEdits(titleDraft, notesDraft)
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

    private func dueActionTint(for frontmatter: TaskFrontmatterV1) -> Color {
        isOverdue(frontmatter) ? theme.overdueColor : theme.accentColor
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

    private func localTime(from date: Date) -> LocalTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (try? LocalTime(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )) ?? .midnight
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

private struct ExpandedTaskInlineIconButton: View {
    let icon: String
    let tint: Color
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ExpandedTaskInlineChipButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ExpandedTaskFooterButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(tint)
        }
        .buttonStyle(ExpandedTaskFooterButtonStyle(pressedFill: pressedFill))
    }

    private var pressedFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}

private struct ExpandedTaskBottomBarPrimaryButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .frame(height: 58)
            .foregroundStyle(tint)
        }
        .buttonStyle(ExpandedTaskFooterButtonStyle(pressedFill: pressedFill))
    }

    private var pressedFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}

private struct ExpandedTaskBottomBarIconButton: View {
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 60, height: 58)
                .foregroundStyle(tint)
        }
        .buttonStyle(ExpandedTaskFooterButtonStyle(pressedFill: pressedFill))
    }

    private var pressedFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}

private struct ExpandedTaskFooterButtonStyle: ButtonStyle {
    let pressedFill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(pressedFill.opacity(configuration.isPressed ? 1 : 0.001))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct InlineTaskDateEditorSheet: View {
    @EnvironmentObject private var theme: ThemeManager

    let hasDate: Binding<Bool>
    let date: Binding<Date>
    let hasTime: Binding<Bool>
    let time: Binding<Date>
    let recurrence: Binding<String>
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                DateChooserView(
                    context: .due,
                    timeMode: .optional,
                    hasDate: hasDate,
                    date: date,
                    hasTime: hasTime,
                    time: time,
                    recurrence: recurrence
                )
                .padding(16)
            }
            .background(theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Due")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                        .accessibilityIdentifier("inlineTaskDate.closeButton")
                }
            }
        }
        .accessibilityIdentifier("inlineTaskDate.modal")
    }
}

private struct ExpandedTaskDateEditorSheet: View {
    @EnvironmentObject private var theme: ThemeManager
    @State private var hasDate: Bool
    @State private var selectedDate: Date
    @State private var recurrence: String
    @State private var lastCommittedState: PersistedExpandedTaskDateState

    let onPersist: (Date?, String?) -> Void
    let onDismiss: () -> Void

    init(
        initialDate: Date?,
        initialRecurrence: String?,
        onPersist: @escaping (Date?, String?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let normalizedRecurrence: String? = {
            let trimmed = initialRecurrence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }()
        _hasDate = State(initialValue: initialDate != nil)
        _selectedDate = State(initialValue: initialDate ?? Date())
        _recurrence = State(initialValue: normalizedRecurrence ?? "")
        _lastCommittedState = State(initialValue: PersistedExpandedTaskDateState(date: initialDate, recurrence: normalizedRecurrence))
        self.onPersist = onPersist
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DateChooserView(
                    context: .due,
                    timeMode: .hidden,
                    hasDate: $hasDate,
                    date: $selectedDate,
                    hasTime: .constant(false),
                    time: .constant(selectedDate),
                    recurrence: $recurrence
                )
                .padding(16)
            }
            .background(theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Due")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                        .accessibilityIdentifier("expandedTaskDate.closeButton")
                }
            }
        }
        .onChange(of: effectiveState, initial: false) { _, newValue in
            guard newValue != lastCommittedState else { return }
            lastCommittedState = newValue
            onPersist(newValue.date, newValue.recurrence)
        }
    }

    private var effectiveState: PersistedExpandedTaskDateState {
        let normalizedRecurrence: String? = {
            let trimmed = recurrence.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        return PersistedExpandedTaskDateState(
            date: hasDate ? selectedDate : nil,
            recurrence: normalizedRecurrence
        )
    }
}

private struct ExpandedTaskTagsEditorSheet: View {
    let suggestedTags: [String]
    let onSave: ([String]) -> Void
    let onCancel: () -> Void

    @State private var tagsText: String
    @EnvironmentObject private var theme: ThemeManager

    init(
        initialTags: [String],
        suggestedTags: [String],
        onSave: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.suggestedTags = suggestedTags
        self.onSave = onSave
        self.onCancel = onCancel
        _tagsText = State(initialValue: initialTags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("work, finance, errands", text: $tagsText)
                        .modifier(RootViewNeverAutocapitalization())
#if os(iOS)
                        .autocorrectionDisabled(true)
#endif

                    Text("Use commas or spaces. #prefix is optional.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondaryColor)
                }

                if !remainingSuggestedTags.isEmpty {
                    Section("Suggestions") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(remainingSuggestedTags, id: \.self) { tag in
                                Button {
                                    appendTag(tag)
                                } label: {
                                    Text("#\(tag)")
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(theme.surfaceColor)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(parsedTags)
                    }
                }
            }
        }
    }

    private var parsedTags: [String] {
        let delimiters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        var seen = Set<String>()
        return tagsText
            .split(whereSeparator: { element in
                element.unicodeScalars.contains { delimiters.contains($0) }
            })
            .compactMap { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
                let normalized = stripped.lowercased()
                guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
                seen.insert(normalized)
                return normalized
            }
    }

    private var remainingSuggestedTags: [String] {
        let selected = Set(parsedTags)
        return suggestedTags.filter { !selected.contains($0.lowercased()) }
    }

    private func appendTag(_ tag: String) {
        var tags = parsedTags
        guard !tags.contains(tag.lowercased()) else { return }
        tags.append(tag.lowercased())
        tagsText = tags.joined(separator: ", ")
    }
}

private struct ExpandedTaskMoveEditorSheet: View {
    let currentArea: String?
    let currentProject: String?
    let groupedAreas: [(area: String, projects: [String])]
    let ungroupedProjects: [String]
    let onMove: (String?, String?) -> Void
    let onCancel: () -> Void
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onMove(nil, nil)
                    } label: {
                        moveRowLabel("Inbox", systemImage: "tray", isSelected: currentArea == nil && currentProject == nil)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(groupedAreas, id: \.area) { group in
                    Section(group.area) {
                        Button {
                            onMove(group.area, nil)
                        } label: {
                            moveRowLabel("Area Only", systemImage: "square.grid.2x2", isSelected: currentArea == group.area && currentProject == nil)
                        }
                        .buttonStyle(.plain)

                        ForEach(group.projects, id: \.self) { project in
                            Button {
                                onMove(group.area, project)
                            } label: {
                                moveRowLabel(project, systemImage: "folder", isSelected: currentArea == group.area && currentProject == project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !ungroupedProjects.isEmpty {
                    Section("No Area") {
                        ForEach(ungroupedProjects, id: \.self) { project in
                            Button {
                                onMove(nil, project)
                            } label: {
                                moveRowLabel(project, systemImage: "folder", isSelected: currentArea == nil && currentProject == project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Move")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func moveRowLabel(_ title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? theme.accentColor : theme.textSecondaryColor)

            Text(title)
                .foregroundStyle(theme.textPrimaryColor)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.accentColor)
            }
        }
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

private struct InlineTaskAccessoryIconLabel: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .padding(4)
            .contentShape(Rectangle())
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
