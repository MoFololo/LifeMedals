import CryptoKit
import Foundation
import SwiftData

enum MonsterMatchKind: String, Codable, Sendable {
    case existing
    case new
}

enum MonsterArtworkFormat {
    static let currentStyleVersion = "grotesque-pixel-v3-transparent"

    static func isCurrent(_ styleVersion: String?) -> Bool {
        styleVersion == currentStyleVersion
    }
}

struct MonsterDescriptor: Equatable, Sendable {
    let canonicalTag: String
    let matchKind: MonsterMatchKind
}

/// Client-side normalization is a compatibility and safety boundary. The
/// server remains authoritative, but older task-generation responses can still
/// receive a stable seed-taxonomy tag without inventing one-off user details.
enum MonsterTaxonomy {
    private static let tagPattern = #"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$"#

    static func isValidCanonicalTag(_ value: String) -> Bool {
        let tag = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard tag.count <= 80 else { return false }
        return tag.range(of: tagPattern, options: .regularExpression) != nil
    }

    static func categoryLabel(for canonicalTag: String) -> String {
        switch canonicalTag {
        case "coding.leetcode": "LeetCode"
        case "coding.project": L10n.text("编程项目", english: "Coding Project")
        case "coding.practice": L10n.text("编程练习", english: "Coding Practice")
        case "study.statistics": L10n.text("统计", english: "Statistics")
        case "study.learning": L10n.text("学习", english: "Learning")
        case "fitness.workout": L10n.text("健身", english: "Workout")
        case "fitness.yoga": L10n.text("瑜伽", english: "Yoga")
        case "sports.basketball": L10n.text("篮球", english: "Basketball")
        case "sports.baseball": L10n.text("棒球", english: "Baseball")
        case "sports.tennis": L10n.text("网球", english: "Tennis")
        case "sports.swimming": L10n.text("游泳", english: "Swimming")
        case "sports.badminton": L10n.text("羽毛球", english: "Badminton")
        case "sports.table_tennis": L10n.text("乒乓球", english: "Table Tennis")
        case "sports.volleyball": L10n.text("排球", english: "Volleyball")
        case "sports.football": L10n.text("橄榄球", english: "Football")
        case "sports.soccer": L10n.text("足球", english: "Soccer")
        case "sports.cycling": L10n.text("骑行", english: "Cycling")
        case "sports.running": L10n.text("跑步", english: "Running")
        case "sports.hiking": L10n.text("徒步", english: "Hiking")
        case "sports.boxing": L10n.text("拳击", english: "Boxing")
        case "sports.golf": L10n.text("高尔夫", english: "Golf")
        case "communication.send_email": L10n.text("邮件", english: "Email")
        case "communication.career": L10n.text("职业沟通", english: "Career Communication")
        case "chores.take_out_trash": L10n.text("倒垃圾", english: "Trash")
        case "chores.household": L10n.text("家务", english: "Household")
        default: prettifiedCategory(for: canonicalTag)
        }
    }

    static func normalizedBadgeKind(
        suggestedBadge: String,
        canonicalTags: [String?]
    ) -> String {
        let gamingTags = canonicalTags.compactMap { tag -> String? in
            let normalized = tag?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return normalized?.hasPrefix("gaming.") == true ? normalized : nil
        }
        guard !gamingTags.isEmpty else { return suggestedBadge }
        return gamingTags.allSatisfy(isGameDevelopmentTag)
            ? BadgeKind.builder.rawValue
            : BadgeKind.life.rawValue
    }

    static func descriptor(
        canonicalTag: String?,
        matchKind: MonsterMatchKind?,
        fallbackText: String,
        badgeKind: String
    ) -> MonsterDescriptor {
        let normalizedTag = canonicalTag?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let tag: String
        let resolvedMatchKind: MonsterMatchKind
        if let normalizedTag, isValidCanonicalTag(normalizedTag) {
            let refinedTag = refinedAthleteTag(
                normalizedTag,
                fallbackText: fallbackText,
                badgeKind: badgeKind
            )
            tag = refinedTag
            resolvedMatchKind = matchKind ?? .existing
        } else {
            tag = fallbackTag(for: fallbackText, badgeKind: badgeKind)
            resolvedMatchKind = .existing
        }

        return MonsterDescriptor(
            canonicalTag: tag,
            matchKind: resolvedMatchKind
        )
    }

