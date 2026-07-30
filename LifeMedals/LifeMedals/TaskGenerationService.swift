//
//  TaskGenerationService.swift
//  LifeMedals
//
//  Created by Codex on 2026/7/30.
//

import Foundation

struct GeneratedTaskContract: Decodable, Sendable {
    let title: String
    let deadline: String
    let evidenceRequirement: String
    let suggestedBadge: String
    let suggestedXP: Int

    enum CodingKeys: String, CodingKey {
        case title
        case deadline
        case evidenceRequirement = "evidence_requirement"
        case suggestedBadge = "suggested_badge"
        case suggestedXP = "suggested_xp"
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
    private struct GenerateTaskRequest: Encodable {
        let text: String
        let timezone: String
        let locale: String
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let code: String
            let message: String
        }

        let error: APIError
    }

    func generate(from text: String) async throws -> GeneratedTaskContract {
        let endpoint = try Self.generateTaskEndpoint()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateTaskRequest(
                text: text,
                timezone: TimeZone.current.identifier,
                locale: Locale.current.identifier
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
        let environmentValue = ProcessInfo.processInfo.environment["LIFEMEDALS_API_BASE_URL"]
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "LifeMedalsAPIBaseURL") as? String
        let rawValue = [environmentValue, bundleValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let rawValue, let baseURL = URL(string: rawValue), baseURL.scheme != nil else {
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
            return "尚未配置代理地址。请在 Xcode Scheme 中设置 LIFEMEDALS_API_BASE_URL。"
        case .invalidResponse:
            return "代理返回了无法读取的数据，请稍后重试。"
        case let .server(statusCode, message):
            if statusCode == 429 {
                return "请求太频繁，请稍后再试。"
            }
            if statusCode == 402 {
                return "本月 AI 内测预算已用完，请等待预算重置。"
            }
            return message ?? "代理请求失败（HTTP \(statusCode)）。"
        }
    }
}
