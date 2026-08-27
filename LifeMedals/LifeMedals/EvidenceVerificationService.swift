//
//  EvidenceVerificationService.swift
//  LifeMedals
//

import Foundation

struct EvidenceVerificationResult: Decodable, Sendable {
    enum Verdict: String, Decodable, Sendable {
        case verified
        case needMoreProof = "need_more_proof"
        case notVerified = "not_verified"
    }

    let verdict: Verdict
    let explanation: String
}

struct EvidenceVerificationService: Sendable {
    private struct VerificationRequest: Encodable {
        struct ImagePayload: Encodable {
            let mimeType = "image/jpeg"
            let base64Data: String

            enum CodingKeys: String, CodingKey {
                case mimeType = "mime_type"
                case base64Data = "base64_data"
            }
        }

        let taskTitle: String
        let evidenceRequirement: String
        let images: [ImagePayload]

        enum CodingKeys: String, CodingKey {
            case taskTitle = "task_title"
            case evidenceRequirement = "evidence_requirement"
            case images
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let code: String
            let message: String
        }

        let error: APIError
    }

    func verify(
        taskTitle: String,
        lockedRequirement: String,
        imageData: [Data]
    ) async throws -> EvidenceVerificationResult {
        guard
            !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !lockedRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            (1...5).contains(imageData.count)
        else {
            throw EvidenceVerificationError.invalidEvidence
        }

        let endpoint = try Self.endpoint()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 50
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(
            VerificationRequest(
                taskTitle: taskTitle,
                evidenceRequirement: lockedRequirement,
                images: imageData.map {
                    VerificationRequest.ImagePayload(base64Data: $0.base64EncodedString())
                }
            )
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EvidenceVerificationError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw EvidenceVerificationError.server(
                statusCode: httpResponse.statusCode,
                message: envelope?.error.message
            )
        }

        do {
            return try JSONDecoder().decode(EvidenceVerificationResult.self, from: data)
        } catch {
            throw EvidenceVerificationError.invalidResponse
        }
    }

    private static func endpoint() throws -> URL {
        guard let baseURL = LifeMedalsAPIConfiguration.baseURL else {
            throw EvidenceVerificationError.missingConfiguration
        }

        if baseURL.path.hasSuffix("/verify-evidence") {
            return baseURL
        }
        return baseURL.appending(path: "verify-evidence")
    }
}

enum EvidenceVerificationError: LocalizedError {
    case missingConfiguration
    case invalidEvidence
    case invalidResponse
    case server(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return L10n.text("尚未配置代理地址。证据已保存在本机，配置后可重试核验。")
        case .invalidEvidence:
            return L10n.text(
                "请提交 1–5 张能说明任务完成情况的照片。",
                english: "Submit 1–5 photos that help show the task is complete."
            )
        case .invalidResponse:
            return L10n.text("代理返回了无法读取的核验结果，证据仍在本机。")
        case let .server(statusCode, message):
            if statusCode == 429 {
                return L10n.text("核验请求太频繁，证据已保存在本机，请稍后重试。")
            }
            if statusCode == 402 {
                return L10n.text("本月 AI 内测预算已用完，证据已保存在本机，可在预算重置后重试。")
            }
            if statusCode == 413 {
                return L10n.text("证据图片仍然过大，请换一张图片后重试。")
            }
            return message ?? L10n.text(
                "核验请求失败（HTTP \(statusCode)），证据仍在本机。",
                english: "Verification failed (HTTP \(statusCode)). The evidence is still saved on this device."
            )
        }
    }
}
