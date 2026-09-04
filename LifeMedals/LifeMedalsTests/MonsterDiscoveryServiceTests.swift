import SwiftData
import XCTest
@testable import LifeMedals

@MainActor
final class MonsterDiscoveryServiceTests: XCTestCase {
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
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        context = container.mainContext
        category = BadgeCategory(name: BadgeKind.solver.rawValue)
        badge = UserBadge(category: category)
        category.userBadge = badge
        context.insert(category)
        context.insert(badge)
    }

    func testBadgeRanksMapDirectlyToMonsterLevels() {
        XCTAssertEqual(BadgeRank.allCases.map(\.rawValue), Array(1...9))
        XCTAssertEqual(BadgeKind.allCases.map(\.rawValue), ["Solver", "Builder", "Career", "Athlete", "Life"])
    }

    func testMonsterPollingCoversSlowBackgroundGeneration() {
        XCTAssertGreaterThanOrEqual(MonsterVariantPollingPolicy.maximumWaitSeconds, 120)
    }

    func testTaskLocksLevelBeforeItsXPAwardCanUpgradeBadge() throws {
        let task = makeMonsterTask(xpReward: 1_000)
        task.monsterLevel = MonsterEncounterRules.lockedLevel(for: category)
        task.status = .verified
        context.insert(task)

        XCTAssertEqual(task.monsterLevel, BadgeRank.bronze.rawValue)
        XCTAssertNotNil(XPService.awardXP(for: task, in: context))
        try context.save()

        XCTAssertEqual(badge.rank, .silver)
        XCTAssertEqual(task.monsterLevel, BadgeRank.bronze.rawValue)
    }

    func testDuplicateCallbackDoesNotDuplicateDiscoveryOrEncounterCount() throws {
        let task = makeMonsterTask()
        context.insert(task)

        let first = try MonsterDiscoveryService.recordEncounter(for: task, in: context)
        let replay = try MonsterDiscoveryService.recordEncounter(for: task, in: context)
        try context.save()

        let discoveries = try context.fetch(FetchDescriptor<MonsterDiscovery>())
        XCTAssertEqual(discoveries.count, 1)
        XCTAssertEqual(discoveries[0].discoveryCount, 1)
        XCTAssertEqual(first?.isFirstDiscovery, true)
        XCTAssertNil(replay)
    }

    func testDifferentVerifiedTaskIncrementsExistingSpeciesEncounter() throws {
        let firstTask = makeMonsterTask()
        let secondTask = makeMonsterTask()
        context.insert(firstTask)
        context.insert(secondTask)

        _ = try MonsterDiscoveryService.recordEncounter(for: firstTask, in: context)
        let second = try MonsterDiscoveryService.recordEncounter(for: secondTask, in: context)
        try context.save()

        let discoveries = try context.fetch(FetchDescriptor<MonsterDiscovery>())
        XCTAssertEqual(discoveries.count, 1)
        XCTAssertEqual(discoveries[0].discoveryCount, 2)
        XCTAssertEqual(second?.encounterCount, 2)
    }

    func testLegacyTaskAndGroupParentDoNotCreateDiscoveries() throws {
        let legacy = TaskContract(
            title: "Legacy",
            deadline: .now,
            evidenceRequirement: "Show it.",
            xpReward: 25,
            badgeCategory: category
        )
        let parent = TaskContract(
            title: "Group",
            deadline: .now,
            evidenceRequirement: "",
            xpReward: 50,
            hierarchyRole: .group,
            monsterTag: "coding.leetcode",
            monsterLevel: 1,
            badgeCategory: category
        )

        XCTAssertNil(try MonsterDiscoveryService.recordEncounter(for: legacy, in: context))
        XCTAssertNil(try MonsterDiscoveryService.recordEncounter(for: parent, in: context))
    }

    func testSeedTaxonomyMapsEquivalentAlgorithmPhrasesToSameTag() {
        let phrases = ["solve two LeetCode problems", "practice algorithms", "刷两道算法题"]
        let tags = phrases.map {
            MonsterTaxonomy.descriptor(
                canonicalTag: nil,
                matchKind: nil,
                fallbackText: $0,
                badgeKind: BadgeKind.solver.rawValue
            ).canonicalTag
        }
        XCTAssertEqual(Set(tags), ["coding.leetcode"])
    }

    func testChineseLifeActivitiesReceiveEnglishTaxonomyFallbacks() {
        let cases = [
            ("在以撒的结合关闭控制台", "gaming.console"),
            ("今晚做饭", "life.cooking"),
            ("去寄快递", "errands.shipping")
        ]

        for (text, expectedTag) in cases {
            let descriptor = MonsterTaxonomy.descriptor(
                canonicalTag: nil,
                matchKind: nil,
                fallbackText: text,
                badgeKind: BadgeKind.life.rawValue
            )
            XCTAssertEqual(descriptor.canonicalTag, expectedTag)
        }
    }

    func testGamingTagsOverrideSolverButNotGameDevelopmentBuilder() {
        XCTAssertEqual(
            MonsterTaxonomy.normalizedBadgeKind(
                suggestedBadge: BadgeKind.solver.rawValue,
                canonicalTags: ["gaming.console"]
            ),
            BadgeKind.life.rawValue
        )
        XCTAssertEqual(
            MonsterTaxonomy.normalizedBadgeKind(
                suggestedBadge: BadgeKind.solver.rawValue,
                canonicalTags: ["gaming.development"]
            ),
            BadgeKind.builder.rawValue
        )
        XCTAssertEqual(
            MonsterTaxonomy.normalizedBadgeKind(
                suggestedBadge: BadgeKind.builder.rawValue,
                canonicalTags: ["gaming.console"]
            ),
            BadgeKind.life.rawValue
        )
    }

    func testNamedSportsReceiveDistinctTaxonomyEvenFromGenericServerTags() {
        let cases = [
            ("周末打篮球", "sports.basketball"),
            ("Play baseball", "sports.baseball"),
            ("打一场网球", "sports.tennis"),
            ("Swim ten laps", "sports.swimming")
        ]

        for (text, expectedTag) in cases {
            let descriptor = MonsterTaxonomy.descriptor(
                canonicalTag: "fitness.workout",
                matchKind: .existing,
                fallbackText: text,
                badgeKind: BadgeKind.life.rawValue
            )
            XCTAssertEqual(descriptor.canonicalTag, expectedTag)
        }
    }

    func testPendingDiscoveryCanBeReplacedWhenArtworkBecomesReady() throws {
        let task = makeMonsterTask()
        context.insert(task)

        let pending = MonsterVariantSnapshot(
            variantID: "variant-1",
            status: .generating,
            imageURL: nil,
            styleVersion: "pixel-v1"
        )
        MonsterVariantSync.apply(pending, to: task)
        _ = try MonsterDiscoveryService.recordEncounter(for: task, in: context)
        try context.save()

        let discovery = try XCTUnwrap(context.fetch(FetchDescriptor<MonsterDiscovery>()).first)
        XCTAssertNil(discovery.imageURL)
        XCTAssertEqual(discovery.variantID, "variant-1")

        let ready = MonsterVariantSnapshot(
            variantID: "variant-1",
            status: .ready,
            imageURL: "https://assets.example.com/monster.webp",
            styleVersion: "pixel-v1"
        )
        MonsterVariantSync.apply(ready, to: task, discovery: discovery)
        try context.save()

        XCTAssertEqual(task.monsterImageURL, ready.imageURL)
        XCTAssertEqual(discovery.imageURL, ready.imageURL)
    }

    func testTaskDetailRevealsReadyArtworkBeforeAtlasDiscovery() {
        let task = makeMonsterTask()
        let ready = MonsterVariantSnapshot(
            variantID: "variant-1",
            status: .ready,
            imageURL: "https://assets.example.com/monster.webp",
            styleVersion: "pixel-v1"
        )
        MonsterVariantSync.apply(ready, to: task)

        let presentation = MonsterEncounterPresentation(task: task, discovery: nil)

        XCTAssertTrue(presentation.revealsAssignedIdentity)
        XCTAssertFalse(presentation.isAtlasDiscovered)
        XCTAssertEqual(presentation.imageURL, ready.imageURL)
    }

    private func makeMonsterTask(xpReward: Int = 25) -> TaskContract {
        TaskContract(
            title: "Practice algorithms",
            deadline: .now.addingTimeInterval(3_600),
            evidenceRequirement: "Show accepted results.",
            xpReward: xpReward,
            monsterTag: "coding.leetcode",
            monsterLevel: 1,
            badgeCategory: category
        )
    }
}
