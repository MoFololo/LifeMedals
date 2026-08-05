//
//  BadgeKind.swift
//  LifeMedals
//

import Foundation

/// Stable business identifiers for the built-in medal categories.
///
/// These values are persisted and exchanged with the task-generation API.
/// They deliberately know nothing about bronze/silver artwork: a category's
/// current material is derived independently from its `UserBadge.rank`.
enum BadgeKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case problemSolver = "Problem Solver"
    case builder = "Builder"
    case career = "Career"
    case athlete = "Athlete"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .problemSolver: "解题勋章"
        case .builder: "创造勋章"
        case .career: "职业勋章"
        case .athlete: "运动勋章"
        }
    }

    static func displayName(for storedName: String) -> String {
        BadgeKind(rawValue: storedName)?.displayName ?? storedName
    }
}
