import PhotosUI
import SwiftUI
import SwiftData

private enum EvidenceVerificationPhase: Equatable {
    case verifying
    case completed
    case failed(EvidenceVerdict, String)
}

private struct PixelTaskCompletionBox: View {
    let isComplete: Bool
    let borderColor: Color
    let accessibilityTitle: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(PixelTheme.background.opacity(0.24))
                .offset(x: 2, y: 2)

            Rectangle()
                .fill(isComplete ? PixelTheme.success : PixelTheme.paperRaised)

            Rectangle()
                .stroke(isComplete ? PixelTheme.success : borderColor, lineWidth: PixelTheme.borderWidth)

            if isComplete {
                PixelCheckmark()
                    .fill(Color.white)
                    .padding(size >= 24 ? 4 : 3)
            } else {
                Rectangle()
                    .stroke(PixelTheme.paper.opacity(0.8), lineWidth: 1)
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }
}

/// A chunky grid-built checkmark that stays crisp beside the app's pixel font.
private struct PixelCheckmark: Shape {
    private static let filledCells: [(column: Int, row: Int)] = [
        (6, 0), (7, 0),
        (5, 1), (6, 1), (7, 1),
        (0, 2), (1, 2), (4, 2), (5, 2), (6, 2),
        (0, 3), (1, 3), (2, 3), (3, 3), (4, 3), (5, 3),
        (1, 4), (2, 4), (3, 4), (4, 4),
        (2, 5), (3, 5)
    ]

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width / 8, rect.height / 6)
        let width = unit * 8
        let height = unit * 6
        let originX = rect.midX - width / 2
        let originY = rect.midY - height / 2
        var path = Path()

        for cell in Self.filledCells {
            path.addRect(
                CGRect(
                    x: originX + CGFloat(cell.column) * unit,
                    y: originY + CGFloat(cell.row) * unit,
                    width: unit,
                    height: unit
                )
            )
        }

        return path
    }
}

private struct BountyDeadlineButton: View {
    @Binding var selection: Date
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("截止日期", english: "Deadline"))
                    .font(PixelTheme.font(size: 20))
                    .foregroundStyle(PixelTheme.inkMuted)
                Text(DeadlineDateOptions.displayText(for: selection, relativeTo: .now))
                    .font(PixelTheme.font(size: 29))
                    .foregroundStyle(PixelTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(PixelTheme.font(size: 18))
                    .foregroundStyle(PixelTheme.brown.opacity(0.72))
                    .padding(.trailing, 16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            isExpanded
                ? L10n.text("收起日期选择器", english: "Close the date picker")
                : L10n.text("在页面底部选择日期", english: "Choose a date at the bottom of the page")
        )
    }
}

private struct BountyDeadlinePanel: View {
    @Binding var draftSelection: Date
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(L10n.text("选择截止日期", english: "Choose Deadline"))
                .font(PixelTheme.displayFont(size: 29))
                .foregroundStyle(PixelTheme.ink)

            DeadlineWheelPicker(selection: $draftSelection)

            HStack(spacing: 48) {
                Button(L10n.text("取消", english: "Cancel"), action: onCancel)
                    .buttonStyle(PixelButtonStyle(tone: PixelTheme.brown))
                    .frame(maxWidth: .infinity)

                Button(L10n.text("保存", english: "Save"), action: onSave)
                    .buttonStyle(PixelButtonStyle(tone: PixelTheme.selection))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 34)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(PixelTheme.paper)
        .clipShape(PixelCornerShape(step: 5))
        .overlay {
            PixelCornerShape(step: 5)
                .stroke(PixelTheme.gold.opacity(0.75), lineWidth: 2)
        }
        .shadow(color: PixelTheme.brown.opacity(0.25), radius: 0, x: 5, y: 6)
    }
}

struct ContentView: View {
    @Environment(CloudSyncMonitor.self) private var syncMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    private enum AppPage: String, CaseIterable, Identifiable {
        case create
        case tasks
        case medals

        var id: Self { self }

        var title: String {
            switch self {
            case .create: L10n.text("新任务", english: "New Task")
            case .tasks: L10n.text("任务", english: "Tasks")
            case .medals: L10n.text("成就", english: "Achievements")
            }
        }

        var icon: String {
            switch self {
            case .create: "plus"
            case .tasks: "checklist"
            case .medals: "trophy"
            }
        }
    }

    private enum AchievementTab: String, CaseIterable, Identifiable {
        case medals
        case monsters

        var id: Self { self }

        var title: String {
            switch self {
            case .medals: L10n.text("勋章", english: "Medals")
            case .monsters: L10n.text("怪物图鉴", english: "Monster Atlas")
            }
        }

        var icon: String {
            switch self {
            case .medals: "medal"
            case .monsters: "book.closed"
            }
        }
    }

    private enum CreationPhase {
        case composing
        case reviewing
    }

    private struct TaskChildDraft: Identifiable {
        let id = UUID()
        var title: String
        var taskDescription: String
        var evidenceRequirement: String
        var evidenceImageCount: Int
        var evidenceImageDescriptions: [String]
        var xpReward: Int
        var monsterTag: String?
        var monsterMatchKind: MonsterMatchKind?

        init(_ child: GeneratedTaskChild) {
            title = child.title
            taskDescription = child.taskDescription
            evidenceRequirement = child.evidenceRequirement
            evidenceImageCount = child.evidenceImageCount
            evidenceImageDescriptions = child.evidenceImageDescriptions
            xpReward = child.suggestedXP
            monsterTag = child.monsterTag
            monsterMatchKind = child.monsterMatchKind
        }
    }

    private struct DraftMonsterPreviewRequest: Sendable {
        let key: String
        let descriptor: MonsterDescriptor
        let badgeKind: String
        let level: Int
    }

    private struct EvidenceVerificationPresentation: Equatable {
        let taskID: UUID
        let taskTitle: String
        let xpReward: Int
        let isSubtask: Bool
        let completesTaskGroup: Bool
        var phase: EvidenceVerificationPhase
    }

    private enum TaskCreationInputMode: String, CaseIterable, Identifiable {
        case text
        case image

        var id: Self { self }

        var title: String {
            switch self {
            case .text: L10n.text("文字", english: "Text")
            case .image: L10n.text("图片", english: "Image")
            }
        }

        var icon: String {
            switch self {
            case .text: "text.alignleft"
            case .image: "photo"
            }
        }
    }

    private enum TaskDetailOrigin {
        case taskList
        case badgeHistory(String)

        var backTitle: String {
            switch self {
            case .taskList: L10n.text("返回任务", english: "Back to Tasks")
            case .badgeHistory: L10n.text("返回历史记录", english: "Back to History")
            }
        }
    }

    private enum TaskListTab: String, CaseIterable, Identifiable {
        case unfinished
        case completed
        case overdue

        var id: Self { self }

        var title: String {
            switch self {
            case .unfinished: L10n.text("未完成", english: "Active")
            case .completed: L10n.text("已完成", english: "Completed")
            case .overdue: L10n.text("已逾期", english: "Overdue")
            }
        }

        var icon: String {
            switch self {
            case .unfinished: "circle.dashed"
            case .completed: "checkmark.circle.fill"
            case .overdue: "clock.badge.exclamationmark"
            }
        }

        var tint: Color {
            switch self {
            case .unfinished: PixelTheme.selection
            case .completed: PixelTheme.success
            case .overdue: PixelTheme.danger
            }
        }
    }

    private enum EdgeSwipeDirection: Equatable {
        case towardPrevious
        case towardNext
    }

    private struct TaskRowAction: Identifiable {
        enum Kind: Hashable {
            case delete

            var title: String {
                L10n.text("删除", english: "Delete")
            }

            var icon: String {
                "trash.fill"
            }

            var tint: Color {
                PixelTheme.danger
            }
        }

        let kind: Kind
        let perform: () -> Void

        var id: Kind { kind }
        var title: String { kind.title }
        var icon: String { kind.icon }
        var tint: Color { kind.tint }
    }

    private struct PixelSwipeActionRow<Content: View>: View {
        private let actionWidth: CGFloat = 68
        private let actionSpacing: CGFloat = PixelTheme.space8
        private let actions: [TaskRowAction]
        private let onSelect: () -> Void
        private let content: Content

        @State private var settledOffset: CGFloat = 0
        @GestureState private var dragTranslation: CGFloat = 0

        init(
            actions: [TaskRowAction],
            onSelect: @escaping () -> Void,
            @ViewBuilder content: () -> Content
        ) {
            self.actions = actions
            self.onSelect = onSelect
            self.content = content()
        }

        var body: some View {
            ZStack(alignment: .trailing) {
                HStack(spacing: actionSpacing) {
                    ForEach(actions) { action in
                        pixelActionButton(action)
                    }
                }
                .padding(.horizontal, PixelTheme.space8)
                .opacity(displayedOffset < -4 ? 1 : 0)
                .allowsHitTesting(displayedOffset < -4)
                .zIndex(1)

                content
                    .offset(x: displayedOffset)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if settledOffset < 0 {
                            closeActions()
                        } else {
                            onSelect()
                        }
                    }
                    .simultaneousGesture(dragGesture)
                    .zIndex(0)
            }
            .clipShape(PixelCornerShape())
            .accessibilityAddTraits(.isButton)
        }

        private var revealWidth: CGFloat {
            let buttonsWidth = CGFloat(actions.count) * actionWidth
            let spacingWidth = CGFloat(max(actions.count - 1, 0)) * actionSpacing
            return buttonsWidth + spacingWidth + PixelTheme.space16
        }

        private var displayedOffset: CGFloat {
            min(0, max(-revealWidth, settledOffset + dragTranslation))
        }

        private var dragGesture: some Gesture {
            DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .updating($dragTranslation) { value, translation, _ in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    translation = value.translation.width
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let projectedOffset = settledOffset + value.predictedEndTranslation.width
                    withAnimation(.snappy(duration: 0.24)) {
                        settledOffset = projectedOffset < -(revealWidth * 0.34) ? -revealWidth : 0
                    }
                }
        }

