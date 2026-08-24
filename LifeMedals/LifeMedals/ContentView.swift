import PhotosUI
import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var accountManager: AppleAccountManager
    @EnvironmentObject private var syncMonitor: CloudSyncMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onSignOut: () -> Void

    init(onSignOut: @escaping () -> Void = {}) {
        self.onSignOut = onSignOut
    }

    private enum AppPage: String, CaseIterable, Identifiable {
        case create
        case tasks
        case medals

        var id: Self { self }

        var title: String {
            switch self {
            case .create: L10n.text("新任务", english: "New Task")
            case .tasks: L10n.text("任务", english: "Tasks")
            case .medals: L10n.text("勋章", english: "Medals")
            }
        }

        var icon: String {
            switch self {
            case .create: "plus"
            case .tasks: "checklist"
            case .medals: "medal"
            }
        }
    }

    private enum CreationPhase {
        case composing
        case reviewing
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
    @Query(sort: \TaskContract.createdAt, order: .reverse) private var taskContracts: [TaskContract]
    @Query(sort: \BadgeCategory.createdAt) private var badgeCategories: [BadgeCategory]

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
    @State private var reminderAuthorization = ReminderAuthorizationState.notDetermined
    @State private var reminderFeedback: String?
    @State private var reminderFeedbackIsError = false
    @State private var selectedTaskTab = TaskListTab.unfinished
    @State private var selectedLibraryBadge: String?
    @State private var medalAnimationPresentation: XPAwardEvent?
    @State private var isShowingSettings = false
    @State private var selectedSourcePhoto: PhotosPickerItem?
    @State private var draftSourceImageData: Data?
    @State private var draftContractSourceImageData: Data?
    @State private var isImportingSourceImage = false
    @State private var isSourceCameraPresented = false
    @State private var sourceImageError: String?
    @FocusState private var isTaskInputFocused: Bool

    @State private var draftTitle = ""
    @State private var draftDeadlinePreset: TaskDeadlinePreset? = .tomorrow
    @State private var draftEvidenceRequirement = ""
    @State private var draftEvidenceImageCount = 1
    @State private var draftEvidenceImageDescriptions: [String] = []
    @State private var draftBadge = "Problem Solver"
    @State private var draftXP = 10

    private let generationService = TaskGenerationService()
    private let notificationService = TaskNotificationService()

    var body: some View {
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
            .task {
                await restoreTaskReminders()
            }
            .onReceive(NotificationCenter.default.publisher(for: .xpAwarded)) { notification in
                guard let event = notification.object as? XPAwardEvent else { return }
                guard event.currentXP > event.previousXP else { return }
                guard event.previousXP < BadgeRank.silver.cumulativeXPThreshold else { return }

                withAnimation(.smooth(duration: 0.3)) {
                    medalAnimationPresentation = event
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(onSignOut: onSignOut)
                    .environmentObject(accountManager)
                    .environmentObject(syncMonitor)
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
        _: AppPage,
        containerSize: CGSize,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ZStack {
            PixelBackground()
            content()
                .frame(width: containerSize.width)
        }
        .frame(width: containerSize.width)
    }
#endif

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
        ScrollView {
            VStack(alignment: .leading, spacing: PixelTheme.space16) {
                pageHeader(title: "创建新任务")

                PixelPanel(fill: PixelTheme.paper, padding: isCompactLayout ? PixelTheme.space16 : PixelTheme.space24) {
                    VStack(alignment: .leading, spacing: PixelTheme.space16) {
                        PixelSectionHeader(title: "任务委托")
                        taskCreationModeTabs

                        Group {
                            switch creationInputMode {
                            case .text:
                                textTaskComposer
                            case .image:
                                imageTaskComposer
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                    }
                }
            }
            .padding(.horizontal, max(compactPageInset, PixelTheme.space16))
            .padding(.vertical, isCompactLayout ? PixelTheme.space24 : 56)
            .platformScrollableContentWidth(790)
            .frame(maxWidth: .infinity)
        }
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
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

    private var taskCreationModeTabs: some View {
        PixelTabBar(
            items: TaskCreationInputMode.allCases.map {
                PixelTabItem(id: $0.rawValue, title: $0.title, systemImage: $0.icon)
            },
            selection: creationInputMode.rawValue
        ) { rawValue in
            guard let mode = TaskCreationInputMode(rawValue: rawValue) else { return }
            selectCreationInputMode(mode)
        }
        .accessibilityLabel("任务生成方式")
    }

    private var textTaskComposer: some View {
        VStack(alignment: .leading, spacing: PixelTheme.space16) {
            PixelInput(isFocused: isTaskInputFocused) {
                TextField("例如：本周完成三次 30 分钟跑步", text: $taskInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(PixelTheme.font(size: isCompactLayout ? 18 : 22, weight: .medium))
                    .foregroundStyle(PixelTheme.ink)
                    .lineLimit(3...6)
                    .focused($isTaskInputFocused)
                    .frame(maxWidth: .infinity, minHeight: isCompactLayout ? 76 : 96, alignment: .topLeading)
                    .accessibilityLabel("输入你想完成的任务")
#if os(iOS)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("完成") {
                                isTaskInputFocused = false
                            }
                        }
                    }
#endif
                    .onSubmit(generateTask)
            }

            generationAction
            generationError
        }
    }

    private var imageTaskComposer: some View {
        VStack(alignment: .leading, spacing: PixelTheme.space16) {
            taskSourceImagePicker

            if draftSourceImageData != nil {
                PixelInput {
                    TextField("补充说明（可选）", text: $imageTaskNote, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(PixelTheme.font(.body))
                        .foregroundStyle(PixelTheme.ink)
                        .lineLimit(1...3)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                        .accessibilityLabel("图片补充说明")
                        .onSubmit(generateTask)
                }
            }

            generationAction

            if let sourceImageError {
                Text(sourceImageError)
                    .font(PixelTheme.font(.caption))
                    .foregroundStyle(PixelTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            generationError
        }
    }

    private var generationAction: some View {
        HStack {
            Spacer()
            PixelButton(
                title: buttonTitle,
                systemImage: errorMessage == nil ? "wand.and.stars" : "arrow.clockwise",
                isLoading: isGenerating,
                action: generateTask
            )
            .disabled(isGenerating || isImportingSourceImage || !canGenerateTask)
            .opacity(isGenerating || isImportingSourceImage || !canGenerateTask ? 0.48 : 1)
        }
    }

    @ViewBuilder
    private var generationError: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(PixelTheme.font(.caption))
                .foregroundStyle(PixelTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var taskSourceImagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let draftSourceImageData {
                PlatformImageView(data: draftSourceImageData)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .background(PixelTheme.background.opacity(0.08))
                    .clipShape(PixelCornerShape(step: 3))
                    .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.gold.opacity(0.72), lineWidth: 1) }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            removeSourceImage()
                        } label: {
                            Image(systemName: "xmark")
                                .font(PixelTheme.font(.caption, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(PixelTheme.danger, in: PixelCornerShape(step: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除任务来源图片")
                        .padding(10)
                    }
            } else {
                VStack(spacing: 12) {
                    if isImportingSourceImage {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在压缩照片…")
                            .font(PixelTheme.font(.caption))
                            .foregroundStyle(PixelTheme.inkMuted)
                    } else {
                        Image(systemName: "doc.viewfinder")
                            .font(PixelTheme.font(size: 30, weight: .semibold))
                            .foregroundStyle(PixelTheme.gold)
                        Text("上传邮件、syllabus 或活动海报")
                            .font(PixelTheme.font(.caption))
                            .foregroundStyle(PixelTheme.inkMuted)
                    }

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedSourcePhoto, matching: .images) {
                            Label("照片图库", systemImage: "photo.on.rectangle")
                                .font(PixelTheme.font(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isImportingSourceImage)
                        .foregroundStyle(.white)
                        .pixelSurface(fill: PixelTheme.selection, border: PixelTheme.gold, step: 2)

                        Button {
                            isSourceCameraPresented = true
                        } label: {
                            Label("拍照", systemImage: "camera")
                                .font(PixelTheme.font(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isImportingSourceImage)
                        .foregroundStyle(PixelTheme.ink)
                        .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 130)
                .background(PixelTheme.paperRaised, in: PixelCornerShape(step: 3))
                .overlay {
                    PixelCornerShape(step: 3)
                        .stroke(PixelTheme.gold.opacity(0.58), style: StrokeStyle(lineWidth: 1, dash: [7, 5]))
                }
            }
        }
    }

    private var contractReview: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            contractReview(now: context.date)
        }
    }

    private func contractReview(now: Date) -> some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 14) {
                        contractReviewBackButton
                        contractReviewTitle
                    }
                } else {
                    HStack(alignment: .top) {
                        contractReviewTitle
                        Spacer()
                        contractReviewBackButton
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    if isCompactLayout {
                        VStack(alignment: .leading, spacing: 18) {
                            taskTitleContractField
                            xpContractField
                        }
                    } else {
                        HStack(alignment: .top, spacing: 22) {
                            taskTitleContractField
                                .frame(maxWidth: .infinity)
                            xpContractField
                                .frame(width: 180)
                        }
                    }

                    if isCompactLayout {
                        VStack(alignment: .leading, spacing: 18) {
                            badgeContractField
                            deadlineContractField
                        }
                    } else {
                        HStack(alignment: .top, spacing: 22) {
                            badgeContractField
                                .frame(width: 220)
                            deadlineContractField
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if let draftContractSourceImageData {
                        contractField("任务来源") {
                            VStack(alignment: .leading, spacing: 10) {
                                PlatformImageView(data: draftContractSourceImageData)
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 280)
                                    .background(PixelTheme.background.opacity(0.08))
                                    .clipShape(PixelCornerShape(step: 3))
                                Label("这个任务由上图内容生成；保存后可在任务详情中回看。", systemImage: "sparkles")
                                    .font(PixelTheme.font(.caption))
                                    .foregroundStyle(PixelTheme.inkMuted)
                            }
                            .padding(12)
                            .background(PixelTheme.paperRaised, in: PixelCornerShape())
                            .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
                        }
                    }

                    contractField("证据照片") {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("需要 \(draftEvidenceImageCount) 张照片", systemImage: "photo.stack")
                                .font(PixelTheme.font(.subheadline, weight: .semibold))

                            ForEach(Array(draftEvidenceImageDescriptions.enumerated()), id: \.offset) { index, description in
                                HStack(alignment: .top, spacing: 8) {
                                    if draftEvidenceImageCount <= 2 {
                                        Text("\(index + 1)")
                                            .font(PixelTheme.statFont(size: 11))
                                            .foregroundStyle(.white)
                                            .frame(width: 20, height: 20)
                                            .background(PixelTheme.selection, in: PixelCornerShape(step: 2))
                                    }
                                    Text(description)
                                        .font(PixelTheme.font(.subheadline))
                                        .foregroundStyle(PixelTheme.inkMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PixelTheme.paperRaised, in: PixelCornerShape())
                        .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
                    }

                    Button(action: saveTask) {
                        Label("确认并保存", systemImage: "checkmark")
                            .font(PixelTheme.font(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(tone: PixelTheme.selection))
                    .disabled(!canSaveDraft)
                    .opacity(canSaveDraft ? 1 : 0.45)

                    if let errorMessage {
                        statusBanner(icon: "exclamationmark.triangle.fill", message: errorMessage, color: PixelTheme.danger)
                    }
                }
                .padding(isCompactLayout ? 18 : 24)
                .background {
                    ZStack {
                        PixelCornerShape()
                            .fill(PixelTheme.background.opacity(0.92))
                            .offset(x: 4, y: 4)
                        PixelCornerShape().fill(PixelTheme.paper)
                    }
                }
                .overlay { PixelCornerShape().stroke(PixelTheme.gold, lineWidth: 2) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .platformScrollableContentWidth(790)
            .frame(maxWidth: .infinity)
        }
    }

    private var contractReviewTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("确认任务契约")
                .font(PixelTheme.displayFont(size: 32))
                .foregroundStyle(PixelTheme.paperRaised)
            Text("确认截止日期和证据照片后，即可开始执行。")
                .foregroundStyle(PixelTheme.paper.opacity(0.72))
        }
    }

    private var contractReviewBackButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.38)) {
                creationPhase = .composing
            }
            focusTaskInput()
        } label: {
            Label("返回修改想法", systemImage: "chevron.left")
        }
        .buttonStyle(PixelButtonStyle(tone: PixelTheme.brown))
    }

    private var taskTitleContractField: some View {
        contractField("任务标题") {
            TextField("任务标题", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(PixelTheme.font(.title3, weight: .medium))
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
            MedalArtworkView(categoryName: draftBadge, rank: badgeRank(for: draftBadge))
                .frame(width: 132, height: 132)
                .frame(maxWidth: .infinity)
                .clipped()
                .padding(4)
                .frame(maxWidth: .infinity, minHeight: 144, maxHeight: 144)
                .background(PixelTheme.paperRaised, in: PixelCornerShape())
                .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
        }
    }

    private var deadlineContractField: some View {
        contractField("截止日期") {
            DeadlinePresetWheelPicker(selection: $draftDeadlinePreset)
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
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity.combined(with: .move(edge: .trailing))
                    )
                )
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

        return List {
            taskListHeader(
                unfinishedCount: unfinishedTasks.count,
                completedCount: completedTasks.count,
                overdueCount: overdueTasks.count
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 24, leading: pageHorizontalInset, bottom: 12, trailing: pageHorizontalInset))

            if selectedTasks.isEmpty {
                taskListEmptyState(for: selectedTaskTab)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalInset, bottom: 28, trailing: pageHorizontalInset))
            } else {
                ForEach(selectedTasks) { task in
                    let actions = taskRowActions(for: task)
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
                        withAnimation(.smooth(duration: 0.3)) {
                            selectedTaskTab = tab
                        }
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
            MedalArtworkView(
                categoryName: task.badgeCategory?.name,
                rank: task.badgeCategory?.userBadge?.rank ?? .bronze
            )
            .frame(width: isCompactLayout ? 44 : 52, height: isCompactLayout ? 44 : 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
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
                        Text(task.badgeCategory.map { badgeDisplayName($0.name) } ?? "未分类")
                    }
                }
            }
            .font(PixelTheme.font(.caption))
            .foregroundStyle(task.deadline <= now && task.status != .verified ? PixelTheme.danger : PixelTheme.inkMuted)

            Spacer()

            VStack(alignment: .trailing, spacing: 9) {
                Text(taskListStatusTitle(for: task, now: now))
                    .font(PixelTheme.font(.caption, weight: .semibold))
                    .foregroundStyle(taskListStatusColor(for: task, now: now))
                    .lineLimit(1)
                Text("+\(task.xpReward) EXP")
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

    @ViewBuilder
    private func adaptiveTaskRow(
        task: TaskContract,
        now: Date,
        actions: [TaskRowAction],
        onSelect: @escaping () -> Void
    ) -> some View {
        PixelSwipeActionRow(actions: actions, onSelect: onSelect) {
            taskRow(task, now: now)
        }
    }

    private func taskDetailPage(_ task: TaskContract) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            taskDetailBackButton
                            Spacer()
                            statusPill(for: task)
                        }
                        taskDetailTitle(task)
                    }
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        taskDetailBackButton
                        taskDetailTitle(task)
                        Spacer()
                        statusPill(for: task)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    detailCard(
                        title: "截止日期",
                        value: deadlineDisplayText(task.deadline),
                        icon: task.deadline < .now ? "clock.badge.exclamationmark" : "calendar.badge.clock",
                        tint: task.deadline < .now ? PixelTheme.danger : PixelTheme.selection
                    )
                    detailCard(
                        title: "所属勋章",
                        value: task.badgeCategory.map { badgeDisplayName($0.name) } ?? "未分类"
                    ) {
                        MedalArtworkView(
                            categoryName: task.badgeCategory?.name,
                            rank: task.badgeCategory?.userBadge?.rank ?? .bronze
                        )
                        .frame(width: 48, height: 48)
                    }
                    detailCard(
                        title: "完成奖励",
                        value: "+\(task.xpReward) EXP",
                        icon: "sparkles",
                        tint: PixelTheme.gold
                    )
                }

                if let sourceImageData = task.sourceImageData {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("任务来源", systemImage: "photo.text.magnifyingglass")
                            .font(PixelTheme.displayFont(size: 17))
                            .foregroundStyle(PixelTheme.ink)

                        PlatformImageView(data: sourceImageData)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 440)
                            .background(PixelTheme.background.opacity(0.08))
                            .clipShape(PixelCornerShape(step: 3))

                        Text("创建任务时由 AI 读取的来源图片副本")
                            .font(PixelTheme.font(.caption))
                            .foregroundStyle(PixelTheme.inkMuted)
                    }
                    .padding(18)
                    .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 4, hasShadow: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("验收标准", systemImage: "doc.text.magnifyingglass")
                            .font(PixelTheme.displayFont(size: 17))
                            .foregroundStyle(PixelTheme.ink)
                        Spacer()
                        Label("已锁定", systemImage: "lock.fill")
                            .font(PixelTheme.font(.caption, weight: .semibold))
                            .foregroundStyle(PixelTheme.inkMuted)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(PixelTheme.paper, in: PixelCornerShape(step: 2))
                            .overlay { PixelCornerShape(step: 2).stroke(PixelTheme.gold.opacity(0.7), lineWidth: 1) }
                    }

                    Text(task.evidenceRequirement)
                        .font(PixelTheme.font(.body))
                        .foregroundStyle(PixelTheme.ink)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()
                        .opacity(0.45)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("需要 \(task.requiredEvidenceImageCount) 张照片", systemImage: "photo.stack")
                            .font(PixelTheme.font(.subheadline, weight: .semibold))
                        ForEach(Array(task.evidenceImageDescriptions.enumerated()), id: \.offset) { index, description in
                            Text(task.requiredEvidenceImageCount <= 2 ? "\(index + 1). \(description)" : description)
                                .font(PixelTheme.font(.subheadline))
                                .foregroundStyle(PixelTheme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider()
                        .opacity(0.45)

                    Text("创建于 \(task.createdAt.formatted(date: .long, time: .shortened))")
                        .font(PixelTheme.font(.caption))
                        .foregroundStyle(PixelTheme.inkMuted.opacity(0.72))
                }
                .padding(22)
                .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 4, hasShadow: true)

                EvidenceSubmissionView(task: task)
                taskReminderDetail(for: task)
            }
            .padding(.horizontal, pageHorizontalInset)
            .padding(.vertical, 38)
            .platformScrollableContentWidth(790)
            .frame(maxWidth: .infinity)
        }
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

    private func taskDetailTitle(_ task: TaskContract) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(task.title)
                .font(PixelTheme.displayFont(size: isCompactLayout ? 28 : 34))
                .foregroundStyle(PixelTheme.paperRaised)
                .fixedSize(horizontal: false, vertical: true)
            Text("任务契约")
                .font(PixelTheme.font(.subheadline))
                .foregroundStyle(PixelTheme.paper.opacity(0.72))
        }
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
            medalsGridPage
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity.combined(with: .move(edge: .trailing))
                    )
                )
        }
    }

    private var medalsGridPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    title: "勋章",
                    subtitle: isCompactLayout
                        ? nil
                        : "收集碎片，铸造属于每个领域的勋章。点开后可回顾历史任务和证据。"
                )

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
            }
            .padding(.horizontal, pageHorizontalInset)
            .padding(.vertical, 38)
            .platformScrollableContentWidth(790)
            .frame(maxWidth: .infinity)
        }
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
            .filter { $0.badgeCategory?.name == badge && $0.status == .verified }
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
                        message: "完成一项属于「\(badgeDisplayName(badge))」的任务后，会出现在这里，方便随时回顾证据截图。"
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
                        Text(task.title)
                            .font(PixelTheme.font(.headline))
                            .foregroundStyle(PixelTheme.ink)
                            .lineLimit(2)
                        Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(PixelTheme.font(.caption))
                            .foregroundStyle(PixelTheme.inkMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 7) {
                        statusPill(for: task)
                        Text("+\(task.xpReward) EXP")
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
            if let imageData = evidence.imageData {
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
                draftDeadlinePreset = contract.deadlinePreset
                    ?? deadlinePreset(for: deadline, relativeTo: .now)
                draftEvidenceRequirement = contract.evidenceRequirement
                draftEvidenceImageCount = contract.evidenceImageCount
                draftEvidenceImageDescriptions = contract.evidenceImageDescriptions
                draftBadge = Self.badgeOptions.contains(contract.suggestedBadge)
                    ? contract.suggestedBadge
                    : Self.badgeOptions[0]
                draftXP = contract.suggestedXP
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
        guard
            !title.isEmpty,
            !requirement.isEmpty,
            let draftDeadlinePreset
        else { return }

        let deadline = taskDeadline(for: draftDeadlinePreset, relativeTo: .now)
        guard deadline > Date.now else {
            errorMessage = "截止时间必须晚于当前时间，请重新选择。"
            self.draftDeadlinePreset = .tomorrow
            return
        }

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

            let task = TaskContract(
                title: title,
                deadline: deadline,
                evidenceRequirement: requirement,
                evidenceImageCount: draftEvidenceImageCount,
                evidenceImageDescriptions: draftEvidenceImageDescriptions,
                xpReward: draftXP,
                sourceImageData: draftContractSourceImageData,
                badgeCategory: category
            )
            modelContext.insert(task)
            try modelContext.save()
            scheduleReminderAfterSave(
                LocalTaskReminder(taskID: task.id, title: task.title, deadline: task.deadline)
            )

            taskInput = ""
            selectedSourcePhoto = nil
            draftSourceImageData = nil
            draftContractSourceImageData = nil
            imageTaskNote = ""
            sourceImageError = nil
            errorMessage = nil
            withAnimation(.smooth(duration: 0.44)) {
                creationPhase = .composing
                creationInputMode = .text
                savedMessage = syncMonitor.isAvailable
                    ? "“\(title)”已保存，正在等待 iCloud 同步"
                    : "“\(title)”已保存到本机"
            }
            focusTaskInput()

            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.smooth(duration: 0.3)) {
                    savedMessage = nil
                }
            }
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func openTask(_ task: TaskContract) {
        withAnimation(.smooth(duration: 0.4)) {
            taskDetailOrigin = .taskList
            selectedTask = task
        }
    }

    private func closeTaskDetail() {
        withAnimation(.smooth(duration: 0.4)) {
            selectedTask = nil

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

    private func taskRowActions(for task: TaskContract) -> [TaskRowAction] {
        [TaskRowAction(kind: .delete) {
            deleteTask(task)
        }]
    }

    private func deleteTask(_ task: TaskContract) {
        modelContext.delete(task)
        persistTaskChange(successMessage: "“\(task.title)”已删除")
    }

    private func persistTaskChange(successMessage: String) {
        do {
            try modelContext.save()
            withAnimation(.smooth(duration: 0.3)) {
                savedMessage = successMessage
            }
            Task {
                await restoreTaskReminders()
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.smooth(duration: 0.3)) {
                    savedMessage = nil
                }
            }
        } catch {
            reminderFeedback = "任务更新失败：\(error.localizedDescription)"
            reminderFeedbackIsError = true
        }
    }

    // MARK: - Helpers

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
        case "account":
            isShowingSettings = true
        case "review":
            draftTitle = "完成一次 30 分钟专注阅读"
            draftEvidenceRequirement = "提交计时结束页面，并确保阅读时长和书名清晰可见。"
            draftEvidenceImageCount = 2
            draftEvidenceImageDescriptions = ["计时结束页面", "本次阅读的书籍页面"]
            draftXP = 20
            creationPhase = .reviewing
        case "task-detail":
            let category = badgeCategories.first ?? BadgeCategory(name: BadgeKind.problemSolver.rawValue)
            if badgeCategories.isEmpty {
                let userBadge = UserBadge(category: category)
                category.userBadge = userBadge
                modelContext.insert(category)
                modelContext.insert(userBadge)
            }
            let task = TaskContract(
                title: "完成一次 30 分钟专注阅读并记录关键收获",
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
                categoryName: BadgeKind.problemSolver.rawValue,
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
        if isGenerating { return "正在整理契约" }
        if creationInputMode == .image {
            return errorMessage == nil ? "识别并生成" : "保留图片并重试"
        }
        return errorMessage == nil ? "生成任务" : "保留输入并重试"
    }

    private var canGenerateTask: Bool {
        switch creationInputMode {
        case .text: !trimmedTaskInput.isEmpty
        case .image: draftSourceImageData != nil
        }
    }

    private var canSaveDraft: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draftEvidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            draftDeadlinePreset.map { taskDeadline(for: $0, relativeTo: .now) > Date.now } == true
    }

    private func taskDeadline(for preset: TaskDeadlinePreset, relativeTo date: Date) -> Date {
        let calendar = Calendar.current
        let dayOffset: Int
        switch preset {
        case .today:
            dayOffset = 0
        case .tomorrow:
            dayOffset = 1
        case .thisWeekend:
            let weekday = calendar.component(.weekday, from: date)
            dayOffset = (8 - weekday) % 7
        }
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: targetDay) ?? targetDay
    }

    private func deadlinePreset(for deadline: Date, relativeTo date: Date) -> TaskDeadlinePreset {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: date)
        let startOfDeadline = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfDeadline).day ?? 0

        if days <= 0 { return .today }
        if days == 1 { return .tomorrow }
        return .thisWeekend
    }

    private func deadlineDisplayText(_ deadline: Date, relativeTo date: Date = .now) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: date)
        let startOfDeadline = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfDeadline).day

        switch days {
        case 0:
            return "今日"
        case 1:
            return "明日"
        default:
            let components = calendar.dateComponents([.month, .day], from: deadline)
            guard let month = components.month, let day = components.day else { return "" }
            return "\(month)月\(day)日"
        }
    }

    private var pendingTasks: [TaskContract] {
        activeTaskContracts
            .filter { $0.status != .verified }
            .sorted {
                if ($0.deadline < .now) != ($1.deadline < .now) {
                    return $0.deadline < .now
                }
                return $0.deadline < $1.deadline
            }
    }

    private var activeTaskContracts: [TaskContract] {
        taskContracts
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
                    let lhsCompletedAt = (lhs.evidences ?? [])
                        .filter { $0.verdict == .verified }
                        .map(\.submittedAt)
                        .max() ?? lhs.createdAt
                    let rhsCompletedAt = (rhs.evidences ?? [])
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
            return "已逾期"
        }

        return switch task.status {
        case .pending: "待完成"
        case .awaitingVerification: "等待核验"
        case .verified: "已完成"
        case .needMoreProof: "需补充证据"
        case .notVerified: "未通过核验"
        }
    }

    private func taskListStatusColor(for task: TaskContract, now: Date) -> Color {
        if task.status != .verified, task.deadline <= now {
            return PixelTheme.danger
        }

        return switch task.status {
        case .pending, .awaitingVerification: PixelTheme.selection
        case .verified: PixelTheme.success
        case .needMoreProof: PixelTheme.gold
        case .notVerified: PixelTheme.danger
        }
    }

    private func statusPill(for task: TaskContract) -> some View {
        let presentation: (title: String, icon: String, color: Color)
        if task.status != .verified, task.deadline <= .now {
            presentation = ("已逾期", "exclamationmark.circle.fill", PixelTheme.danger)
        } else {
            presentation = switch task.status {
            case .pending:
                ("待完成", "circle.dashed", PixelTheme.selection)
            case .awaitingVerification:
                ("等待核验", "hourglass", PixelTheme.selection)
            case .verified:
                ("已完成", "checkmark.circle.fill", PixelTheme.success)
            case .needMoreProof:
                ("需补充证据", "photo.badge.plus", PixelTheme.gold)
            case .notVerified:
                ("未通过核验", "xmark.circle.fill", PixelTheme.danger)
            }
        }

        return PixelStatusBadge(title: presentation.title, color: presentation.color)
            .accessibilityLabel(presentation.title)
    }

    @ViewBuilder
    private var reminderStatusBanner: some View {
        if let reminderFeedback {
            statusBanner(
                icon: reminderFeedbackIsError ? "bell.slash.fill" : "bell.badge.fill",
                message: reminderFeedback,
                color: reminderFeedbackIsError ? PixelTheme.gold : PixelTheme.success
            )
        } else {
            switch reminderAuthorization {
            case .authorized:
                statusBanner(icon: "bell.badge.fill", message: "截止提醒已开启；未来任务会在截止时间发送系统通知。", color: PixelTheme.success)
            case .denied:
                statusBanner(icon: "bell.slash.fill", message: "系统通知已关闭。任务仍会保存在本机；可在系统设置中为 LifeMedals 开启通知。", color: PixelTheme.gold)
            case .notDetermined:
                statusBanner(icon: "bell", message: "保存未来任务时，系统会询问是否允许截止提醒。", color: PixelTheme.selection)
            }
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
                statusBanner(
                    icon: "bell.badge.fill",
                    message: "将在 \(deadlineDisplayText(task.deadline)) 发送本地通知。",
                    color: PixelTheme.success
                )
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
                reminderFeedback = "任务已保存，但提醒安排失败：\(error.localizedDescription)"
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
            reminderFeedback = "已读取本地任务，但恢复截止提醒失败：\(error.localizedDescription)"
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
                return "当前没有网络，输入已保存在本机。联网后点击重试即可。"
            case .timedOut:
                return "请求超时，输入仍在。请稍后重试。"
            default:
                return "网络请求失败，输入仍在：\(urlError.localizedDescription)"
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
                Text(message)
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

#Preview {
    ContentView()
        .modelContainer(for: [
            BadgeCategory.self,
            UserBadge.self,
            TaskContract.self,
            Evidence.self,
            XPLog.self
        ], inMemory: true)
}
