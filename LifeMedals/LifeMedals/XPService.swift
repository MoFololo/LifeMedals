//
//  XPService.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/8/1.
//

import Foundation
import SwiftData

/// Awards XP for a verified task: writes an immutable `XPLog` entry and
/// updates the task's badge category's cumulative EXP and rank/level.
///
/// This is the single place that turns a "Verified" evidence result into
/// permanent progress, so every call site (currently only evidence
/// verification) shares the same accounting and rank recalculation.
enum XPService {
    @MainActor
    static func awardXP(for task: TaskContract, in context: ModelContext) {
        // A task is only ever rewarded once; this also guards against
        // accidentally double-awarding if verification is ever retried after
        // a task already reached `.verified`.
        guard task.xpLogs.isEmpty else { return }
        guard let category = task.badgeCategory else { return }

        let badge: UserBadge
        if let existing = category.userBadge {
            badge = existing
        } else {
            badge = UserBadge(category: category)
            category.userBadge = badge
            context.insert(badge)
        }

        let log = XPLog(amount: task.xpReward, taskContract: task, badgeCategory: category)
        context.insert(log)

        badge.currentXP += task.xpReward
        badge.level = BadgeRank.rank(forCumulativeXP: badge.currentXP).rawValue
    }

    #if DEBUG
    /// Debug-only shortcut for manually granting (or, with a negative amount,
    /// removing) XP for a badge category without a real verified task —
    /// lets development builds quickly test level-up thresholds and the
    /// Library UI. Never call this from release/user-facing code paths.
    @MainActor
    static func debugAddXP(_ amount: Int, to category: BadgeCategory, in context: ModelContext) {
        let badge: UserBadge
        if let existing = category.userBadge {
            badge = existing
        } else {
            badge = UserBadge(category: category)
            category.userBadge = badge
            context.insert(badge)
        }

        let log = XPLog(amount: amount, badgeCategory: category)
        context.insert(log)

        badge.currentXP = max(0, badge.currentXP + amount)
        badge.level = BadgeRank.rank(forCumulativeXP: badge.currentXP).rawValue
    }
    #endif
}
