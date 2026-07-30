//
//  XPLog.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/30.
//

import Foundation
import SwiftData

/// 每次 EXP 变动记录，关联任务和勋章，用于周报与历史回顾。
@Model
final class XPLog {
    @Attribute(.unique) var id: UUID
    var amount: Int
    var timestamp: Date

    var taskContract: TaskContract?
    var badgeCategory: BadgeCategory?

    init(
        id: UUID = UUID(),
        amount: Int,
        timestamp: Date = .now,
        taskContract: TaskContract? = nil,
        badgeCategory: BadgeCategory? = nil
    ) {
        self.id = id
        self.amount = amount
        self.timestamp = timestamp
        self.taskContract = taskContract
        self.badgeCategory = badgeCategory
    }
}