    private static func fallbackTag(for text: String, badgeKind: String) -> String {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()

        if containsAny(normalized, ["leetcode", "algorithm", "algorithms", "算法", "刷题"]) {
            return "coding.leetcode"
        }
        if containsAny(normalized, ["statistics", "statistic", "统计"]) {
            return "study.statistics"
        }
        if containsAny(normalized, ["email", "e-mail", "mail", "邮件", "邮箱"]) {
            return "communication.send_email"
        }
        if containsAny(normalized, ["basketball", "hoops", "篮球"]) {
            return "sports.basketball"
        }
        if containsAny(normalized, ["baseball", "棒球"]) {
            return "sports.baseball"
        }
        if containsAny(normalized, ["tennis", "网球"]) {
            return "sports.tennis"
        }
        if containsAny(normalized, ["swimming", "swim", "游泳"]) {
            return "sports.swimming"
        }
        if containsAny(normalized, ["badminton", "羽毛球"]) {
            return "sports.badminton"
        }
        if containsAny(normalized, ["table tennis", "ping pong", "ping-pong", "乒乓球"]) {
            return "sports.table_tennis"
        }
        if containsAny(normalized, ["volleyball", "排球"]) {
            return "sports.volleyball"
        }
        if containsAny(normalized, ["american football", "gridiron", "橄榄球"]) {
            return "sports.football"
        }
        if containsAny(normalized, ["soccer", "football", "足球"]) {
            return "sports.soccer"
        }
        if containsAny(normalized, ["cycling", "biking", "bike ride", "骑行", "骑自行车"]) {
            return "sports.cycling"
        }
        if containsAny(normalized, ["running", "jogging", "marathon", "5k run", "10k run", "跑步", "慢跑", "马拉松"]) {
            return "sports.running"
        }
        if containsAny(normalized, ["hiking", "hike", "徒步", "爬山"]) {
            return "sports.hiking"
        }
        if containsAny(normalized, ["boxing", "拳击"]) {
            return "sports.boxing"
        }
        if containsAny(normalized, ["golf", "高尔夫"]) {
            return "sports.golf"
        }
        if containsAny(normalized, ["yoga", "瑜伽"]) {
            return "fitness.yoga"
        }
        if containsAny(normalized, ["workout", "gym", "exercise", "sport", "健身", "锻炼", "运动"]) {
            return "fitness.workout"
        }
        if containsAny(normalized, ["take out the trash", "garbage", "rubbish", "倒垃圾", "垃圾"]) {
            return "chores.take_out_trash"
        }
        if containsAny(normalized, ["console", "控制台"]) {
            return "gaming.console"
        }
        if containsAny(normalized, ["video game", "gaming", "game", "游戏", "主机"]) {
            return "gaming.game"
        }
        if containsAny(normalized, ["cook", "cooking", "meal", "recipe", "烹饪", "做饭", "做菜"]) {
            return "life.cooking"
        }
        if containsAny(normalized, ["ship", "shipping", "send package", "mail package", "寄快递", "寄包裹", "快递"]) {
            return "errands.shipping"
        }
        if containsAny(normalized, ["chore", "household", "clean", "laundry", "家务", "打扫", "洗衣"]) {
            return "chores.household"
        }

        switch BadgeKind(rawValue: badgeKind) {
        case .builder: return "coding.project"
        case .career: return "communication.career"
        case .athlete: return "fitness.workout"
        case .solver: return "coding.practice"
        case .life: return "life.activity"
        case nil: return "study.learning"
        }
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func refinedAthleteTag(
        _ canonicalTag: String,
        fallbackText: String,
        badgeKind: String
    ) -> String {
        guard canonicalTag == "fitness.workout" || canonicalTag == "sports.activity" else {
            return canonicalTag
        }
        let fallback = fallbackTag(for: fallbackText, badgeKind: badgeKind)
        return fallback.hasPrefix("sports.") || fallback == "fitness.yoga"
            ? fallback
            : canonicalTag
    }

    private static func isGameDevelopmentTag(_ tag: String) -> Bool {
        let developmentComponents: Set<String> = [
            "coding",
            "develop",
            "development",
            "programming"
        ]
        return tag
            .split(whereSeparator: { $0 == "." || $0 == "_" })
            .contains { developmentComponents.contains(String($0)) }
    }

    private static func prettifiedCategory(for tag: String) -> String {
        let finalComponent = tag.split(separator: ".").last.map(String.init) ?? tag
        return finalComponent
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

enum MonsterEncounterRules {
    static func lockedLevel(for category: BadgeCategory) -> Int {
        (category.userBadge?.rank ?? .bronze).rawValue
    }
}

enum MonsterVariantStatus: String, Decodable, Sendable {
    case pending
    case generating
    case ready
    case failed
}

struct MonsterVariantSnapshot: Decodable, Equatable, Sendable {
    let variantID: String?
    let status: MonsterVariantStatus
    let imageURL: String?
    let styleVersion: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case variantID = "variant_id"
        case status
        case imageURL = "image_url"
        case styleVersion = "style_version"
    }

    init(
        variantID: String?,
        status: MonsterVariantStatus,
        imageURL: String?,
        styleVersion: String?
    ) {
        self.variantID = variantID
        self.status = status
        self.imageURL = imageURL
        self.styleVersion = styleVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variantID = (try? container.decode(String.self, forKey: .variantID))
            ?? (try? container.decode(String.self, forKey: .id))
        status = (try? container.decode(MonsterVariantStatus.self, forKey: .status)) ?? .pending
        imageURL = try? container.decode(String.self, forKey: .imageURL)
        styleVersion = try? container.decode(String.self, forKey: .styleVersion)
    }
}

enum MonsterDraftPreviewState: Equatable, Sendable {
    case loading
    case variant(MonsterVariantSnapshot)
    case unavailable
}

enum MonsterVariantPollingPolicy {
    static let intervalSeconds = 4
    static let maxAttempts = 45
    static let maximumWaitSeconds = intervalSeconds * maxAttempts
}

enum MonsterVariantError: LocalizedError {
    case missingConfiguration
    case invalidEncounter
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            L10n.text("尚未配置怪物素材服务。", english: "The monster asset service is not configured.")
        case .invalidEncounter:
            L10n.text("怪物标签或等级无效。", english: "The monster tag or level is invalid.")
        case .invalidResponse:
            L10n.text("怪物素材服务返回了无法读取的数据。", english: "The monster asset service returned unreadable data.")
        case let .server(code):
            L10n.text("怪物素材暂时不可用（HTTP \(code)）。", english: "Monster artwork is temporarily unavailable (HTTP \(code)).")
        }
    }
}

