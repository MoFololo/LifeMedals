//
//  TaskContract.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/30.
//

import Foundation
import SwiftData

/// 任务契约的当前状态。原始值持久化，新增枚举值时不会破坏已有数据。
enum TaskStatus: String, Codable {
    case pending
    case awaitingVerification
    case verified
    case needMoreProof
    case notVerified
}

/// Only one level of grouping is supported. Optional storage keeps every
/// task created before task groups compatible with lightweight migration.
enum TaskHierarchyRole: String, Codable {
    case group
    case child
}

/// 任务契约：标题、截止时间、锁定的验收标准、所属勋章、XP 奖励和状态。
///
/// - Important: `evidenceRequirement` 一旦用户确认任务，即为锁定值，
///   AI 核验阶段不能再修改或重新解释它。
@Model
final class TaskContract {
    var id: UUID = UUID()
    var title: String = ""
    var deadline: Date = Date.now
    var evidenceRequirement: String = ""
    /// Optional backing values keep existing local stores lightweight-migration compatible.
    /// Tasks created before evidence planning default to one photo.
    var evidenceImageCount: Int?
    var evidenceImageDescriptionsJSON: String?
    var xpReward: Int = 0
    var statusRawValue: String = TaskStatus.pending.rawValue
    var createdAt: Date = Date.now
    /// Nil means the task is active. Optional storage keeps existing local stores migration-compatible.
    var archivedAt: Date?
    /// Nil means this is a legacy/standalone task.
    var hierarchyRoleRawValue: String?
    /// Stable identifier avoids a CloudKit-sensitive self relationship.
    var parentTaskID: UUID?
    /// Stable source order for children. Nil for standalone tasks and groups.
    var childOrder: Int?
    /// Parent containers have no evidence, so this records their completion time.
    var groupCompletedAt: Date?
    /// App-owned compressed copy of the image that was used to generate this task.
    /// Optional external storage keeps text-created tasks and existing stores migration-compatible.
    @Attribute(.externalStorage) var sourceImageData: Data?

    // Optional monster encounter fields keep legacy stores and CloudKit
    // lightweight migration compatible. A task group parent intentionally
    // leaves every field nil; only independently verifiable tasks encounter a
    // monster.
    var monsterTag: String?
    var monsterDisplayName: String?
    var monsterLevel: Int?
    var monsterVariantID: String?
    var monsterImageURL: String?
    var monsterStyleVersion: String?

    var badgeCategory: BadgeCategory?

    @Relationship(deleteRule: .cascade, inverse: \Evidence.taskContract)
    var evidences: [Evidence]?

    @Relationship(deleteRule: .cascade, inverse: \XPLog.taskContract)
    var xpLogs: [XPLog]?

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    var hierarchyRole: TaskHierarchyRole? {
        get { hierarchyRoleRawValue.flatMap(TaskHierarchyRole.init(rawValue:)) }
        set { hierarchyRoleRawValue = newValue?.rawValue }
    }

    var isTaskGroup: Bool {
        hierarchyRole == .group && parentTaskID == nil
    }

    var isSubtask: Bool {
        hierarchyRole == .child && parentTaskID != nil
    }

    var requiredEvidenceImageCount: Int {
        min(max(evidenceImageCount ?? 1, 1), 5)
    }

    var evidenceImageDescriptions: [String] {
        get {
            guard
                let evidenceImageDescriptionsJSON,
                let data = evidenceImageDescriptionsJSON.data(using: .utf8),
                let descriptions = try? JSONDecoder().decode([String].self, from: data),
                !descriptions.isEmpty
            else {
                return [evidenceRequirement]
            }
            return descriptions
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            evidenceImageDescriptionsJSON = String(data: data, encoding: .utf8)
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        deadline: Date,
        evidenceRequirement: String,
        evidenceImageCount: Int = 1,
        evidenceImageDescriptions: [String] = [],
        xpReward: Int,
        status: TaskStatus = .pending,
        createdAt: Date = .now,
        archivedAt: Date? = nil,
        hierarchyRole: TaskHierarchyRole? = nil,
        parentTaskID: UUID? = nil,
        childOrder: Int? = nil,
        groupCompletedAt: Date? = nil,
        sourceImageData: Data? = nil,
        monsterTag: String? = nil,
        monsterDisplayName: String? = nil,
        monsterLevel: Int? = nil,
        monsterVariantID: String? = nil,
        monsterImageURL: String? = nil,
        monsterStyleVersion: String? = nil,
        badgeCategory: BadgeCategory? = nil
    ) {
        self.id = id
        self.title = title
        self.deadline = deadline
        self.evidenceRequirement = evidenceRequirement
        self.evidenceImageCount = min(max(evidenceImageCount, 1), 5)
        let normalizedDescriptions = evidenceImageDescriptions.isEmpty
            ? [evidenceRequirement]
            : evidenceImageDescriptions
        let descriptionsData = try? JSONEncoder().encode(normalizedDescriptions)
        self.evidenceImageDescriptionsJSON = descriptionsData.flatMap {
            String(data: $0, encoding: .utf8)
        }
        self.xpReward = xpReward
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.hierarchyRoleRawValue = hierarchyRole?.rawValue
        self.parentTaskID = hierarchyRole == .child ? parentTaskID : nil
        self.childOrder = hierarchyRole == .child ? childOrder : nil
        self.groupCompletedAt = hierarchyRole == .group ? groupCompletedAt : nil
        self.sourceImageData = sourceImageData
        self.monsterTag = monsterTag
        self.monsterDisplayName = monsterDisplayName
        self.monsterLevel = monsterLevel.map { min(max($0, 1), 9) }
        self.monsterVariantID = monsterVariantID
        self.monsterImageURL = monsterImageURL
        self.monsterStyleVersion = monsterStyleVersion
        self.badgeCategory = badgeCategory
    }
}
