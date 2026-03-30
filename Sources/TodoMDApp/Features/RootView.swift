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

enum CompactRootTab: String, Hashable, CaseIterable, Identifiable {
    case inbox
    case today
    case areas
    case customPrimary
    case customSecondary

    var id: String { rawValue }
}

struct CompactTabSelectionPolicy {
    let primaryView: ViewIdentifier
    let secondaryView: ViewIdentifier

    func tab(for view: ViewIdentifier) -> CompactRootTab {
        switch view {
        case .builtIn(.inbox):
            return .inbox
        case .builtIn(.today):
            return .today
        case let candidate where candidate == primaryView:
            return .customPrimary
        case let candidate where candidate == secondaryView:
            return .customSecondary
        default:
            return .areas
        }
    }

    func rootView(for tab: CompactRootTab, currentView: ViewIdentifier) -> ViewIdentifier {
        switch tab {
        case .inbox:
            return .builtIn(.inbox)
        case .today:
            return .builtIn(.today)
        case .customPrimary:
            return primaryView
        case .areas:
            return self.tab(for: currentView) == .areas ? currentView : .browse
        case .customSecondary:
            return secondaryView
        }
    }

    func reselectionTarget(for tab: CompactRootTab, currentView: ViewIdentifier) -> ViewIdentifier? {
        guard tab == .areas, self.tab(for: currentView) == .areas, currentView != .browse else {
            return nil
        }

        return .browse
    }
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
    let onTabReselection: (CompactRootTab) -> Void

    final class TabButtonTapHandler: NSObject {
        weak var owner: ProbeView?
        let index: Int

        init(owner: ProbeView, index: Int) {
            self.owner = owner
            self.index = index
        }

        @MainActor
        @objc
        func handleTap() {
            owner?.handleTabBarTap(at: index)
        }
    }

    final class ProbeView: UIView {
        var choices: [CompactTabChoice] = []
        var onTabReselection: ((CompactRootTab) -> Void)?
        private var pendingApplyWorkItem: DispatchWorkItem?
        private var observedTabButtons: [UIControl] = []
        private var tabButtonHandlers: [TabButtonTapHandler] = []

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

            installTabBarTapHandlers(on: tabBar)

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

        func handleTabBarTap(at index: Int) {
            guard let tabBar = findTabBar(in: window),
                  let selectedItem = tabBar.selectedItem,
                  let selectedIndex = tabBar.items?.firstIndex(of: selectedItem),
                  selectedIndex == index,
                  CompactRootTab.allCases.indices.contains(index) else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.onTabReselection?(CompactRootTab.allCases[index])
            }
        }

        private func installTabBarTapHandlers(on tabBar: UITabBar) {
            for (button, handler) in zip(observedTabButtons, tabButtonHandlers) {
                button.removeTarget(handler, action: #selector(TabButtonTapHandler.handleTap), for: .touchUpInside)
            }

            let buttons = tabBar.subviews
                .compactMap { $0 as? UIControl }
                .sorted { $0.frame.minX < $1.frame.minX }

            observedTabButtons = Array(buttons.prefix(choices.count))
            tabButtonHandlers = observedTabButtons.enumerated().map { index, button in
                let handler = TabButtonTapHandler(owner: self, index: index)
                button.addTarget(handler, action: #selector(TabButtonTapHandler.handleTap), for: .touchUpInside)
                return handler
            }
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
        probeView.onTabReselection = onTabReselection
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

struct SectionHeaderView: View {
    let title: String
    let count: Int?
    let systemImage: String?
    @EnvironmentObject private var theme: ThemeManager

    init(_ title: String, count: Int? = nil, systemImage: String? = nil) {
        self.title = title
        self.count = count
        self.systemImage = systemImage
    }

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondaryColor)
            }
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

private enum RootDismissibleSurfaceID {
    static let inlineTaskComposer = "inlineTaskComposer"

    static func expandedTask(_ path: String) -> String {
        "expandedTask:\(path)"
    }
}

#if os(iOS)
private enum RootPullToSearchCoordinateSpace {
    static let name = "rootPullToSearchScrollArea"
}

private struct RootListContentMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct RootListContentBoundaryReporter: ViewModifier {
    let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func body(content: Content) -> some View {
        if isEnabled {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RootListContentMaxYPreferenceKey.self,
                        value: proxy.frame(in: .named(RootPullToSearchCoordinateSpace.name)).maxY
                    )
                }
            }
        } else {
            content
        }
    }
}

private struct RootDismissibleSurfaceFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct RootDismissibleSurfaceFrameReporter: ViewModifier {
    let id: String
    let isEnabled: Bool

    init(id: String, isEnabled: Bool = true) {
        self.id = id
        self.isEnabled = isEnabled
    }

    func body(content: Content) -> some View {
        if isEnabled {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RootDismissibleSurfaceFramesPreferenceKey.self,
                        value: [id: proxy.frame(in: .named(RootPullToSearchCoordinateSpace.name))]
                    )
                }
            }
        } else {
            content
        }
    }
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

enum RootPullToSearchFeedbackState: Equatable {
    case hidden
    case visible
    case armed

    private static let defaultPolicy = RootPullToSearchFeedbackPolicy()

    static func make(
        isEnabled: Bool,
        dragStartedAtTop: Bool,
        translation: CGSize
    ) -> RootPullToSearchFeedbackState {
        defaultPolicy.phase(
            isEnabled: isEnabled,
            dragStartedAtTop: dragStartedAtTop,
            translation: translation
        )
    }

    static func shouldTriggerSearch(
        isEnabled: Bool,
        dragStartedAtTop: Bool,
        translation: CGSize
    ) -> Bool {
        defaultPolicy.shouldTrigger(
            isEnabled: isEnabled,
            dragStartedAtTop: dragStartedAtTop,
            translation: translation
        )
    }
}

struct RootPullToSearchFeedbackPolicy {
    let revealDistance: CGFloat
    let activationDistance: CGFloat
    let maxHorizontalDrift: CGFloat

    init(
        revealDistance: CGFloat = 24,
        activationDistance: CGFloat = 96,
        maxHorizontalDrift: CGFloat = 140
    ) {
        self.revealDistance = revealDistance
        self.activationDistance = activationDistance
        self.maxHorizontalDrift = maxHorizontalDrift
    }

    func phase(
        isEnabled: Bool,
        dragStartedAtTop: Bool,
        translation: CGSize
    ) -> RootPullToSearchFeedbackState {
        guard isEnabled, dragStartedAtTop else { return .hidden }

        let verticalPull = max(0, translation.height)
        guard verticalPull > 0, abs(translation.width) < maxHorizontalDrift else {
            return .hidden
        }

        if verticalPull >= activationDistance {
            return .armed
        }
        if verticalPull >= revealDistance {
            return .visible
        }
        return .hidden
    }

    func shouldTrigger(
        isEnabled: Bool,
        dragStartedAtTop: Bool,
        translation: CGSize
    ) -> Bool {
        phase(
            isEnabled: isEnabled,
            dragStartedAtTop: dragStartedAtTop,
            translation: translation
        ) == .armed
    }
}

private struct RootPullToSearchIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let phase: RootPullToSearchFeedbackState

    private var armedAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return .spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0.1)
    }

    private var isVisible: Bool {
        phase != .hidden
    }

    private var isArmed: Bool {
        phase == .armed
    }

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: isArmed ? "magnifyingglass.circle.fill" : "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isArmed ? 1 : 0.92))
                .scaleEffect(isArmed ? 1.04 : 1)

            Text(isArmed ? "Release to search" : "Pull to search")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
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
        .scaleEffect(isVisible ? 1 : 0.9)
        .offset(y: isVisible ? -6 : 18)
        .opacity(isVisible ? 1 : 0)
        .animation(armedAnimation, value: isArmed)
        .animation(armedAnimation, value: isVisible)
        .accessibilityHidden(true)
    }
}

struct RootPullToSearchGestureModifier: ViewModifier {
    let isEnabled: Bool
    let onTrigger: () -> Void

#if os(iOS)
    @State private var feedbackPhase: RootPullToSearchFeedbackState = .hidden
    @State private var isListAtTop = true
    @State private var dragStartedAtTop = false
    @State private var isTrackingDrag = false

