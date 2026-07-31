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

    private static let badgeOptions = [
        "Problem Solver",
        "Builder",
        "Career",
        "Athlete"
    ]

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
    @FocusState private var isTaskInputFocused: Bool

    @State private var draftTitle = ""
    @State private var draftDeadline = Date.now.addingTimeInterval(24 * 60 * 60)
    @State private var draftEvidenceRequirement = ""
    @State private var draftBadge = "Problem Solver"
    @State private var draftXP = 10

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
                    switch selectedPage {
                    case .create:
                        creationPage
                            .transition(pageTransition)
                    case .tasks:
                        taskListPage
                            .transition(pageTransition)
                    case .medals:
                        medalsPage
                            .transition(pageTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let savedMessage {
                saveConfirmation(message: savedMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
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
            }
        }
        .task {
            await restoreTaskReminders()
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
                            withAnimation(.smooth(duration: 0.38)) {
                                selectedPage = page
                                if page == .tasks {
                                    selectedTask = nil
                                }
                            }
                        } label: {
                            Label(page.title, systemImage: page.icon)
                                .font(.subheadline.weight(selectedPage == page ? .semibold : .medium))
                                .foregroundStyle(selectedPage == page ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
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
        ScrollView {
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
                        contractField("截止时间") {
                            PlatformWheelDatePicker(selection: $draftDeadline)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 18) {
                            contractField("所属勋章") {
                                Picker("所属勋章", selection: $draftBadge) {
                                    ForEach(Self.badgeOptions, id: \.self) { badge in
                                        Label(badgeDisplayName(badge), systemImage: badgeIconName(badge))
                                            .tag(badge)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            contractField("完成奖励") {
                                Label("+\(draftXP) EXP", systemImage: "sparkles")
                                    .font(.title3.bold())
                                    .foregroundStyle(.orange)
                                    .padding(.vertical, 7)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    contractField("验收标准") {
                        TextEditor(text: $draftEvidenceRequirement)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 105)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    title: "任务",
                    subtitle: taskContracts.isEmpty
                        ? "你保存的任务契约会出现在这里。"
                        : "\(pendingTasks.count) 项待处理 · \(verifiedTasks.count) 项 Verified，全部保存在这台设备上。"
                )

                reminderStatusBanner

                if taskContracts.isEmpty {
                    emptyState(icon: "checklist", title: "还没有任务", message: "从“新任务”开始写下第一件想完成的事。")
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(visibleTasks) { task in
                            taskRow(task)
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

    private func taskRow(_ task: TaskContract) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.4)) {
                selectedTask = task
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: task.badgeCategory?.iconName ?? "medal.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(.orange.opacity(0.12)), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        Label(
                            task.deadline.formatted(date: .abbreviated, time: .shortened),
                            systemImage: task.deadline < .now ? "clock.badge.exclamationmark" : "clock"
                        )
                        Text("·")
                        Text(task.badgeCategory.map { badgeDisplayName($0.name) } ?? "未分类")
                    }
                    .font(.caption)
                    .foregroundStyle(task.deadline < .now ? .red : .secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 9) {
                    Text(taskListStatusTitle(task.status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(taskListStatusColor(task.status))
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
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHint("查看任务契约详情")
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
                        value: task.badgeCategory.map { badgeDisplayName($0.name) } ?? "未分类",
                        icon: task.badgeCategory?.iconName ?? "medal.fill",
                        tint: .orange
                    )
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

                    Text("创建于 \(task.createdAt.formatted(date: .long, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(22)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                EvidenceSubmissionView(task: task)

                taskReminderDetail(for: task)
            }
            .frame(maxWidth: 790)
            .padding(.horizontal, 36)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Medals

    private var medalsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(title: "勋章", subtitle: "每个领域独立积累经验与等级。")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], spacing: 16) {
                    ForEach(Self.badgeOptions, id: \.self) { badge in
                        medalCard(for: badge)
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
        let level = category?.userBadge?.level ?? 1
        let currentXP = category?.userBadge?.currentXP ?? 0
        let taskCount = category?.taskContracts.count ?? 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: badgeIconName(badge))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.tint(.orange.opacity(0.13)), in: Circle())
                Spacer()
                Text("Lv. \(level)")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(badgeDisplayName(badge))
                    .font(.headline)
                Text("\(currentXP) EXP · \(taskCount) 个任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Actions

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
                draftDeadline = deadline
                draftEvidenceRequirement = contract.evidenceRequirement
                draftBadge = Self.badgeOptions.contains(contract.suggestedBadge)
                    ? contract.suggestedBadge
                    : Self.badgeOptions[0]
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
        guard !title.isEmpty, !requirement.isEmpty else { return }

        do {
            let category: BadgeCategory
            if let existingCategory = badgeCategories.first(where: { $0.name == draftBadge }) {
                category = existingCategory
            } else {
                category = BadgeCategory(name: draftBadge, iconName: badgeIconName(draftBadge))
                let userBadge = UserBadge(category: category)
                category.userBadge = userBadge
                modelContext.insert(category)
                modelContext.insert(userBadge)
            }

            let task = TaskContract(
                title: title,
                deadline: draftDeadline,
                evidenceRequirement: requirement,
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

    // MARK: - Helpers

    private var pageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985))
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
            !draftEvidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pendingTasks: [TaskContract] {
        taskContracts
            .filter { $0.status != .verified }
            .sorted {
                if ($0.deadline < .now) != ($1.deadline < .now) {
                    return $0.deadline < .now
                }
                return $0.deadline < $1.deadline
            }
    }

    private var verifiedTasks: [TaskContract] {
        taskContracts.filter { $0.status == .verified }
    }

    private var visibleTasks: [TaskContract] {
        taskContracts.sorted { lhs, rhs in
            if (lhs.status == .verified) != (rhs.status == .verified) {
                return lhs.status != .verified
            }
            if lhs.status == .verified {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.deadline < rhs.deadline
        }
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(tint.opacity(0.10)), in: Circle())

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

    private func taskListStatusTitle(_ status: TaskStatus) -> String {
        switch status {
        case .pending: "待完成"
        case .awaitingVerification: "Pending Verification"
        case .verified: "Verified"
        case .needMoreProof: "Need More Proof"
        case .notVerified: "Not Verified"
        }
    }

    private func taskListStatusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .pending, .awaitingVerification: .accentColor
        case .verified: .green
        case .needMoreProof: .orange
        case .notVerified: .red
        }
    }

    private func statusPill(for task: TaskContract) -> some View {
        let presentation: (title: String, icon: String, color: Color) = switch task.status {
        case .pending:
            (task.deadline < .now ? "已逾期" : "待完成", task.deadline < .now ? "exclamationmark.circle.fill" : "circle.dashed", task.deadline < .now ? .red : .accentColor)
        case .awaitingVerification:
            ("等待核验", "hourglass", .accentColor)
        case .verified:
            ("已完成", "checkmark.circle.fill", .green)
        case .needMoreProof:
            ("需补充证据", "photo.badge.plus", .orange)
        case .notVerified:
            ("未通过核验", "xmark.circle.fill", .red)
        }

        return Label(presentation.title, systemImage: presentation.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(presentation.color.opacity(0.10)), in: Capsule())
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
        switch badge {
        case "Problem Solver": "解题者"
        case "Builder": "创造者"
        case "Career": "职业成长"
        case "Athlete": "运动者"
        default: badge
        }
    }

    private func badgeIconName(_ badge: String) -> String {
        switch badge {
        case "Problem Solver": "brain.head.profile"
        case "Builder": "hammer.fill"
        case "Career": "briefcase.fill"
        case "Athlete": "figure.run"
        default: "medal.fill"
        }
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
