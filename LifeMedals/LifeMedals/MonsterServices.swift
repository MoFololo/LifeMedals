import CryptoKit
import Foundation
import SwiftData

enum MonsterMatchKind: String, Codable, Sendable {
    case existing
    case new
}

struct MonsterDescriptor: Equatable, Sendable {
    let canonicalTag: String
    let displayName: String
    let matchKind: MonsterMatchKind
}

/// Client-side normalization is a compatibility and safety boundary. The
/// server remains authoritative, but older task-generation responses can still
/// receive a stable seed-taxonomy tag without inventing one-off user details.
enum MonsterTaxonomy {
    private static let tagPattern = #"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$"#

    private static let displayNames: [String: String] = [
        "coding.leetcode": "Algorithm Imp",
        "coding.project": "Forge Sprite",
        "coding.practice": "Puzzle Imp",
        "study.statistics": "Stat Wisp",
        "study.learning": "Study Wisp",
        "fitness.workout": "Training Brute",
        "communication.send_email": "Mail Bat",
        "communication.career": "Courier Wisp",
        "chores.take_out_trash": "Trash Slime",
        "chores.household": "Chore Slime"
    ]

    static func isValidCanonicalTag(_ value: String) -> Bool {
        let tag = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard tag.count <= 80 else { return false }
        return tag.range(of: tagPattern, options: .regularExpression) != nil
    }

    static func localizedDisplayName(for canonicalTag: String, fallback: String) -> String {
        switch canonicalTag {
        case "coding.leetcode": L10n.text("算法小鬼", english: fallback)
        case "coding.project": L10n.text("锻造精灵", english: fallback)
        case "coding.practice": L10n.text("解谜小鬼", english: fallback)
        case "study.statistics": L10n.text("统计幽灵", english: fallback)
        case "study.learning": L10n.text("学习幽灵", english: fallback)
        case "fitness.workout": L10n.text("训练蛮兽", english: fallback)
        case "communication.send_email": L10n.text("邮差蝙蝠", english: fallback)
        case "communication.career": L10n.text("信使幽灵", english: fallback)
        case "chores.take_out_trash": L10n.text("垃圾史莱姆", english: fallback)
        case "chores.household": L10n.text("家务史莱姆", english: fallback)
        default: fallback
        }
    }

    static func descriptor(
        canonicalTag: String?,
        displayName: String?,
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
            tag = normalizedTag
            resolvedMatchKind = matchKind ?? .existing
        } else {
            tag = fallbackTag(for: fallbackText, badgeKind: badgeKind)
            resolvedMatchKind = .existing
        }

        let trimmedDisplayName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeDisplayName: String?
        if let trimmedDisplayName, !trimmedDisplayName.isEmpty, trimmedDisplayName.count <= 60 {
            safeDisplayName = trimmedDisplayName
        } else {
            safeDisplayName = nil
        }

        return MonsterDescriptor(
            canonicalTag: tag,
            displayName: safeDisplayName ?? displayNames[tag] ?? prettifiedName(for: tag),
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
        if containsAny(normalized, ["workout", "gym", "exercise", "running", "run ", "健身", "锻炼", "跑步", "运动"]) {
            return "fitness.workout"
        }
        if containsAny(normalized, ["take out the trash", "garbage", "rubbish", "倒垃圾", "垃圾"]) {
            return "chores.take_out_trash"
        }

        switch BadgeKind(rawValue: badgeKind) {
        case .builder: return "coding.project"
        case .career: return "communication.career"
        case .athlete: return "fitness.workout"
        case .solver: return "coding.practice"
        case nil: return "study.learning"
        }
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func prettifiedName(for tag: String) -> String {
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
        let displayName: String
        let badgeKind: String
        let level: Int

        enum CodingKeys: String, CodingKey {
            case canonicalTag = "canonical_tag"
            case displayName = "display_name"
            case badgeKind = "badge_kind"
            case level
        }
    }

    private struct VariantEnvelope: Decodable {
        let variant: MonsterVariantSnapshot
    }

    func ensureVariant(
        canonicalTag: String,
        displayName: String,
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
                displayName: String(displayName.prefix(60)),
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
        let resolvedImageURL = discovery?.imageURL ?? task.monsterImageURL
        imageURL = resolvedImageURL?.isEmpty == false ? resolvedImageURL : nil
        revealsAssignedIdentity = task.monsterTag != nil && task.monsterLevel != nil
        isAtlasDiscovered = discovery != nil
    }
}

struct MonsterDiscoveryEvent: Identifiable, Equatable, Sendable {
    let id = UUID()
    let canonicalTag: String
    let sourceTaskID: UUID
    let displayName: String
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

        let displayName = task.monsterDisplayName ?? canonicalTag
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
                displayName: displayName,
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
            displayName: discovery.displayName,
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
        cacheDirectory = baseDirectory.appending(path: "LifeMedalsMonsterImages", directoryHint: .isDirectory)
    }

    func data(for url: URL) async throws -> Data {
        let fileURL = cacheDirectory.appending(path: cacheKey(for: url))
        if let cached = try? Data(contentsOf: fileURL), !cached.isEmpty {
            return cached
        }

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("image/avif,image/webp,image/*", forHTTPHeaderField: "Accept")
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
