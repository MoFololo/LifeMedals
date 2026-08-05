import AppKit
import SwiftUI
import SwiftData

struct ContentView: View {
    private enum AppPage: String, CaseIterable, Identifiable {
        case create
        case tasks
        case medals

        var id: Self { self }

        var title: String {
            switch self {
            case .create: "新任务"
            case .tasks: "任务"
            case .medals: "勋章"
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

    private enum TaskListTab: String, CaseIterable, Identifiable {
        case unfinished
        case completed
        case overdue

        var id: Self { self }

        var title: String {
            switch self {
            case .unfinished: "未完成"
            case .completed: "已完成"
            case .overdue: "已逾期"
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
            case .unfinished: .accentColor
            case .completed: .green
            case .overdue: .red
            }
        }
    }

    private struct TaskRowAction: Identifiable {
        enum Kind: Hashable {
            case archive
            case restore
            case delete

            var title: String {
                switch self {
                case .archive: "归档"
                case .restore: "取消归档"
                case .delete: "删除"
                }
            }

            var icon: String {
                switch self {
                case .archive: "archivebox.fill"
                case .restore: "tray.and.arrow.up.fill"
                case .delete: "trash.fill"
                }
            }

            var tint: Color {
                switch self {
                case .archive: .orange
                case .restore: .accentColor
                case .delete: .red
                }
            }
        }

        let kind: Kind
        let perform: () -> Void

        var id: Kind { kind }
        var title: String { kind.title }
        var icon: String { kind.icon }
        var tint: Color { kind.tint }
    }

    private struct MouseDragSwipeRow<Content: View>: View {
        private let revealWidth: CGFloat = 188
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
                HStack(spacing: 16) {
                    ForEach(actions) { action in
                        mouseActionButton(action)
                    }
                }
                .padding(.trailing, 8)
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
                    .simultaneousGesture(mouseDragGesture)
                    .zIndex(0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityAddTraits(.isButton)
        }

        private var displayedOffset: CGFloat {
            min(0, max(-revealWidth, settledOffset + dragTranslation))
        }

        private var mouseDragGesture: some Gesture {
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

        private func mouseActionButton(_ action: TaskRowAction) -> some View {
            VStack(spacing: 5) {
                Button {
                    closeActions()
                    action.perform()
                } label: {
                    Image(systemName: action.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 30)
                        .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
                .background(action.tint, in: Capsule())
                .accessibilityLabel(action.title)
                .help(action.title)

                Text(action.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 56)
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
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var selectedTask: TaskContract?
    @State private var reminderAuthorization = ReminderAuthorizationState.notDetermined
    @State private var reminderFeedback: String?
    @State private var reminderFeedbackIsError = false
    @State private var selectedTaskTab = TaskListTab.unfinished
    @State private var isShowingArchivedTasks = false
    @State private var selectedLibraryBadge: String?
    @State private var medalAnimationPresentation: XPAwardEvent?
    @FocusState private var isTaskInputFocused: Bool

    @State private var draftTitle = ""
    @State private var draftDeadlinePreset: TaskDeadlinePreset? = .tomorrow
    @State private var draftEvidenceRequirement = ""
    @State private var draftEvidenceImageCount = 1
    @State private var draftEvidenceImageDescriptions: [String] = []
    @State private var draftBadge = "Problem Solver"
    @State private var draftXP = 10
    @State private var draftEstimatedHours = 0.25

    private let generationService = TaskGenerationService()
    private let notificationService = TaskNotificationService()

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 0) {
                topNavigation
                    .padding(.top, 22)
                    .padding(.horizontal, 28)

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

            if let savedMessage {
                saveConfirmation(message: savedMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            if let medalAnimationPresentation {
                MedalAwardAnimationOverlay(event: medalAnimationPresentation) {
                    withAnimation(.smooth(duration: 0.28)) {
                        self.medalAnimationPresentation = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(20)
            }
        }
        .frame(minWidth: 920, minHeight: 680)
        .preferredColorScheme(.light)
        .animation(.smooth(duration: 0.42), value: selectedPage)
        .animation(.smooth(duration: 0.42), value: creationPhase)
        .animation(.smooth(duration: 0.32), value: savedMessage)
        .onAppear {
            notificationService.configureForegroundPresentation()
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
            guard event.categoryName == "Problem Solver" else { return }
            guard event.currentXP > event.previousXP else { return }
            guard event.previousXP < BadgeRank.silver.cumulativeXPThreshold else { return }

            withAnimation(.smooth(duration: 0.3)) {
                medalAnimationPresentation = event
            }
        }
    }

    // MARK: - Navigation

    private var topNavigation: some View {
        ZStack {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("人生勋章")
                        .font(.headline)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())

                Spacer()

                Text("本机保存")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(AppPage.allCases) { page in
                        Button {
                            selectPage(page)
                        } label: {
                            Label(page.title, systemImage: page.icon)
                                .font(.subheadline.weight(selectedPage == page ? .semibold : .medium))
                                .foregroundStyle(selectedPage == page ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            .regular
                                .tint(selectedPage == page ? Color.accentColor.opacity(0.16) : .clear)
                                .interactive(),
                            in: Capsule()
                        )
                        .accessibilityLabel("切换到\(page.title)页面")
                    }
                }
            }
        }
        .frame(height: 48)
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
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 18) {
                TextField("", text: $taskInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(1...5)
                    .focused($isTaskInputFocused)
                    .frame(maxWidth: 680, minHeight: 48)
                    .padding(.horizontal, 24)
                    .accessibilityLabel("输入你想完成的任务")
                    .onSubmit(generateTask)

                if !trimmedTaskInput.isEmpty || isGenerating || errorMessage != nil {
                    VStack(spacing: 14) {
                        Button(action: generateTask) {
                            HStack(spacing: 9) {
                                if isGenerating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: errorMessage == nil ? "arrow.up" : "arrow.clockwise")
                                }
                                Text(buttonTitle)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating || trimmedTaskInput.isEmpty)
                        .contentShape(Capsule())
                        .glassEffect(.regular.tint(Color.accentColor.opacity(0.14)).interactive(), in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))

                        if let errorMessage {
                            statusBanner(icon: "wifi.exclamationmark", message: errorMessage, color: .orange)
                                .frame(maxWidth: 560)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            .animation(.snappy(duration: 0.32), value: trimmedTaskInput.isEmpty)
            .animation(.smooth(duration: 0.3), value: errorMessage)

            Spacer()

            Text("在这里写下你想完成的事")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .opacity(taskInput.isEmpty && !isTaskInputFocused ? 1 : 0)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .contentShape(Rectangle())
        .onTapGesture { isTaskInputFocused = true }
    }

    private var contractReview: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            contractReview(now: context.date)
        }
    }

    private func contractReview(now: Date) -> some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("确认任务契约")
                            .font(.largeTitle.bold())
                        Text("保存后，验收标准将作为这项任务的约定。")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.smooth(duration: 0.38)) {
                            creationPhase = .composing
                        }
                        focusTaskInput()
                    } label: {
                        Label("返回修改想法", systemImage: "chevron.left")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 18) {
                    contractField("任务标题") {
                        TextField("任务标题", text: $draftTitle)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.medium))
                            .padding(14)
                            .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 14))
                    }

                    HStack(alignment: .top, spacing: 22) {
                        contractField("所属勋章") {
                            VStack(spacing: 8) {
                                Text(badgeDisplayName(draftBadge))
                                    .font(.headline)

                                MedalArtworkView(categoryName: draftBadge, rank: badgeRank(for: draftBadge))
                                    .frame(maxWidth: .infinity, maxHeight: 106)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 144, maxHeight: 144)
                            .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .frame(width: 220)

                        contractField("截止日期") {
                            DeadlinePresetWheelPicker(selection: $draftDeadlinePreset)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    contractField("完成奖励") {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("+\(draftXP) EXP", systemImage: "sparkles")
                                .font(.title3.bold())
                                .foregroundStyle(.orange)
                            Text("预计用时约 \(formattedEstimatedHours) 小时 · 1 小时 = 100 EXP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                    }

                    contractField("验收标准") {
                        Text(draftEvidenceRequirement)
                            .font(.body)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
                            .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 14))
                    }

                    contractField("证据照片") {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("需要 \(draftEvidenceImageCount) 张照片", systemImage: "photo.stack")
                                .font(.subheadline.weight(.semibold))

                            ForEach(Array(draftEvidenceImageDescriptions.enumerated()), id: \.offset) { index, description in
                                HStack(alignment: .top, spacing: 8) {
                                    if draftEvidenceImageCount <= 2 {
                                        Text("\(index + 1)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Color.accentColor, in: Circle())
                                    }
                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: saveTask) {
                        Label("确认并保存到本机", systemImage: "checkmark")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSaveDraft)
                    .opacity(canSaveDraft ? 1 : 0.45)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .glassEffect(
                        .regular.tint(Color.accentColor.opacity(0.16)).interactive(),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                    if let errorMessage {
                        statusBanner(icon: "exclamationmark.triangle.fill", message: errorMessage, color: .orange)
                    }
                }
                .padding(24)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .frame(maxWidth: 790)
            .padding(.horizontal, 36)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity)
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
            if isShowingArchivedTasks {
                archivedTaskListRoot(now: context.date)
            } else {
                taskListRoot(now: context.date)
            }
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
            .listRowInsets(EdgeInsets(top: 38, leading: 36, bottom: 12, trailing: 36))

            if selectedTasks.isEmpty {
                taskListEmptyState(for: selectedTaskTab)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 36, bottom: 36, trailing: 36))
            } else {
                ForEach(selectedTasks) { task in
                    let actions = taskRowActions(for: task, isArchived: false)
                    MouseDragSwipeRow(
                        actions: actions,
                        onSelect: { openTask(task) }
                    ) {
                        taskRow(task, now: now)
                    }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            taskSwipeActions(actions)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 7, leading: 36, bottom: 7, trailing: 36))
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
            HStack(alignment: .top, spacing: 12) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowingArchivedTasks = true
                    }
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("查看已归档任务")
                .help("查看已归档任务")

                pageHeader(
                    title: "任务",
                    subtitle: activeTaskContracts.isEmpty
                        ? "你保存的任务契约会出现在这里。"
                        : "\(unfinishedCount) 项未完成 · \(completedCount) 项已完成 · \(overdueCount) 项已逾期，全部保存在这台设备上。"
                )
            }

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

    private func archivedTaskListRoot(now: Date) -> some View {
        let archivedTasks = taskContracts
            .filter(\.isArchived)
            .sorted { ($0.archivedAt ?? $0.createdAt) > ($1.archivedAt ?? $1.createdAt) }

        return List {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowingArchivedTasks = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("返回任务")
                .help("返回任务")

                pageHeader(
                    title: "已归档",
                    subtitle: archivedTasks.isEmpty ? "归档的任务会保存在这里，不会出现在任务状态列表中。" : "共 \(archivedTasks.count) 项已归档任务。"
                )
            }
            .frame(maxWidth: 790, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 38, leading: 36, bottom: 12, trailing: 36))

            if archivedTasks.isEmpty {
                emptyState(icon: "archivebox", title: "还没有已归档任务", message: "向左滑动任何任务，即可将它归档。")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 36, bottom: 36, trailing: 36))
            } else {
                ForEach(archivedTasks) { task in
                    let actions = taskRowActions(for: task, isArchived: true)
                    MouseDragSwipeRow(
                        actions: actions,
                        onSelect: { openTask(task) }
                    ) {
                        taskRow(task, now: now)
                    }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            taskSwipeActions(actions)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 7, leading: 36, bottom: 7, trailing: 36))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func taskListTabs(
        unfinishedCount: Int,
        completedCount: Int,
        overdueCount: Int
    ) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
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
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                            Text(tab.title)
                            Text("\(count)")
                                .font(.caption.bold())
                                .monospacedDigit()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    (selectedTaskTab == tab ? tab.tint : Color.secondary).opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        .font(.subheadline.weight(selectedTaskTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTaskTab == tab ? tab.tint : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular
                            .tint(selectedTaskTab == tab ? tab.tint.opacity(0.12) : .clear)
                            .interactive(),
                        in: Capsule()
                    )
                    .accessibilityLabel("\(tab.title)，\(count) 项")
                    .accessibilityAddTraits(selectedTaskTab == tab ? .isSelected : [])
                }
            }
        }
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
        HStack(spacing: 16) {
            MedalArtworkView(
                categoryName: task.badgeCategory?.name,
                rank: task.badgeCategory?.userBadge?.rank ?? .bronze
            )
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Label(
                        task.deadline.formatted(date: .abbreviated, time: .shortened),
                        systemImage: task.deadline <= now ? "clock.badge.exclamationmark" : "clock"
                    )
                    Text("·")
                    Text(task.badgeCategory.map { badgeDisplayName($0.name) } ?? "未分类")
                }
                .font(.caption)
                .foregroundStyle(task.deadline <= now && task.status != .verified ? .red : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 9) {
                Text(taskListStatusTitle(for: task, now: now))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(taskListStatusColor(for: task, now: now))
                    .lineLimit(1)
                Text("+\(task.xpReward) EXP")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHint("查看任务契约详情")
    }