    private let topOffsetTolerance: CGFloat = 12
    private let feedbackPolicy = RootPullToSearchFeedbackPolicy()
#endif

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .coordinateSpace(name: RootPullToSearchCoordinateSpace.name)
            .onPreferenceChange(RootPullToSearchTopOffsetPreferenceKey.self) { minY in
                guard let minY else { return }
                let isNowAtTop = minY >= -topOffsetTolerance
                guard isListAtTop != isNowAtTop else { return }
                isListAtTop = isNowAtTop
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 14, coordinateSpace: .global)
                    .onChanged { value in
                        if !isTrackingDrag {
                            isTrackingDrag = true
                            dragStartedAtTop = isListAtTop
                        }

                        guard isEnabled, dragStartedAtTop else {
                            resetIndicatorIfNeeded(animated: true)
                            return
                        }

                        let nextPhase = feedbackPolicy.phase(
                            isEnabled: isEnabled,
                            dragStartedAtTop: dragStartedAtTop,
                            translation: value.translation
                        )
                        guard nextPhase != feedbackPhase else { return }
                        feedbackPhase = nextPhase
                    }
                    .onEnded { value in
                        let shouldTrigger = feedbackPolicy.shouldTrigger(
                            isEnabled: isEnabled,
                            dragStartedAtTop: dragStartedAtTop,
                            translation: value.translation
                        )

                        resetGestureState(animated: true)

                        guard shouldTrigger else { return }
                        onTrigger()
                    }
            )
            .overlay(alignment: .top) {
                RootPullToSearchIndicator(
                    phase: feedbackPhase
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
        guard feedbackPhase != .hidden else { return }
        if animated {
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.84, blendDuration: 0.08)) {
                feedbackPhase = .hidden
            }
        } else {
            feedbackPhase = .hidden
        }
    }

    private func resetIndicatorIfNeeded(animated: Bool) {
        guard feedbackPhase != .hidden else { return }
        resetIndicator(animated: animated)
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
    @State private var inlineTaskNotesVisible = false
    @State private var expandedInlineTaskPanel: InlineTaskPanel?
    @State private var showingInlineTaskDateModal = false
    @State private var inlineComposerTransitionTask: Task<Void, Never>?
    @State private var inlineTaskTitleParseTask: Task<Void, Never>?
    @State private var inlineTaskAvailableProjects: [String] = []
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
    @State private var inlineTaskHasManualProjectSelection = false
    @State private var inlineTaskHasManualDueSelection = false
    @State private var inlineTaskHasManualTagsSelection = false
    @State private var showingInlineVoiceRamble = false
    @State private var inlineAddButtonLongPressTriggered = false
    @State private var inlineAddButtonLongPressTask: Task<Void, Never>?
    @State private var inlineTaskFocusTask: Task<Void, Never>?
    @State private var taskListContentMaxY: CGFloat = .zero
    @State private var dismissibleSurfaceFrames: [String: CGRect] = [:]
    @FocusState private var inlineTaskFocused: Bool
    @Namespace private var compactQuickAddNamespace
    @State private var logbookSearchText = ""
    @AppStorage(CompactTabSettings.leadingViewKey) private var compactPrimaryTabRawValue = CompactTabSettings.defaultLeadingView.rawValue
    @AppStorage(CompactTabSettings.trailingViewKey) private var compactSecondaryTabRawValue = CompactTabSettings.defaultTrailingView.rawValue
    @AppStorage(CompactTabSettings.leadingDisplayNameKey) private var compactPrimaryTabDisplayName = ""
    @AppStorage(CompactTabSettings.trailingDisplayNameKey) private var compactSecondaryTabDisplayName = ""
    @AppStorage("settings_pomodoro_enabled") private var pomodoroEnabled = false
    private let logbookSearchEngine = LogbookSearchEngine()

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
                        TapOutsideDismissBackdrop(
                            fillColor: Color.black.opacity(0.001),
                            accessibilityIdentifier: "quickFind.backdrop",
                            onDismiss: dismissRootSearch
                        )

                        GeometryReader { geo in
                            QuickFindCard(
                                query: $universalSearchText,
                                store: quickFindStore,
                                maxHeight: geo.size.height * 0.68,
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
                            .padding(.top, ThingsSurfaceLayout.quickFindTopPadding)
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
                    onClose: {
                        showingInlineVoiceRamble = false
                    },
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
            .onChange(of: container.shouldPresentVoiceRamble) { _, shouldPresent in
                guard shouldPresent else { return }
                presentInlineVoiceRambleFromCurrentContext()
                container.clearVoiceRambleRequest()
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
                if container.shouldPresentVoiceRamble {
                    presentInlineVoiceRambleFromCurrentContext()
                    container.clearVoiceRambleRequest()
                }
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-show-quick-entry") {
                    showingQuickEntry = true
                }
            }
            .onDisappear {
                cancelInlineTaskComposer()
                expandedTaskPath = nil
                inlineComposerTransitionTask?.cancel()
                inlineComposerTransitionTask = nil
                inlineTaskFocusTask?.cancel()
                inlineTaskFocusTask = nil
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
                if selectedView != .builtIn(.logbook) {
                    logbookSearchText = ""
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
                choices: CompactRootTab.allCases.map(compactTabChoice(for:)),
                onTabReselection: handleCompactTabReselection
            )
        )
#endif
        .tint(theme.accentColor)
    }

    private var compactTabViewLegacy: some View {
        TabView(selection: compactTabSelectionBinding) {
            ForEach(CompactRootTab.allCases) { tab in
                compactTabScene(tab)
            }
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    private var compactTabViewNative: some View {
        TabView(selection: compactTabSelectionBinding) {
            compactTabItemsNative
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    @TabContentBuilder<CompactRootTab>
    private var compactTabItemsNative: some TabContent<CompactRootTab> {
        ForEach(CompactRootTab.allCases) { tab in
            let choice = compactTabChoice(for: tab)

            Tab(value: tab) {
                compactTabContent(for: tab)
                    .accessibilityIdentifier(choice.accessibilityIdentifier)
            } label: {
                compactTabItemLabel(choice: choice)
            }
        }
    }

    private var compactPerspectiveViews: [ViewIdentifier] {
        container.perspectives.map { container.perspectiveViewIdentifier(for: $0.id) }
    }

    private var compactProjectViews: [ViewIdentifier] {
        container.allProjects().map(ViewIdentifier.project)
    }

    private var compactAdditionalTabViews: [ViewIdentifier] {
        compactPerspectiveViews + compactProjectViews
    }

    private var compactCustomViews: (primary: ViewIdentifier, secondary: ViewIdentifier) {
        CompactTabSettings.normalizedCustomViews(
            leadingRawValue: compactPrimaryTabRawValue,
            trailingRawValue: compactSecondaryTabRawValue,
            pomodoroEnabled: pomodoroEnabled,
            additionalViews: compactAdditionalTabViews
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

        let choice = CompactTabChoiceCatalog.choice(for: view, perspectives: container.perspectives)
        let displayName = compactTabDisplayName(for: tab, view: view)
        guard displayName != choice.title else { return choice }
        return CompactTabChoice(view: choice.view, title: displayName, iconToken: choice.iconToken)
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
                    .lineLimit(1)
            } icon: {
                Text(choice.iconToken.storageValue)
            }
            .accessibilityLabel(choice.title)
        } else {
            Label {
                Text(choice.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: CompactTabChoiceCatalog.compactTabBarSymbolName(for: choice))
            }
        }
    }

    private func compactTabDisplayName(for tab: CompactRootTab, view: ViewIdentifier) -> String {
        guard CompactTabSettings.isPerspectiveCustomView(view),
              let perspectiveName = perspectiveName(for: view)
        else {
            return CompactTabChoiceCatalog.choice(for: view, perspectives: container.perspectives).title
        }

        let storedName: String = switch tab {
        case .customPrimary:
            compactPrimaryTabDisplayName
        case .customSecondary:
            compactSecondaryTabDisplayName
        case .inbox, .today, .areas:
            ""
        }

        return CompactTabSettings.normalizedPerspectiveDisplayName(
            storedName,
            perspectiveName: perspectiveName
        )
    }

    private var activeCompactTab: CompactRootTab {
        horizontalSizeClass == .compact ? compactSelectedTab : compactRootTab(for: container.selectedView)
    }

    private var compactTabSelectionPolicy: CompactTabSelectionPolicy {
        CompactTabSelectionPolicy(
            primaryView: compactPrimaryView,
            secondaryView: compactSecondaryView
        )
    }

    private var compactTabSelectionBinding: Binding<CompactRootTab> {
        Binding(
            get: { compactSelectedTab },
            set: { newTab in
                let previousTab = compactRootTab(for: container.selectedView)
                compactSelectedTab = newTab

                guard horizontalSizeClass == .compact else { return }

                if previousTab == newTab {
                    handleCompactTabReselection(newTab)
                } else {
                    selectCompactTab(newTab)
                }
            }
        )
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
                TaskDetailView(path: path, onDuplicate: openFullTaskEditor(path:))
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
            .overlay {
                if shouldShowDockedInlineTaskComposer {
                    TapOutsideDismissBackdrop(
                        fillColor: Color.black.opacity(0.001),
                        accessibilityIdentifier: "inlineTask.backdrop"
                    ) {
                        cancelInlineTaskComposer()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if shouldShowExpandedTaskBottomBar {
                    expandedTaskBottomBar
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if shouldShowDockedInlineTaskComposer {
                    dockedInlineTaskComposer
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
                    handleInlineAddButtonTap()
                } label: {
                    Image(systemName: isCreatingTask ? "xmark" : "plus")
                        .font(.title3.weight(.regular))
                }
                .onLongPressGesture(minimumDuration: 0.45, perform: handleInlineAddButtonLongPress)
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

#if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            if isCreatingTask {
                Spacer()
                Button {
                    commitInlineTaskComposer()
                } label: {
                    Label("Add Task", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .disabled(!canCommitInlineTask)
                .accessibilityLabel("Add task")
                .accessibilityIdentifier("inlineTask.keyboardCommitButton")
            }
        }
#endif
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
                upcomingMainContent()
                    .transition(rootScreenTransition)
            )
        }
        if container.selectedView == .builtIn(.review) {
            return AnyView(
                ReviewTabView(
                    sections: container.weeklyReviewSections(),
                    backgroundColor: theme.backgroundColor,
                    textPrimaryColor: theme.textPrimaryColor,
                    textSecondaryColor: theme.textSecondaryColor,
                    accentColor: theme.accentColor,
                    isPullToSearchEnabled: shouldAllowPullToSearchGesture,
                    onSearchTrigger: {
                        Task { @MainActor in
                            presentRootSearch()
                        }
                    },
                    onSelectProject: { project in
                        applyFilter(.project(project))
                    },
                    projectIcon: { project in
                        container.projectIconSymbol(for: project)
                    },
                    projectColor: { project in
                        color(forHex: container.projectColorHex(for: project))
                    },
                    heroRow: {
                        mainHeroListRow
                    },
                    taskRow: { record in
                        taskRowItem(record)
                    }
                )
                    .transition(rootScreenTransition)
            )
        }
        if container.selectedView == .builtIn(.anytime) {
            return AnyView(
                anytimeMainContent(records: container.filteredRecords())
                .transition(rootScreenTransition)
            )
        }
        if container.selectedView == .builtIn(.someday) {
            return AnyView(
                somedayMainContent(records: container.filteredRecords())
                .transition(rootScreenTransition)
            )
        }
        if container.selectedView == .builtIn(.logbook) {
            return AnyView(
                logbookMainContent(records: container.filteredRecords())
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
        if container.selectedView == .builtIn(.today) {
            return AnyView(todayMainContent(records: records))
        }
        if container.selectedView == .builtIn(.inbox) {
            return AnyView(inboxMainContent(records: records))
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
#if os(iOS)
                    .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
#endif
            }
        }
        .id("\(container.selectedView.rawValue)-inline-empty")
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
#if os(iOS)
        .onPreferenceChange(RootListContentMaxYPreferenceKey.self) { maxY in
            taskListContentMaxY = maxY
        }
        .onPreferenceChange(RootDismissibleSurfaceFramesPreferenceKey.self) { frames in
            dismissibleSurfaceFrames = frames
        }
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    handleTaskListBlankSpaceTap(at: value.location)
                }
        )
#endif
    }

    private func emptyStateMainContent() -> AnyView {
        if container.selectedView == .builtIn(.inbox) {
            return AnyView(inboxEmptyStateContent)
        }
        return AnyView(
            genericEmptyStateContent
        )
    }

    private func todayMainContent(records: [TaskRecord]) -> some View {
        let sections = container.todaySections()
        let descriptor = TodayTabDescriptor.makeForRootState(
            records: records,
            sections: sections,
            isCalendarConnected: container.isCalendarConnected,
            showsInlineComposer: shouldRenderInlineTaskComposerInList,
            isEditing: isEditing
        )

        return taskList(id: descriptor.listID, creationScrollTarget: records.last?.identity.path) {
            TodayTabView(
                descriptor: descriptor,
                onReorder: { filenames in
                    container.saveManualOrder(filenames: filenames)
                },
                heroRow: {
                    mainHeroListRow
                },
                calendarCard: {
                    todayCalendarCardListRow
                },
                inlineComposer: {
                    inlineTaskComposerListRow
                },
                taskRow: { record in
                    taskRowItem(record)
                },
                unparseableSummary: {
                    unparseableFilesSummary
                }
            )
        }
    }

    private func upcomingMainContent() -> some View {
        let descriptor = UpcomingTabDescriptor.makeForRootState(
            sections: container.upcomingAgendaSections()
        )

        return UpcomingTabView(descriptor: descriptor) { record in
            taskRowItem(record)
        }
    }

    private var inboxEmptyStateContent: some View {
        taskList(id: "\(container.selectedView.rawValue)-empty") {
            mainHeroListRow
            InboxRemindersImportPanel()
#if os(iOS)
                .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
#endif

            VStack(spacing: 12) {
                IllustratedEmptyState(
                    symbol: "tray.fill",
                    glowColor: Color.accentColor.opacity(0.18),
                    title: "Inbox is clear",
                    subtitle: "New tasks land here first."
                )
                unparseableFilesSummary
            }
            .frame(maxWidth: .infinity)
            .padding(.top, ThingsSurfaceLayout.emptyStateTopPadding)
            .padding(.bottom, ThingsSurfaceLayout.emptyStateBottomPadding)
#if os(iOS)
            .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
#endif
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var genericEmptyStateContent: some View {
        taskList(id: "\(container.selectedView.rawValue)-empty") {
            mainHeroListRow

            VStack(spacing: 12) {
                IllustratedEmptyState(
                    symbol: "checkmark.circle",
                    glowColor: Color.teal.opacity(0.15),
                    title: "Nothing here",
                    subtitle: "Tap + to add a task."
                )
                unparseableFilesSummary
            }
            .frame(maxWidth: .infinity)
            .padding(.top, ThingsSurfaceLayout.emptyStateTopPadding)
            .padding(.bottom, ThingsSurfaceLayout.emptyStateBottomPadding)
#if os(iOS)
            .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
#endif
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func anytimeMainContent(records: [TaskRecord]) -> some View {
        let descriptor = AnytimeTabDescriptor.make(records: records)

        return taskList(id: descriptor.listID, creationScrollTarget: records.last?.identity.path) {
            AnytimeTabView(
                descriptor: descriptor,
                records: records,
                onReorder: { filenames in
                    container.saveManualOrder(filenames: filenames)
                },
                heroRow: {
                    mainHeroListRow
                },
                taskRow: { record in
                    taskRowItem(record)
                },
                unparseableSummary: {
                    unparseableFilesSummary
                }
            )
        }
    }

    private func inboxMainContent(records: [TaskRecord]) -> some View {
        let descriptor = InboxTabDescriptor.make(
            records: records,
            showsInlineComposer: shouldRenderInlineTaskComposerInList
        )

        return taskList(id: descriptor.listID, creationScrollTarget: records.last?.identity.path) {
            InboxTabView(
                descriptor: descriptor,
                records: records,
                onReorder: { filenames in
                    guard container.canManuallyReorderSelectedView() else { return }
                    container.saveManualOrder(filenames: filenames)
                },
                heroRow: {
                    mainHeroListRow
                },
                importPanel: {
                    InboxRemindersImportPanel()
#if os(iOS)
                        .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
#endif
                },
                inlineComposer: {
                    inlineTaskComposerListRow
                },
                taskRow: { record in
                    taskRowItem(record)
                },
                unparseableSummary: {
                    unparseableFilesSummary
                }
            )
        }
    }

    private func somedayMainContent(records: [TaskRecord]) -> some View {
        let descriptor = SomedayTabDescriptor.make(records: records)

        return taskList(id: descriptor.listID, creationScrollTarget: records.last?.identity.path) {
            SomedayTabView(
                descriptor: descriptor,
                records: records,
                onReorder: { filenames in
                    container.saveManualOrder(filenames: filenames)
                },
                heroRow: {
                    mainHeroListRow
                },
                taskRow: { record in
                    taskRowItem(record)
                },
                unparseableSummary: {
                    unparseableFilesSummary
                }
            )
        }
    }

    private func logbookMainContent(records: [TaskRecord]) -> some View {
        let filtered = logbookSearchEngine.filter(records: records, query: logbookSearchText)
        let descriptor = LogbookTabDescriptor.make(records: records, filteredRecords: filtered)

        return LogbookTabView(
            descriptor: descriptor,
            searchText: $logbookSearchText,
            filteredRecords: filtered,
            genericEmptyContent: {
                genericEmptyStateContent
            },
            searchEmptyContent: { searchEmptyState in
                logbookSearchEmptyStateContent(
                    listID: descriptor.listID,
                    searchEmptyState: searchEmptyState
                )
            },
            populatedContent: { filteredRecords in
                populatedRecordsMainContent(records: filteredRecords)
            }
        )
    }

    private func logbookSearchEmptyStateContent(
        listID: String,
        searchEmptyState: LogbookSearchEmptyState
    ) -> some View {
        taskList(id: listID) {
            mainHeroListRow

            VStack(spacing: 12) {
                IllustratedEmptyState(
                    symbol: searchEmptyState.symbol,
                    glowColor: Color.green.opacity(0.14),
                    title: searchEmptyState.title,
                    subtitle: searchEmptyState.subtitle
                )
                Text(searchEmptyState.exampleQuery)
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondaryColor)
                    .multilineTextAlignment(.center)
                unparseableFilesSummary
            }
            .frame(maxWidth: .infinity)
            .padding(.top, ThingsSurfaceLayout.emptyStateTopPadding)
            .padding(.bottom, ThingsSurfaceLayout.emptyStateBottomPadding)
#if os(iOS)
            .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
#endif
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
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
        taskList(
            id: container.selectedView.rawValue,
            creationScrollTarget: records.last?.identity.path
        ) {
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
            .padding(.horizontal, ThingsSurfaceLayout.heroHorizontalPadding)
            .padding(.top, ThingsSurfaceLayout.heroTopPadding)
            .padding(.bottom, ThingsSurfaceLayout.heroBottomPadding)
#if os(iOS)
            .modifier(RootPullToSearchTopMarker())
            .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
#endif
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
            .padding(.horizontal, ThingsSurfaceLayout.heroHorizontalPadding)
            .padding(.top, ThingsSurfaceLayout.supportingCardTopPadding)
            .padding(.bottom, ThingsSurfaceLayout.supportingCardBottomPadding)
#if os(iOS)
            .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
#endif
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
                    if inlineTaskNotesVisible || !inlineTaskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        inlineTaskExpandedNotesField
                    } else {
                        inlineTaskRevealNotesButton
                    }
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
            ThingsSurfaceBackdrop(
                kind: .elevatedCard,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .padding(.horizontal, ThingsSurfaceLayout.floatingCardHorizontalInset)
        .padding(.vertical, ThingsSurfaceLayout.floatingCardVerticalInset)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(inlineTaskComposerScrollID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inlineTask.row")
        .accessibilityValue("expanded")
#if os(iOS)
        .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
        .modifier(RootDismissibleSurfaceFrameReporter(id: RootDismissibleSurfaceID.inlineTaskComposer, isEnabled: isCreatingTask))
#endif
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

            TextField("", text: $inlineTaskDraft.title)
                .modifier(RootViewWordsAutocapitalization())
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(theme.textPrimaryColor)
                .focused($inlineTaskFocused)
                .lineLimit(1)
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

    private var inlineTaskRevealNotesButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) {
                inlineTaskNotesVisible = true
            }
        } label: {
            Label("Add note", systemImage: "text.alignleft")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textSecondaryColor)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inlineTask.addNoteButton")
    }

    private var inlineTaskComposerNoteTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.82) : theme.textSecondaryColor
    }

    private var inlineTaskComposerNotePlaceholderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.3) : theme.textSecondaryColor.opacity(0.7)
    }

    private func compactInlineTaskComposerCard(maxHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    CompactComposerCheckbox(strokeColor: compactComposerCheckboxColor)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("New To-Do", text: $inlineTaskDraft.title)
                            .modifier(RootViewWordsAutocapitalization())
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(compactComposerPrimaryTextColor)
                            .focused($inlineTaskFocused)
                            .lineLimit(1)
                            .submitLabel(.done)
                            .accessibilityIdentifier("inlineTask.titleField")
                            .onChange(of: inlineTaskDraft.title) { _, newValue in
                                handleInlineTaskTitleChanged(newValue)
                            }
                            .onSubmit {
                                commitInlineTaskComposer()
                            }

                        if inlineTaskNotesVisible || !inlineTaskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            compactInlineTaskNotesField
                        } else {
                            compactInlineTaskRevealNotesButton
                        }

                        Text("Add details only if you need them.")
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
        .allowsHitTesting(compactComposerContentVisible)
        .accessibilityHidden(!compactComposerContentVisible)
        .opacity(compactComposerContentVisible ? 1 : 0.001)
        .offset(y: compactComposerContentVisible ? 0 : 10)
        .scaleEffect(compactComposerContentVisible ? 1 : 0.978, anchor: .bottomTrailing)
        .accessibilityIdentifier("inlineTask.row")
        .background(
            ThingsSurfaceBackdrop(
                kind: floatingComposerSurfaceKind,
                theme: theme,
                colorScheme: colorScheme
            )
            .matchedGeometryEffect(
                id: "compactQuickAddShell",
                in: compactQuickAddNamespace,
                properties: .frame,
                anchor: .bottomTrailing
            )
        )
        .animation(ThingsSurfaceMotion.overlayClose, value: compactComposerContentVisible)
    }

    private var compactInlineTaskNotesField: some View {
        ZStack(alignment: .topLeading) {
            if inlineTaskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Notes")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(compactComposerSecondaryTextColor)
                    .padding(.top, 1)
            }

            TextField("", text: $inlineTaskDraft.description, axis: .vertical)
                .modifier(RootViewWordsAutocapitalization())
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(compactComposerPrimaryTextColor)
                .lineLimit(1...4)
                .accessibilityIdentifier("inlineTask.notesField")
        }
        .frame(minHeight: 56, alignment: .topLeading)
    }

    private var compactInlineTaskRevealNotesButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) {
                inlineTaskNotesVisible = true
            }
        } label: {
            Label("Add note", systemImage: "text.alignleft")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(compactComposerPrimaryTextColor)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inlineTask.addNoteButton")
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
        return HStack(spacing: 18) {
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

    @ViewBuilder
    private func inlineTaskProjectAccessoryMenu(
        activeTint: Color,
        inactiveTint: Color
    ) -> some View {
        let isActive = inlineTaskDraft.project != nil || inlineTaskDraft.area != nil
        if horizontalSizeClass == .compact {
            Button {
                toggleInlineTaskPanel(.destination)
            } label: {
                InlineTaskAccessoryIconLabel(
                    systemImage: "list.bullet",
                    tint: isActive ? activeTint : inactiveTint
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("inlineTask.projectMenuButton")
            .accessibilityLabel("Project")
            .accessibilityValue(inlineTaskDestinationLabel)
        } else {
            Menu {
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

    private var compactComposerPrimaryTextColor: Color {
        horizontalSizeClass == .compact ? Color.white.opacity(0.92) : theme.textPrimaryColor
    }

    private var compactComposerSecondaryTextColor: Color {
        horizontalSizeClass == .compact ? Color.white.opacity(0.34) : theme.textSecondaryColor
    }

    private var compactComposerIconColor: Color {
        horizontalSizeClass == .compact ? Color.white.opacity(0.42) : theme.textSecondaryColor.opacity(0.9)
    }

    private var compactComposerIconActiveColor: Color {
        compactComposerPrimaryTextColor
    }

    private var compactComposerTodayTint: Color {
        Color(.sRGB, red: 0.949, green: 0.784, blue: 0.192, opacity: 1)
    }

    private var compactComposerFlagTint: Color {
        horizontalSizeClass == .compact ? Color(.sRGB, red: 0.969, green: 0.604, blue: 0.22, opacity: 1) : theme.flaggedColor
    }

    private var compactComposerCheckboxColor: Color {
        horizontalSizeClass == .compact ? Color.white.opacity(0.48) : theme.textSecondaryColor.opacity(0.6)
    }

    private var floatingComposerSurfaceKind: ThingsSurfaceKind {
        horizontalSizeClass == .compact ? .compactOverlay : .elevatedCard
    }

    private var inlineComposerMetadataPrimaryTextColor: Color {
        horizontalSizeClass == .compact ? compactComposerPrimaryTextColor : theme.textPrimaryColor
    }

    private var inlineComposerMetadataSecondaryTextColor: Color {
        horizontalSizeClass == .compact ? compactComposerSecondaryTextColor : theme.textSecondaryColor
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
                        tint: theme.accentColor,
                        accessibilityIdentifier: "inlineTask.projectMenuItem.Inbox"
                    ) {
                        applyInlineTaskDestination(project: nil, area: nil, isManual: true)
                    }

                    if let currentArea = defaultInlineTaskDraft(for: container.selectedView).area {
                        InlineTaskOptionButton(
                            title: currentArea,
                            isSelected: inlineTaskDraft.area == currentArea && inlineTaskDraft.project == nil,
                            tint: theme.accentColor,
                            accessibilityIdentifier: "inlineTask.projectMenuItem.\(currentArea)"
                        ) {
                            applyInlineTaskDestination(project: nil, area: currentArea, isManual: true)
                        }
                    }

                    ForEach(container.projectPickerContent(excluding: inlineTaskDraft.project).allProjects, id: \.self) { project in
                        InlineTaskOptionButton(
                            title: project,
                            isSelected: inlineTaskDraft.project == project,
                            tint: theme.accentColor,
                            accessibilityIdentifier: "inlineTask.projectMenuItem.\(project)"
                        ) {
                            applyInlineTaskDestination(project: project, area: nil, isManual: true)
                        }
                    }
                }
            }

        case .tags:
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    "Tags",
                    text: Binding(
                        get: { inlineTaskDraft.tagsText },
                        set: { newValue in
                            inlineTaskDraft.tagsText = newValue
                            inlineTaskHasManualTagsSelection = true
                        }
                    )
                )
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
                                    appendInlineTag(tag, isManualEdit: true)
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
                        inlineTaskHasManualDueSelection = true
                        setInlineTaskDueDate(Calendar.current.startOfDay(for: Date()))
                    }
                } else {
                    inlineTaskHasManualDueSelection = true
                    setInlineTaskDueDate(nil)
                }
            }
        )
    }

    private var inlineTaskDueDateBinding: Binding<Date> {
        Binding(
            get: { inlineTaskDraft.dueDate ?? Calendar.current.startOfDay(for: Date()) },
            set: { date in
                inlineTaskHasManualDueSelection = true
                setInlineTaskDueDate(Calendar.current.startOfDay(for: date))
            }
        )
    }

    private var inlineTaskHasDueTimeBinding: Binding<Bool> {
        Binding(
            get: { inlineTaskDraft.dueDate != nil && inlineTaskDraft.hasDueTime },
            set: { hasDueTime in
                inlineTaskHasManualDueSelection = true
                inlineTaskDraft.hasDueTime = hasDueTime && inlineTaskDraft.dueDate != nil
                inlineAutoDatePhrase = nil
            }
        )
    }

    private var inlineTaskDueTimeBinding: Binding<Date> {
        Binding(
            get: { inlineTaskDraft.dueTime },
            set: { time in
                inlineTaskHasManualDueSelection = true
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
            applyInlineTaskDestination(project: nil, area: nil, isManual: true)
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
                        applyInlineTaskDestination(project: nil, area: area, isManual: true)
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
                        applyInlineTaskDestination(project: project, area: nil, isManual: true)
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
            let suggestions = container.projectPickerContent(excluding: inlineTaskDraft.project).allProjects.filter { project in
                query.isEmpty || matchesQuery(project, query: query)
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

    private func applyInlineTaskDestination(project: String?, area: String?, isManual: Bool) {
        if isManual {
            inlineTaskHasManualProjectSelection = true
        }
        inlineTaskDraft.project = project
        inlineTaskDraft.area = area
    }

    private func appendInlineTag(_ tag: String) {
        appendInlineTag(tag, isManualEdit: false)
    }

    private func appendInlineTag(_ tag: String, isManualEdit: Bool) {
        if isManualEdit {
            inlineTaskHasManualTagsSelection = true
        }
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
            ThingsSurfaceBackdrop(
                kind: .inset,
                theme: theme,
                colorScheme: colorScheme
            )
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
            ThingsSurfaceBackdrop(
                kind: .inset,
                theme: theme,
                colorScheme: colorScheme
            )
        )
    }

    private func applyInlineTaskSuggestion(
        kind: InlineTaskComposerSuggestionKind,
        suggestion: String
    ) {
        inlineTaskDraft.title = titleWithoutTrailingSuggestionToken(from: inlineTaskDraft.title)
        switch kind {
        case .project:
            applyInlineTaskDestination(project: suggestion, area: nil, isManual: true)
        case .tag:
            appendInlineTag(suggestion, isManualEdit: true)
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
        let projects = container.allProjects().filter { matchesQuery($0, query: query) }
        let perspectives = container.perspectives.filter { matchesQuery($0.name, query: query) }

        let hasNavigationResults = !projects.isEmpty
            || !perspectives.isEmpty

        if tasks.isEmpty && tags.isEmpty && !hasNavigationResults {
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
                // Progress ring for project views; suppress checkmark when ring is shown
                if case .project(let projectName) = view {
                    let (completed, total) = container.projectProgress(for: projectName)
                    if total > 0 {
                        let progress = Double(completed) / Double(total)
                        ProjectProgressRing(progress: progress, tint: tint ?? theme.accentColor)
                    }
                } else if isSelected {
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
        fallbackIcon: String? = nil,
        accessibilityIdentifier: String? = nil
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
        .accessibilityIdentifier(accessibilityIdentifier ?? "root.search.destination.\(view.rawValue)")
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
        compactTabSelectionPolicy.tab(for: view)
    }

    private func rootView(for tab: CompactRootTab, currentView: ViewIdentifier? = nil) -> ViewIdentifier {
        compactTabSelectionPolicy.rootView(for: tab, currentView: currentView ?? container.selectedView)
    }

    private func selectCompactTab(_ tab: CompactRootTab) {
        let targetView = rootView(for: tab)
        applyFilter(targetView)
    }

    private func handleCompactTabReselection(_ tab: CompactRootTab) {
        var path = navigationPathBinding(for: tab).wrappedValue
        guard !path.isEmpty || compactTabSelectionPolicy.reselectionTarget(for: tab, currentView: container.selectedView) != nil else {
            return
        }

        path = NavigationPath()
        navigationPathBinding(for: tab).wrappedValue = path

        if let targetView = compactTabSelectionPolicy.reselectionTarget(for: tab, currentView: container.selectedView) {
            applyFilter(targetView)
        }
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
        false
    }

    private var shouldShowDockedInlineTaskComposer: Bool {
        shouldRenderInlineTaskComposer
    }

    private var shouldShowExpandedTaskBottomBar: Bool {
        horizontalSizeClass == .compact && isAtActiveNavigationRoot && expandedTaskPath != nil
    }

    private var shouldAllowPullToSearchGesture: Bool {
        isAtActiveNavigationRoot && !inboxTriageMode && !isRootSearchPresented
    }

    private var shouldTrackTaskListBoundaryMetrics: Bool {
        expandedTaskPath != nil
    }

    private var compactComposerOpenAnimation: Animation {
        .smooth(duration: 0.18)
    }

    private var compactComposerCloseAnimation: Animation {
        .smooth(duration: 0.14)
    }

    private var inlineTaskDockReservedHeight: CGFloat {
        let expandedPanelHeight: CGFloat = expandedInlineTaskPanel == nil ? 0 : 176
        let noteHeight: CGFloat = (inlineTaskNotesVisible || !inlineTaskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 66 : 0
        let baseHeight: CGFloat = horizontalSizeClass == .compact ? 228 : 248
        return min(horizontalSizeClass == .compact ? 440 : 468, baseHeight + expandedPanelHeight + noteHeight)
    }

    private var dockedInlineTaskComposer: some View {
        compactInlineTaskComposerCard(maxHeight: inlineTaskDockReservedHeight)
            .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 580, alignment: .top)
            .padding(.horizontal, horizontalSizeClass == .compact ? 12 : 16)
            .padding(.top, 8)
            .padding(.bottom, horizontalSizeClass == .compact ? 6 : 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityValue(horizontalSizeClass == .compact ? "docked" : "tray")
    }

    private var floatingAddButton: some View {
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
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    beginInlineAddButtonPress()
                }
                .onEnded { _ in
                    finishInlineAddButtonPress()
                }
        )
        .accessibilityLabel("Add Task")
        .accessibilityIdentifier("root.inlineAddButton")
        .accessibilityAddTraits(.isButton)
        .shadow(color: theme.accentColor.opacity(0.3), radius: 20, x: 0, y: 10)
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .transition(.scale(scale: 0.86, anchor: .bottomTrailing).combined(with: .opacity))
    }

    @ViewBuilder
    private var expandedTaskBottomBar: some View {
        if let path = expandedTaskPath {
            HStack(spacing: 0) {
                ExpandedTaskBottomBarIconButton(
                    systemImage: "xmark",
                    tint: Color.white.opacity(0.88),
                    action: {
                        withAnimation(expandedTaskCloseAnimation) {
                            expandedTaskPath = nil
                        }
                    }
                )

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 30)
                    .padding(.vertical, 10)

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
        creationScrollTarget: String? = nil,
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
#if os(iOS)
            .onPreferenceChange(RootListContentMaxYPreferenceKey.self) { maxY in
                taskListContentMaxY = maxY
            }
            .onPreferenceChange(RootDismissibleSurfaceFramesPreferenceKey.self) { frames in
                dismissibleSurfaceFrames = frames
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleTaskListBlankSpaceTap(at: value.location)
                    }
            )
#endif
            .onChange(of: expandedTaskPath) { _, path in
                expandedTaskScrollTask?.cancel()
                guard let path else { return }
                scheduleExpandedTaskScroll(to: path, proxy: proxy)
            }
            .onChange(of: isCreatingTask) { _, isCreating in
                inlineComposerScrollTask?.cancel()
                guard isCreating else { return }
                if shouldRenderInlineTaskComposerInList {
                    scheduleInlineTaskComposerScroll(proxy: proxy)
                } else if shouldShowDockedInlineTaskComposer, let creationScrollTarget {
                    scheduleDockedInlineTaskComposerScroll(to: creationScrollTarget, proxy: proxy)
                }
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

    private func scheduleDockedInlineTaskComposerScroll(to path: String, proxy: ScrollViewProxy) {
        inlineComposerScrollTask?.cancel()

        inlineComposerScrollTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled, isCreatingTask, shouldShowDockedInlineTaskComposer else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(path, anchor: .bottom)
            }
            scheduleInlineTaskFocus(after: 0)

            do {
                try await Task.sleep(nanoseconds: 220_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled, isCreatingTask, shouldShowDockedInlineTaskComposer else { return }
            withTransaction(transaction) {
                proxy.scrollTo(path, anchor: .bottom)
            }
            scheduleInlineTaskFocus(after: 0)
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

    private func handleInlineAddButtonTap() {
        if inlineAddButtonLongPressTriggered {
            inlineAddButtonLongPressTriggered = false
            return
        }
        triggerInlineTaskComposer()
    }

    private func handleInlineAddButtonLongPress() {
        guard !isCreatingTask else { return }
        inlineAddButtonLongPressTriggered = true
        presentInlineVoiceRambleFromCurrentContext()
    }

    private func beginInlineAddButtonPress() {
        guard inlineAddButtonLongPressTask == nil else { return }
        inlineAddButtonLongPressTriggered = false
        inlineAddButtonLongPressTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            handleInlineAddButtonLongPress()
        }
    }

    private func finishInlineAddButtonPress() {
        inlineAddButtonLongPressTask?.cancel()
        inlineAddButtonLongPressTask = nil

        if inlineAddButtonLongPressTriggered {
            inlineAddButtonLongPressTriggered = false
            return
        }

        handleInlineAddButtonTap()
    }

    private func presentInlineVoiceRambleFromCurrentContext() {
        inlineComposerTransitionTask?.cancel()
        inlineComposerTransitionTask = nil
        inlineTaskFocusTask?.cancel()
        inlineTaskFocusTask = nil
        inlineTaskDraft = defaultInlineTaskDraft(for: container.selectedView)
        inlineTaskNotesVisible = false
        expandedInlineTaskPanel = nil
        showingInlineTaskDateModal = false
        inlineTaskHasManualProjectSelection = false
        inlineTaskHasManualDueSelection = false
        inlineTaskHasManualTagsSelection = false
        inlineAutoDatePhrase = nil
        inlineTaskAvailableProjects = container.allProjects()
        compactComposerContentVisible = horizontalSizeClass != .compact
        showingInlineVoiceRamble = true
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
        inlineTaskNotesVisible = false
        expandedInlineTaskPanel = nil
        showingInlineTaskDateModal = false
        inlineAutoDatePhrase = nil
        inlineTaskHasManualProjectSelection = false
        inlineTaskHasManualDueSelection = false
        inlineTaskHasManualTagsSelection = false
        inlineTaskAvailableProjects = container.allProjects()
        compactComposerContentVisible = true
        withAnimation(compactComposerOpenAnimation) {
            isCreatingTask = true
        }

        scheduleInlineTaskFocus(after: horizontalSizeClass == .compact ? 20_000_000 : 10_000_000)
    }

    private func cancelInlineTaskComposer() {
        guard isCreatingTask else { return }
        inlineComposerTransitionTask?.cancel()
        inlineComposerTransitionTask = nil
        inlineTaskTitleParseTask?.cancel()
        inlineTaskTitleParseTask = nil
        inlineTaskFocusTask?.cancel()
        inlineTaskFocusTask = nil
        showingInlineVoiceRamble = false
        showingInlineTaskDateModal = false
        compactComposerContentVisible = false
        withAnimation(compactComposerCloseAnimation) {
            isCreatingTask = false
        }
        inlineTaskDraft = InlineTaskDraft()
        inlineTaskNotesVisible = false
        inlineAutoDatePhrase = nil
        inlineTaskAvailableProjects = []
        inlineTaskHasManualProjectSelection = false
        inlineTaskHasManualDueSelection = false
        inlineTaskHasManualTagsSelection = false
        inlineTaskFocused = false
        expandedInlineTaskPanel = nil
    }

    private func scheduleInlineTaskFocus(after delayNanoseconds: UInt64) {
        inlineTaskFocusTask?.cancel()
        inlineTaskFocusTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard !Task.isCancelled, isCreatingTask, shouldRenderInlineTaskComposer else { return }
            inlineTaskFocused = true

            let retryDelay: UInt64 = horizontalSizeClass == .compact ? 60_000_000 : 45_000_000
            try? await Task.sleep(nanoseconds: retryDelay)

            guard !Task.isCancelled, isCreatingTask, shouldRenderInlineTaskComposer, !inlineTaskFocused else {
                inlineTaskFocusTask = nil
                return
            }

            inlineTaskFocused = true
            inlineTaskFocusTask = nil
        }
    }

    private func handleTaskListBlankSpaceTap(at location: CGPoint) {
        if isCreatingTask {
            if let frame = dismissibleSurfaceFrame(for: RootDismissibleSurfaceID.inlineTaskComposer), frame.contains(location) {
                return
            }
            cancelInlineTaskComposer()
            return
        }

        if let expandedTaskPath,
           let frame = dismissibleSurfaceFrame(for: RootDismissibleSurfaceID.expandedTask(expandedTaskPath)) {
            guard !frame.contains(location) else { return }
            withAnimation(expandedTaskCloseAnimation) {
                self.expandedTaskPath = nil
            }
            return
        }

        guard location.y > taskListContentMaxY + 8 else { return }

        if isCreatingTask {
            cancelInlineTaskComposer()
            return
        }

        guard expandedTaskPath != nil else { return }
        withAnimation(expandedTaskCloseAnimation) {
            expandedTaskPath = nil
        }
    }

    private func dismissibleSurfaceFrame(for id: String) -> CGRect? {
        guard let frame = dismissibleSurfaceFrames[id], !frame.isNull, !frame.isEmpty else {
            return nil
        }
        return frame
    }

    private func handleInlineTaskTitleChanged(_ value: String) {
        guard !inlineTaskTitleMutationInFlight else { return }
        inlineTaskTitleParseTask?.cancel()

        let currentTitle = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTitle.isEmpty else {
            inlineTaskTitleParseTask = nil
            return
        }

        let capturedValue = value
        let availableProjects = inlineTaskAvailableProjects
        inlineTaskTitleParseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled, isCreatingTask, inlineTaskDraft.title == capturedValue else {
                return
            }

            let parser = NaturalLanguageTaskParser(availableProjects: availableProjects)
            guard let parsed = parser.parse(capturedValue),
                  let due = parsed.due,
                  parsed.dueTime == nil,
                  let phrase = parsed.recognizedDatePhrase else {
                inlineTaskTitleParseTask = nil
                return
            }

            inlineTaskTitleMutationInFlight = true
            if !inlineTaskHasManualProjectSelection, let parsedProject = parsed.project {
                applyInlineTaskDestination(project: parsedProject, area: nil, isManual: false)
            }
            if !inlineTaskHasManualTagsSelection, !parsed.tags.isEmpty {
                for tag in parsed.tags {
                    appendInlineTag(tag)
                }
            }
            if !inlineTaskHasManualDueSelection {
                let loweredPhrase = phrase.lowercased()
                let chipPhrase = loweredPhrase.hasPrefix("due ")
                    || loweredPhrase.hasPrefix("by ")
                    || loweredPhrase.hasPrefix("on ")
                    || loweredPhrase.hasPrefix("at ")
                    ? loweredPhrase
                    : "due \(loweredPhrase)"
                applyInlineDueDate(dateFromLocalDate(due), autoPhrase: chipPhrase)
            }
            inlineTaskTitleMutationInFlight = false
            inlineTaskTitleParseTask = nil
        }
    }

    private func resolvedInlineTaskDestinationForCommit(title: String) -> (area: String?, project: String?) {
        guard !inlineTaskHasManualProjectSelection else {
            return (area: inlineTaskDraft.area, project: inlineTaskDraft.project)
        }

        let parser = NaturalLanguageTaskParser(availableProjects: inlineTaskAvailableProjects)
        guard let parsedProject = parser.parse(title)?.project else {
            return (area: inlineTaskDraft.area, project: inlineTaskDraft.project)
        }
        return (area: nil, project: parsedProject)
    }

    private func commitInlineTaskComposer() {
        let trimmedTitle = inlineTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            cancelInlineTaskComposer()
            return
        }

        let defaultDraft = defaultInlineTaskDraft(for: container.selectedView)
        let resolvedDestination = resolvedInlineTaskDestinationForCommit(title: trimmedTitle)
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
            area: resolvedDestination.area,
            project: resolvedDestination.project,
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
                area: resolvedDestination.area,
                project: resolvedDestination.project,
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
                TapOutsideDismissBackdrop(
                    fillColor: Color.black.opacity(0.42),
                    accessibilityIdentifier: "expandedTaskDate.backdrop"
                ) {
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
        let pickerContent = container.projectPickerContent()
        let currentFrontmatter = container.record(for: target.path)?.document.frontmatter

        return ExpandedTaskMoveEditorSheet(
            currentArea: currentFrontmatter?.area,
            currentProject: currentFrontmatter?.project,
            groupedAreas: pickerContent.groupedAreas.map { (area: $0.area, projects: $0.projects) },
            ungroupedProjects: pickerContent.ungroupedProjects
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
        let pickerContent = container.projectPickerContent(excluding: record.document.frontmatter.project)
        let quickProjects = pickerContent.allProjects
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
#if os(iOS)
        .modifier(RootListContentBoundaryReporter(isEnabled: shouldTrackTaskListBoundaryMetrics))
        .modifier(RootDismissibleSurfaceFrameReporter(id: RootDismissibleSurfaceID.expandedTask(path), isEnabled: expandedTaskPath == path))
#endif
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
                        Button("No Projects") {}
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
                ForEach(pickerContent.groupedAreas, id: \.area) { group in
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
                if !pickerContent.ungroupedProjects.isEmpty {
                    Menu("No Area") {
                        ForEach(pickerContent.ungroupedProjects, id: \.self) { project in
                            Button(project) {
                                _ = container.moveTask(path: record.identity.path, area: nil, project: project)
                            }
                        }
                    }
                }
            }

            Button(record.document.frontmatter.flagged ? "Remove Flag" : "Flag") {
                _ = container.toggleFlag(path: record.identity.path)
            }

            Button("Duplicate") {
                if let duplicate = container.duplicateTask(path: record.identity.path) {
                    openFullTaskEditor(path: duplicate.identity.path)
                }
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
                // Progress ring for project views; suppress checkmark when ring is shown
                if case .project(let projectName) = view {
                    let (completed, total) = container.projectProgress(for: projectName)
                    if total > 0 {
                        let progress = Double(completed) / Double(total)
                        ProjectProgressRing(progress: progress, tint: tint ?? theme.accentColor)
                    }
                } else if isSelected {
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
            additionalViews: compactAdditionalTabViews
        )

        if compactPrimaryTabRawValue != normalized.primary.rawValue {
            compactPrimaryTabRawValue = normalized.primary.rawValue
        }
        if compactSecondaryTabRawValue != normalized.secondary.rawValue {
            compactSecondaryTabRawValue = normalized.secondary.rawValue
        }

        let normalizedPrimaryDisplayName = normalizedCompactTabDisplayName(
            storedValue: compactPrimaryTabDisplayName,
            view: normalized.primary
        )
        if compactPrimaryTabDisplayName != normalizedPrimaryDisplayName {
            compactPrimaryTabDisplayName = normalizedPrimaryDisplayName
        }

        let normalizedSecondaryDisplayName = normalizedCompactTabDisplayName(
            storedValue: compactSecondaryTabDisplayName,
            view: normalized.secondary
        )
        if compactSecondaryTabDisplayName != normalizedSecondaryDisplayName {
            compactSecondaryTabDisplayName = normalizedSecondaryDisplayName
        }
    }

    private func normalizedCompactTabDisplayName(
        storedValue: String,
        view: ViewIdentifier
    ) -> String {
        guard CompactTabSettings.isPerspectiveCustomView(view),
              let perspectiveName = perspectiveName(for: view)
        else {
            return ""
        }

        return CompactTabSettings.normalizedPerspectiveDisplayName(
            storedValue,
            perspectiveName: perspectiveName
        )
    }

    private func perspectiveName(for view: ViewIdentifier) -> String? {
        perspective(for: view)?.name
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

private struct ExpandedTaskRow: View {
    private struct MetadataSegment {
        let text: String
        let color: Color
        let accessibilityText: String?
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
    @EnvironmentObject private var container: AppContainer
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

                // Star icon — active tasks only
                if !isExpanded,
                   frontmatter.status == .todo || frontmatter.status == .inProgress {
                    let isScheduledToday = frontmatter.scheduled == LocalDate.today(in: .current)
                    Button {
                        if isScheduledToday {
                            _ = container.setScheduled(path: record.identity.path, date: nil)
                        } else {
                            _ = container.setScheduled(path: record.identity.path,
                                                       date: LocalDate.today(in: .current))
                        }
                    } label: {
                        Image(systemName: isScheduledToday ? "star.fill" : "star")
                            .foregroundStyle(isScheduledToday ? Color.yellow : Color.secondary)
                            .font(.system(size: 16))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isScheduledToday ? "Remove from Today" : "Schedule for Today")
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
        .background {
            if isExpanded {
                ThingsSurfaceBackdrop(
                    kind: .elevatedCard,
                    theme: theme,
                    colorScheme: colorScheme
                )
            }
        }
        .padding(.horizontal, isExpanded ? ThingsSurfaceLayout.floatingCardHorizontalInset : 0)
        .padding(.vertical, isExpanded ? ThingsSurfaceLayout.floatingCardVerticalInset : 0)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .zIndex(isExpanded ? 1 : 0)
        .onTapGesture {
            onExpand()
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
        let segments = metadataSegments(for: frontmatter)
        let sourceBadge = TaskSourceAttribution.badge(for: frontmatter.source)
        let metadataText = metadataLine(segments: segments)

        return VStack(alignment: .leading, spacing: 3) {
            Text(frontmatter.title)
                .font(.body)
                .fontWeight(.regular)
                .foregroundStyle(isCompleting ? theme.textSecondaryColor : theme.textPrimaryColor)
                .strikethrough(isCompleting, color: theme.textSecondaryColor)
                .lineLimit(2)

            if sourceBadge != nil || metadataText != nil {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let sourceBadge {
                        TaskRowSourceBadge(badge: sourceBadge)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if let metadataText {
                        metadataText
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(collapsedDetailAccessibilityLabel(badge: sourceBadge, segments: segments))
                .accessibilityChildren {
                    if let sourceBadge {
                        Text(sourceBadge.accessibilityLabel)
                    }
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Text(segment.accessibilityText ?? segment.text)
                    }
                }
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
            ThingsSurfaceBackdrop(
                kind: .inset,
                theme: theme,
                colorScheme: colorScheme
            )
        )
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

    private func metadataLine(segments: [MetadataSegment]) -> Text? {
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
            segments.append(MetadataSegment(text: project, color: theme.textSecondaryColor, accessibilityText: nil))
        } else if let area = frontmatter.area?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !area.isEmpty {
            segments.append(MetadataSegment(text: area, color: theme.textSecondaryColor, accessibilityText: nil))
        }

        if let segment = deadlineSegment(for: frontmatter) {
            segments.append(segment)
        }

        if let completionText = completionDisplayText(for: frontmatter) {
            segments.append(MetadataSegment(text: completionText, color: theme.textSecondaryColor, accessibilityText: nil))
        }

        if let recurrenceText = recurrenceDisplayText(for: frontmatter) {
            segments.append(MetadataSegment(text: recurrenceText, color: theme.textSecondaryColor, accessibilityText: nil))
        }

        segments.append(contentsOf: frontmatter.tags.prefix(2).map {
            MetadataSegment(text: "#\($0)", color: theme.textSecondaryColor, accessibilityText: nil)
        })
        return segments
    }

    private func deadlineSegment(for frontmatter: TaskFrontmatterV1) -> MetadataSegment? {
        guard let due = frontmatter.due else { return nil }
        guard let dueDate = date(from: due, time: nil) else {
            return MetadataSegment(text: due.isoString, color: theme.textSecondaryColor, accessibilityText: due.isoString)
        }

        let today = Calendar.current.startOfDay(for: Date())
        let dueDayStart = Calendar.current.startOfDay(for: dueDate)
        let days = Calendar.current.dateComponents([.day], from: today, to: dueDayStart).day ?? 0

        let dateLabel: String
        if Calendar.current.isDateInToday(dueDate) {
            dateLabel = "today"
        } else {
            dateLabel = dueDisplayText(for: frontmatter) ?? due.isoString
        }

        if days <= 0 {
            // Due today or overdue
            return MetadataSegment(text: "◆ Deadline \(dateLabel)",
                                   color: Color(red: 1.0, green: 0.23, blue: 0.19),
                                   accessibilityText: dateLabel)
        } else if days <= 3 {
            // 1–3 days away
            return MetadataSegment(text: "◆ Deadline \(dateLabel)",
                                   color: Color(red: 1.0, green: 0.62, blue: 0.04),
                                   accessibilityText: dateLabel)
        } else {
            // Far future — plain due text
            return MetadataSegment(text: dueDisplayText(for: frontmatter) ?? due.isoString,
                                   color: isOverdue(frontmatter) ? theme.overdueColor : theme.textSecondaryColor,
                                   accessibilityText: dueDisplayText(for: frontmatter) ?? due.isoString)
        }
    }

    private func metadataAccessibilityLabel(for segments: [MetadataSegment]) -> String {
        segments
            .map { $0.accessibilityText ?? $0.text }
            .joined(separator: ", ")
    }

    private func collapsedDetailAccessibilityLabel(
        badge: TaskSourceAttribution.Badge?,
        segments: [MetadataSegment]
    ) -> String {
        let rawComponents: [String?] = [
            badge?.accessibilityLabel,
            metadataAccessibilityLabel(for: segments)
        ]
        let components: [String] = rawComponents
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return components.joined(separator: ", ")
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

private struct TapOutsideDismissBackdrop: View {
    let fillColor: Color
    let accessibilityIdentifier: String?
    let onDismiss: () -> Void

    init(
        fillColor: Color = Color.black.opacity(0.001),
        accessibilityIdentifier: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.fillColor = fillColor
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onDismiss = onDismiss
    }

    @ViewBuilder
    var body: some View {
        if let accessibilityIdentifier {
            backdropSurface
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            backdropSurface
        }
    }

    private var backdropSurface: some View {
        fillColor
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dismiss")
            .accessibilityAddTraits(.isButton)
            .onTapGesture(perform: onDismiss)
        .ignoresSafeArea()
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
    @State private var checkmarkProgress: CGFloat

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
        _checkmarkProgress = State(initialValue: isCompleted ? 1 : 0)
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
            if completed {
                // Phase 1: fill the circle
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    fillProgress = 1
                }
                // Phase 2: draw the checkmark after fill completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        checkmarkProgress = 1
                    }
                }
            } else {
                // Undo: reset both immediately
                withAnimation(nil) {
                    fillProgress = 0
                    checkmarkProgress = 0
                }
            }
        }
    }

    private var checkboxBody: some View {
        ZStack {
            // Stroke ring (always visible, dashed when in-progress)
            Circle()
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 1.5, dash: isDashed && fillProgress == 0 ? [3, 2] : [])
                )
                .frame(width: 22, height: 22)

            // Filled circle — scales in during phase 1
            Circle()
                .fill(tint)
                .frame(width: 22, height: 22)
                .scaleEffect(fillProgress)
                .opacity(fillProgress)

            // Keep the checkmark centered within the filled circle.
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .opacity(checkmarkProgress)
                .scaleEffect(0.82 + (0.18 * checkmarkProgress))
                .frame(width: 22, height: 22)
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

private struct ProjectProgressRing: View {
    let progress: Double  // 0.0 ... 1.0
    let tint: Color

    var body: some View {
        let isComplete = progress >= 1.0
        let arcColor = isComplete ? Color(.systemGreen) : tint
        ZStack {
            Circle()
                .stroke(Color(.secondarySystemFill), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(arcColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
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
    let accessibilityIdentifier: String?
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeManager

    init(
        title: String,
        isSelected: Bool,
        tint: Color,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.tint = tint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        let button = Button(action: action) {
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

        if let accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }
}

struct IllustratedEmptyState: View {
    let symbol: String
    let glowColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [glowColor, .clear]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 36
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: symbol)
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }
}
