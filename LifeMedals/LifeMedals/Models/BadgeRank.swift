//
//  BadgeRank.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/8/1.
//

import Foundation

/// The 9 fixed medal tiers a `UserBadge` can progress through, from the
/// initial 青铜 (Bronze) up to 王者 (Champion). Raw values double as
/// `UserBadge.level`, so renumbering cases would require a data migration.
///
/// - Important: Cumulative XP thresholds mirror the fixed progression table
///   in docs/product-plan.md §4.3 (total 50,000 EXP across 8 promotions).
///   Do not change these numbers without updating that table.
enum BadgeRank: Int, CaseIterable, Comparable, Codable, Sendable {
    case bronze = 1
    case silver = 2
    case gold = 3
    case platinum = 4
    case emerald = 5
    case diamond = 6
    case master = 7
    case grandmaster = 8
    case champion = 9

    static func < (lhs: BadgeRank, rhs: BadgeRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .bronze: L10n.text("青铜", english: "Bronze")
        case .silver: L10n.text("白银", english: "Silver")
        case .gold: L10n.text("黄金", english: "Gold")
        case .platinum: L10n.text("铂金", english: "Platinum")
        case .emerald: L10n.text("翡翠", english: "Emerald")
        case .diamond: L10n.text("钻石", english: "Diamond")
        case .master: L10n.text("大师", english: "Master")
        case .grandmaster: L10n.text("宗师", english: "Grandmaster")
        case .champion: L10n.text("王者", english: "Champion")
        }
    }

    /// Total cumulative XP required to *reach* this rank (the "累计经验"
    /// column of the progression table). Bronze starts at 0.
    var cumulativeXPThreshold: Int {
        switch self {
        case .bronze: 0
        case .silver: 1_000
        case .gold: 3_000
        case .platinum: 6_000
        case .emerald: 10_000
        case .diamond: 16_000
        case .master: 24_000
        case .grandmaster: 34_000
        case .champion: 50_000
        }
    }

    /// The next rank up, or `nil` if this is already the highest rank.
    var next: BadgeRank? {
        BadgeRank(rawValue: rawValue + 1)
    }

    /// Additional cumulative XP needed to reach the next rank from this one
    /// (the "所需经验" column). `nil` once at the maximum rank.
    var xpNeededForNextRank: Int? {
        guard let next else { return nil }
        return next.cumulativeXPThreshold - cumulativeXPThreshold
    }

    /// Returns the highest rank whose threshold has been reached by
    /// `cumulativeXP`.
    static func rank(forCumulativeXP cumulativeXP: Int) -> BadgeRank {
        allCases.reversed().first { cumulativeXP >= $0.cumulativeXPThreshold } ?? .bronze
    }
}

/// Fixed rule for converting an AI-estimated task duration into XP: every
/// focused hour of work is worth 100 XP. This conversion is a product rule
/// owned by the client, not something the AI decides directly — the AI only
/// estimates `estimated_hours` when generating a task contract.
enum XPRules {
    static let xpPerHour = 100

    /// Converts an estimated task duration (in hours) into a whole XP
    /// reward, rounded to the nearest whole number and never below 5.
    static func xp(forEstimatedHours hours: Double) -> Int {
        max(5, Int((hours * Double(xpPerHour)).rounded()))
    }
}
