import SwiftData
import XCTest
@testable import LifeMedals

@MainActor
final class TaskGroupServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var category: BadgeCategory!
    private var badge: UserBadge!

    override func setUpWithError() throws {
        let schema = Schema([
            BadgeCategory.self,
            UserBadge.self,
            TaskContract.self,
            MonsterDiscovery.self,
            Evidence.self,
            XPLog.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
        category = BadgeCategory(name: BadgeKind.solver.rawValue)
        badge = UserBadge(category: category)
        category.userBadge = badge
        context.insert(category)
        context.insert(badge)
    }

    func testLegacyTaskHasNoHierarchyRole() {
        let task = TaskContract(
            title: "Legacy task",
            deadline: .now.addingTimeInterval(3_600),
            evidenceRequirement: "Show completion.",
            xpReward: 25,
            badgeCategory: category
        )

        XCTAssertFalse(task.isTaskGroup)
        XCTAssertFalse(task.isSubtask)
    }

    func testIntermediateThenFinalChildAwardsParentExactlyOnce() throws {
        let (parent, first, second) = makeTwoChildGroup(xpReward: 100)
        try context.save()

        first.status = .verified
        XCTAssertNil(try TaskGroupService.reconcileParent(for: first, in: context))
        try context.save()
        XCTAssertEqual(parent.status, .pending)
        XCTAssertEqual(badge.currentXP, 0)

        second.status = .verified
        let finalAward = try TaskGroupService.reconcileParent(for: second, in: context)
        try context.save()
        XCTAssertEqual(finalAward?.amount, 100)
        XCTAssertEqual(parent.status, .verified)
        XCTAssertNotNil(parent.groupCompletedAt)
        XCTAssertEqual(badge.currentXP, 100)

        XCTAssertNil(try TaskGroupService.reconcileParent(for: second, in: context))
        try context.save()
        let parentLogs = try context.fetch(FetchDescriptor<XPLog>())
            .filter { $0.taskContract?.id == parent.id }
        XCTAssertEqual(parentLogs.count, 1)
        XCTAssertEqual(badge.currentXP, 100)
    }

    func testDeletingLastPendingChildReconcilesRemainingCompletedChildren() throws {
        let (parent, completed, pending) = makeTwoChildGroup(xpReward: 50)
        completed.status = .verified
        try context.save()

        context.delete(pending)
        let award = try TaskGroupService.reconcileParent(
            id: parent.id,
            in: context,
            excludingChildID: pending.id
        )
        try context.save()

        XCTAssertEqual(award?.amount, 50)
        XCTAssertEqual(parent.status, .verified)
        XCTAssertEqual(badge.currentXP, 50)
    }

    func testEmptyGroupDegradesWithoutCompletingOrAwardingXP() throws {
        let parent = TaskContract(
            title: "Empty group",
            deadline: .now.addingTimeInterval(3_600),
            evidenceRequirement: "",
            xpReward: 500,
            hierarchyRole: .group,
            badgeCategory: category
        )
        context.insert(parent)
        try context.save()

        XCTAssertNil(try TaskGroupService.reconcileParent(id: parent.id, in: context))
        try context.save()
        XCTAssertFalse(parent.isTaskGroup)
        XCTAssertEqual(parent.status, .pending)
        XCTAssertEqual(badge.currentXP, 0)
    }

    @discardableResult
    private func makeTwoChildGroup(xpReward: Int) -> (TaskContract, TaskContract, TaskContract) {
        let parent = TaskContract(
            title: "Complete all tasks",
            deadline: .now.addingTimeInterval(3_600),
            evidenceRequirement: "",
            xpReward: xpReward,
            hierarchyRole: .group,
            badgeCategory: category
        )
        let first = makeChild("First", parent: parent, order: 0)
        let second = makeChild("Second", parent: parent, order: 1)
        [parent, first, second].forEach(context.insert)
        return (parent, first, second)
    }

    private func makeChild(_ title: String, parent: TaskContract, order: Int) -> TaskContract {
        TaskContract(
            title: title,
            deadline: parent.deadline,
            evidenceRequirement: "Show completion of \(title).",
            evidenceImageCount: 1,
            evidenceImageDescriptions: ["Completion result"],
            xpReward: 25,
            hierarchyRole: .child,
            parentTaskID: parent.id,
            childOrder: order,
            badgeCategory: category
        )
    }
}
