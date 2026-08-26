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
    case solver = "Solver"
    case builder = "Builder"
    case career = "Career"
    case athlete = "Athlete"
    case life = "Life"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solver: L10n.text("解题勋章", english: "Solver")
        case .builder: L10n.text("创造勋章", english: "Creator")
        case .career: L10n.text("职业勋章", english: "Career")
        case .athlete: L10n.text("运动勋章", english: "Athlete")
        case .life: L10n.text("生活勋章", english: "Life")
        }
    }

    static func displayName(for storedName: String) -> String {
        if storedName == legacySolverName {
            return BadgeKind.solver.displayName
        }
        return BadgeKind(rawValue: storedName)?.displayName ?? storedName
    }

    static var legacySolverName: String {
        ["Problem", "Solver"].joined(separator: " ")
    }
}
