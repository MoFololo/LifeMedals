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

/// 任务契约：标题、截止时间、锁定的验收标准、所属勋章、XP 奖励和状态。
///
/// - Important: `evidenceRequirement` 一旦用户确认任务，即为锁定值，
///   AI 核验阶段不能再修改或重新解释它。
@Model
final class TaskContract {
    @Attribute(.unique) var id: UUID
    var title: String
    var deadline: Date
    var evidenceRequirement: String
    var xpReward: Int
    var statusRawValue: String
    var createdAt: Date

    var badgeCategory: BadgeCategory?

    @Relationship(deleteRule: .cascade, inverse: \Evidence.taskContract)
    var evidences: [Evidence] = []

    @Relationship(deleteRule: .cascade, inverse: \XPLog.taskContract)
    var xpLogs: [XPLog] = []

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        deadline: Date,
        evidenceRequirement: String,
        xpReward: Int,
        status: TaskStatus = .pending,
        createdAt: Date = .now,
        badgeCategory: BadgeCategory? = nil
    ) {
        self.id = id
        self.title = title
        self.deadline = deadline
        self.evidenceRequirement = evidenceRequirement
        self.xpReward = xpReward
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.badgeCategory = badgeCategory
    }
}
