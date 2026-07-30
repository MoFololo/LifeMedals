//
//  Evidence.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/30.
//

import Foundation
import SwiftData

/// AI 核验的三态结果。
enum EvidenceVerdict: String, Codable {
    case pending
    case verified
    case needMoreProof
    case notVerified
}

/// 用户提交的证据：本地保存的图片（外部存储）、提交时间、AI 核验结果和解释。
@Model
final class Evidence {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var imageData: Data?
    var submittedAt: Date
    var verdictRawValue: String
    var explanation: String?

    var taskContract: TaskContract?

    var verdict: EvidenceVerdict {
        get { EvidenceVerdict(rawValue: verdictRawValue) ?? .pending }
        set { verdictRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        submittedAt: Date = .now,
        verdict: EvidenceVerdict = .pending,
        explanation: String? = nil,
        taskContract: TaskContract? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.submittedAt = submittedAt
        self.verdictRawValue = verdict.rawValue
        self.explanation = explanation
        self.taskContract = taskContract
    }
}
