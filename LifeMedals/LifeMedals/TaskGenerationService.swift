//
//  TaskGenerationService.swift
//  LifeMedals
//
//  Created by Codex on 2026/7/30.
//

import Foundation

enum LifeMedalsAPIConfiguration {
    static let defaultBaseURL = "https://lifemedals-api.david-lian0809.workers.dev/"

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

struct GeneratedTaskContract: Decodable, Sendable {
    let title: String
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

    enum CodingKeys: String, CodingKey {
        case title
        case deadline
        case deadlinePreset = "deadline_preset"
        case evidenceRequirement = "evidence_requirement"
        case evidenceImageCount = "evidence_image_count"
        case evidenceImageDescriptions = "evidence_image_descriptions"
        case suggestedBadge = "suggested_badge"
        case estimatedHours = "estimated_hours"
        case suggestedXP = "suggested_xp"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        deadline = try container.decode(String.self, forKey: .deadline)
        deadlinePreset = try container.decodeIfPresent(TaskDeadlinePreset.self, forKey: .deadlinePreset)
        evidenceRequirement = try container.decode(String.self, forKey: .evidenceRequirement)
        suggestedBadge = try container.decode(String.self, forKey: .suggestedBadge)

        // Tolerate the previously deployed Worker (which returned a direct
        // suggested_xp) while it is being upgraded to estimate hours instead.
        if let hours = try container.decodeIfPresent(Double.self, forKey: .estimatedHours) {
            estimatedHours = hours
            suggestedXP = XPRules.xp(forEstimatedHours: hours)
        } else {
            let legacyXP = try container.decode(Int.self, forKey: .suggestedXP)
            estimatedHours = Double(legacyXP) / Double(XPRules.xpPerHour)
            suggestedXP = legacyXP
        }

        // Tolerate the previously deployed Worker while it is being upgraded.
        let decodedCount = try container.decodeIfPresent(Int.self, forKey: .evidenceImageCount) ?? 1
        evidenceImageCount = min(max(decodedCount, 1), 5)
        let decodedDescriptions = try container.decodeIfPresent(
            [String].self,
            forKey: .evidenceImageDescriptions
        ) ?? []
        evidenceImageDescriptions = decodedDescriptions.isEmpty
            ? [evidenceRequirement]
            : decodedDescriptions
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
                locale: Locale.current.identifier,
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
            return "尚未配置代理地址。请在 Xcode 构建配置中设置 LIFEMEDALS_API_BASE_URL。"
        case .invalidResponse:
            return "代理返回了无法读取的数据，请稍后重试。"
        case let .server(statusCode, message):
            if statusCode == 429 {
                return "请求太频繁，请稍后再试。"
            }
            if statusCode == 402 {
                return "本月 AI 内测预算已用完，请等待预算重置。"
            }
            if statusCode == 413 {
                return "照片已自动压缩，但当前 AI 服务仍使用旧版上传限制。请更新服务后重试。"
            }
            return message ?? "代理请求失败（HTTP \(statusCode)）。"
        }
    }
}
