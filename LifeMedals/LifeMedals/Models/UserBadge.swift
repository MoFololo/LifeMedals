//
//  UserBadge.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/30.
//

import Foundation
import SwiftData

/// 每个勋章类别独立累计的当前 EXP 和等级。
///
/// `level` stores the raw value of the current `BadgeRank` (1 = 青铜 ...
/// 9 = 王者) and is kept in sync with `currentXP` by `XPService`.
@Model
final class UserBadge {
    var id: UUID = UUID()
    var currentXP: Int = 0
    var level: Int = 1

    var category: BadgeCategory?

    /// The current medal tier, derived from `level`. Falls back to `.bronze`
    /// if `level` is ever out of range.
    var rank: BadgeRank {
        BadgeRank(rawValue: level) ?? .bronze
    }

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
