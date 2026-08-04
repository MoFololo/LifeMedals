//
//  XPService.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/8/1.
//

import Foundation
import SwiftData

struct XPAwardEvent: Identifiable, Sendable {
    let id = UUID()
    let categoryName: String
    let amount: Int
    let previousXP: Int
    let currentXP: Int
    let previousRank: BadgeRank
    let currentRank: BadgeRank
}

extension Notification.Name {
    static let xpAwarded = Notification.Name("LifeMedals.xpAwarded")
}

/// Awards XP for a verified task: writes an immutable `XPLog` entry and
/// updates the task's badge category's cumulative EXP and rank/level.
///
/// This is the single place that turns a "Verified" evidence result into
/// permanent progress, so every call site (currently only evidence
/// verification) shares the same accounting and rank recalculation.
enum XPService {
    @MainActor
    @discardableResult
    static func awardXP(for task: TaskContract, in context: ModelContext) -> XPAwardEvent? {
        // A task is only ever rewarded once; this also guards against
        // accidentally double-awarding if verification is ever retried after
        // a task already reached `.verified`.
        guard task.xpLogs.isEmpty else { return nil }
        guard let category = task.badgeCategory else { return nil }

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

        let previousXP = badge.currentXP
        let previousRank = BadgeRank.rank(forCumulativeXP: previousXP)
        badge.currentXP += task.xpReward
        let currentRank = BadgeRank.rank(forCumulativeXP: badge.currentXP)
        badge.level = currentRank.rawValue

        let event = XPAwardEvent(
            categoryName: category.name,
            amount: task.xpReward,
            previousXP: previousXP,
            currentXP: badge.currentXP,
            previousRank: previousRank,
            currentRank: currentRank
        )
        return event
    }

    #if DEBUG
    /// Debug-only shortcut for manually granting (or, with a negative amount,
    /// removing) XP for a badge category without a real verified task —
    /// lets development builds quickly test level-up thresholds and the
    /// Library UI. Never call this from release/user-facing code paths.
    @MainActor
    @discardableResult
    static func debugAddXP(_ amount: Int, to category: BadgeCategory, in context: ModelContext) -> XPAwardEvent? {
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

        let previousXP = badge.currentXP
        let previousRank = BadgeRank.rank(forCumulativeXP: previousXP)
        badge.currentXP = max(0, badge.currentXP + amount)
        let currentRank = BadgeRank.rank(forCumulativeXP: badge.currentXP)
        badge.level = currentRank.rawValue

        guard amount > 0, badge.currentXP > previousXP else { return nil }
        let event = XPAwardEvent(
            categoryName: category.name,
            amount: badge.currentXP - previousXP,
            previousXP: previousXP,
            currentXP: badge.currentXP,
            previousRank: previousRank,
            currentRank: currentRank
        )
        return event
    }
    #endif

    @MainActor
    static func publishAward(_ event: XPAwardEvent) {
        NotificationCenter.default.post(name: .xpAwarded, object: event)
    }
}
