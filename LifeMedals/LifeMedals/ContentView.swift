//
//  ContentView.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/29.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private static let badgeOptions = [
        "Problem Solver",
        "Builder",
        "Career",
        "Athlete"
    ]

    @Environment(\.modelContext) private var modelContext
    @Query private var badgeCategories: [BadgeCategory]
    @Query private var taskContracts: [TaskContract]

    @AppStorage("pendingTaskInput") private var taskInput = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    @State private var showsDraft = false
    @State private var draftTitle = ""
    @State private var draftDeadline = Date.now.addingTimeInterval(24 * 60 * 60)
    @State private var draftEvidenceRequirement = ""
    @State private var draftBadge = "Problem Solver"
    @State private var draftXP = 10

    private let generationService = TaskGenerationService()

    var body: some View {
        ZStack {
            backgroundView

            GlassEffectContainer(spacing: 18) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        HStack(alignment: .top, spacing: 18) {
                            inputCard
                            if showsDraft {
                                contractCard
                            } else {
                                emptyContractCard
                            }
                        }

                        if let savedMessage {
                            statusBanner(
                                icon: "checkmark.circle.fill",
                                message: savedMessage,
                                color: .green
                            )
                        }
                    }
                    .padding(28)
                }
            }
        }
        .frame(minWidth: 920, minHeight: 680)
    }

    // MARK: - Main sections

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 54, height: 54)
                Image(systemName: "medal.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.yellow)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("创建一份任务契约")
                    .font(.title.bold())
                Text("说出你准备完成的事，AI 会把它整理成可编辑的行动计划。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(taskContracts.count)")
                    .font(.title2.bold())
                Text("已保存任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("你想完成什么？", systemImage: "sparkles")
                .font(.headline)

            TextEditor(text: $taskInput)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 170)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    if taskInput.isEmpty {
                        Text("例如：明晚 10 点前完成两道 LeetCode Medium")
                            .foregroundStyle(.tertiary)
                            .padding(18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .allowsHitTesting(false)
                    }
                }

            Text("输入会自动保存在本机。断网或请求失败后，可以原样重试。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                statusBanner(icon: "wifi.exclamationmark", message: errorMessage, color: .orange)
            }

            Button(action: generateTask) {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: errorMessage == nil ? "wand.and.stars" : "arrow.clockwise")
                    }
                    Text(errorMessage == nil ? "生成任务契约" : "保留输入并重试")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating || taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var contractCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("确认任务契约", systemImage: "doc.text.fill")
                    .font(.headline)
                Spacer()
                Text("可编辑")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            fieldLabel("任务标题")
            TextField("任务标题", text: $draftTitle)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

            fieldLabel("截止时间")
            DatePicker(
                "截止时间",
                selection: $draftDeadline,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()

            fieldLabel("验收标准")
            TextEditor(text: $draftEvidenceRequirement)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 105)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    fieldLabel("所属勋章")
                    Picker("所属勋章", selection: $draftBadge) {
                        ForEach(Self.badgeOptions, id: \.self) { badge in
                            Text(badgeDisplayName(badge)).tag(badge)
                        }
                    }
                    .labelsHidden()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 7) {
                    fieldLabel("完成奖励")
                    Text("+\(draftXP) EXP")
                        .font(.headline)
                        .foregroundStyle(.yellow)
                }
            }

            Button(action: saveTask) {
                Label("确认并保存到本机", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .disabled(!canSaveDraft)
            .opacity(canSaveDraft ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var emptyContractCard: some View {
        VStack(spacing: 15) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text("生成结果会出现在这里")
                .font(.headline)
            Text("标题、日期、验收标准和勋章都可以在保存前修改。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(22)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: - Actions

    private func generateTask() {
        let input = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isGenerating = true
        errorMessage = nil
        savedMessage = nil

        Task {
            do {
                let contract = try await generationService.generate(from: input)
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
                showsDraft = true
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
                category = BadgeCategory(
                    name: draftBadge,
                    iconName: badgeIconName(draftBadge)
                )
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

            savedMessage = "“\(title)”已保存，可在断网状态下继续访问。"
            taskInput = ""
            errorMessage = nil
            showsDraft = false
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private var canSaveDraft: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draftEvidenceRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
    }

    private func badgeDisplayName(_ badge: String) -> String {
        switch badge {
        case "Problem Solver": "解题者 · Problem Solver"
        case "Builder": "创造者 · Builder"
        case "Career": "职业成长 · Career"
        case "Athlete": "运动者 · Athlete"
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

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.13),
                    Color(red: 0.10, green: 0.045, blue: 0.16),
                    Color(red: 0.025, green: 0.09, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.purple.opacity(0.46))
                .frame(width: 460, height: 460)
                .blur(radius: 135)
                .offset(x: -360, y: -250)
            Circle()
                .fill(.blue.opacity(0.42))
                .frame(width: 430, height: 430)
                .blur(radius: 140)
                .offset(x: 380, y: 250)
            Circle()
                .fill(.pink.opacity(0.24))
                .frame(width: 340, height: 340)
                .blur(radius: 130)
                .offset(x: 330, y: -270)
        }
        .ignoresSafeArea()
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