        private func pixelActionButton(_ action: TaskRowAction) -> some View {
            Button {
                closeActions()
                action.perform()
            } label: {
                VStack(spacing: PixelTheme.space4) {
                    Image(systemName: action.icon)
                        .font(PixelTheme.font(size: 18, weight: .bold))

                    Text(action.title)
                        .font(PixelTheme.font(.caption2, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth, height: 58)
                .background {
                    ZStack {
                        PixelCornerShape(step: 3)
                            .fill(PixelTheme.background.opacity(0.9))
                            .offset(x: 3, y: 3)
                        PixelCornerShape(step: 3)
                            .fill(action.tint)
                    }
                }
                .overlay {
                    PixelCornerShape(step: 3)
                        .stroke(PixelTheme.goldBright.opacity(0.9), lineWidth: 2)
                }
                .contentShape(PixelCornerShape(step: 3))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(action.title)
            .help(action.title)
        }

        private func closeActions() {
            withAnimation(.snappy(duration: 0.22)) {
                settledOffset = 0
            }
        }
    }

    private static let badgeOptions = BadgeKind.allCases.map(\.rawValue)

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TaskContract.createdAt, order: .reverse) private var taskContracts: [TaskContract]
    @Query(sort: \BadgeCategory.createdAt) private var badgeCategories: [BadgeCategory]
    @Query(sort: \MonsterDiscovery.discoveredAt) private var monsterDiscoveries: [MonsterDiscovery]

    @AppStorage("pendingTaskInput") private var taskInput = ""
    @State private var selectedPage = AppPage.create
    @State private var creationPhase = CreationPhase.composing
    @State private var creationInputMode = TaskCreationInputMode.text
    @State private var imageTaskNote = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var selectedTask: TaskContract?
    @State private var taskDetailOrigin = TaskDetailOrigin.taskList
    @State private var isEvidenceDeliveryPresented = false
    @State private var isTaskDetailDeadlinePickerPresented = false
    @State private var isTaskFailureDetailPresented = false
    @State private var taskDetailDeadlinePickerSelection = DeadlineDateOptions.defaultSelection()
    @State private var reminderAuthorization = ReminderAuthorizationState.notDetermined
    @State private var reminderFeedback: String?
    @State private var reminderFeedbackIsError = false
    @State private var isReminderStatusDismissed = false
    @GestureState private var reminderBannerTranslation: CGFloat = 0
    @State private var selectedTaskTab = TaskListTab.unfinished
    @State private var taskTabTransitionDirection = EdgeSwipeDirection.towardNext
    /// Absence means expanded, so newly created and synced groups default open.
    @State private var collapsedTaskGroupIDs: Set<UUID> = []
    @State private var selectedLibraryBadge: String?
    @State private var selectedAchievementTab = AchievementTab.medals
    @State private var achievementTabTransitionDirection = EdgeSwipeDirection.towardNext
    @State private var medalAnimationPresentation: XPAwardEvent?
    @State private var deferredMedalAnimationPresentation: XPAwardEvent?
    @State private var evidenceVerificationPresentation: EvidenceVerificationPresentation?
    @State private var monsterRevealPresentation: MonsterDiscoveryEvent?
    @State private var isShowingSettings = false
    @State private var selectedSourcePhoto: PhotosPickerItem?
    @State private var draftSourceImageData: Data?
    @State private var draftContractSourceImageData: Data?
    @State private var isImportingSourceImage = false
    @State private var isSourceCameraPresented = false
    @State private var sourceImageError: String?
    @FocusState private var isTaskInputFocused: Bool

    @State private var draftTitle = ""
    @State private var draftTaskDescription = ""
    @State private var draftDeadline = DeadlineDateOptions.defaultSelection()
    @State private var draftDeadlinePickerSelection = DeadlineDateOptions.defaultSelection()
    @State private var isDeadlinePickerPresented = false
    @State private var draftEvidenceRequirement = ""
    @State private var draftEvidenceImageCount = 1
    @State private var draftEvidenceImageDescriptions: [String] = []
    @State private var draftBadge = BadgeKind.solver.rawValue
    @State private var badgeSwitchDirection = 1
    @State private var draftXP = 10
    @State private var draftChildren: [TaskChildDraft] = []
    @State private var draftMonsterTag: String?
    @State private var draftMonsterMatchKind: MonsterMatchKind?
    @State private var draftMonsterPreviewStates: [String: MonsterDraftPreviewState] = [:]
    @State private var monsterArtworkSyncActivation = 0

    private let generationService = TaskGenerationService()
    private let monsterVariantService = MonsterVariantService()
    private let notificationService = TaskNotificationService()

    var body: some View {
        let _ = locale.identifier
        platformRoot
            .macOSMinimumWindowSize(width: 920, height: 680)
            .preferredColorScheme(.light)
            .tint(PixelTheme.selection)
            .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: selectedPage)
            .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: creationPhase)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: creationInputMode)
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: savedMessage)
            .onAppear {
                notificationService.configureForegroundPresentation()
                migrateLegacySolverCategoriesIfNeeded()
#if DEBUG
                applyDebugLaunchScenario()
#endif
                focusTaskInput()
            }
            .onChange(of: selectedPage) { _, page in
                if page == .create, creationPhase == .composing {
                    focusTaskInput()
                } else {
                    isTaskInputFocused = false
                }
            }
            .onChange(of: reminderAuthorization) { _, _ in
                isReminderStatusDismissed = false
            }
            .onChange(of: reminderFeedback) { _, feedback in
                if feedback != nil {
                    isReminderStatusDismissed = false
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    monsterArtworkSyncActivation += 1
                }
            }
            .task {
                await restoreTaskReminders()
            }
            .task(id: pendingMonsterArtworkSyncKey) {
                await ensureMonsterVariants(for: tasksAwaitingMonsterArtwork)
            }
            .onReceive(NotificationCenter.default.publisher(for: .xpAwarded)) { notification in
                guard let event = notification.object as? XPAwardEvent else { return }
                guard event.currentXP > event.previousXP else { return }
                guard event.previousXP < BadgeRank.silver.cumulativeXPThreshold else { return }

                if evidenceVerificationPresentation != nil || monsterRevealPresentation != nil {
                    deferredMedalAnimationPresentation = event
                } else {
                    withAnimation(.smooth(duration: 0.3)) {
                        medalAnimationPresentation = event
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environment(syncMonitor)
            }
            .iOSFullScreenCover(item: $medalAnimationPresentation) { event in
                MedalAwardAnimationOverlay(event: event) {
                    withAnimation(.smooth(duration: 0.28)) {
                        medalAnimationPresentation = nil
                    }
                }
                .presentationBackground(.clear)
            }
    }

    @ViewBuilder
    private var platformRoot: some View {
#if os(iOS)
        GeometryReader { proxy in
            rootContent(containerSize: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
#else
        rootContent(containerSize: nil)
#endif
    }

    private func rootContent(containerSize: CGSize?) -> some View {
        ZStack {
            PixelBackground()

            navigationLayout(containerSize: containerSize)

            if let savedMessage {
                saveConfirmation(message: savedMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            if let evidenceVerificationPresentation {
                PixelEvidenceVerificationOverlay(
                    phase: evidenceVerificationPresentation.phase,
                    taskTitle: evidenceVerificationPresentation.taskTitle,
                    xpReward: evidenceVerificationPresentation.xpReward,
                    isSubtask: evidenceVerificationPresentation.isSubtask,
                    completesTaskGroup: evidenceVerificationPresentation.completesTaskGroup,
                    onDismissFailure: {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                            self.evidenceVerificationPresentation = nil
                            if selectedTask?.status == .needMoreProof || selectedTask?.status == .notVerified {
                                isTaskFailureDetailPresented = true
                            }
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(15)
            }

            if let monsterRevealPresentation {
                MonsterRevealOverlay(event: monsterRevealPresentation) {
                    finishMonsterReveal(for: monsterRevealPresentation)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(18)
            }

#if os(macOS)
            if let medalAnimationPresentation {
                MedalAwardAnimationOverlay(event: medalAnimationPresentation, containerSize: containerSize) {
                    withAnimation(.smooth(duration: 0.28)) {
                        self.medalAnimationPresentation = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(20)
            }
#endif
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func navigationLayout(containerSize: CGSize?) -> some View {
#if os(iOS)
        let resolvedSize = containerSize ?? .zero
        VStack(spacing: 0) {
            ZStack {
                topLevelPage(.create) {
                    mobileTab(.create, containerSize: resolvedSize) {
                        creationPage
                    }
                }

                topLevelPage(.tasks) {
                    mobileTab(.tasks, containerSize: resolvedSize) {
                        taskListPage
                    }
                }

                topLevelPage(.medals) {
                    mobileTab(.medals, containerSize: resolvedSize) {
                        medalsPage
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            pixelNavigationTabs
                .padding(.horizontal, PixelTheme.space12)
                .padding(.top, PixelTheme.space8)
                .padding(.bottom, PixelTheme.space4)
                .allowsHitTesting(!isDeadlinePickerPresented)
        }
        .frame(width: resolvedSize.width, height: resolvedSize.height)
#else
        VStack(spacing: 0) {
            topNavigation
                .padding(.top, 22)
                .padding(.horizontal, 28)
            pageStack
        }
#endif
    }

#if os(iOS)
    private func mobileTab<Content: View>(
        _ page: AppPage,
        containerSize: CGSize,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ZStack {
            PixelBackground()
            content()
                .frame(width: containerSize.width)
        }
        .frame(width: containerSize.width)
        .overlay(alignment: .leading) {
            if page == .create, creationPhase == .reviewing, !isDeadlinePickerPresented {
                edgeSwipeRegion(direction: .towardPrevious) {
                    returnToTaskComposer()
                }
            } else if page == .tasks || page == .medals {
                edgeSwipeRegion(direction: .towardPrevious) {
                    handleEdgeSwipe(on: page, direction: .towardPrevious)
                }
            }
        }
        .overlay(alignment: .trailing) {
            if page == .tasks || page == .medals {
                edgeSwipeRegion(direction: .towardNext) {
                    handleEdgeSwipe(on: page, direction: .towardNext)
                }
            }
        }
    }

    private func edgeSwipeRegion(
        direction: EdgeSwipeDirection,
        action: @escaping () -> Void
    ) -> some View {
        Color.clear
            .frame(width: 26)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontalDistance = value.translation.width
                        let verticalDistance = value.translation.height
                        guard abs(horizontalDistance) >= 54 else { return }
                        guard abs(horizontalDistance) > abs(verticalDistance) * 1.25 else { return }

                        switch direction {
                        case .towardPrevious where horizontalDistance > 0:
                            action()
                        case .towardNext where horizontalDistance < 0:
                            action()
                        default:
                            break
                        }
                    }
            )
            .accessibilityHidden(true)
    }
#endif

    private func returnToTaskComposer() {
        isDeadlinePickerPresented = false
        withAnimation(.smooth(duration: 0.38)) {
            creationPhase = .composing
        }
        focusTaskInput()
    }

    private var pageStack: some View {
        ZStack {
            topLevelPage(.create) {
                creationPage
            }

            topLevelPage(.tasks) {
                taskListPage
            }

            topLevelPage(.medals) {
                medalsPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topNavigation: some View {
        ZStack {
            HStack {
                HStack(spacing: 10) {
                    Image("LifeMedalsLogo")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    Text("人生勋章")
                        .font(PixelTheme.displayFont(size: 17))
                        .foregroundStyle(PixelTheme.paper)
                }
                .padding(.horizontal, PixelTheme.space16)
                .padding(.vertical, PixelTheme.space8)
                .background {
                    ZStack {
                        PixelCornerShape()
                            .fill(PixelTheme.background)
                            .offset(x: 3, y: 3)
                        PixelCornerShape().fill(PixelTheme.backgroundRaised)
                    }
                }
                .overlay { PixelCornerShape().stroke(PixelTheme.gold, lineWidth: 2) }

                Spacer()

                Button {
                    isShowingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape.fill")
                        .font(PixelTheme.font(.caption, weight: .medium))
                        .foregroundStyle(PixelTheme.paper)
                        .padding(.horizontal, PixelTheme.space12)
                        .padding(.vertical, PixelTheme.space8)
                        .background(PixelTheme.backgroundRaised, in: PixelCornerShape())
                        .overlay { PixelCornerShape().stroke(PixelTheme.gold, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .help("打开设置")
            }

            pixelNavigationTabs
                .frame(width: 390)
        }
        .frame(height: 48)
    }

    private var pixelNavigationTabs: some View {
        PixelTabBar(
            items: AppPage.allCases.map {
                PixelTabItem(id: $0.rawValue, title: $0.title, systemImage: $0.icon)
            },
            selection: selectedPage.rawValue
        ) { rawValue in
            guard let page = AppPage(rawValue: rawValue) else { return }
            selectPage(page)
        }
    }

    // MARK: - Creation flow

    @ViewBuilder
    private var creationPage: some View {
        switch creationPhase {
        case .composing:
            taskComposer
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    )
                )
        case .reviewing:
            contractReview
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    )
                )
        }
    }

    private var taskComposer: some View {
        VStack(spacing: isCompactLayout ? 8 : 16) {
            pageHeader(title: "创建新任务")
                .padding(.horizontal, pageHorizontalInset)
                .padding(.top, isCompactLayout ? 12 : 32)
                .zIndex(10)

            GeometryReader { proxy in
                let maximumPosterWidth = min(max(proxy.size.width, 1), isCompactLayout ? 460 : 700)
                let posterScale = min(maximumPosterWidth / 853, max(proxy.size.height, 1) / 830)
                let posterWidth = 853 * posterScale
                let posterHeight = 830 * posterScale

                taskComposerCard
                    .scaleEffect(posterScale, anchor: .top)
                    .frame(width: posterWidth, height: posterHeight, alignment: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .clipped()
            .zIndex(0)
        }
#if os(iOS)
        .ignoresSafeArea(.keyboard, edges: .bottom)
#endif
        .platformCameraPresentation(isPresented: $isSourceCameraPresented) {
            EvidenceCameraView(
                title: "拍摄任务来源",
                detail: "照片会先压缩，再用于生成任务。"
            ) { sourceData in
                importCapturedSourceImage(sourceData)
            }
        }
        .onChange(of: selectedSourcePhoto) { _, item in
            guard let item else { return }
            Task { await importSourcePhoto(item) }
        }
    }

    /// The supplied artwork uses a full-phone canvas with transparent space
    /// above and below the parchment. Crop that space so the interactive card
    /// stays fixed to the top of the creation page instead of becoming scrollable.
    private var taskComposerCard: some View {
        taskComposerPoster
            .offset(y: -560)
            .frame(width: 853, height: 830, alignment: .top)
            .clipped()
    }

    private var taskComposerPoster: some View {
        ZStack(alignment: .topLeading) {
            Image("TaskComposerBackground")
                .resizable()
                .interpolation(.high)
                .frame(width: 853, height: 1844)
                .accessibilityHidden(true)

            taskComposerModeButtons
                .frame(width: 650, height: 78)
                .position(x: 426, y: 711)

            Group {
                switch creationInputMode {
                case .text:
                    posterTextTaskComposer
                case .image:
                    posterImageTaskComposer
                }
            }
            .frame(width: 620, height: 410)
            .position(x: 426, y: 1007)
            .transition(.opacity.combined(with: .scale(scale: 0.99)))

            posterGenerationButton
                .frame(width: 245, height: 66)
                .position(x: 620, y: 1298)
        }
        .frame(width: 853, height: 1844)
    }

    private var taskComposerModeButtons: some View {
        HStack(spacing: 8) {
            ForEach(TaskCreationInputMode.allCases) { mode in
                Button {
                    selectCreationInputMode(mode)
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(creationInputMode == mode ? PixelTheme.selection : PixelTheme.inkMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if creationInputMode == mode {
                                PixelCornerShape(step: 3)
                                    .fill(PixelTheme.goldBright.opacity(0.13))
                                    .padding(4)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(creationInputMode == mode ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("任务生成方式", english: "Task creation method"))
    }

    private var posterTextTaskComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                L10n.text("例如：本周完成三次 30 分钟跑步", english: "For example: Run for 30 minutes three times this week"),
                text: $taskInput,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(PixelTheme.font(size: 40, weight: .medium))
            .foregroundStyle(PixelTheme.ink)
            .lineLimit(3...6)
            .focused($isTaskInputFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityLabel(L10n.text("输入你想完成的任务", english: "Enter the task you want to complete"))
#if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.text("完成", english: "Done")) {
                        isTaskInputFocused = false
                    }
                }
            }
#endif
            .onSubmit(generateTask)

            generationError
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var posterImageTaskComposer: some View {
        VStack(spacing: 10) {
            if let draftSourceImageData {
                HStack(alignment: .top, spacing: 16) {
                    PlatformImageView(data: draftSourceImageData)
                        .scaledToFit()
                        .frame(width: 210, height: 220)
                        .clipShape(PixelCornerShape(step: 3))
                        .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.gold.opacity(0.72), lineWidth: 2) }
                        .overlay(alignment: .topTrailing) {
                            Button(action: removeSourceImage) {
                                Image(systemName: "xmark")
                                    .font(PixelTheme.font(size: 18))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(PixelTheme.danger, in: PixelCornerShape(step: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("移除任务来源图片", english: "Remove source image"))
                            .padding(8)
                        }

                    TextField(
                        L10n.text("补充说明（可选）", english: "Additional notes (optional)"),
                        text: $imageTaskNote,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(PixelTheme.font(size: 36))
                    .foregroundStyle(PixelTheme.ink)
                    .lineLimit(4...7)
                    .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
                    .accessibilityLabel(L10n.text("图片补充说明", english: "Image notes"))
                    .onSubmit(generateTask)
                }
            } else {
                VStack(spacing: 16) {
                    if isImportingSourceImage {
                        ProgressView()
                            .controlSize(.regular)
                        Text(L10n.text("正在压缩照片…", english: "Compressing photo…"))
                            .font(PixelTheme.font(size: 30))
                            .foregroundStyle(PixelTheme.inkMuted)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 54, weight: .medium))
                                .foregroundStyle(PixelTheme.gold)
                            Text(L10n.text("上传邮件、syllabus 或活动海报", english: "Upload an email, syllabus, or event poster"))
                                .font(PixelTheme.font(size: 32))
                                .foregroundStyle(PixelTheme.inkMuted)
                                .multilineTextAlignment(.center)
                        }
                    }

                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedSourcePhoto, matching: .images) {
                            posterSourceButtonLabel(
                                title: L10n.text("照片图库", english: "Photo Library"),
                                systemImage: "photo.on.rectangle"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isImportingSourceImage)

                        Button {
                            isSourceCameraPresented = true
                        } label: {
                            posterSourceButtonLabel(
                                title: L10n.text("拍照", english: "Camera"),
                                systemImage: "camera"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isImportingSourceImage)
                    }
                    .frame(height: 160)
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let sourceImageError {
                Text(L10n.text(sourceImageError))
                    .font(PixelTheme.font(size: 20))
                    .foregroundStyle(PixelTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            generationError
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func posterSourceButtonLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .medium))
            Text(title)
                .font(PixelTheme.font(size: 29))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(PixelTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PixelTheme.paperRaised.opacity(0.72), in: PixelCornerShape(step: 3))
        .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.gold.opacity(0.75), lineWidth: 2) }
        .contentShape(Rectangle())
    }

    private var posterGenerationButton: some View {
        Button(action: generateTask) {
            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView()
                        .tint(PixelTheme.goldBright)
                } else {
                    Image(systemName: errorMessage == nil ? "wand.and.stars" : "arrow.clockwise")
                        .font(.system(size: 30, weight: .semibold))
                }
                Text(buttonTitle)
                    .font(PixelTheme.displayFont(size: 38))
            }
            .foregroundStyle(Color(red: 0.88, green: 0.75, blue: 0.48))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || isImportingSourceImage || !canGenerateTask)
        .opacity(isGenerating || isImportingSourceImage || !canGenerateTask ? 0.48 : 1)
    }

    @ViewBuilder
    private var generationError: some View {
        if let errorMessage {
            Text(L10n.text(errorMessage))
                .font(PixelTheme.font(size: 20))
                .foregroundStyle(PixelTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var contractReview: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            contractReview(now: context.date)
        }
    }

    private func contractReview(now: Date) -> some View {
        GeometryReader { proxy in
            let posterWidth = min(
                max(proxy.size.width - bountyPosterHorizontalInset * 2, 1),
                700
            )
            let posterScale = posterWidth / 848

            ScrollViewReader { scrollProxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 0) {
                            bountyPoster(now: now)
                                .frame(width: 848, height: 1855)
                                .scaleEffect(posterScale, anchor: .top)
                                .frame(width: posterWidth, height: 1855 * posterScale, alignment: .top)
                                .frame(maxWidth: .infinity)

                            Color.clear
                                .frame(height: 1)
                                .id("bounty-poster-bottom")
                        }
                        .padding(.bottom, isCompactLayout ? 8 : 28)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDisabled(isDeadlinePickerPresented)
                    .allowsHitTesting(!isDeadlinePickerPresented)

                    if isDeadlinePickerPresented {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .transition(.opacity)

                        BountyDeadlinePanel(
                            draftSelection: $draftDeadlinePickerSelection,
                            onCancel: dismissDeadlinePicker,
                            onSave: saveDeadlinePicker
                        )
                        .frame(width: posterWidth)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .onChange(of: isDeadlinePickerPresented) { _, isPresented in
                    guard isPresented else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.34)) {
                        scrollProxy.scrollTo("bounty-poster-bottom", anchor: .bottom)
                    }
                }
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.34),
                    value: isDeadlinePickerPresented
                )
            }
        }
        .task(id: draftMonsterPreviewKey) {
            await refreshDraftMonsterPreviews()
        }
    }

    private func bountyPoster(now _: Date) -> some View {
        ZStack(alignment: .topLeading) {
            Image("BountyContractBackground")
                .resizable()
                .interpolation(.high)
                .frame(width: 848, height: 1855)
                .accessibilityHidden(true)

            bountyTitleField
                .frame(width: 590, height: 116)
                .position(x: 432, y: 184)

            bountyMonsterField
                .frame(width: 440, height: 465)
                .position(x: 424, y: 552)

            bountyBadgeField
                .frame(width: 300, height: 294)
                .position(x: 258, y: 995)

            BountyDeadlineButton(
                selection: $draftDeadline,
                isExpanded: isDeadlinePickerPresented,
                action: toggleDeadlinePicker
            )
            .frame(width: 306, height: 126)
            .position(x: 592, y: 911)

            bountyXPField
                .frame(width: 306, height: 126)
                .position(x: 592, y: 1074)

            bountyDescriptionField
                .frame(width: 660, height: 210)
                .position(x: 424, y: 1305)

            bountyEvidenceField
                .frame(width: 660, height: 160)
                .position(x: 424, y: 1544)

            bountySaveButton
                .frame(width: 490, height: 88)
                .position(x: 424, y: 1715)

            if let errorMessage {
                Text(errorMessage)
                    .font(PixelTheme.font(size: 18))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .frame(width: 610, height: 48)
                    .background(PixelTheme.danger.opacity(0.94), in: PixelCornerShape(step: 3))
                    .position(x: 424, y: 1642)
            }
        }
        .frame(width: 848, height: 1855)
    }

    private var bountyTitleField: some View {
        TextField(
            isDraftTaskGroup
                ? L10n.text("主任务标题", english: "Main Task Title")
                : L10n.text("任务标题", english: "Task Title"),
            text: $draftTitle,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(PixelTheme.displayFont(size: 42))
        .foregroundStyle(PixelTheme.ink)
        .multilineTextAlignment(.center)
        .lineLimit(1...2)
        .minimumScaleFactor(0.72)
        .onChange(of: draftTitle) { _, newValue in
            if !newValue.isEmpty, !TaskTitleRules.isValid(newValue) {
                draftTitle = TaskTitleRules.limited(newValue)
            }
        }
        .accessibilityLabel(L10n.text("任务标题", english: "Task title"))
    }

    @ViewBuilder
    private var bountyMonsterField: some View {
        if isDraftTaskGroup {
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(draftChildren) { child in
                        VStack(spacing: 4) {
                            MonsterArtworkView(
                                imageURL: draftMonsterReadyImageURL(for: child.id.uuidString),
                                isDiscovered: true
                            )
                            .frame(height: 156)

                            Text(child.title)
                                .font(PixelTheme.font(size: 20))
                                .foregroundStyle(PixelTheme.ink)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(16)
        } else {
            VStack(spacing: 2) {
                MonsterArtworkView(
                    imageURL: draftMonsterReadyImageURL(for: "single"),
                    isDiscovered: true
                )
                .padding(.horizontal, 24)

                Text(MonsterTaxonomy.categoryLabel(for: singleDraftMonsterDescriptor.canonicalTag))
                    .font(PixelTheme.displayFont(size: 25))
                    .foregroundStyle(PixelTheme.ink)
                    .lineLimit(1)
            }
            .padding(.vertical, 14)
        }
    }

    private var bountyBadgeField: some View {
        VStack(spacing: 2) {
            Text(L10n.text("所属勋章", english: "Medal"))
                .font(PixelTheme.font(size: 18))
                .foregroundStyle(PixelTheme.inkMuted)

            HStack(spacing: 4) {
                badgeCycleButton(systemImage: "chevron.left", offset: -1)

                Button {
                    switchBadge(by: 1)
                } label: {
                    MedalArtworkView(categoryName: draftBadge, rank: badgeRank(for: draftBadge))
                        .frame(width: 176, height: 176)
                        .contentShape(Rectangle())
                        .phaseAnimator([false, true, false], trigger: draftBadge) { content, highlighted in
                            content
                                .scaleEffect(highlighted ? 1.08 : 1)
                                .rotation3DEffect(
                                    .degrees(highlighted ? Double(badgeSwitchDirection * 10) : 0),
                                    axis: (x: 0, y: 1, z: 0)
                                )
                                .brightness(highlighted ? 0.1 : 0)
                        } animation: { highlighted in
                            reduceMotion ? nil : .spring(response: highlighted ? 0.2 : 0.32, dampingFraction: 0.58)
                        }
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(PixelTheme.goldBright)
                                .symbolEffect(.bounce, value: draftBadge)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("切换所属勋章", english: "Change medal"))

                badgeCycleButton(systemImage: "chevron.right", offset: 1)
            }

            Text(badgeDisplayName(draftBadge))
                .font(PixelTheme.displayFont(size: 26))
                .foregroundStyle(PixelTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    let horizontalTravel = value.predictedEndTranslation.width
                    guard abs(horizontalTravel) > 45 else { return }
                    switchBadge(by: horizontalTravel < 0 ? 1 : -1)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityHint(L10n.text("左右滑动或点击切换勋章", english: "Swipe or tap to change medal"))
    }

    private func badgeCycleButton(systemImage: String, offset: Int) -> some View {
        Button {
            switchBadge(by: offset)
        } label: {
            Image(systemName: systemImage)
                .font(PixelTheme.font(size: 20))
                .foregroundStyle(PixelTheme.brown.opacity(0.78))
                .frame(width: 44, height: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            offset < 0
                ? L10n.text("上一个勋章", english: "Previous medal")
                : L10n.text("下一个勋章", english: "Next medal")
        )
    }

    private var bountyXPField: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text("完成奖励", english: "Reward"))
                .font(PixelTheme.font(size: 19))
                .foregroundStyle(PixelTheme.inkMuted)
            Text("+\(draftXP) EXP")
                .font(PixelTheme.statFont(size: 35))
                .foregroundStyle(PixelTheme.brown)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func switchBadge(by offset: Int) {
        guard let currentIndex = Self.badgeOptions.firstIndex(of: draftBadge) else { return }
        let count = Self.badgeOptions.count
        let nextIndex = (currentIndex + offset + count) % count
        badgeSwitchDirection = offset < 0 ? -1 : 1
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0.24)) {
            draftBadge = Self.badgeOptions[nextIndex]
        }
    }

    private func toggleDeadlinePicker() {
        if isDeadlinePickerPresented {
            dismissDeadlinePicker()
            return
        }

        draftDeadlinePickerSelection = DeadlineDateOptions.normalized(draftDeadline, relativeTo: .now)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.34)) {
            isDeadlinePickerPresented = true
        }
    }

    private func dismissDeadlinePicker() {
        draftDeadlinePickerSelection = DeadlineDateOptions.normalized(draftDeadline, relativeTo: .now)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            isDeadlinePickerPresented = false
        }
    }

    private func saveDeadlinePicker() {
        draftDeadline = DeadlineDateOptions.normalized(draftDeadlinePickerSelection, relativeTo: .now)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            isDeadlinePickerPresented = false
        }
    }

    @ViewBuilder
    private var bountyDescriptionField: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("任务说明", english: "Task Description"))
                    .font(PixelTheme.font(size: 20))
                    .foregroundStyle(PixelTheme.inkMuted)

                if isDraftTaskGroup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(
                                L10n.text("主任务说明（可选）", english: "Main task details (optional)"),
                                text: $draftTaskDescription,
                                axis: .vertical
                            )
                            .lineLimit(1...3)

                            ForEach($draftChildren) { $child in
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField(
                                        L10n.text("子任务标题", english: "Subtask title"),
                                        text: $child.title,
                                        axis: .vertical
                                    )
                                    .font(PixelTheme.font(size: 24))
                                    .onChange(of: child.title) { _, newValue in
                                        if !newValue.isEmpty, !TaskTitleRules.isValid(newValue) {
                                            child.title = TaskTitleRules.limited(newValue)
                                        }
                                    }

                                    TextField(
                                        L10n.text("任务说明（可选）", english: "Task details (optional)"),
                                        text: $child.taskDescription,
                                        axis: .vertical
                                    )
                                    .font(PixelTheme.font(size: 20))
                                    .foregroundStyle(PixelTheme.inkMuted)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                } else {
                    TextField(
                        L10n.text("补充任务的具体内容（可选）", english: "Add task details (optional)"),
                        text: $draftTaskDescription,
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                }
            }
            .textFieldStyle(.plain)
            .font(PixelTheme.font(size: 25))
            .foregroundStyle(PixelTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let draftContractSourceImageData {
                PlatformImageView(data: draftContractSourceImageData)
                    .scaledToFit()
                    .frame(width: 108, height: 108)
                    .clipShape(PixelCornerShape(step: 3))
                    .accessibilityLabel(L10n.text("任务来源图片", english: "Task source image"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var bountyEvidenceField: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L10n.text("提交照片", english: "Evidence Photos"))
                    .font(PixelTheme.font(size: 20))
                    .foregroundStyle(PixelTheme.inkMuted)
                Spacer()
                Text(L10n.text("\(posterEvidencePhotoCount) 张", english: "\(posterEvidencePhotoCount) photo(s)"))
                    .font(PixelTheme.font(size: 20))
                    .foregroundStyle(PixelTheme.brown)
            }

            if isDraftTaskGroup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach($draftChildren) { $child in
                            TextField(
                                child.title,
                                text: $child.evidenceRequirement,
                                axis: .vertical
                            )
                            .lineLimit(1...2)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                TextField(
                    L10n.text("写明完成任务时需要拍到什么", english: "Describe what the completion photos must show"),
                    text: $draftEvidenceRequirement,
                    axis: .vertical
                )
                .lineLimit(2...3)
            }
        }
        .textFieldStyle(.plain)
        .font(PixelTheme.font(size: 23))
        .foregroundStyle(PixelTheme.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var bountySaveButton: some View {
        Button(action: saveTask) {
            Label(L10n.text("确认并保存", english: "Confirm & Save"), systemImage: "checkmark")
                .font(PixelTheme.displayFont(size: 31))
                .foregroundStyle(Color(red: 0.88, green: 0.75, blue: 0.48))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSaveDraft)
        .opacity(canSaveDraft ? 1 : 0.45)
    }

    private var posterEvidencePhotoCount: Int {
        if isDraftTaskGroup {
            return draftChildren.reduce(0) { $0 + $1.evidenceImageCount }
        }
        return draftEvidenceImageCount
    }

    private func draftMonsterReadyImageURL(for key: String) -> String? {
        guard let snapshot = draftMonsterSnapshot(for: key), snapshot.status == .ready else { return nil }
        return snapshot.imageURL
    }

    private var taskTitleContractField: some View {
        let fieldTitle = isDraftTaskGroup
            ? L10n.text("主任务标题", english: "Main task title")
            : L10n.text("任务标题", english: "Task title")
        return contractField(fieldTitle) {
            TextField(fieldTitle, text: $draftTitle)
                .textFieldStyle(.plain)
                .font(PixelTheme.font(.title3, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(PixelTheme.paperRaised, in: PixelCornerShape())
                .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
                .onChange(of: draftTitle) { _, newValue in
                    if !newValue.isEmpty, !TaskTitleRules.isValid(newValue) {
                        draftTitle = TaskTitleRules.limited(newValue)
                    }
                }

            Text(TaskTitleRules.limitDescription(for: draftTitle))
                .font(PixelTheme.font(.caption2))
                .foregroundStyle(PixelTheme.inkMuted)
        }
    }

    private var taskDescriptionContractField: some View {
        contractField(L10n.text("任务说明", english: "Task description")) {
            TextField(
                L10n.text("补充任务的具体内容（可选）", english: "Add task details (optional)"),
                text: $draftTaskDescription,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(PixelTheme.font(.body))
            .lineLimit(3...7)
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(PixelTheme.paperRaised, in: PixelCornerShape())
            .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
        }
    }

    private var xpContractField: some View {
        contractField("完成奖励") {
            Label("+\(draftXP) EXP", systemImage: "sparkles")
                .font(PixelTheme.font(.title3, weight: .bold))
                .foregroundStyle(PixelTheme.brown)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PixelTheme.paperRaised, in: PixelCornerShape())
                .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
        }
    }

    private var badgeContractField: some View {
        contractField("所属勋章") {
            VStack(spacing: PixelTheme.space8) {
                MedalArtworkView(categoryName: draftBadge, rank: badgeRank(for: draftBadge))
                    .frame(width: 108, height: 108)
                    .clipped()

                Picker(L10n.text("所属勋章", english: "Medal"), selection: $draftBadge) {
                    ForEach(Self.badgeOptions, id: \.self) { badge in
                        Text(badgeDisplayName(badge)).tag(badge)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel(L10n.text("选择所属勋章", english: "Choose medal category"))
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 144)
            .background(PixelTheme.paperRaised, in: PixelCornerShape())
            .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
        }
    }

    private var draftMonsterContractField: some View {
        contractField(L10n.text("任务怪物", english: "Task Monster")) {
            MonsterDraftPreviewCard(
                descriptor: singleDraftMonsterDescriptor,
                level: draftMonsterLevel,
                state: draftMonsterPreviewStates["single"] ?? .loading
            )
        }
    }

    private var draftMonsterLevel: Int {
        badgeRank(for: draftBadge).rawValue
    }

    private var singleDraftMonsterDescriptor: MonsterDescriptor {
        MonsterTaxonomy.descriptor(
            canonicalTag: draftMonsterTag,
            matchKind: draftMonsterMatchKind,
            fallbackText: "\(draftTitle) \(draftEvidenceRequirement)",
            badgeKind: draftBadge
        )
    }

    private func monsterDescriptor(for child: TaskChildDraft) -> MonsterDescriptor {
        MonsterTaxonomy.descriptor(
            canonicalTag: child.monsterTag,
            matchKind: child.monsterMatchKind,
            fallbackText: "\(child.title) \(child.evidenceRequirement)",
            badgeKind: draftBadge
        )
    }

    private var draftMonsterPreviewRequests: [DraftMonsterPreviewRequest] {
        if isDraftTaskGroup {
            return draftChildren.map { child in
                DraftMonsterPreviewRequest(
                    key: child.id.uuidString,
                    descriptor: monsterDescriptor(for: child),
                    badgeKind: draftBadge,
                    level: draftMonsterLevel
                )
            }
        }
        return [
            DraftMonsterPreviewRequest(
                key: "single",
                descriptor: singleDraftMonsterDescriptor,
                badgeKind: draftBadge,
                level: draftMonsterLevel
            )
        ]
    }

    private var draftMonsterPreviewKey: String {
        draftMonsterPreviewRequests
            .map { "\($0.key):\($0.descriptor.canonicalTag):\($0.level)" }
            .joined(separator: "|")
    }

    @MainActor
    private func refreshDraftMonsterPreviews() async {
        let requests = draftMonsterPreviewRequests
        draftMonsterPreviewStates = Dictionary(
            uniqueKeysWithValues: requests.map { ($0.key, MonsterDraftPreviewState.loading) }
        )

        for request in requests {
            guard !Task.isCancelled else { return }
            do {
                let snapshot = try await monsterVariantService.ensureVariant(
                    canonicalTag: request.descriptor.canonicalTag,
                    badgeKind: request.badgeKind,
                    level: request.level
                )
                guard !Task.isCancelled else { return }
                draftMonsterPreviewStates[request.key] = .variant(snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                draftMonsterPreviewStates[request.key] = .unavailable
            }
        }

        for _ in 0..<MonsterVariantPollingPolicy.maxAttempts {
            let pending = requests.filter { request in
                guard case let .variant(snapshot) = draftMonsterPreviewStates[request.key] else { return false }
                return snapshot.status == .pending || snapshot.status == .generating
            }
            guard !pending.isEmpty, !Task.isCancelled else { return }

            do {
                try await Task.sleep(for: .seconds(MonsterVariantPollingPolicy.intervalSeconds))
            } catch {
                return
            }

            for request in pending {
                guard !Task.isCancelled else { return }
                guard let snapshot = try? await monsterVariantService.fetchVariant(
                    canonicalTag: request.descriptor.canonicalTag,
                    level: request.level
                ) else { continue }
                draftMonsterPreviewStates[request.key] = .variant(snapshot)
            }
        }
    }

    private func draftMonsterSnapshot(for key: String) -> MonsterVariantSnapshot? {
        guard case let .variant(snapshot) = draftMonsterPreviewStates[key] else { return nil }
        return snapshot
    }

    private var deadlineContractField: some View {
        contractField("截止日期") {
            DeadlinePickerField(selection: $draftDeadline)
        }
    }

    // MARK: - Task list

    @ViewBuilder
    private var taskListPage: some View {
        if let selectedTask {
            taskDetailPage(selectedTask)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    )
                )
        } else {
            taskListRoot
        }
    }

    private var taskListRoot: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            taskListRoot(now: context.date)
        }
    }

    private func taskListRoot(now: Date) -> some View {
        let unfinishedTasks = tasks(in: .unfinished, now: now)
        let completedTasks = tasks(in: .completed, now: now)
        let overdueTasks = tasks(in: .overdue, now: now)
        let selectedTasks = switch selectedTaskTab {
        case .unfinished: unfinishedTasks
        case .completed: completedTasks
        case .overdue: overdueTasks
        }

        return VStack(spacing: 0) {
            taskListHeader(
                unfinishedCount: unfinishedTasks.count,
                completedCount: completedTasks.count,
                overdueCount: overdueTasks.count
            )
            .padding(.top, 24)
            .padding(.horizontal, pageHorizontalInset)
            .padding(.bottom, 12)

            ZStack {
                taskListContent(tasks: selectedTasks, now: now)
                    .id(selectedTaskTab)
                    .transition(horizontalTabTransition(direction: taskTabTransitionDirection))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private func taskListContent(tasks selectedTasks: [TaskContract], now: Date) -> some View {
        List {
            if selectedTasks.isEmpty {
                taskListEmptyState(for: selectedTaskTab)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalInset, bottom: 28, trailing: pageHorizontalInset))
            } else {
                ForEach(selectedTasks) { task in
                    let actions = taskRowActions(for: task)
                    if task.isTaskGroup {
                        adaptiveTaskGroupRow(
                            task: task,
                            now: now,
                            actions: actions,
                            onSelect: { toggleTaskGroup(task) }
                        )
                        .clipShape(PixelCornerShape())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 7, leading: pageHorizontalInset, bottom: 7, trailing: pageHorizontalInset))

                        if !collapsedTaskGroupIDs.contains(task.id) {
                            ForEach(children(of: task)) { child in
                                adaptiveTaskRow(
                                    task: child,
                                    now: now,
                                    actions: taskRowActions(for: child),
                                    onSelect: { openTask(child) }
                                )
                                .clipShape(PixelCornerShape())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 5,
                                        leading: pageHorizontalInset + (isCompactLayout ? 24 : 38),
                                        bottom: 5,
                                        trailing: pageHorizontalInset
                                    )
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    } else {
                        adaptiveTaskRow(
                            task: task,
                            now: now,
                            actions: actions,
                            onSelect: { openTask(task) }
                        )
                            .clipShape(PixelCornerShape())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 7, leading: pageHorizontalInset, bottom: 7, trailing: pageHorizontalInset))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func taskListHeader(
        unfinishedCount: Int,
        completedCount: Int,
        overdueCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader(
                title: "任务",
                subtitle: isCompactLayout
                    ? nil
                    : activeTaskContracts.isEmpty
                        ? "你保存的任务契约会出现在这里。"
                        : L10n.text(
                            "\(unfinishedCount) 项未完成 · \(completedCount) 项已完成 · \(overdueCount) 项已逾期，全部保存在这台设备上。",
                            english: "\(unfinishedCount) active · \(completedCount) completed · \(overdueCount) overdue. All are saved on this device."
                        )
            )

            taskListTabs(
                unfinishedCount: unfinishedCount,
                completedCount: completedCount,
                overdueCount: overdueCount
            )

            reminderStatusBanner
        }
        .frame(maxWidth: 790, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func taskListTabs(
        unfinishedCount: Int,
        completedCount: Int,
        overdueCount: Int
    ) -> some View {
        HStack(spacing: PixelTheme.space4) {
                ForEach(TaskListTab.allCases) { tab in
                    let count = switch tab {
                    case .unfinished: unfinishedCount
                    case .completed: completedCount
                    case .overdue: overdueCount
                    }

                    Button {
                        selectTaskTab(tab)
                    } label: {
                        Group {
                            if isCompactLayout {
                                HStack(spacing: 5) {
                                    Text(tab.title)
                                    Text("\(count)")
                                        .font(PixelTheme.font(.caption2, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            selectedTaskTab == tab ? PixelTheme.paperRaised.opacity(0.22) : PixelTheme.brown.opacity(0.2),
                                            in: PixelCornerShape(step: 2)
                                        )
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: tab.icon)
                                    Text(tab.title)
                                    Text("\(count)")
                                        .font(PixelTheme.font(.caption, weight: .bold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(
                                            selectedTaskTab == tab ? PixelTheme.paperRaised.opacity(0.22) : PixelTheme.brown.opacity(0.2),
                                            in: PixelCornerShape(step: 2)
                                        )
                                }
                            }
                        }
                        .font(PixelTheme.font(isCompactLayout ? .caption : .subheadline, weight: selectedTaskTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTaskTab == tab ? Color.white : PixelTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .contentShape(PixelCornerShape(step: 3))
                    }
                    .buttonStyle(.plain)
                    .background(
                        selectedTaskTab == tab ? tab.tint : PixelTheme.paperRaised,
                        in: PixelCornerShape(step: 3)
                    )
                    .overlay { PixelCornerShape(step: 3).stroke(selectedTaskTab == tab ? PixelTheme.goldBright : PixelTheme.gold.opacity(0.55), lineWidth: selectedTaskTab == tab ? 2 : 1) }
                    .accessibilityLabel("\(tab.title)，\(count) 项")
                    .accessibilityAddTraits(selectedTaskTab == tab ? .isSelected : [])
                }
            }
        .padding(PixelTheme.space4)
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
    }

    @ViewBuilder
    private func taskListEmptyState(for tab: TaskListTab) -> some View {
        if activeTaskContracts.isEmpty {
            emptyState(icon: "checklist", title: "还没有任务", message: "从“新任务”开始写下第一件想完成的事。")
        } else {
            switch tab {
            case .unfinished:
                emptyState(icon: tab.icon, title: "没有未完成任务", message: "当前没有仍在截止时间内、需要继续处理的任务。")
            case .completed:
                emptyState(icon: tab.icon, title: "还没有已完成任务", message: "任务通过证据核验后，会出现在这里。")
            case .overdue:
                emptyState(icon: tab.icon, title: "没有已逾期任务", message: "很好，所有未完成任务都还在截止时间内。")
            }
        }
    }

    private func taskRow(_ task: TaskContract, now: Date) -> some View {
        HStack(spacing: isCompactLayout ? 12 : 16) {
            taskMonsterThumbnail(for: task)
            .frame(width: isCompactLayout ? 44 : 52, height: isCompactLayout ? 44 : 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(task.title))
                    .font(PixelTheme.font(.headline))
                    .foregroundStyle(PixelTheme.ink)
                    .lineLimit(2)
                if isCompactLayout {
                    Label(
                        deadlineDisplayText(task.deadline, relativeTo: now),
                        systemImage: task.deadline <= now ? "clock.badge.exclamationmark" : "clock"
                    )
                    .lineLimit(1)
                } else {
                    HStack(spacing: 7) {
                        Label(
                            deadlineDisplayText(task.deadline, relativeTo: now),
                            systemImage: task.deadline <= now ? "clock.badge.exclamationmark" : "clock"
                        )
                        Text("·")
                        Text(
                            task.badgeCategory.map { badgeDisplayName($0.name) }
                                ?? L10n.text("未分类", english: "Uncategorized")
                        )
                    }
                }
            }
            .font(PixelTheme.font(.caption))
            .foregroundStyle(task.deadline <= now && task.status != .verified ? PixelTheme.danger : PixelTheme.inkMuted)

            Spacer()

            VStack(alignment: .trailing, spacing: 9) {
                taskListCompletionBox(for: task, now: now)
                Text(
                    task.isSubtask
                        ? L10n.text("任务组奖励", english: "Group reward")
                        : "+\(task.xpReward) EXP"
                )
                    .font(PixelTheme.font(.subheadline, weight: .bold))
                    .foregroundStyle(PixelTheme.brown)
                if !isCompactLayout {
                    Image(systemName: "chevron.right")
                        .font(PixelTheme.font(.caption, weight: .semibold))
                        .foregroundStyle(PixelTheme.inkMuted.opacity(0.7))
                }
            }
        }
        .padding(isCompactLayout ? 14 : 18)
        .foregroundStyle(PixelTheme.ink)
        .contentShape(PixelCornerShape())
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
        .accessibilityHint("查看任务契约详情")
    }

    private func taskGroupRow(_ task: TaskContract, now: Date) -> some View {
        let childTasks = children(of: task)
        let completedCount = childTasks.filter { $0.status == .verified }.count
        let isExpanded = !collapsedTaskGroupIDs.contains(task.id)
        let middleLayerOffset: CGFloat = isExpanded ? 0 : 5
        let backLayerOffset: CGFloat = isExpanded ? 0 : 10

        return ZStack {
            PixelCornerShape()
                .fill(PixelTheme.background.opacity(0.92))
                .offset(x: PixelTheme.shadowOffset, y: PixelTheme.shadowOffset)
                .opacity(isExpanded ? 1 : 0)
                .accessibilityHidden(true)

            taskGroupStackLayer(fill: PixelTheme.paper.opacity(0.72), borderOpacity: 0.45)
                .offset(x: backLayerOffset, y: backLayerOffset)
                .opacity(isExpanded ? 0 : 1)

            taskGroupStackLayer(fill: PixelTheme.paperRaised.opacity(0.88), borderOpacity: 0.68)
                .offset(x: middleLayerOffset, y: middleLayerOffset)
                .opacity(isExpanded ? 0 : 1)

            HStack(spacing: isCompactLayout ? 10 : 14) {
                taskMonsterThumbnail(for: task)
                .frame(width: isCompactLayout ? 42 : 50, height: isCompactLayout ? 42 : 50)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(task.title))
                        .font(PixelTheme.font(.headline))
                        .foregroundStyle(PixelTheme.ink)
                        .lineLimit(3)
                        .layoutPriority(1)

                    Label(
                        deadlineDisplayText(task.deadline, relativeTo: now),
                        systemImage: task.deadline <= now && task.status != .verified
                            ? "clock.badge.exclamationmark"
                            : "clock"
                    )
                    .font(PixelTheme.font(.caption))
                    .foregroundStyle(
                        task.deadline <= now && task.status != .verified
                            ? PixelTheme.danger
                            : PixelTheme.inkMuted
                    )
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 7) {
                    Text("\(completedCount)/\(childTasks.count)")
                        .font(PixelTheme.statFont(size: isCompactLayout ? 14 : 16))
                        .foregroundStyle(task.status == .verified ? PixelTheme.success : PixelTheme.selection)
                    taskListCompletionBox(for: task, now: now)
                    if !isCompactLayout {
                        Text("+\(task.xpReward) EXP")
                            .font(PixelTheme.font(.caption, weight: .bold))
                            .foregroundStyle(PixelTheme.brown)
                    }
                }
            }
            .padding(isCompactLayout ? 14 : 18)
            .foregroundStyle(PixelTheme.ink)
            .background(PixelTheme.paper, in: PixelCornerShape())
            .overlay {
                PixelCornerShape()
                    .stroke(PixelTheme.gold, lineWidth: PixelTheme.borderWidth)
            }
            .overlay {
                PixelCornerShape(step: 2)
                    .stroke(PixelTheme.paperRaised.opacity(0.42), lineWidth: 1)
                    .padding(3)
            }
        }
        .padding(.trailing, isExpanded ? 0 : 10)
        .padding(.bottom, isExpanded ? 0 : 10)
        .contentShape(PixelCornerShape())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.text(
                "\(task.title)，已完成 \(completedCount)/\(childTasks.count)，\(isExpanded ? "已展开" : "已收起")",
                english: "\(task.title), \(completedCount) of \(childTasks.count) completed, \(isExpanded ? "expanded" : "collapsed")"
            )
        )
        .accessibilityHint(
            isExpanded
                ? L10n.text("收起子任务", english: "Collapse subtasks")
                : L10n.text("展开子任务", english: "Expand subtasks")
        )
    }

    private func taskMonsterThumbnail(for task: TaskContract) -> some View {
        let presentation = MonsterEncounterPresentation(
            task: task,
            discovery: monsterDiscovery(for: task)
        )
        return MonsterArtworkView(
            imageURL: presentation.imageURL,
            isDiscovered: presentation.revealsAssignedIdentity
        )
        .scaleEffect(presentation.imageURL == nil ? 0.52 : 1)
    }

    private func taskGroupStackLayer(fill: Color, borderOpacity: Double) -> some View {
        PixelCornerShape()
            .fill(fill)
            .overlay {
                PixelCornerShape()
                    .stroke(PixelTheme.gold.opacity(borderOpacity), lineWidth: PixelTheme.borderWidth)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func adaptiveTaskRow(
        task: TaskContract,
        now: Date,
        actions: [TaskRowAction],
        onSelect: @escaping () -> Void
    ) -> some View {
#if os(iOS)
        Button(action: onSelect) {
            taskRow(task, now: now)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach(actions) { action in
                Button(role: action.kind == .delete ? .destructive : nil) {
                    action.perform()
                } label: {
                    Label(action.title, systemImage: action.icon)
                }
                .tint(action.tint)
            }
        }
#else
        PixelSwipeActionRow(actions: actions, onSelect: onSelect) {
            taskRow(task, now: now)
        }
#endif
    }

    @ViewBuilder
    private func adaptiveTaskGroupRow(
        task: TaskContract,
        now: Date,
        actions: [TaskRowAction],
        onSelect: @escaping () -> Void
    ) -> some View {
#if os(iOS)
        Button(action: onSelect) {
            taskGroupRow(task, now: now)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach(actions) { action in
                Button(role: action.kind == .delete ? .destructive : nil) {
                    action.perform()
                } label: {
                    Label(action.title, systemImage: action.icon)
                }
                .tint(action.tint)
            }
        }
#else
        PixelSwipeActionRow(actions: actions, onSelect: onSelect) {
            taskGroupRow(task, now: now)
        }
#endif
    }

    private func taskDetailPage(_ task: TaskContract) -> some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        taskDetailHeader(task)
                            .id("task-detail-top")
                            .padding(.horizontal, pageHorizontalInset)

                        Group {
                            if isEvidenceDeliveryPresented, !task.isTaskGroup {
                                evidenceDeliveryStage(for: task)
                                    .padding(.horizontal, bountyPosterHorizontalInset)
                                    .transition(
                                        reduceMotion
                                            ? .opacity
                                            : .move(edge: .bottom).combined(with: .opacity)
                                    )
                            } else {
                                VStack(spacing: 14) {
                                    taskBountyDetailPresentation(for: task)
                                        .padding(.horizontal, bountyPosterHorizontalInset)

                                    VStack(spacing: 14) {
                                        taskSourceReferenceCard(for: task)
                                        taskReminderDetail(for: task)
                                    }
                                    .padding(.horizontal, pageHorizontalInset)
                                }
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                                )
                            }
                        }
                        .animation(
                            reduceMotion ? nil : .snappy(duration: 0.46, extraBounce: 0.08),
                            value: isEvidenceDeliveryPresented
                        )
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 38)
                    .platformScrollableContentWidth(790)
                    .frame(maxWidth: .infinity)
                }
                .scrollDisabled(isTaskDetailDeadlinePickerPresented || isTaskFailureDetailPresented)
                .allowsHitTesting(!isTaskDetailDeadlinePickerPresented && !isTaskFailureDetailPresented)
                .onChange(of: isEvidenceDeliveryPresented) { _, _ in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.34)) {
                        scrollProxy.scrollTo("task-detail-top", anchor: .top)
                    }
                }
            }

            if isTaskDetailDeadlinePickerPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                BountyDeadlinePanel(
                    draftSelection: $taskDetailDeadlinePickerSelection,
                    onCancel: { dismissTaskDetailDeadlinePicker(for: task) },
                    onSave: { saveTaskDetailDeadline(for: task) }
                )
                .frame(maxWidth: 700)
                .padding(.horizontal, pageHorizontalInset)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }

            if isTaskFailureDetailPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                TaskFailureDetailPanel(
                    evidences: latestFailedEvidenceBatch(for: task),
                    onDismiss: dismissTaskFailureDetail
                )
                .frame(maxWidth: 700)
                .padding(.horizontal, pageHorizontalInset)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.34),
            value: isTaskDetailDeadlinePickerPresented
        )
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.34),
            value: isTaskFailureDetailPresented
        )
        .task(id: monsterDetailSyncKey(for: task)) {
            await ensureMonsterVariant(for: task)
        }
        .onChange(of: task.id) { _, _ in
            isEvidenceDeliveryPresented = false
            isTaskDetailDeadlinePickerPresented = false
            isTaskFailureDetailPresented = false
        }
    }

    private func taskDetailHeader(_ task: TaskContract) -> some View {
        HStack {
            taskDetailNavigationButton
            Spacer()
            if task.status == .needMoreProof || task.status == .notVerified {
                Button {
                    presentTaskFailureDetail()
                } label: {
                    statusPill(for: task)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    L10n.text("查看未通过核验的照片和原因", english: "View the rejected photos and reason")
                )
            } else {
                statusPill(for: task)
            }
        }
    }

    @ViewBuilder
    private var taskDetailNavigationButton: some View {
        if isEvidenceDeliveryPresented {
            Button {
                closeEvidenceDelivery()
            } label: {
                Label(L10n.text("返回悬赏令", english: "Back to Bounty"), systemImage: "chevron.left")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(PixelTheme.ink)
            }
            .buttonStyle(.plain)
            .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3, hasShadow: true)
        } else {
            taskDetailBackButton
        }
    }

    private func taskBountyDetailPresentation(for task: TaskContract) -> some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 848

            taskBountyDetailPoster(for: task)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(CGFloat(848) / 1855, contentMode: .fit)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func taskSourceReferenceCard(for task: TaskContract) -> some View {
        if task.hadSourceImage == true || task.localSourceImageData != nil {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("原始委托", english: "Original Brief"), systemImage: "photo.text.magnifyingglass")
                    .font(PixelTheme.displayFont(size: 17))
                    .foregroundStyle(PixelTheme.ink)

                if let sourceImageData = task.localSourceImageData {
                    PlatformImageView(data: sourceImageData)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 440)
                        .background(PixelTheme.background.opacity(0.08))
                        .clipShape(PixelCornerShape(step: 3))
                } else {
                    Label(
                        L10n.text(
                            "来源图片仅保存在创建它的设备",
                            english: "The source image is stored only on the device that created this task"
                        ),
                        systemImage: "internaldrive"
                    )
                    .font(PixelTheme.font(.subheadline))
                    .foregroundStyle(PixelTheme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(PixelTheme.background.opacity(0.08))
                    .clipShape(PixelCornerShape(step: 3))
                }

                Text(
                    L10n.text(
                        "来源图片不会上传到 iCloud",
                        english: "The source image is not uploaded to iCloud"
                    )
                )
                .font(PixelTheme.font(.caption))
                .foregroundStyle(PixelTheme.inkMuted)
            }
            .padding(18)
            .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 4, hasShadow: true)
        }
    }

    private func taskBountyDetailPoster(for task: TaskContract) -> some View {
        ZStack(alignment: .topLeading) {
            Image("BountyContractBackground")
                .resizable()
                .interpolation(.high)
                .frame(width: 848, height: 1855)
                .accessibilityHidden(true)

            Text(L10n.text(task.title))
                .font(PixelTheme.displayFont(size: 42))
                .foregroundStyle(PixelTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 570, height: 112)
                .position(x: 432, y: 184)

            taskBountyMonsterField(for: task)
                .frame(width: 440, height: 465)
                .position(x: 424, y: 552)

            taskBountyBadgeField(for: task)
                .frame(width: 300, height: 294)
                .position(x: 258, y: 995)

            BountyDeadlineButton(
                selection: Binding(
                    get: { task.deadline },
                    set: { _ in }
                ),
                isExpanded: isTaskDetailDeadlinePickerPresented,
                action: { presentTaskDetailDeadlinePicker(for: task) }
            )
            .frame(width: 306, height: 126)
            .position(x: 592, y: 911)

            taskBountyMetadataField(
                title: L10n.text("完成奖励", english: "Reward"),
                value: task.isSubtask
                    ? L10n.text("任务组奖励", english: "Group Reward")
                    : "+\(task.xpReward) EXP",
                icon: "sparkles"
            )
            .frame(width: 306, height: 126)
            .position(x: 592, y: 1074)

            taskBountyDescriptionField(for: task)
                .frame(width: 660, height: 210)
                .position(x: 424, y: 1305)

            taskBountyEvidenceField(for: task)
                .frame(width: 660, height: 160)
                .position(x: 424, y: 1544)

            taskBountyPrimaryAction(for: task)
                .frame(width: 490, height: 88)
                .position(x: 424, y: 1715)
        }
        .frame(width: 848, height: 1855)
    }

    @ViewBuilder
    private func taskBountyMonsterField(for task: TaskContract) -> some View {
        if task.isTaskGroup {
            let childTasks = children(of: task)
            VStack(spacing: 14) {
                Image(systemName: "scroll.fill")
                    .font(.system(size: 86, weight: .medium))
                    .foregroundStyle(PixelTheme.gold)
                Text(L10n.text("任务组", english: "Task Group"))
                    .font(PixelTheme.displayFont(size: 28))
                ForEach(childTasks.prefix(4)) { child in
                    Label(
                        L10n.text(child.title),
                        systemImage: child.status == .verified ? "checkmark.square.fill" : "square"
                    )
                    .font(PixelTheme.font(size: 21))
                    .foregroundStyle(PixelTheme.inkMuted)
                    .lineLimit(1)
                }
            }
        } else {
            VStack(spacing: 4) {
                taskMonsterThumbnail(for: task)
                    .frame(width: 350, height: 350)

                if let monsterTag = task.monsterTag {
                    Text(MonsterTaxonomy.categoryLabel(for: monsterTag))
                        .font(PixelTheme.displayFont(size: 25))
                        .foregroundStyle(PixelTheme.ink)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 14)
        }
    }

    private func taskBountyBadgeField(for task: TaskContract) -> some View {
        VStack(spacing: 3) {
            Text(L10n.text("所属勋章", english: "Medal"))
                .font(PixelTheme.font(size: 18))
                .foregroundStyle(PixelTheme.inkMuted)

            MedalArtworkView(
                categoryName: task.badgeCategory?.name,
                rank: task.badgeCategory?.userBadge?.rank ?? .bronze
            )
            .frame(width: 176, height: 176)

            Text(
                task.badgeCategory.map { badgeDisplayName($0.name) }
                    ?? L10n.text("未分类", english: "Uncategorized")
            )
            .font(PixelTheme.displayFont(size: 25))
            .foregroundStyle(PixelTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
    }

    private func taskBountyMetadataField(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(PixelTheme.gold)
                .frame(width: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PixelTheme.font(size: 18))
                    .foregroundStyle(PixelTheme.inkMuted)
                Text(value)
                    .font(PixelTheme.displayFont(size: 25))
                    .foregroundStyle(PixelTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
    }

    private func taskBountyDescriptionField(for task: TaskContract) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.text("任务说明", english: "Task Description"), systemImage: "text.alignleft")
                    .font(PixelTheme.font(size: 19))
                    .foregroundStyle(PixelTheme.inkMuted)

                Text(
                    task.taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? L10n.text(task.taskDescription ?? "")
                        : L10n.text("完成悬赏令上约定的任务。", english: "Complete the task described by this bounty.")
                )
                .font(PixelTheme.font(size: 24))
                .foregroundStyle(PixelTheme.ink)
                .lineSpacing(4)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let sourceImageData = task.localSourceImageData {
                PlatformImageView(data: sourceImageData)
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(PixelCornerShape(step: 3))
                    .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.gold, lineWidth: 2) }
                    .accessibilityLabel(L10n.text("任务来源图片", english: "Task source image"))
            } else if task.hadSourceImage == true {
                Image(systemName: "internaldrive")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(PixelTheme.inkMuted)
                    .frame(width: 120, height: 120)
                    .accessibilityLabel(
                        L10n.text("来源图片仅保存在创建它的设备", english: "Source image is stored only on its original device")
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private func taskBountyEvidenceField(for task: TaskContract) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("悬赏凭证", english: "Bounty Evidence"), systemImage: "photo.on.rectangle.angled")
                .font(PixelTheme.font(size: 19))
                .foregroundStyle(PixelTheme.inkMuted)

            if task.isTaskGroup {
                Text(
                    L10n.text(
                        "分别完成并核验任务组中的每一项悬赏。",
                        english: "Complete and verify each bounty in this task group."
                    )
                )
                .font(PixelTheme.font(size: 23))
                .foregroundStyle(PixelTheme.ink)
            } else {
                Text(L10n.text(task.evidenceRequirement))
                    .font(PixelTheme.font(size: 23))
                    .foregroundStyle(PixelTheme.ink)
                    .lineSpacing(3)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func taskBountyPrimaryAction(for task: TaskContract) -> some View {
        if task.isTaskGroup {
            let childTasks = children(of: task)
            let completedCount = childTasks.filter { $0.status == .verified }.count
            Label("\(completedCount)/\(childTasks.count)", systemImage: "checklist")
                .font(PixelTheme.displayFont(size: 31))
                .foregroundStyle(Color(red: 0.88, green: 0.75, blue: 0.48))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Button {
                openEvidenceDelivery()
            } label: {
                Label(taskBountyActionTitle(for: task), systemImage: taskBountyActionIcon(for: task))
                    .font(PixelTheme.displayFont(size: 31))
                    .foregroundStyle(Color(red: 0.88, green: 0.75, blue: 0.48))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func taskBountyActionTitle(for task: TaskContract) -> String {
        switch task.status {
        case .pending:
            L10n.text("提交证据", english: "Submit Evidence")
        case .awaitingVerification:
            L10n.text("查看核验进度", english: "View Verification")
        case .verified:
            L10n.text("查看核验记录", english: "View Evidence")
        case .needMoreProof, .notVerified:
            L10n.text("补充证据", english: "Add Evidence")
        }
    }

    private func taskBountyActionIcon(for task: TaskContract) -> String {
        switch task.status {
        case .pending: "photo.badge.plus"
        case .awaitingVerification: "hourglass"
        case .verified: "checkmark.seal.fill"
        case .needMoreProof, .notVerified: "arrow.clockwise"
        }
    }

    private func evidenceDeliveryStage(for task: TaskContract) -> some View {
        EvidenceSubmissionView(
            task: task,
            onVerificationStarted: {
                beginEvidenceVerification(for: task)
            },
            onVerificationFinished: { verdict, monsterEvent in
                finishEvidenceVerification(
                    for: task,
                    verdict: verdict,
                    monsterEvent: monsterEvent
                )
            },
            presentationStyle: .deliveryTray
        )
        // Transparent canvas gutters are trimmed from the asset, so the
        // parchment follows the same page-width rule as both bounty views.
        .aspectRatio(CGFloat(850) / 1450, contentMode: .fit)
        .frame(maxWidth: 700)
        .background {
            Image("EvidenceDeliveryTray")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private func openEvidenceDelivery() {
        isTaskDetailDeadlinePickerPresented = false
        isTaskFailureDetailPresented = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.46, extraBounce: 0.08)) {
            isEvidenceDeliveryPresented = true
        }
    }

    private func closeEvidenceDelivery() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.38)) {
            isEvidenceDeliveryPresented = false
        }
    }

    private func presentTaskDetailDeadlinePicker(for task: TaskContract) {
        guard task.status != .verified else { return }
        isTaskFailureDetailPresented = false
        taskDetailDeadlinePickerSelection = DeadlineDateOptions.normalized(task.deadline, relativeTo: .now)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.34)) {
            isTaskDetailDeadlinePickerPresented = true
        }
    }

    private func dismissTaskDetailDeadlinePicker(for task: TaskContract) {
        taskDetailDeadlinePickerSelection = DeadlineDateOptions.normalized(task.deadline, relativeTo: .now)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            isTaskDetailDeadlinePickerPresented = false
        }
    }

    private func saveTaskDetailDeadline(for task: TaskContract) {
        let normalizedDeadline = DeadlineDateOptions.normalized(
            taskDetailDeadlinePickerSelection,
            relativeTo: .now
        )
        updateDeadline(normalizedDeadline, for: task)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            isTaskDetailDeadlinePickerPresented = false
        }
    }

    private func presentTaskFailureDetail() {
        isTaskDetailDeadlinePickerPresented = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.34)) {
            isTaskFailureDetailPresented = true
        }
    }

    private func dismissTaskFailureDetail() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            isTaskFailureDetailPresented = false
        }
    }

    private func latestFailedEvidenceBatch(for task: TaskContract) -> [Evidence] {
        let failedEvidences = (task.evidences ?? []).filter {
            $0.verdict == .needMoreProof || $0.verdict == .notVerified
        }
        guard let latest = failedEvidences.max(by: { $0.submittedAt < $1.submittedAt }) else {
            return []
        }

        if let batchID = latest.submissionBatchID {
            return failedEvidences
                .filter { $0.submissionBatchID == batchID }
                .sorted { ($0.submissionIndex ?? 0) < ($1.submissionIndex ?? 0) }
        }

        return failedEvidences
            .filter {
                $0.submissionBatchID == nil &&
                    abs($0.submittedAt.timeIntervalSince(latest.submittedAt)) <= 1 &&
                    $0.verdict == latest.verdict &&
                    $0.explanation == latest.explanation
            }
            .sorted { $0.submittedAt < $1.submittedAt }
    }

    private var taskDetailBackButton: some View {
        Button {
            closeTaskDetail()
        } label: {
            Label(taskDetailOrigin.backTitle, systemImage: "chevron.left")
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(PixelTheme.ink)
        }
        .buttonStyle(.plain)
        .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3, hasShadow: true)
    }

    // MARK: - Medals

    @ViewBuilder
    private var medalsPage: some View {
        if let selectedLibraryBadge {
            medalLibraryPage(for: selectedLibraryBadge)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    )
                )
        } else {
            VStack(spacing: 0) {
                achievementOverviewHeader

                ZStack {
                    Group {
                        switch selectedAchievementTab {
                        case .medals:
                            medalsGridPage
                        case .monsters:
                            monsterAtlasPage
                        }
                    }
                    .id(selectedAchievementTab)
                    .transition(horizontalTabTransition(direction: achievementTabTransitionDirection))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
    }

    private var achievementOverviewHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader(
                title: "成就",
                subtitle: isCompactLayout
                    ? nil
                    : selectedAchievementTab == .medals
                        ? "收集碎片，铸造属于每个领域的勋章。点开后可回顾历史任务和证据。"
                        : L10n.text(
                            "只有亲自完成并通过核验的怪物才会进入你的图鉴。",
                            english: "Only monsters you personally reveal through verified tasks enter your atlas."
                        )
            )

            achievementTabPicker
        }
        .padding(.top, 38)
        .padding(.horizontal, pageHorizontalInset)
        .padding(.bottom, 12)
        .frame(maxWidth: 790, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medalsGridPage: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 0), spacing: 16),
                    GridItem(.flexible(minimum: 0), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(Self.badgeOptions, id: \.self) { badge in
                    Button {
                        withAnimation(.smooth(duration: 0.38)) {
                            selectedLibraryBadge = badge
                        }
                    } label: {
                        medalCard(for: badge)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, pageHorizontalInset)
            .padding(.top, 8)
            .padding(.bottom, 38)
            .platformScrollableContentWidth(790)
            .frame(maxWidth: .infinity)
        }
    }

    private var monsterAtlasPage: some View {
        ScrollView {
            MonsterAtlasView()
                .padding(.horizontal, pageHorizontalInset)
                .padding(.top, 8)
                .padding(.bottom, 38)
                .platformScrollableContentWidth(790)
                .frame(maxWidth: .infinity)
        }
    }

    private var achievementTabPicker: some View {
        PixelTabBar(
            items: AchievementTab.allCases.map {
                PixelTabItem(id: $0.rawValue, title: $0.title, systemImage: $0.icon)
            },
            selection: selectedAchievementTab.rawValue
        ) { rawValue in
            guard let tab = AchievementTab(rawValue: rawValue) else { return }
            selectAchievementTab(tab)
        }
        .accessibilityLabel(L10n.text("成就类别", english: "Achievement category"))
    }

    private func medalCard(for badge: String) -> some View {
        let category = badgeCategories.first { $0.name == badge }
        let userBadge = category?.userBadge
        let rank = userBadge?.rank ?? .bronze
        let currentXP = userBadge?.currentXP ?? 0

        return VStack(spacing: 10) {
            MedalArtworkView(categoryName: badge, rank: rank)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            Text(badgeDisplayName(badge))
                .font(PixelTheme.displayFont(size: 19))
                .foregroundStyle(PixelTheme.ink)
                .lineLimit(1)

            MedalFragmentStatusLabel(
                currentXP: currentXP,
                categoryName: badge,
                wording: .earned
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .foregroundStyle(PixelTheme.ink)
        .contentShape(PixelCornerShape())
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看历史任务和证据")
    }

    // MARK: - Library (per-badge history)

    private func medalLibraryPage(for badge: String) -> some View {
        let category = badgeCategories.first { $0.name == badge }
        let userBadge = category?.userBadge
        let rank = userBadge?.rank ?? .bronze
        let currentXP = userBadge?.currentXP ?? 0
        let historyTasks = taskContracts
            .filter {
                $0.badgeCategory?.name == badge &&
                    $0.status == .verified &&
                    !$0.isTaskGroup
            }
            .sorted { $0.createdAt > $1.createdAt }

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 18) {
                    Button {
                        withAnimation(.smooth(duration: 0.38)) {
                            selectedLibraryBadge = nil
                        }
                    } label: {
                        Label("返回勋章", systemImage: "chevron.left")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(PixelTheme.ink)
                    }
                    .buttonStyle(.plain)
                    .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3, hasShadow: true)

                    Text(badgeDisplayName(badge))
                        .font(PixelTheme.displayFont(size: 32))
                        .foregroundStyle(PixelTheme.paperRaised)

                    Spacer()
                }

                MedalDetailHeroView(categoryName: badge, currentXP: currentXP, rank: rank)

                #if DEBUG
                debugXPControls(for: badge)
                #endif

                Text("历史任务与证据")
                    .font(PixelTheme.displayFont(size: 18))
                    .foregroundStyle(PixelTheme.paperRaised)

                if historyTasks.isEmpty {
                    emptyState(
                        icon: "clock.arrow.circlepath",
                        title: "还没有历史任务",
                        message: L10n.text(
                            "完成一项属于「\(badgeDisplayName(badge))」的任务后，会出现在这里，方便随时回顾证据截图。",
                            english: "Complete a \(badgeDisplayName(badge)) task and it will appear here for easy review of its evidence."
                        )
                    )
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(historyTasks) { task in
                            libraryTaskRow(task, badge: badge)
                        }
                    }
                }
            }
            .padding(.horizontal, pageHorizontalInset)
            .padding(.vertical, 38)
            .platformScrollableContentWidth(790)
            .frame(maxWidth: .infinity)
        }
    }

    private func libraryTaskRow(_ task: TaskContract, badge: String) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.4)) {
                taskDetailOrigin = .badgeHistory(badge)
                selectedPage = .tasks
                selectedTask = task
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text(task.title))
                            .font(PixelTheme.font(.headline))
                            .foregroundStyle(PixelTheme.ink)
                            .lineLimit(2)
                        Text(L10n.date(task.createdAt, dateStyle: .medium, timeStyle: .short))
                            .font(PixelTheme.font(.caption))
                            .foregroundStyle(PixelTheme.inkMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 7) {
                        statusPill(for: task)
                        Text(
                            task.isSubtask
                                ? L10n.text("计入任务组奖励", english: "Included in group reward")
                                : "+\(task.xpReward) EXP"
                        )
                            .font(PixelTheme.font(.caption, weight: .bold))
                            .foregroundStyle(PixelTheme.brown)
                    }
                }

                if task.evidences?.isEmpty == false {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach((task.evidences ?? []).sorted { $0.submittedAt < $1.submittedAt }) { evidence in
                                libraryEvidenceThumbnail(evidence)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(PixelCornerShape())
        }
        .buttonStyle(.plain)
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
    }

    private func libraryEvidenceThumbnail(_ evidence: Evidence) -> some View {
        Group {
            if let imageData = evidence.localImageData {
                PlatformImageView(data: imageData)
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(PixelTheme.font(.title2))
                    .foregroundStyle(PixelTheme.inkMuted)
            }
        }
        .frame(width: 88, height: 66)
        .background(PixelTheme.paperRaised)
        .clipShape(PixelCornerShape(step: 3))
        .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.gold.opacity(0.7), lineWidth: 1) }
    }

    #if DEBUG
    /// Debug-only quick actions to add or remove XP for a badge with a tap,
    /// so level-up thresholds and the Library UI can be tested without
    /// completing real tasks. Never shown in release builds.
    private func debugXPControls(for badge: String) -> some View {
        HStack(spacing: 10) {
            Label("调试", systemImage: "ladybug.fill")
                .font(PixelTheme.font(.caption, weight: .semibold))
                .foregroundStyle(PixelTheme.paper.opacity(0.72))

            ForEach([25, 100, 500, 1000], id: \.self) { amount in
                Button("+\(amount)") {
                    debugAddXP(amount, toBadge: badge)
                }
                .buttonStyle(.plain)
                .font(PixelTheme.font(.caption, weight: .semibold))
                .foregroundStyle(PixelTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.selection, step: 2)
            }

            Button("重置") {
                debugAddXP(nil, toBadge: badge)
            }
            .buttonStyle(.plain)
            .font(PixelTheme.font(.caption, weight: .semibold))
            .foregroundStyle(PixelTheme.danger)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.danger, step: 2)

            Spacer()
        }
    }

    /// Adds `amount` XP to `badge`'s category (creating the category/badge if
    /// needed), or resets it to 0 XP when `amount` is `nil`.
    private func debugAddXP(_ amount: Int?, toBadge badge: String) {
        let category: BadgeCategory
        if let existingCategory = badgeCategories.first(where: { $0.name == badge }) {
            category = existingCategory
        } else {
            category = BadgeCategory(name: badge)
            modelContext.insert(category)
        }

        let awardEvent: XPAwardEvent?
        if let amount {
            awardEvent = XPService.debugAddXP(amount, to: category, in: modelContext)
        } else if let existingBadge = category.userBadge {
            existingBadge.currentXP = 0
            existingBadge.level = BadgeRank.bronze.rawValue
            awardEvent = nil
        } else {
            awardEvent = nil
        }

        do {
            try modelContext.save()
            if let awardEvent {
                XPService.publishAward(awardEvent)
            }
        } catch {
            modelContext.rollback()
        }
    }
    #endif

    // MARK: - Actions

    private func selectCreationInputMode(_ mode: TaskCreationInputMode) {
        guard mode != creationInputMode, !isGenerating else { return }
        isTaskInputFocused = false
        errorMessage = nil
        withAnimation(.smooth(duration: 0.24)) {
            creationInputMode = mode
        }
        if mode == .text {
            focusTaskInput()
        }
    }

    @MainActor
    private func importSourcePhoto(_ item: PhotosPickerItem) async {
        isImportingSourceImage = true
        sourceImageError = nil
        defer {
            isImportingSourceImage = false
            selectedSourcePhoto = nil
        }

        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                throw EvidenceImageProcessingError.unreadableImage
            }
            draftSourceImageData = try EvidenceImageProcessor.compressedJPEG(from: sourceData)
            errorMessage = nil
        } catch {
            sourceImageError = error.localizedDescription
        }
    }

    private func importCapturedSourceImage(_ sourceData: Data) {
        sourceImageError = nil
        do {
            draftSourceImageData = try EvidenceImageProcessor.compressedJPEG(from: sourceData)
            errorMessage = nil
        } catch {
            sourceImageError = error.localizedDescription
        }
    }

    private func removeSourceImage() {
        selectedSourcePhoto = nil
        draftSourceImageData = nil
        sourceImageError = nil
    }

    private func selectPage(_ page: AppPage) {
        if page == selectedPage {
            if page == .tasks {
                withAnimation(.smooth(duration: 0.38)) {
                    selectedTask = nil
                    taskDetailOrigin = .taskList
                    isEvidenceDeliveryPresented = false
                    isTaskDetailDeadlinePickerPresented = false
                }
            }
            return
        }

        if page == .tasks, selectedTask != nil {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTask = nil
                taskDetailOrigin = .taskList
                isEvidenceDeliveryPresented = false
                isTaskDetailDeadlinePickerPresented = false
            }
        }

        withAnimation(.smooth(duration: 0.38)) {
            selectedPage = page
        }
    }

    private func generateTask() {
        guard canGenerateTask, !isGenerating else { return }
        let prompt = currentTaskPrompt
        let sourceImageData = activeSourceImageData

        isTaskInputFocused = false
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let contract = try await generationService.generate(
                    from: prompt,
                    sourceImageData: sourceImageData
                )
                guard let deadline = contract.parsedDeadline else {
                    throw TaskGenerationError.invalidResponse
                }

                draftTitle = contract.title
                draftTaskDescription = contract.taskDescription
                draftDeadline = DeadlineDateOptions.normalized(deadline, relativeTo: .now)
                draftEvidenceRequirement = contract.evidenceRequirement
                draftEvidenceImageCount = contract.evidenceImageCount
                draftEvidenceImageDescriptions = contract.evidenceImageDescriptions
                let normalizedBadge = MonsterTaxonomy.normalizedBadgeKind(
                    suggestedBadge: contract.suggestedBadge,
                    canonicalTags: [contract.monsterTag] + contract.children.map(\.monsterTag)
                )
                draftBadge = Self.badgeOptions.contains(normalizedBadge)
                    ? normalizedBadge
                    : Self.badgeOptions[0]
                draftXP = contract.suggestedXP
                draftMonsterTag = contract.monsterTag
                draftMonsterMatchKind = contract.monsterMatchKind
                draftMonsterPreviewStates = [:]
                draftChildren = contract.kind == .taskGroup
                    ? contract.children.map(TaskChildDraft.init)
                    : []
                draftContractSourceImageData = sourceImageData

                withAnimation(.smooth(duration: 0.46)) {
                    creationPhase = .reviewing
                }
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
            isGenerating = false
        }
    }

    private func saveTask() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let requirement = draftEvidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasTaskGroup = isDraftTaskGroup
        guard
            TaskTitleRules.isValid(title),
            (isDraftTaskGroup || !requirement.isEmpty),
            draftChildren.allSatisfy({
                TaskTitleRules.isValid($0.title) &&
                    !$0.evidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { return }

        let deadline = DeadlineDateOptions.normalized(draftDeadline, relativeTo: .now)
        guard deadline > Date.now else {
            errorMessage = "截止时间必须晚于当前时间，请重新选择。"
            draftDeadline = DeadlineDateOptions.defaultSelection()
            return
        }

        var newlyStoredSourceImageIDs: [UUID] = []
        do {
            let category: BadgeCategory
            if let existingCategory = badgeCategories.first(where: { $0.name == draftBadge }) {
                category = existingCategory
            } else {
                category = BadgeCategory(name: draftBadge)
                let userBadge = UserBadge(category: category)
                category.userBadge = userBadge
                modelContext.insert(category)
                modelContext.insert(userBadge)
            }
            let lockedMonsterLevel = MonsterEncounterRules.lockedLevel(for: category)

            let savedTasks: [TaskContract]
            if wasTaskGroup {
                let parentID = UUID()
                if let sourceImageData = draftContractSourceImageData {
                    try LocalImageStore.shared.save(sourceImageData, kind: .taskSource, id: parentID)
                    newlyStoredSourceImageIDs.append(parentID)
                }
                let parent = TaskContract(
                    id: parentID,
                    title: title,
                    taskDescription: draftTaskDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    deadline: deadline,
                    evidenceRequirement: "",
                    evidenceImageCount: 1,
                    evidenceImageDescriptions: [],
                    xpReward: draftXP,
                    hierarchyRole: .group,
                    hadSourceImage: draftContractSourceImageData != nil,
                    badgeCategory: category
                )
                modelContext.insert(parent)

                let children = draftChildren.enumerated().map { index, draft in
                    let monster = MonsterTaxonomy.descriptor(
                        canonicalTag: draft.monsterTag,
                        matchKind: draft.monsterMatchKind,
                        fallbackText: "\(draft.title) \(draft.evidenceRequirement)",
                        badgeKind: draftBadge
                    )
                    let snapshot = draftMonsterSnapshot(for: draft.id.uuidString)
                    return TaskContract(
                        title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        taskDescription: draft.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                        deadline: deadline,
                        evidenceRequirement: draft.evidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines),
                        evidenceImageCount: draft.evidenceImageCount,
                        evidenceImageDescriptions: draft.evidenceImageDescriptions,
                        xpReward: draft.xpReward,
                        hierarchyRole: .child,
                        parentTaskID: parent.id,
                        childOrder: index,
                        monsterTag: monster.canonicalTag,
                        monsterLevel: lockedMonsterLevel,
                        monsterVariantID: snapshot?.variantID,
                        monsterImageURL: snapshot?.status == .ready ? snapshot?.imageURL : nil,
                        monsterStyleVersion: snapshot?.styleVersion,
                        badgeCategory: category
                    )
                }
                children.forEach(modelContext.insert)
                savedTasks = children
            } else {
                let monster = MonsterTaxonomy.descriptor(
                    canonicalTag: draftMonsterTag,
                    matchKind: draftMonsterMatchKind,
                    fallbackText: "\(title) \(requirement)",
                    badgeKind: draftBadge
                )
                let snapshot = draftMonsterSnapshot(for: "single")
                let taskID = UUID()
                if let sourceImageData = draftContractSourceImageData {
                    try LocalImageStore.shared.save(sourceImageData, kind: .taskSource, id: taskID)
                    newlyStoredSourceImageIDs.append(taskID)
                }
                let task = TaskContract(
                    id: taskID,
                    title: title,
                    taskDescription: draftTaskDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    deadline: deadline,
                    evidenceRequirement: requirement,
                    evidenceImageCount: draftEvidenceImageCount,
                    evidenceImageDescriptions: draftEvidenceImageDescriptions,
                    xpReward: draftXP,
                    hadSourceImage: draftContractSourceImageData != nil,
                    monsterTag: monster.canonicalTag,
                    monsterLevel: lockedMonsterLevel,
                    monsterVariantID: snapshot?.variantID,
                    monsterImageURL: snapshot?.status == .ready ? snapshot?.imageURL : nil,
                    monsterStyleVersion: snapshot?.styleVersion,
                    badgeCategory: category
                )
                modelContext.insert(task)
                savedTasks = [task]
            }
            try modelContext.save()
            for task in savedTasks {
                scheduleReminderAfterSave(
                    LocalTaskReminder(taskID: task.id, title: task.title, deadline: task.deadline)
                )
            }
            Task { await ensureMonsterVariants(for: savedTasks) }

            taskInput = ""
            selectedSourcePhoto = nil
            draftSourceImageData = nil
            draftContractSourceImageData = nil
            draftChildren = []
            draftTaskDescription = ""
            draftMonsterTag = nil
            draftMonsterMatchKind = nil
            draftMonsterPreviewStates = [:]
            draftDeadline = DeadlineDateOptions.defaultSelection()
            draftDeadlinePickerSelection = draftDeadline
            isDeadlinePickerPresented = false
            imageTaskNote = ""
            sourceImageError = nil
            errorMessage = nil
            withAnimation(.smooth(duration: 0.44)) {
                creationPhase = .composing
                creationInputMode = .text
                savedMessage = syncMonitor.isAvailable
                    ? L10n.text(
                        wasTaskGroup
                            ? "“\(title)”任务组已保存，正在等待 iCloud 同步"
                            : "“\(title)”已保存，正在等待 iCloud 同步",
                        english: wasTaskGroup
                            ? "The “\(title)” task group was saved and is waiting for iCloud sync"
                            : "“\(title)” was saved and is waiting for iCloud sync"
                    )
                    : L10n.text(
                        wasTaskGroup ? "“\(title)”任务组已保存到本机" : "“\(title)”已保存到本机",
                        english: wasTaskGroup
                            ? "The “\(title)” task group was saved on this device"
                            : "“\(title)” was saved on this device"
                    )
            }
            focusTaskInput()

            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.smooth(duration: 0.3)) {
                    savedMessage = nil
                }
            }
        } catch {
            modelContext.rollback()
            newlyStoredSourceImageIDs.forEach {
                LocalImageStore.shared.remove(kind: .taskSource, id: $0)
            }
            errorMessage = L10n.text(
                "保存失败：\(error.localizedDescription)",
                english: "Could not save: \(error.localizedDescription)"
            )
        }
    }

    private func openTask(_ task: TaskContract) {
        withAnimation(.smooth(duration: 0.4)) {
            taskDetailOrigin = .taskList
            selectedTask = task
        }
    }

    private func updateDeadline(_ deadline: Date, for task: TaskContract) {
        let normalizedDeadline = DeadlineDateOptions.normalized(deadline, relativeTo: .now)

        do {
            if task.isTaskGroup {
                task.deadline = normalizedDeadline
                children(of: task).forEach { $0.deadline = normalizedDeadline }
            } else {
                task.deadline = normalizedDeadline

                if
                    let parentTaskID = task.parentTaskID,
                    let parent = taskContracts.first(where: { $0.id == parentTaskID && $0.isTaskGroup })
                {
                    parent.deadline = children(of: parent).map(\.deadline).max() ?? normalizedDeadline
                }
            }

            try modelContext.save()
            reminderFeedback = L10n.text(
                "截止日期已更新为 \(deadlineDisplayText(normalizedDeadline))。",
                english: "Deadline updated to \(deadlineDisplayText(normalizedDeadline))."
            )
            reminderFeedbackIsError = false

            Task {
                await restoreTaskReminders()
            }
        } catch {
            modelContext.rollback()
            reminderFeedback = L10n.text(
                "截止日期更新失败：\(error.localizedDescription)",
                english: "Could not update the deadline: \(error.localizedDescription)"
            )
            reminderFeedbackIsError = true
        }
    }

    private func beginEvidenceVerification(for task: TaskContract) {
        let parent = task.parentTaskID.flatMap { parentID in
            taskContracts.first { $0.id == parentID && $0.isTaskGroup }
        }
        let siblingTasks = parent.map(children(of:)) ?? []
        let completesTaskGroup = task.isSubtask &&
            !siblingTasks.isEmpty &&
            siblingTasks.filter { $0.id != task.id }.allSatisfy { $0.status == .verified }

        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
            evidenceVerificationPresentation = EvidenceVerificationPresentation(
                taskID: task.id,
                taskTitle: L10n.text(task.title),
                xpReward: completesTaskGroup ? (parent?.xpReward ?? 0) : (task.isSubtask ? 0 : task.xpReward),
                isSubtask: task.isSubtask,
                completesTaskGroup: completesTaskGroup,
                phase: .verifying
            )
        }
    }

    private func finishEvidenceVerification(
        for task: TaskContract,
        verdict: EvidenceVerdict?,
        monsterEvent: MonsterDiscoveryEvent?
    ) {
        guard evidenceVerificationPresentation?.taskID == task.id else { return }

        guard verdict == .verified else {
            if let verdict {
                let explanation = (task.evidences ?? [])
                    .filter { $0.verdict == verdict }
                    .max(by: { $0.submittedAt < $1.submittedAt })?
                    .explanation ?? L10n.text(
                        "这次提交未能通过核验，请查看提交记录后补充证据。",
                        english: "This submission did not pass verification. Review the submission and add more evidence."
                    )
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                    evidenceVerificationPresentation?.phase = .failed(verdict, explanation)
                }
            } else {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                    evidenceVerificationPresentation?.phase = .failed(
                        .pending,
                        L10n.text(
                            "核验请求没有完成，照片仍保存在本机，请稍后重试。",
                            english: "Verification did not complete. Your photos remain on this device; please try again later."
                        )
                    )
                }
            }
            return
        }

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            evidenceVerificationPresentation?.phase = .completed
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.45 : 0.9))
            guard
                evidenceVerificationPresentation?.taskID == task.id,
                evidenceVerificationPresentation?.phase == .completed
            else { return }

            if let monsterEvent {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
                    evidenceVerificationPresentation = nil
                    monsterRevealPresentation = monsterEvent
                }
                return
            }

            completeVerifiedTaskTransition(for: task)
        }
    }

    private func finishMonsterReveal(for event: MonsterDiscoveryEvent) {
        guard monsterRevealPresentation?.id == event.id else { return }
        let task = taskContracts.first { $0.id == event.sourceTaskID }

        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            monsterRevealPresentation = nil
        }

        if let task {
            completeVerifiedTaskTransition(for: task)
        } else {
            presentDeferredMedalAnimationIfNeeded()
        }
    }

    private func completeVerifiedTaskTransition(for task: TaskContract) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.38)) {
            selectedPage = .tasks
            let wasSubtask = task.isSubtask
            let parent = task.parentTaskID.flatMap { parentID in
                taskContracts.first { $0.id == parentID }
            }
            if wasSubtask, parent?.status != .verified {
                selectedTaskTab = task.deadline <= .now ? .overdue : .unfinished
            } else {
                selectedTaskTab = .completed
            }
            selectedTask = nil
            taskDetailOrigin = .taskList
            evidenceVerificationPresentation = nil
            isEvidenceDeliveryPresented = false
            isTaskDetailDeadlinePickerPresented = false
            isTaskFailureDetailPresented = false
        }

        presentDeferredMedalAnimationIfNeeded()
    }

    private func presentDeferredMedalAnimationIfNeeded() {
        guard let deferredEvent = deferredMedalAnimationPresentation else { return }
        deferredMedalAnimationPresentation = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                medalAnimationPresentation = deferredEvent
            }
        }
    }

    private func closeTaskDetail() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
            selectedTask = nil
            isEvidenceDeliveryPresented = false
            isTaskDetailDeadlinePickerPresented = false
            isTaskFailureDetailPresented = false

            switch taskDetailOrigin {
            case .taskList:
                break
            case let .badgeHistory(badge):
                selectedLibraryBadge = badge
                selectedPage = .medals
            }

            taskDetailOrigin = .taskList
        }
    }

    private func horizontalTabTransition(direction: EdgeSwipeDirection) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        let insertionEdge: Edge = direction == .towardNext ? .trailing : .leading
        let removalEdge: Edge = direction == .towardNext ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func selectTaskTab(_ tab: TaskListTab) {
        guard tab != selectedTaskTab else { return }
        let tabs = TaskListTab.allCases
        guard
            let currentIndex = tabs.firstIndex(of: selectedTaskTab),
            let destinationIndex = tabs.firstIndex(of: tab)
        else { return }

        taskTabTransitionDirection = destinationIndex > currentIndex ? .towardNext : .towardPrevious
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            selectedTaskTab = tab
        }
    }

    private func selectAchievementTab(_ tab: AchievementTab) {
        guard tab != selectedAchievementTab else { return }
        let tabs = AchievementTab.allCases
        guard
            let currentIndex = tabs.firstIndex(of: selectedAchievementTab),
            let destinationIndex = tabs.firstIndex(of: tab)
        else { return }

        achievementTabTransitionDirection = destinationIndex > currentIndex ? .towardNext : .towardPrevious
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            selectedAchievementTab = tab
        }
    }

    private func handleEdgeSwipe(on page: AppPage, direction: EdgeSwipeDirection) {
        switch page {
        case .create:
            break
        case .tasks:
            if selectedTask != nil {
                if direction == .towardPrevious {
                    closeTaskDetail()
                }
                return
            }

            let destination: TaskListTab? = switch (selectedTaskTab, direction) {
            case (.unfinished, .towardNext): .completed
            case (.completed, .towardPrevious): .unfinished
            case (.completed, .towardNext): .overdue
            case (.overdue, .towardPrevious): .completed
            default: nil
            }

            guard let destination else { return }
            selectTaskTab(destination)
        case .medals:
            guard selectedLibraryBadge == nil else {
                if direction == .towardPrevious {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.38)) {
                        selectedLibraryBadge = nil
                    }
                }
                return
            }

            let destination: AchievementTab? = switch (selectedAchievementTab, direction) {
            case (.medals, .towardNext): .monsters
            case (.monsters, .towardPrevious): .medals
            default: nil
            }

            guard let destination else { return }
            selectAchievementTab(destination)
        }
    }

    private func taskRowActions(for task: TaskContract) -> [TaskRowAction] {
        [TaskRowAction(kind: .delete) {
            deleteTask(task)
        }]
    }

    private func deleteTask(_ task: TaskContract) {
        do {
            var awardEvent: XPAwardEvent?
            var deletedTasks = [task]
            if task.isTaskGroup {
                let childTasks = children(of: task)
                deletedTasks.append(contentsOf: childTasks)
                collapsedTaskGroupIDs.remove(task.id)
            }
            let deletedTaskIDs = deletedTasks.map(\.id)
            let deletedEvidenceIDs = deletedTasks.flatMap { ($0.evidences ?? []).map(\.id) }
            if task.isTaskGroup {
                deletedTasks.dropFirst().forEach(modelContext.delete)
            }
            modelContext.delete(task)

            if let parentID = task.parentTaskID {
                awardEvent = try TaskGroupService.reconcileParent(
                    id: parentID,
                    in: modelContext,
                    excludingChildID: task.id
                )
            }
            try modelContext.save()
            deletedTaskIDs.forEach { LocalImageStore.shared.remove(kind: .taskSource, id: $0) }
            deletedEvidenceIDs.forEach { LocalImageStore.shared.remove(kind: .evidence, id: $0) }
            if let awardEvent {
                XPService.publishAward(awardEvent)
            }
            withAnimation(.smooth(duration: 0.3)) {
                savedMessage = L10n.text(
                    "“\(task.title)”已删除",
                    english: "“\(task.title)” was deleted"
                )
            }
            Task {
                await restoreTaskReminders()
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.smooth(duration: 0.3)) {
                    savedMessage = nil
                }
            }
        } catch {
            modelContext.rollback()
            reminderFeedback = L10n.text(
                "任务更新失败：\(error.localizedDescription)",
                english: "Could not update the task: \(error.localizedDescription)"
            )
            reminderFeedbackIsError = true
        }
    }

    // MARK: - Helpers

    private var tasksAwaitingMonsterArtwork: [TaskContract] {
        taskContracts.filter {
            !$0.isTaskGroup &&
                $0.monsterTag != nil &&
                $0.monsterLevel != nil &&
                (($0.monsterImageURL?.isEmpty != false) ||
                    !MonsterArtworkFormat.isCurrent($0.monsterStyleVersion))
        }
    }

    private var pendingMonsterArtworkSyncKey: String {
        let taskIDs = tasksAwaitingMonsterArtwork
            .map(\.id.uuidString)
            .sorted()
            .joined(separator: ",")
        return "\(monsterArtworkSyncActivation):\(taskIDs)"
    }

    @MainActor
    private func ensureMonsterVariants(for tasks: [TaskContract]) async {
        for task in tasks {
            await ensureMonsterVariant(for: task)
        }
    }

    @MainActor
    private func ensureMonsterVariant(for task: TaskContract) async {
        guard
            let canonicalTag = task.monsterTag,
            let level = task.monsterLevel,
            let badgeKind = task.badgeCategory?.name
        else { return }

        guard var snapshot = try? await monsterVariantService.ensureVariant(
            canonicalTag: canonicalTag,
            badgeKind: badgeKind,
            level: level
        ) else { return }

        applyMonsterSnapshot(snapshot, to: task)

        for _ in 0..<MonsterVariantPollingPolicy.maxAttempts
        where snapshot.status == .pending || snapshot.status == .generating {
            do {
                try await Task.sleep(for: .seconds(MonsterVariantPollingPolicy.intervalSeconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let refreshed = try? await monsterVariantService.fetchVariant(
                canonicalTag: canonicalTag,
                level: level
            ) else { continue }
            snapshot = refreshed
            applyMonsterSnapshot(snapshot, to: task)
        }
    }

    @MainActor
    private func applyMonsterSnapshot(_ snapshot: MonsterVariantSnapshot, to task: TaskContract) {
        MonsterVariantSync.apply(
            snapshot,
            to: task,
            discovery: monsterDiscovery(for: task)
        )
        try? modelContext.save()
    }

    private func monsterDetailSyncKey(for task: TaskContract) -> String {
        "\(task.id.uuidString):\(task.monsterTag ?? "none"):\(task.monsterLevel ?? 0):\(task.monsterImageURL ?? "pending")"
    }

    private func monsterDiscovery(for task: TaskContract) -> MonsterDiscovery? {
        guard let tag = task.monsterTag, let level = task.monsterLevel else { return nil }
        return monsterDiscoveries.first {
            $0.canonicalTag == tag &&
                $0.level == level &&
                (task.monsterStyleVersion == nil || $0.styleVersion == task.monsterStyleVersion)
        }
    }

    private func migrateLegacySolverCategoriesIfNeeded() {
        let legacyName = BadgeKind.legacySolverName
        let legacyCategories = badgeCategories.filter { $0.name == legacyName }
        guard !legacyCategories.isEmpty else { return }

        let solverName = BadgeKind.solver.rawValue
        let targetCategory = badgeCategories.first { $0.name == solverName } ?? legacyCategories[0]
        let categoriesToMerge = badgeCategories.filter {
            $0.name == solverName || $0.name == legacyName
        }
        let combinedXP = categoriesToMerge.reduce(0) { total, category in
            total + (category.userBadge?.currentXP ?? 0)
        }

        targetCategory.name = solverName

        let targetUserBadge: UserBadge
        if let existingBadge = targetCategory.userBadge {
            targetUserBadge = existingBadge
        } else {
            targetUserBadge = UserBadge(category: targetCategory)
            targetCategory.userBadge = targetUserBadge
            modelContext.insert(targetUserBadge)
        }
        targetUserBadge.currentXP = combinedXP
        targetUserBadge.level = BadgeRank.rank(forCumulativeXP: combinedXP).rawValue

        for duplicateCategory in categoriesToMerge where duplicateCategory.id != targetCategory.id {
            for task in duplicateCategory.taskContracts ?? [] {
                task.badgeCategory = targetCategory
            }
            for log in duplicateCategory.xpLogs ?? [] {
                log.badgeCategory = targetCategory
            }
            modelContext.delete(duplicateCategory)
        }

        try? modelContext.save()
    }

    private func topLevelPage<Content: View>(
        _ page: AppPage,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selectedPage == page ? 1 : 0)
            .scaleEffect(selectedPage == page ? 1 : 0.985)
            .allowsHitTesting(selectedPage == page)
            .accessibilityHidden(selectedPage != page)
            .zIndex(selectedPage == page ? 1 : 0)
    }

    private var trimmedTaskInput: String {
        taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedImageTaskNote: String {
        imageTaskNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentTaskPrompt: String {
        switch creationInputMode {
        case .text: trimmedTaskInput
        case .image: trimmedImageTaskNote
        }
    }

    private var activeSourceImageData: Data? {
        creationInputMode == .image ? draftSourceImageData : nil
    }

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var pageHorizontalInset: CGFloat {
        isCompactLayout ? 16 : 36
    }

    /// Keep the review and detail posters on the same width calculation.
    /// Compact screens intentionally let the parchment use the full page;
    /// regular layouts retain a small gutter before applying the 700pt cap.
    private var bountyPosterHorizontalInset: CGFloat {
        isCompactLayout ? 0 : 28
    }

    private var compactPageInset: CGFloat {
        isCompactLayout ? 20 : 40
    }

#if DEBUG
    /// Opt-in simulator routes used by screenshot regression checks. Normal
    /// Debug and all Release launches are unchanged unless the environment
    /// variable is explicitly supplied.
    private func applyDebugLaunchScenario() {
        guard let scenario = ProcessInfo.processInfo.environment["LIFEMEDALS_DEBUG_PAGE"] else { return }

        switch scenario {
        case "tasks":
            selectedPage = .tasks
        case "medals":
            selectedPage = .medals
        case "atlas":
            selectedPage = .medals
            selectedAchievementTab = .monsters
            if monsterDiscoveries.isEmpty {
                modelContext.insert(
                    MonsterDiscovery(
                        canonicalTag: "coding.leetcode",
                        level: 1,
                        badgeKindRawValue: BadgeKind.solver.rawValue,
                        sourceTaskID: UUID(),
                        discoveryCount: 3
                    )
                )
                modelContext.insert(
                    MonsterDiscovery(
                        canonicalTag: "fitness.workout",
                        level: 2,
                        badgeKindRawValue: BadgeKind.athlete.rawValue,
                        sourceTaskID: UUID()
                    )
                )
                try? modelContext.save()
            }
        case "account":
            isShowingSettings = true
        case "review":
            draftTitle = "完成专注阅读"
            draftTaskDescription = "专注阅读 30 分钟，并记录本次阅读的关键收获。"
            draftEvidenceRequirement = "提交计时结束页面，并确保阅读时长和书名清晰可见。"
            draftEvidenceImageCount = 2
            draftEvidenceImageDescriptions = ["计时结束页面", "本次阅读的书籍页面"]
            draftXP = 20
            creationPhase = .reviewing
        case "task-detail":
            let category = badgeCategories.first ?? BadgeCategory(name: BadgeKind.solver.rawValue)
            if badgeCategories.isEmpty {
                let userBadge = UserBadge(category: category)
                category.userBadge = userBadge
                modelContext.insert(category)
                modelContext.insert(userBadge)
            }
            let task = TaskContract(
                title: "完成专注阅读",
                taskDescription: "专注阅读 30 分钟，并记录本次阅读的关键收获。",
                deadline: .now.addingTimeInterval(86_400),
                evidenceRequirement: "提交两张照片，分别证明专注时长和本次阅读内容。",
                evidenceImageCount: 2,
                evidenceImageDescriptions: ["计时结束页面", "书籍页面与阅读笔记"],
                xpReward: 20,
                badgeCategory: category
            )
            modelContext.insert(task)
            try? modelContext.save()
            selectedTask = task
            selectedPage = .tasks
        case "award":
            medalAnimationPresentation = XPAwardEvent(
                categoryName: BadgeKind.solver.rawValue,
                amount: 80,
                previousXP: 420,
                currentXP: 500,
                previousRank: .bronze,
                currentRank: .bronze
            )
        default:
            break
        }
    }
#endif

    private var buttonTitle: String {
        if isGenerating {
            return L10n.text("生成中", english: "Generating")
        }
        if errorMessage != nil {
            return L10n.text("重试", english: "Retry")
        }
        return L10n.text("生成", english: "Generate")
    }

    private var canGenerateTask: Bool {
        switch creationInputMode {
        case .text: !trimmedTaskInput.isEmpty
        case .image: draftSourceImageData != nil
        }
    }

    private var canSaveDraft: Bool {
        TaskTitleRules.isValid(draftTitle) &&
            (isDraftTaskGroup || !draftEvidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            (!isDraftTaskGroup || draftChildren.allSatisfy {
                TaskTitleRules.isValid($0.title) &&
                    !$0.evidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) &&
            DeadlineDateOptions.normalized(draftDeadline, relativeTo: .now) > Date.now
    }

    private var isDraftTaskGroup: Bool {
        draftChildren.count >= 2
    }

    private func deadlineDisplayText(_ deadline: Date, relativeTo date: Date = .now) -> String {
        DeadlineDateOptions.displayText(for: deadline, relativeTo: date)
    }

    private var pendingTasks: [TaskContract] {
        taskContracts
            .filter { !$0.isTaskGroup }
            .filter { $0.status != .verified }
            .sorted {
                if ($0.deadline < .now) != ($1.deadline < .now) {
                    return $0.deadline < .now
                }
                return $0.deadline < $1.deadline
            }
    }

    private var activeTaskContracts: [TaskContract] {
        taskContracts.filter { !$0.isSubtask }
    }

    private func children(of parent: TaskContract) -> [TaskContract] {
        taskContracts
            .filter { $0.isSubtask && $0.parentTaskID == parent.id }
            .sorted { lhs, rhs in
                let leftOrder = lhs.childOrder ?? .max
                let rightOrder = rhs.childOrder ?? .max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private func toggleTaskGroup(_ task: TaskContract) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
            if collapsedTaskGroupIDs.contains(task.id) {
                collapsedTaskGroupIDs.remove(task.id)
            } else {
                collapsedTaskGroupIDs.insert(task.id)
            }
        }
    }

    private func tasks(in tab: TaskListTab, now: Date) -> [TaskContract] {
        activeTaskContracts
            .filter { task in
                switch tab {
                case .unfinished:
                    task.status != .verified && task.deadline > now
                case .completed:
                    task.status == .verified
                case .overdue:
                    task.status != .verified && task.deadline <= now
                }
            }
            .sorted { lhs, rhs in
                switch tab {
                case .unfinished:
                    if lhs.deadline != rhs.deadline {
                        return lhs.deadline < rhs.deadline
                    }
                case .completed:
                    let lhsCompletedAt = lhs.groupCompletedAt ?? (lhs.evidences ?? [])
                        .filter { $0.verdict == .verified }
                        .map(\.submittedAt)
                        .max() ?? lhs.createdAt
                    let rhsCompletedAt = rhs.groupCompletedAt ?? (rhs.evidences ?? [])
                        .filter { $0.verdict == .verified }
                        .map(\.submittedAt)
                        .max() ?? rhs.createdAt
                    if lhsCompletedAt != rhsCompletedAt {
                        return lhsCompletedAt > rhsCompletedAt
                    }
                case .overdue:
                    if lhs.deadline != rhs.deadline {
                        return lhs.deadline > rhs.deadline
                    }
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func taskListStatusTitle(for task: TaskContract, now: Date) -> String {
        if task.status != .verified, task.deadline <= now {
            return L10n.text("已逾期")
        }

        return switch task.status {
        case .pending: L10n.text("待完成")
        case .awaitingVerification: L10n.text("等待核验")
        case .verified: L10n.text("已完成")
        case .needMoreProof: L10n.text("需补充证据")
        case .notVerified: L10n.text("未通过核验")
        }
    }

    private func taskListCompletionBox(for task: TaskContract, now: Date) -> some View {
        let borderColor: Color
        if task.status != .verified, task.deadline <= now {
            borderColor = PixelTheme.danger
        } else {
            borderColor = switch task.status {
            case .pending, .awaitingVerification: PixelTheme.inkMuted
            case .verified: PixelTheme.success
            case .needMoreProof: PixelTheme.gold
            case .notVerified: PixelTheme.danger
            }
        }

        return PixelTaskCompletionBox(
            isComplete: task.status == .verified,
            borderColor: borderColor,
            accessibilityTitle: taskListStatusTitle(for: task, now: now),
            size: isCompactLayout ? 22 : 24
        )
    }

    private func statusPill(for task: TaskContract) -> some View {
        let presentation: (title: String, icon: String, color: Color)
        if task.status != .verified, task.deadline <= .now {
            presentation = (L10n.text("已逾期"), "exclamationmark.circle.fill", PixelTheme.danger)
        } else {
            presentation = switch task.status {
            case .pending:
                (L10n.text("待完成"), "circle.dashed", PixelTheme.selection)
            case .awaitingVerification:
                (L10n.text("等待核验"), "hourglass", PixelTheme.selection)
            case .verified:
                (L10n.text("已完成"), "checkmark.circle.fill", PixelTheme.success)
            case .needMoreProof:
                (L10n.text("需补充证据"), "photo.badge.plus", PixelTheme.gold)
            case .notVerified:
                (L10n.text("未通过核验"), "xmark.circle.fill", PixelTheme.danger)
            }
        }

        return PixelStatusBadge(title: presentation.title, color: presentation.color)
            .accessibilityLabel(presentation.title)
    }

    @ViewBuilder
    private var reminderStatusBanner: some View {
        if !isReminderStatusDismissed {
            Group {
                if let reminderFeedback {
                    statusBanner(
                        icon: reminderFeedbackIsError ? "bell.slash.fill" : "bell.badge.fill",
                        message: reminderFeedback,
                        color: reminderFeedbackIsError ? PixelTheme.gold : PixelTheme.success
                    )
                } else {
                    switch reminderAuthorization {
                    case .authorized:
                        EmptyView()
                    case .denied:
                        statusBanner(icon: "bell.slash.fill", message: "系统通知已关闭。任务仍会保存在本机；可在系统设置中为 LifeMedals 开启通知。", color: PixelTheme.gold)
                    case .notDetermined:
                        statusBanner(icon: "bell", message: "保存未来任务时，系统会询问是否允许截止提醒。", color: PixelTheme.selection)
                    }
                }
            }
            .offset(x: reminderBannerTranslation)
            .opacity(reminderBannerOpacity)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissReminderStatus)
            .gesture(reminderBannerDismissGesture)
            .accessibilityAction(named: Text("关闭"), dismissReminderStatus)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var reminderBannerOpacity: Double {
        max(0.35, 1 - Double(abs(reminderBannerTranslation) / 180))
    }

    private var reminderBannerDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($reminderBannerTranslation) { value, translation, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                translation = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if abs(value.predictedEndTranslation.width) > 90 {
                    dismissReminderStatus()
                }
            }
    }

    private func dismissReminderStatus() {
        withAnimation(.snappy(duration: 0.25)) {
            isReminderStatusDismissed = true
        }
    }

    private func detailCard(title: String, value: String, icon: String, tint: Color) -> some View {
        detailCard(title: title, value: value) {
            PixelSymbolTile(systemImage: icon, tint: tint)
        }
    }

    private func detailCard<Leading: View>(
        title: String,
        value: String,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 14) {
            leading()

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(PixelTheme.font(.caption, weight: .semibold))
                    .foregroundStyle(PixelTheme.inkMuted)
                Text(value)
                    .font(PixelTheme.font(.subheadline, weight: .semibold))
                    .foregroundStyle(PixelTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
    }

    @ViewBuilder
    private func taskReminderDetail(for task: TaskContract) -> some View {
        if task.deadline <= .now {
            statusBanner(icon: "clock.badge.exclamationmark", message: "这项任务已过截止时间，不再安排新的系统提醒。", color: PixelTheme.danger)
        } else {
            switch reminderAuthorization {
            case .authorized:
                EmptyView()
            case .denied:
                statusBanner(icon: "bell.slash.fill", message: "系统通知权限已关闭；任务本身不受影响。", color: PixelTheme.gold)
            case .notDetermined:
                statusBanner(icon: "bell", message: "尚未授予通知权限。新建任务时可以开启截止提醒。", color: PixelTheme.selection)
            }
        }
    }

    private func scheduleReminderAfterSave(_ reminder: LocalTaskReminder) {
        Task {
            do {
                let state = try await notificationService.requestAuthorizationAndSchedule(reminder)
                reminderAuthorization = state
                switch state {
                case .authorized:
                    reminderFeedback = reminder.deadline > .now
                        ? "任务已保存，截止提醒也已安排。"
                        : "任务已保存；截止时间已过，因此没有安排提醒。"
                    reminderFeedbackIsError = false
                case .denied:
                    reminderFeedback = "任务已保存，但系统通知未开启。可稍后在系统设置中允许通知。"
                    reminderFeedbackIsError = true
                case .notDetermined:
                    reminderFeedback = "任务已保存，但暂未取得系统通知权限。"
                    reminderFeedbackIsError = true
                }
            } catch {
                reminderFeedback = L10n.text(
                    "任务已保存，但提醒安排失败：\(error.localizedDescription)",
                    english: "The task was saved, but its reminder could not be scheduled: \(error.localizedDescription)"
                )
                reminderFeedbackIsError = true
            }
        }
    }

    @MainActor
    private func restoreTaskReminders() async {
        let reminders = pendingTasks.map {
            LocalTaskReminder(taskID: $0.id, title: $0.title, deadline: $0.deadline)
        }

        do {
            reminderAuthorization = try await notificationService.synchronize(reminders)
        } catch {
            reminderFeedback = L10n.text(
                "已读取本地任务，但恢复截止提醒失败：\(error.localizedDescription)",
                english: "Local tasks were loaded, but deadline reminders could not be restored: \(error.localizedDescription)"
            )
            reminderFeedbackIsError = true
        }
    }

    private func focusTaskInput() {
        guard creationInputMode == .text else { return }
#if os(macOS)
        Task { @MainActor in
            isTaskInputFocused = true
        }
#endif
    }

    private func friendlyMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return L10n.text("当前没有网络，输入已保存在本机。联网后点击重试即可。")
            case .timedOut:
                return L10n.text("请求超时，输入仍在。请稍后重试。")
            default:
                return L10n.text(
                    "网络请求失败，输入仍在：\(urlError.localizedDescription)",
                    english: "The network request failed. Your input is still here: \(urlError.localizedDescription)"
                )
            }
        }
        return error.localizedDescription
    }

    private func badgeDisplayName(_ badge: String) -> String {
        BadgeKind.displayName(for: badge)
    }

    private func badgeRank(for badge: String) -> BadgeRank {
        badgeCategories.first { $0.name == badge }?.userBadge?.rank ?? .bronze
    }

    private func contractField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(PixelTheme.font(.caption, weight: .semibold))
                .foregroundStyle(PixelTheme.inkMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pageHeader(title: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .top, spacing: PixelTheme.space12) {
            VStack(alignment: .leading, spacing: 5) {
                if !isCompactLayout {
                    Text("QUEST LOG")
                        .font(PixelTheme.statFont(size: 11))
                        .foregroundStyle(PixelTheme.goldBright)
                }
                Text(LocalizedStringKey(title))
                    .font(PixelTheme.displayFont(size: isCompactLayout ? 28 : 34))
                    .foregroundStyle(PixelTheme.paperRaised)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .foregroundStyle(PixelTheme.paper.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isCompactLayout {
                PixelIconButton(
                    systemImage: "gearshape.fill",
                    accessibilityLabel: "打开设置"
                ) {
                    isShowingSettings = true
                }
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: icon)
                .font(PixelTheme.font(size: 36, weight: .bold))
                .foregroundStyle(PixelTheme.gold)
            Text(LocalizedStringKey(title))
                .font(PixelTheme.displayFont(size: 18))
                .foregroundStyle(PixelTheme.ink)
            Text(LocalizedStringKey(message))
                .font(PixelTheme.font(.subheadline))
                .foregroundStyle(PixelTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
        .padding(24)
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
    }

    private func statusBanner(icon: String, message: String, color: Color) -> some View {
        PixelNotice(systemImage: icon, message: message, color: color)
    }

    private func saveConfirmation(message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PixelTheme.success)
                Text(L10n.text(message))
                    .font(PixelTheme.font(.subheadline, weight: .semibold))
                    .foregroundStyle(PixelTheme.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.success, step: 3, hasShadow: true)

            Spacer()
        }
        .padding(.top, 82)
    }
}

private struct TaskFailureDetailPanel: View {
    let evidences: [Evidence]
    let onDismiss: () -> Void

    private var verdict: EvidenceVerdict {
        evidences.first?.verdict ?? .notVerified
    }

    private var explanation: String {
        evidences.lazy.compactMap(\.explanation).first { !$0.isEmpty }
            ?? L10n.text(
                "这次提交未能通过核验，请补充更清晰或更相关的照片。",
                english: "This submission did not pass verification. Add clearer or more relevant photos."
            )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label(
                    verdict == .needMoreProof
                        ? L10n.text("需补充证据", english: "More Evidence Needed")
                        : L10n.text("未通过核验", english: "Not Verified"),
                    systemImage: verdict == .needMoreProof ? "photo.badge.plus" : "xmark.circle.fill"
                )
                .font(PixelTheme.displayFont(size: 21))
                .foregroundStyle(verdict == .needMoreProof ? PixelTheme.gold : PixelTheme.danger)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(PixelTheme.font(.subheadline, weight: .bold))
                        .foregroundStyle(PixelTheme.inkMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("关闭", english: "Close"))
            }

            HStack(alignment: .center, spacing: 22) {
                evidenceStack
                    .frame(width: 168, height: 126)

                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("核验说明", english: "Verification Details"))
                        .font(PixelTheme.font(.caption, weight: .semibold))
                        .foregroundStyle(PixelTheme.inkMuted)
                    Text(L10n.text(explanation))
                        .font(PixelTheme.font(.subheadline))
                        .foregroundStyle(PixelTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .pixelSurface(
            fill: PixelTheme.paperRaised,
            border: verdict == .needMoreProof ? PixelTheme.gold : PixelTheme.danger,
            step: 5,
            hasShadow: true
        )
        .accessibilityElement(children: .contain)
    }

    private var evidenceStack: some View {
        ZStack {
            if evidences.isEmpty {
                Image(systemName: "photo")
                    .font(PixelTheme.font(size: 34))
                    .foregroundStyle(PixelTheme.inkMuted)
                    .frame(width: 128, height: 96)
                    .background(PixelTheme.paper)
            } else {
                ForEach(Array(evidences.prefix(5).enumerated()), id: \.element.id) { index, evidence in
                    Group {
                        if let imageData = evidence.localImageData {
                            PlatformImageView(data: imageData)
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(PixelTheme.font(size: 28))
                                .foregroundStyle(PixelTheme.inkMuted)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(PixelTheme.paper)
                        }
                    }
                    .frame(width: 128, height: 96)
                    .clipped()
                    .padding(4)
                    .background(Color(red: 0.95, green: 0.89, blue: 0.72))
                    .overlay(Rectangle().stroke(PixelTheme.brown.opacity(0.62), lineWidth: 1))
                    .shadow(color: .black.opacity(0.24), radius: 2, x: 2, y: 3)
                    .rotationEffect(.degrees([-6, 5, -3, 7, -5][index % 5]))
                    .offset(x: CGFloat(index) * 5 - CGFloat(min(evidences.count, 5) - 1) * 2.5)
                    .zIndex(Double(index))
                }
            }
        }
        .accessibilityLabel(
            L10n.text(
                "本次提交的 \(evidences.count) 张照片",
                english: "\(evidences.count) photos in this submission"
            )
        )
    }
}

private struct PixelEvidenceVerificationOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let phase: EvidenceVerificationPhase
    let taskTitle: String
    let xpReward: Int
    let isSubtask: Bool
    let completesTaskGroup: Bool
    let onDismissFailure: () -> Void

    private let pixelOffsets: [CGSize] = [
        CGSize(width: 0, height: -42),
        CGSize(width: 30, height: -30),
        CGSize(width: 42, height: 0),
        CGSize(width: 30, height: 30),
        CGSize(width: 0, height: 42),
        CGSize(width: -30, height: 30),
        CGSize(width: -42, height: 0),
        CGSize(width: -30, height: -30)
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()

            VStack(spacing: PixelTheme.space24) {
                verificationGlyph

                VStack(spacing: PixelTheme.space8) {
                    Text(title)
                        .font(PixelTheme.displayFont(size: 26))
                        .foregroundStyle(titleColor)

                    Text(taskTitle)
                        .font(PixelTheme.font(.headline))
                        .foregroundStyle(PixelTheme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(message)
                        .font(PixelTheme.font(.subheadline))
                        .foregroundStyle(PixelTheme.inkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isFailed {
                    Button(failureActionTitle, action: onDismissFailure)
                        .buttonStyle(PixelButtonStyle(tone: PixelTheme.danger))
                        .frame(maxWidth: .infinity)
                } else {
                    verificationPips
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
            .frame(maxWidth: 360)
            .pixelSurface(
                fill: PixelTheme.paperRaised,
                border: isCompleted ? PixelTheme.success : (isFailed ? PixelTheme.danger : PixelTheme.goldBright),
                step: 6,
                hasShadow: true
            )
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isCompleted
                ? L10n.text("任务完成，正在返回已完成任务", english: "Quest complete, returning to completed tasks")
                : isFailed
                    ? title
                    : L10n.text("正在核验证据", english: "Verifying evidence")
        )
    }

    private var isCompleted: Bool {
        phase == .completed
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private var title: String {
        switch phase {
        case .verifying:
            L10n.text("证据鉴定中", english: "Verifying Evidence")
        case .completed:
            completionTitle
        case let .failed(verdict, _):
            switch verdict {
            case .needMoreProof:
                L10n.text("需补充证据", english: "More Evidence Needed")
            case .notVerified:
                L10n.text("未通过核验", english: "Not Verified")
            case .pending, .verified:
                L10n.text("核验请求失败", english: "Verification Failed")
            }
        }
    }

    private var failureActionTitle: String {
        if case let .failed(verdict, _) = phase, verdict == .pending {
            return L10n.text("返回重试", english: "Return to Retry")
        }
        return L10n.text("查看提交记录", english: "View Submission")
    }

    private var titleColor: Color {
        switch phase {
        case .completed: PixelTheme.success
        case .failed: PixelTheme.danger
        case .verifying: PixelTheme.ink
        }
    }

    private var message: String {
        switch phase {
        case .verifying:
            L10n.text(
                "公会鉴定师正在核验任务证据…",
                english: "The guild appraiser is checking the task evidence…"
            )
        case .completed:
            completionMessage
        case let .failed(_, explanation):
            L10n.text(explanation)
        }
    }

    private var completionTitle: String {
        if completesTaskGroup {
            return L10n.text("所有子任务已完成", english: "All Subtasks Complete")
        }
        if isSubtask {
            return L10n.text("子任务完成", english: "Subtask Complete")
        }
        return L10n.text("任务完成", english: "Quest Complete")
    }

    private var completionMessage: String {
        if completesTaskGroup {
            return L10n.text(
                "任务组已完成，获得 +\(xpReward) EXP\n正在返回已完成任务…",
                english: "The task group is complete. +\(xpReward) EXP earned.\nReturning to completed tasks…"
            )
        }
        if isSubtask {
            return L10n.text(
                "证据核验通过，主任务进度已更新。",
                english: "Evidence verified. The group progress has been updated."
            )
        }
        return L10n.text(
            "证据核验通过，获得 +\(xpReward) EXP\n正在返回已完成任务…",
            english: "Evidence verified. +\(xpReward) EXP earned.\nReturning to completed tasks…"
        )
    }

    @ViewBuilder
    private var verificationGlyph: some View {
        if isCompleted {
            ZStack {
                PixelCornerShape(step: 5)
                    .fill(PixelTheme.success)
                    .frame(width: 104, height: 104)
                    .shadow(color: PixelTheme.background.opacity(0.8), radius: 0, x: 5, y: 5)

                Image(systemName: "checkmark")
                    .font(PixelTheme.font(size: 48, weight: .bold))
                    .foregroundStyle(.white)
            }
            .transition(.scale(scale: 0.72).combined(with: .opacity))
        } else if isFailed {
            ZStack {
                PixelCornerShape(step: 5)
                    .fill(PixelTheme.danger)
                    .frame(width: 104, height: 104)
                    .shadow(color: PixelTheme.background.opacity(0.8), radius: 0, x: 5, y: 5)

                Image(systemName: "xmark")
                    .font(PixelTheme.font(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
            .transition(.scale(scale: 0.72).combined(with: .opacity))
        } else {
            TimelineView(.animation(minimumInterval: 0.12, paused: reduceMotion)) { context in
                let activePixel = reduceMotion
                    ? 0
                    : Int(context.date.timeIntervalSinceReferenceDate * 8) % pixelOffsets.count

                ZStack {
                    PixelCornerShape(step: 5)
                        .fill(PixelTheme.backgroundRaised)
                        .frame(width: 104, height: 104)
                        .overlay { PixelCornerShape(step: 5).stroke(PixelTheme.gold, lineWidth: 2) }

                    Image(systemName: "photo.badge.checkmark")
                        .font(PixelTheme.font(size: 34, weight: .bold))
                        .foregroundStyle(PixelTheme.paperRaised)

                    ForEach(pixelOffsets.indices, id: \.self) { index in
                        Rectangle()
                            .fill(index == activePixel ? PixelTheme.goldBright : PixelTheme.gold.opacity(0.28))
                            .frame(width: index == activePixel ? 12 : 8, height: index == activePixel ? 12 : 8)
                            .offset(pixelOffsets[index])
                    }
                }
                .frame(width: 120, height: 120)
            }
            .transition(.opacity)
        }
    }

    private var verificationPips: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: reduceMotion || isCompleted || isFailed)) { context in
            let litPips = isCompleted
                ? 8
                : reduceMotion
                    ? 4
                    : (Int(context.date.timeIntervalSinceReferenceDate * 6) % 8) + 1

            HStack(spacing: PixelTheme.space4) {
                ForEach(0..<8, id: \.self) { index in
                    Rectangle()
                        .fill(
                            index < litPips
                                ? (isCompleted ? PixelTheme.success : PixelTheme.selectionBright)
                                : PixelTheme.background.opacity(0.16)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)
                }
            }
            .padding(3)
            .overlay { Rectangle().stroke(PixelTheme.ink, lineWidth: 2) }
        }
        .frame(height: 18)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            BadgeCategory.self,
            UserBadge.self,
            TaskContract.self,
            MonsterDiscovery.self,
            Evidence.self,
            XPLog.self
        ], inMemory: true)
}
