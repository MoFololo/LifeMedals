import Foundation
import XCTest
@testable import LifeMedals

final class TaskGenerationServiceTests: XCTestCase {
    func testLegacySingleTaskResponseRemainsCompatible() throws {
        let contract = try decode(#"""
        {
          "title":"Complete the survey",
          "deadline":"2026-08-25T23:59:00-04:00",
          "deadline_preset":"tomorrow",
          "evidence_requirement":"Show the submission confirmation.",
          "suggested_badge":"Solver",
          "suggested_xp":25
        }
        """#)

        XCTAssertEqual(contract.kind, .singleTask)
        XCTAssertEqual(contract.evidenceImageCount, 1)
        XCTAssertEqual(contract.suggestedXP, 25)
        XCTAssertTrue(contract.children.isEmpty)
    }

    func testTwoValidActionsCreateTaskGroup() throws {
        let contract = try decode(groupJSON(children: [
            childJSON(title: "Complete the survey"),
            childJSON(title: "Join Piazza")
        ]))

        XCTAssertEqual(contract.kind, .taskGroup)
        XCTAssertEqual(contract.children.map(\.title), ["Complete the survey", "Join Piazza"])
        XCTAssertTrue(contract.evidenceRequirement.isEmpty)
        XCTAssertEqual(contract.evidenceImageCount, 0)
    }

    func testOneChildGroupDegradesToSingleTaskWithChildEvidence() throws {
        let contract = try decode(groupJSON(children: [
            childJSON(
                title: "Join Piazza",
                requirement: "Show the joined course page."
            )
        ]))

        XCTAssertEqual(contract.kind, .singleTask)
        XCTAssertEqual(contract.title, "Join Piazza")
        XCTAssertEqual(contract.evidenceRequirement, "Show the joined course page.")
        XCTAssertTrue(contract.children.isEmpty)
    }

    func testEmptyTitlesDuplicatesAndInvalidFieldsAreNormalized() throws {
        let contract = try decode(groupJSON(
            estimatedHours: -4,
            children: [
                #"{"title":"  ","estimated_hours":0,"evidence_image_count":0}"#,
                #"{"title":"Join Piazza","estimated_hours":99,"evidence_image_count":9}"#,
                #"{"title":"join piazza","estimated_hours":0.1,"evidence_image_count":-2}"#
            ]
        ))

        XCTAssertEqual(contract.kind, .singleTask)
        XCTAssertEqual(contract.title, "Join Piazza")
        XCTAssertEqual(contract.evidenceImageCount, 5)
        XCTAssertEqual(contract.estimatedHours, 8)
        XCTAssertFalse(contract.evidenceRequirement.isEmpty)
    }

    func testMonsterFieldsDecodeForSingleTask() throws {
        let contract = try decode(#"""
        {
          "kind":"single_task",
          "title":"Practice algorithms",
          "deadline":"2026-08-25T23:59:00-04:00",
          "deadline_preset":"tomorrow",
          "evidence_requirement":"Show two accepted solutions.",
          "evidence_image_count":1,
          "evidence_image_descriptions":["Accepted results"],
          "suggested_badge":"Solver",
          "estimated_hours":1,
          "monster_tag":"coding.leetcode",
          "monster_display_name":"Algorithm Imp",
          "monster_match_kind":"existing",
          "children":[]
        }
        """#)

        XCTAssertEqual(contract.monsterTag, "coding.leetcode")
        XCTAssertEqual(contract.monsterDisplayName, "Algorithm Imp")
        XCTAssertEqual(contract.monsterMatchKind, .existing)
    }

    func testTaskGroupParentHasNoMonsterWhileChildrenKeepAssignments() throws {
        let contract = try decode(groupJSON(children: [
            childJSON(title: "Practice algorithms", monsterTag: "coding.leetcode"),
            childJSON(title: "Send the email", monsterTag: "communication.send_email")
        ]))

        XCTAssertNil(contract.monsterTag)
        XCTAssertEqual(contract.children.map(\.monsterTag), ["coding.leetcode", "communication.send_email"])
    }

    private func decode(_ json: String) throws -> GeneratedTaskContract {
        try JSONDecoder().decode(GeneratedTaskContract.self, from: Data(json.utf8))
    }

    private func groupJSON(estimatedHours: Double = 1, children: [String]) -> String {
        """
        {
          "kind":"task_group",
          "title":"Complete all Next Steps",
          "deadline":"2026-08-25T23:59:00-04:00",
          "deadline_preset":"tomorrow",
          "evidence_requirement":"",
          "evidence_image_count":0,
          "evidence_image_descriptions":[],
          "suggested_badge":"Solver",
          "estimated_hours":\(estimatedHours),
          "children":[\(children.joined(separator: ","))]
        }
        """
    }

    private func childJSON(
        title: String,
        requirement: String = "Show the completion result.",
        monsterTag: String = "coding.practice"
    ) -> String {
        """
        {
          "title":"\(title)",
          "evidence_requirement":"\(requirement)",
          "evidence_image_count":1,
          "evidence_image_descriptions":["Completion result"],
          "estimated_hours":0.25,
          "monster_tag":"\(monsterTag)",
          "monster_display_name":"Quest Creature",
          "monster_match_kind":"existing"
        }
        """
    }
}