    @ViewBuilder
    private func taskSwipeActions(_ actions: [TaskRowAction]) -> some View {
        ForEach(Array(actions.reversed())) { action in
            Button(role: action.kind == .delete ? .destructive : nil) {
                action.perform()
            } label: {
                Label(action.title, systemImage: action.icon)
            }
            .tint(action.tint)
        }
    }

    private func taskDetailPage(_ task: TaskContract) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 18) {
                    Button {
                        withAnimation(.smooth(duration: 0.4)) {
                            selectedTask = nil
                        }
                    } label: {
                        Label("返回任务", systemImage: "chevron.left")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())

                    VStack(alignment: .leading, spacing: 7) {
                        Text(task.title)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text("任务契约")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusPill(for: task)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    detailCard(
                        title: "截止时间",
                        value: task.deadline.formatted(date: .long, time: .shortened),
                        icon: task.deadline < .now ? "clock.badge.exclamationmark" : "calendar.badge.clock",
                        tint: task.deadline < .now ? .red : .accentColor
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
                        tint: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("验收标准", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                        Spacer()
                        Label("已锁定", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .glassEffect(.regular, in: Capsule())
                    }

                    Text(task.evidenceRequirement)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()
                        .opacity(0.45)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("需要 \(task.requiredEvidenceImageCount) 张照片", systemImage: "photo.stack")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(task.evidenceImageDescriptions.enumerated()), id: \.offset) { index, description in
                            Text(task.requiredEvidenceImageCount <= 2 ? "\(index + 1). \(description)" : description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider()
                        .opacity(0.45)

                    Text("创建于 \(task.createdAt.formatted(date: .long, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(22)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                if task.isArchived {
                    statusBanner(
                        icon: "archivebox.fill",
                        message: "这项任务已归档。向左滑动并选择“取消归档”后，才能继续提交证据。",
                        color: .orange
                    )
                } else {
                    EvidenceSubmissionView(task: task)
                    taskReminderDetail(for: task)
                }
            }
            .frame(maxWidth: 790)
            .padding(.horizontal, 36)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity)
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
                pageHeader(title: "勋章", subtitle: "收集碎片，铸造属于每个领域的勋章。点开后可回顾历史任务和证据。")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
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
            .frame(maxWidth: 790)
            .padding(.horizontal, 36)
            .padding(.vertical, 38)
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
                .font(.title3.bold())
                .lineLimit(1)

            MedalFragmentStatusLabel(currentXP: currentXP, wording: .earned)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            .filter { $0.badgeCategory?.name == badge }
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
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())

                    Text(badgeDisplayName(badge))
                        .font(.largeTitle.bold())

                    Spacer()
                }

                MedalDetailHeroView(categoryName: badge, currentXP: currentXP, rank: rank)

                #if DEBUG
                debugXPControls(for: badge)
                #endif

                Text("历史任务与证据")
                    .font(.headline)

                if historyTasks.isEmpty {
                    emptyState(
                        icon: "clock.arrow.circlepath",
                        title: "还没有历史任务",
                        message: "完成一项属于「\(badgeDisplayName(badge))」的任务后，会出现在这里，方便随时回顾证据截图。"
                    )
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(historyTasks) { task in
                            libraryTaskRow(task)
                        }
                    }
                }
            }
            .frame(maxWidth: 790)
            .padding(.horizontal, 36)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity)
        }
    }

    private func libraryTaskRow(_ task: TaskContract) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.4)) {
                selectedLibraryBadge = nil
                selectedPage = .tasks
                selectedTask = task
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 7) {
                        statusPill(for: task)
                        Text("+\(task.xpReward) EXP")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }

                if !task.evidences.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(task.evidences.sorted { $0.submittedAt < $1.submittedAt }) { evidence in
                                libraryEvidenceThumbnail(evidence)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func libraryEvidenceThumbnail(_ evidence: Evidence) -> some View {
        Group {
            if let imageData = evidence.imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 66)
        .background(.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    #if DEBUG
    /// Debug-only quick actions to add or remove XP for a badge with a tap,
    /// so level-up thresholds and the Library UI can be tested without
    /// completing real tasks. Never shown in release builds.
    private func debugXPControls(for badge: String) -> some View {
        HStack(spacing: 10) {
            Label("调试", systemImage: "ladybug.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach([25, 100, 500, 1000], id: \.self) { amount in
                Button("+\(amount)") {
                    debugAddXP(amount, toBadge: badge)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(Color.purple.opacity(0.12)).interactive(), in: Capsule())
            }

            Button("重置") {
                debugAddXP(nil, toBadge: badge)
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(Color.red.opacity(0.10)).interactive(), in: Capsule())

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

    private func selectPage(_ page: AppPage) {
        if page == selectedPage {
            if page == .tasks {
                withAnimation(.smooth(duration: 0.38)) {
                    selectedTask = nil
                }
            }
            return
        }

        if page == .tasks, selectedTask != nil {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTask = nil
            }
        }

        withAnimation(.smooth(duration: 0.38)) {
            selectedPage = page
        }
    }

    private func generateTask() {
        guard !trimmedTaskInput.isEmpty, !isGenerating else { return }

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let contract = try await generationService.generate(from: trimmedTaskInput)
                guard let deadline = contract.parsedDeadline else {
                    throw TaskGenerationError.invalidResponse
                }

                draftTitle = contract.title
                draftDeadlinePreset = deadlinePreset(for: deadline, relativeTo: .now)
                draftEvidenceRequirement = contract.evidenceRequirement
                draftEvidenceImageCount = contract.evidenceImageCount
                draftEvidenceImageDescriptions = contract.evidenceImageDescriptions
                draftBadge = Self.badgeOptions.contains(contract.suggestedBadge)
                    ? contract.suggestedBadge
                    : Self.badgeOptions[0]
                draftEstimatedHours = contract.estimatedHours
                draftXP = contract.suggestedXP

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
                badgeCategory: category
            )
            modelContext.insert(task)
            try modelContext.save()
            scheduleReminderAfterSave(
                LocalTaskReminder(taskID: task.id, title: task.title, deadline: task.deadline)
            )

            taskInput = ""
            errorMessage = nil
            withAnimation(.smooth(duration: 0.44)) {
                creationPhase = .composing
                savedMessage = "“\(title)”已保存到本机"
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
            selectedTask = task
        }
    }

    private func taskRowActions(for task: TaskContract, isArchived: Bool) -> [TaskRowAction] {
        let secondaryAction = TaskRowAction(
            kind: isArchived ? .restore : .archive,
            perform: isArchived ? { restoreTask(task) } : { archiveTask(task) }
        )
        let deleteAction = TaskRowAction(kind: .delete) {
            deleteTask(task)
        }
        return [secondaryAction, deleteAction]
    }

    private func archiveTask(_ task: TaskContract) {
        task.archivedAt = .now
        persistTaskChange(successMessage: "“\(task.title)”已归档")
    }

    private func restoreTask(_ task: TaskContract) {
        task.archivedAt = nil
        persistTaskChange(successMessage: "“\(task.title)”已恢复到任务列表")
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

    private var buttonTitle: String {
        if isGenerating { return "正在整理契约" }
        return errorMessage == nil ? "提交" : "保留输入并重试"
    }

    private var canSaveDraft: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draftEvidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            draftDeadlinePreset.map { taskDeadline(for: $0, relativeTo: .now) > Date.now } == true
    }

    private func taskDeadline(for preset: TaskDeadlinePreset, relativeTo date: Date) -> Date {
        let calendar = Calendar.current
        let targetDay = calendar.date(byAdding: .day, value: preset.dayOffset, to: date) ?? date
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: targetDay) ?? targetDay
    }

    private func deadlinePreset(for deadline: Date, relativeTo date: Date) -> TaskDeadlinePreset {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: date)
        let startOfDeadline = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfDeadline).day ?? 0

        if days <= 0 { return .today }
        if days == 1 { return .tomorrow }
        return .nextWeek
    }

    private var formattedEstimatedHours: String {
        draftEstimatedHours.formatted(.number.precision(.fractionLength(0...2)))
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
        taskContracts.filter { !$0.isArchived }
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
                    let lhsCompletedAt = lhs.evidences
                        .filter { $0.verdict == .verified }
                        .map(\.submittedAt)
                        .max() ?? lhs.createdAt
                    let rhsCompletedAt = rhs.evidences
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
            return .red
        }

        return switch task.status {
        case .pending, .awaitingVerification: .accentColor
        case .verified: .green
        case .needMoreProof: .orange
        case .notVerified: .red
        }
    }

    private func statusPill(for task: TaskContract) -> some View {
        let presentation: (title: String, icon: String, color: Color)
        if task.status != .verified, task.deadline <= .now {
            presentation = ("已逾期", "exclamationmark.circle.fill", .red)
        } else {
            presentation = switch task.status {
            case .pending:
                ("待完成", "circle.dashed", .accentColor)
            case .awaitingVerification:
                ("等待核验", "hourglass", .accentColor)
            case .verified:
                ("已完成", "checkmark.circle.fill", .green)
            case .needMoreProof:
                ("需补充证据", "photo.badge.plus", .orange)
            case .notVerified:
                ("未通过核验", "xmark.circle.fill", .red)
            }
        }

        return Label(presentation.title, systemImage: presentation.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(presentation.color.opacity(0.10)), in: Capsule())
    }

    @ViewBuilder
    private var reminderStatusBanner: some View {
        if let reminderFeedback {
            statusBanner(
                icon: reminderFeedbackIsError ? "bell.slash.fill" : "bell.badge.fill",
                message: reminderFeedback,
                color: reminderFeedbackIsError ? .orange : .green
            )
        } else {
            switch reminderAuthorization {
            case .authorized:
                statusBanner(icon: "bell.badge.fill", message: "截止提醒已开启；未来任务会在截止时间发送系统通知。", color: .green)
            case .denied:
                statusBanner(icon: "bell.slash.fill", message: "系统通知已关闭。任务仍会保存在本机；可在系统设置中为 LifeMedals 开启通知。", color: .orange)
            case .notDetermined:
                statusBanner(icon: "bell", message: "保存未来任务时，系统会询问是否允许截止提醒。", color: .accentColor)
            }
        }
    }

    private func detailCard(title: String, value: String, icon: String, tint: Color) -> some View {
        detailCard(title: title, value: value) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(tint.opacity(0.10)), in: Circle())
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
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    @ViewBuilder
    private func taskReminderDetail(for task: TaskContract) -> some View {
        if task.deadline <= .now {
            statusBanner(icon: "clock.badge.exclamationmark", message: "这项任务已过截止时间，不再安排新的系统提醒。", color: .red)
        } else {
            switch reminderAuthorization {
            case .authorized:
                statusBanner(
                    icon: "bell.badge.fill",
                    message: "将在 \(task.deadline.formatted(date: .long, time: .shortened)) 发送本地通知。",
                    color: .green
                )
            case .denied:
                statusBanner(icon: "bell.slash.fill", message: "系统通知权限已关闭；任务本身不受影响。", color: .orange)
            case .notDetermined:
                statusBanner(icon: "bell", message: "尚未授予通知权限。新建任务时可以开启截止提醒。", color: .accentColor)
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
        Task { @MainActor in
            isTaskInputFocused = true
        }
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
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func statusBanner(icon: String, message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 15))
        .glassEffect(.regular.tint(color.opacity(0.08)), in: RoundedRectangle(cornerRadius: 15))
    }

    private func saveConfirmation(message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(.green.opacity(0.10)), in: Capsule())

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