struct MonsterVariantService: Sendable {
    private struct EnsureRequest: Encodable {
        let canonicalTag: String
        let badgeKind: String
        let level: Int

        enum CodingKeys: String, CodingKey {
            case canonicalTag = "canonical_tag"
            case badgeKind = "badge_kind"
            case level
        }
    }

    private struct VariantEnvelope: Decodable {
        let variant: MonsterVariantSnapshot
    }

    func ensureVariant(
        canonicalTag: String,
        badgeKind: String,
        level: Int
    ) async throws -> MonsterVariantSnapshot {
        guard MonsterTaxonomy.isValidCanonicalTag(canonicalTag), (1...9).contains(level) else {
            throw MonsterVariantError.invalidEncounter
        }
        guard let baseURL = LifeMedalsAPIConfiguration.baseURL else {
            throw MonsterVariantError.missingConfiguration
        }

        var request = URLRequest(url: apiRoot(from: baseURL).appending(path: "monster-variants/ensure"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            EnsureRequest(
                canonicalTag: canonicalTag,
                badgeKind: badgeKind,
                level: level
            )
        )
        return try await perform(request)
    }

    func fetchVariant(canonicalTag: String, level: Int) async throws -> MonsterVariantSnapshot {
        guard MonsterTaxonomy.isValidCanonicalTag(canonicalTag), (1...9).contains(level) else {
            throw MonsterVariantError.invalidEncounter
        }
        guard let baseURL = LifeMedalsAPIConfiguration.baseURL else {
            throw MonsterVariantError.missingConfiguration
        }
        let endpoint = apiRoot(from: baseURL)
            .appending(path: "monster-variants")
            .appending(path: canonicalTag)
            .appending(path: String(level))
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> MonsterVariantSnapshot {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonsterVariantError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MonsterVariantError.server(httpResponse.statusCode)
        }

        if let envelope = try? JSONDecoder().decode(VariantEnvelope.self, from: data) {
            return envelope.variant
        }
        if let direct = try? JSONDecoder().decode(MonsterVariantSnapshot.self, from: data) {
            return direct
        }
        throw MonsterVariantError.invalidResponse
    }

    private func apiRoot(from baseURL: URL) -> URL {
        baseURL.path.hasSuffix("/generate-task")
            ? baseURL.deletingLastPathComponent()
            : baseURL
    }
}

@MainActor
enum MonsterVariantSync {
    static func apply(
        _ snapshot: MonsterVariantSnapshot,
        to task: TaskContract,
        discovery: MonsterDiscovery? = nil
    ) {
        task.monsterVariantID = snapshot.variantID ?? task.monsterVariantID
        task.monsterStyleVersion = snapshot.styleVersion ?? task.monsterStyleVersion
        if snapshot.status == .ready, let imageURL = snapshot.imageURL, !imageURL.isEmpty {
            task.monsterImageURL = imageURL
        }

        guard let discovery else { return }
        apply(snapshot, to: discovery)
    }

    static func apply(_ snapshot: MonsterVariantSnapshot, to discovery: MonsterDiscovery) {
        discovery.variantID = snapshot.variantID ?? discovery.variantID
        discovery.styleVersion = snapshot.styleVersion ?? discovery.styleVersion
        if snapshot.status == .ready, let imageURL = snapshot.imageURL, !imageURL.isEmpty {
            discovery.imageURL = imageURL
        }
    }
}

struct MonsterEncounterPresentation: Equatable {
    let imageURL: String?
    let revealsAssignedIdentity: Bool
    let isAtlasDiscovered: Bool

