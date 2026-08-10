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

        let evidenceRequirement: String
        let evidenceImageCount: Int
        let evidenceImageDescriptions: [String]
        let images: [ImagePayload]

        enum CodingKeys: String, CodingKey {
            case evidenceRequirement = "evidence_requirement"
            case evidenceImageCount = "evidence_image_count"
            case evidenceImageDescriptions = "evidence_image_descriptions"
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
        lockedRequirement: String,
        expectedImageCount: Int,
        imageDescriptions: [String],
        imageData: [Data]
    ) async throws -> EvidenceVerificationResult {
        guard
            (1...5).contains(expectedImageCount),
            imageData.count == expectedImageCount,
            !imageDescriptions.isEmpty
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
                evidenceRequirement: lockedRequirement,
                evidenceImageCount: expectedImageCount,
                evidenceImageDescriptions: imageDescriptions,
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
            return "尚未配置代理地址。证据已保存在本机，配置后可重试核验。"
        case .invalidEvidence:
            return "证据照片数量与任务要求不一致。"
        case .invalidResponse:
            return "代理返回了无法读取的核验结果，证据仍在本机。"
        case let .server(statusCode, message):
            if statusCode == 429 {
                return "核验请求太频繁，证据已保存在本机，请稍后重试。"
            }
            if statusCode == 402 {
                return "本月 AI 内测预算已用完，证据已保存在本机，可在预算重置后重试。"
            }
            if statusCode == 413 {
                return "证据图片仍然过大，请换一张图片后重试。"
            }
            return message ?? "核验请求失败（HTTP \(statusCode)），证据仍在本机。"
        }
    }
}
