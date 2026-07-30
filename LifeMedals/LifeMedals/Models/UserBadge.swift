//
//  UserBadge.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/30.
//

import Foundation
import SwiftData

/// 每个勋章类别独立累计的当前 EXP 和等级。
@Model
final class UserBadge {
    @Attribute(.unique) var id: UUID
    var currentXP: Int
    var level: Int

    var category: BadgeCategory?

    init(
        id: UUID = UUID(),
        currentXP: Int = 0,
        level: Int = 1,
        category: BadgeCategory? = nil
    ) {
        self.id = id
        self.currentXP = currentXP
        self.level = level
        self.category = category
    }
}
