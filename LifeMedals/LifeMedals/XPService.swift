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
        guard task.xpLogs?.isEmpty != false else { return nil }
        // Child XP is an effort estimate rolled into its parent reward. It is
        // never credited directly, even if a verification callback is replayed.
        guard !task.isSubtask else { return nil }
        // A group is rewardable only after the coordinator has completed it.
        guard !task.isTaskGroup || task.status == .verified else { return nil }
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

/// Reconciles a one-level task group after child verification or deletion.
/// `XPLog` remains the durable idempotency boundary; recomputing this on app
/// launch or after CloudKit callbacks cannot grant the group twice.
enum TaskGroupService {
    @MainActor
    static func reconcileParent(
        for child: TaskContract,
        in context: ModelContext,
        excludingChildID: UUID? = nil
    ) throws -> XPAwardEvent? {
        guard let parentID = child.parentTaskID else { return nil }
        return try reconcileParent(id: parentID, in: context, excludingChildID: excludingChildID)
    }

    @MainActor
    static func reconcileParent(
        id parentID: UUID,
        in context: ModelContext,
        excludingChildID: UUID? = nil
    ) throws -> XPAwardEvent? {
        let parentDescriptor = FetchDescriptor<TaskContract>(
            predicate: #Predicate { $0.id == parentID }
        )
        guard let parent = try context.fetch(parentDescriptor).first, parent.isTaskGroup else {
            return nil
        }

        let childDescriptor = FetchDescriptor<TaskContract>(
            predicate: #Predicate { $0.parentTaskID == parentID }
        )
        let children = try context.fetch(childDescriptor).filter { child in
            child.isSubtask && child.id != excludingChildID
        }

        // Empty groups are corrupted/incomplete data, never completed rewards.
        guard !children.isEmpty else {
            parent.hierarchyRole = nil
            parent.evidenceRequirement = L10n.text(
                "提交一张能够清楚证明任务已完成的照片。",
                english: "Submit a photo that clearly shows the task is complete."
            )
            parent.evidenceImageCount = 1
            parent.evidenceImageDescriptions = [parent.evidenceRequirement]
            parent.status = parent.xpLogs?.isEmpty == false ? .verified : .pending
            parent.groupCompletedAt = nil
            return nil
        }

        guard children.allSatisfy({ $0.status == .verified }) else {
            parent.status = .pending
            parent.groupCompletedAt = nil
            return nil
        }

        parent.status = .verified
        if parent.groupCompletedAt == nil {
            parent.groupCompletedAt = .now
        }
        return XPService.awardXP(for: parent, in: context)
    }
}
