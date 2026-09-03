//
//  TaskGenerationService.swift
//  LifeMedals
//
//  Created by Codex on 2026/7/30.
//

import Foundation

enum LifeMedalsAPIConfiguration {
#if DEBUG
    static let defaultBaseURL = "https://lifemedals-api-staging.david-lian0809.workers.dev/"
#else
    static let defaultBaseURL = "https://lifemedals-api.david-lian0809.workers.dev/"
#endif

    static var baseURL: URL? {
        let environmentValue = ProcessInfo.processInfo.environment["LIFEMEDALS_API_BASE_URL"]
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "LifeMedalsAPIBaseURL") as? String

        return [environmentValue, bundleValue, defaultBaseURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
            .first { $0.scheme != nil }
    }
}

enum GeneratedTaskKind: String, Decodable, Sendable {
    case singleTask = "single_task"
    case taskGroup = "task_group"
}

struct GeneratedTaskChild: Decodable, Identifiable, Sendable {
    let id = UUID()
    let title: String
    let taskDescription: String
    let evidenceRequirement: String
    let evidenceImageCount: Int
    let evidenceImageDescriptions: [String]
    let estimatedHours: Double
    let monsterTag: String?
    let monsterMatchKind: MonsterMatchKind?

    var suggestedXP: Int {
        XPRules.xp(forEstimatedHours: estimatedHours)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case taskDescription = "description"
        case evidenceRequirement = "evidence_requirement"
        case evidenceImageCount = "evidence_image_count"
        case evidenceImageDescriptions = "evidence_image_descriptions"
        case estimatedHours = "estimated_hours"
        case monsterTag = "monster_tag"
        case monsterMatchKind = "monster_match_kind"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = TaskTitleRules.limited((try? container.decode(String.self, forKey: .title)) ?? "")
        taskDescription = ((try? container.decode(String.self, forKey: .taskDescription)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawRequirement = (try? container.decode(String.self, forKey: .evidenceRequirement)) ?? ""
        evidenceRequirement = GeneratedTaskContract.normalizedRequirement(rawRequirement)
        evidenceImageCount = GeneratedTaskContract.normalizedEvidenceCount(
            (try? container.decode(Int.self, forKey: .evidenceImageCount)) ?? 1
        )
        evidenceImageDescriptions = GeneratedTaskContract.normalizedDescriptions(
            (try? container.decode([String].self, forKey: .evidenceImageDescriptions)) ?? [],
            count: evidenceImageCount,
            requirement: evidenceRequirement
        )
        estimatedHours = GeneratedTaskContract.normalizedHours(
            (try? container.decode(Double.self, forKey: .estimatedHours)) ?? 0.25
        )
        monsterTag = try? container.decode(String.self, forKey: .monsterTag)
        monsterMatchKind = try? container.decode(MonsterMatchKind.self, forKey: .monsterMatchKind)
    }
}

struct GeneratedTaskContract: Decodable, Sendable {
    let kind: GeneratedTaskKind
    let title: String
    let taskDescription: String
    let deadline: String
    let deadlinePreset: TaskDeadlinePreset?
    let evidenceRequirement: String
    let evidenceImageCount: Int
    let evidenceImageDescriptions: [String]
    let suggestedBadge: String
    /// Hours the AI estimates the task will take. The app — not the AI —
    /// converts this into `suggestedXP` at a fixed 100 XP per hour (see
    /// `XPRules`), so task rewards follow one consistent, product-owned rule.
    let estimatedHours: Double
    let suggestedXP: Int
    let children: [GeneratedTaskChild]
    let monsterTag: String?
    let monsterMatchKind: MonsterMatchKind?

    enum CodingKeys: String, CodingKey {
        case title
        case taskDescription = "description"
        case kind
        case deadline
        case deadlinePreset = "deadline_preset"
        case evidenceRequirement = "evidence_requirement"
        case evidenceImageCount = "evidence_image_count"
        case evidenceImageDescriptions = "evidence_image_descriptions"
        case suggestedBadge = "suggested_badge"
        case estimatedHours = "estimated_hours"
        case suggestedXP = "suggested_xp"
        case children
        case monsterTag = "monster_tag"
        case monsterMatchKind = "monster_match_kind"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rootTitle = TaskTitleRules.limited(
            ((try? container.decode(String.self, forKey: .title)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let rootDescription = ((try? container.decode(String.self, forKey: .taskDescription)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        deadline = (try? container.decode(String.self, forKey: .deadline)) ?? ""
        deadlinePreset = try? container.decode(TaskDeadlinePreset.self, forKey: .deadlinePreset)
        suggestedBadge = (try? container.decode(String.self, forKey: .suggestedBadge)) ?? BadgeKind.solver.rawValue

        let decodedChildren = (try? container.decode([GeneratedTaskChild].self, forKey: .children)) ?? []
        var seenTitles = Set<String>()
        let validChildren = decodedChildren.filter { child in
            let trimmedTitle = child.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return false }
            let comparisonKey = trimmedTitle
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return seenTitles.insert(comparisonKey).inserted
        }

        // Trust the actions more than the discriminator so an otherwise valid
        // AI list is never collapsed because of one malformed `kind` value.
        if validChildren.count >= 2 {
            kind = .taskGroup
            title = rootTitle.isEmpty ? "Complete all tasks" : rootTitle
            taskDescription = rootDescription
            evidenceRequirement = ""
            evidenceImageCount = 0
            evidenceImageDescriptions = []
            children = validChildren
            monsterTag = nil
            monsterMatchKind = nil
        } else {
            kind = .singleTask
            children = []
            if let onlyChild = validChildren.first {
                // A one-child group is a normal task, using the child's own
                // evidence plan rather than the empty parent container plan.
                title = onlyChild.title.trimmingCharacters(in: .whitespacesAndNewlines)
                taskDescription = onlyChild.taskDescription
                evidenceRequirement = onlyChild.evidenceRequirement
                evidenceImageCount = onlyChild.evidenceImageCount
                evidenceImageDescriptions = onlyChild.evidenceImageDescriptions
                monsterTag = onlyChild.monsterTag
                monsterMatchKind = onlyChild.monsterMatchKind
            } else {
                title = rootTitle
                taskDescription = rootDescription
                evidenceRequirement = Self.normalizedRequirement(
                    (try? container.decode(String.self, forKey: .evidenceRequirement)) ?? ""
                )
                evidenceImageCount = Self.normalizedEvidenceCount(
                    (try? container.decode(Int.self, forKey: .evidenceImageCount)) ?? 1
                )
                evidenceImageDescriptions = Self.normalizedDescriptions(
                    (try? container.decode([String].self, forKey: .evidenceImageDescriptions)) ?? [],
                    count: evidenceImageCount,
                    requirement: evidenceRequirement
                )
                monsterTag = try? container.decode(String.self, forKey: .monsterTag)
                monsterMatchKind = try? container.decode(MonsterMatchKind.self, forKey: .monsterMatchKind)
            }
        }

        // Tolerate the previously deployed Worker (which returned a direct
        // suggested_xp) while it is being upgraded to estimate hours instead.
        if let onlyChild = validChildren.first, kind == .singleTask {
            estimatedHours = onlyChild.estimatedHours
            suggestedXP = onlyChild.suggestedXP
        } else if let hours = try? container.decode(Double.self, forKey: .estimatedHours) {
            estimatedHours = Self.normalizedHours(hours)
            suggestedXP = XPRules.xp(forEstimatedHours: estimatedHours)
        } else {
            let legacyXP = max((try? container.decode(Int.self, forKey: .suggestedXP)) ?? 25, 0)
            estimatedHours = Self.normalizedHours(Double(legacyXP) / Double(XPRules.xpPerHour))
            suggestedXP = XPRules.xp(forEstimatedHours: estimatedHours)
        }
    }

    static func normalizedRequirement(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "Submit a photo that clearly shows this task is complete."
            : trimmed
    }

    static func normalizedEvidenceCount(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }

    static func normalizedDescriptions(
        _ values: [String],
        count: Int,
        requirement: String
    ) -> [String] {
        let valid = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if count > 2 {
            return [valid.first ?? requirement]
        }
        return (0..<count).map { index in
            valid.indices.contains(index) ? valid[index] : requirement
        }
    }

    static func normalizedHours(_ value: Double) -> Double {
        guard value.isFinite else { return 0.25 }
        let clamped = min(max(value, 0.25), 8)
        return (clamped * 4).rounded() / 4
    }

    var parsedDeadline: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: deadline) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: deadline)
    }
}

enum TaskTitleRules {
    static let chineseCharacterLimit = 12
    static let englishWordLimit = 8

    static func isValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if containsHan(in: trimmed) {
            return trimmed.filter { !$0.isWhitespace }.count <= chineseCharacterLimit
        }
        return words(in: trimmed).count <= englishWordLimit
    }

    static func limited(_ value: String) -> String {
        let trimmed = value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard containsHan(in: trimmed) else {
            return words(in: trimmed).prefix(englishWordLimit).joined(separator: " ")
        }

        var count = 0
        return String(trimmed.prefix { character in
            guard !character.isWhitespace else { return true }
            guard count < chineseCharacterLimit else { return false }
            count += 1
            return true
        }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func limitDescription(for value: String) -> String {
        containsHan(in: value)
            ? L10n.text("最多 12 个字", english: "Up to 12 characters")
            : L10n.text("最多 8 个单词", english: "Up to 8 words")
    }

    private static func words(in value: String) -> [Substring] {
        value.split(whereSeparator: \Character.isWhitespace)
    }

    private static func containsHan(in value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}

struct TaskGenerationService: Sendable {
    private struct ImagePayload: Encodable {
        let mimeType: String
        let base64Data: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case base64Data = "base64_data"
        }
    }

    private struct GenerateTaskRequest: Encodable {
        let text: String
        let timezone: String
        let locale: String
        let sourceImage: ImagePayload?

        enum CodingKeys: String, CodingKey {
            case text
            case timezone
            case locale
            case sourceImage = "source_image"
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let code: String
            let message: String
        }

        let error: APIError
    }

    func generate(from text: String, sourceImageData: Data? = nil) async throws -> GeneratedTaskContract {
        let endpoint = try Self.generateTaskEndpoint()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = sourceImageData == nil ? 35 : 50
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateTaskRequest(
                text: text,
                timezone: TimeZone.current.identifier,
                locale: AppLanguage.current.locale.identifier,
                sourceImage: sourceImageData.map {
                    ImagePayload(mimeType: "image/jpeg", base64Data: $0.base64EncodedString())
                }
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TaskGenerationError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw TaskGenerationError.server(
                statusCode: httpResponse.statusCode,
                message: envelope?.error.message
            )
        }

        do {
            return try JSONDecoder().decode(GeneratedTaskContract.self, from: data)
        } catch {
            throw TaskGenerationError.invalidResponse
        }
    }

    private static func generateTaskEndpoint() throws -> URL {
        guard let baseURL = LifeMedalsAPIConfiguration.baseURL else {
            throw TaskGenerationError.missingConfiguration
        }

        if baseURL.path.hasSuffix("/generate-task") {
            return baseURL
        }
        return baseURL.appending(path: "generate-task")
    }
}

enum TaskGenerationError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case server(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return L10n.text("尚未配置代理地址。请在 Xcode 构建配置中设置 LIFEMEDALS_API_BASE_URL。")
        case .invalidResponse:
            return L10n.text("代理返回了无法读取的数据，请稍后重试。")
        case let .server(statusCode, message):
            if statusCode == 429 {
                return L10n.text("请求太频繁，请稍后再试。")
            }
            if statusCode == 402 {
                return L10n.text("本月 AI 内测预算已用完，请等待预算重置。")
            }
            if statusCode == 413 {
                return L10n.text("照片已自动压缩，但当前 AI 服务仍使用旧版上传限制。请更新服务后重试。")
            }
            return message ?? L10n.text(
                "代理请求失败（HTTP \(statusCode)）。",
                english: "The service request failed (HTTP \(statusCode))."
            )
        }
    }
}