    init(task: TaskContract, discovery: MonsterDiscovery?) {
        let currentDiscoveryURL = MonsterArtworkFormat.isCurrent(discovery?.styleVersion)
            ? discovery?.imageURL
            : nil
        let currentTaskURL = MonsterArtworkFormat.isCurrent(task.monsterStyleVersion)
            ? task.monsterImageURL
            : nil
        let resolvedImageURL = currentDiscoveryURL ?? currentTaskURL
        imageURL = resolvedImageURL?.isEmpty == false ? resolvedImageURL : nil
        revealsAssignedIdentity = task.monsterTag != nil && task.monsterLevel != nil
        isAtlasDiscovered = discovery != nil
    }
}

struct MonsterDiscoveryEvent: Identifiable, Equatable, Sendable {
    let id = UUID()
    let canonicalTag: String
    let sourceTaskID: UUID
    let level: Int
    let badgeKindRawValue: String
    let variantID: String?
    let imageURL: String?
    let styleVersion: String?
    let isFirstDiscovery: Bool
    let encounterCount: Int
}

enum MonsterDiscoveryService {
    /// Records one verified encounter in the user's private store. App logic,
    /// rather than a CloudKit-incompatible unique constraint, enforces one row
    /// per canonicalTag + level + styleVersion.
    @MainActor
    static func recordEncounter(
        for task: TaskContract,
        in context: ModelContext
    ) throws -> MonsterDiscoveryEvent? {
        guard
            !task.isTaskGroup,
            let canonicalTag = task.monsterTag,
            MonsterTaxonomy.isValidCanonicalTag(canonicalTag),
            let level = task.monsterLevel,
            (1...9).contains(level)
        else { return nil }

        let allDiscoveries = try context.fetch(FetchDescriptor<MonsterDiscovery>())
        let existing = allDiscoveries.first {
            $0.canonicalTag == canonicalTag &&
                $0.level == level &&
                ($0.styleVersion == task.monsterStyleVersion ||
                    $0.styleVersion == nil || task.monsterStyleVersion == nil)
        }

        let badgeKind = task.badgeCategory?.name ?? ""
        let isFirstDiscovery = existing == nil
        let discovery: MonsterDiscovery
        if let existing {
            discovery = existing
            guard discovery.registerEncounter(sourceTaskID: task.id) else { return nil }
            discovery.discoveryCount = max(discovery.discoveryCount, 1) + 1
            if discovery.variantID == nil { discovery.variantID = task.monsterVariantID }
            if discovery.imageURL == nil { discovery.imageURL = task.monsterImageURL }
            if discovery.styleVersion == nil { discovery.styleVersion = task.monsterStyleVersion }
        } else {
            discovery = MonsterDiscovery(
                canonicalTag: canonicalTag,
                level: level,
                badgeKindRawValue: badgeKind,
                variantID: task.monsterVariantID,
                imageURL: task.monsterImageURL,
                sourceTaskID: task.id,
                styleVersion: task.monsterStyleVersion
            )
            context.insert(discovery)
        }

        return MonsterDiscoveryEvent(
            canonicalTag: canonicalTag,
            sourceTaskID: task.id,
            level: level,
            badgeKindRawValue: discovery.badgeKindRawValue,
            variantID: discovery.variantID,
            imageURL: discovery.imageURL,
            styleVersion: discovery.styleVersion,
            isFirstDiscovery: isFirstDiscovery,
            encounterCount: discovery.discoveryCount
        )
    }
}

actor MonsterImageCache {
    static let shared = MonsterImageCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    init() {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let legacyCacheDirectory = baseDirectory.appending(
            path: "LifeMedalsMonsterImages",
            directoryHint: .isDirectory
        )
        if fileManager.fileExists(atPath: legacyCacheDirectory.path) {
            try? fileManager.removeItem(at: legacyCacheDirectory)
        }
        cacheDirectory = baseDirectory.appending(
            path: "LifeMedalsMonsterImages-v3-transparent",
            directoryHint: .isDirectory
        )
    }

    func data(for url: URL) async throws -> Data {
        let fileURL = cacheDirectory.appending(path: cacheKey(for: url))
        if fileManager.fileExists(atPath: fileURL.path),
           let cached = try? Data(contentsOf: fileURL),
           !cached.isEmpty {
            return cached
        }

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("image/png,image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            data.count <= 10_000_000,
            httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true
        else {
            throw MonsterVariantError.invalidResponse
        }

        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return data
    }

    private func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined() + ".image"
    }
}
