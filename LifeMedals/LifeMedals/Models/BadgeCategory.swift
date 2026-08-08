//
//  BadgeCategory.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/30.
//

import Foundation
import SwiftData

/// 勋章类别（如 Problem Solver / Builder / Athlete...），支持用户自定义新增。
@Model
final class BadgeCategory {
    /// CloudKit doesn't support database-enforced uniqueness. UUIDs remain the
    /// stable application identifier and duplicate protection happens in app logic.
    var id: UUID = UUID()
    var name: String = ""
    /// Kept for compatibility with existing SwiftData stores. Medal UI no
    /// longer reads this legacy SF Symbol value; it uses MedalVisualSystem.
    var iconName: String = "medal.fill"
    var isCustom: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \UserBadge.category)
    var userBadge: UserBadge?

    @Relationship(deleteRule: .nullify, inverse: \TaskContract.badgeCategory)
    var taskContracts: [TaskContract]?

    @Relationship(deleteRule: .nullify, inverse: \XPLog.badgeCategory)
    var xpLogs: [XPLog]?

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "medal.fill",
        isCustom: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.isCustom = isCustom
        self.createdAt = createdAt
    }
}
