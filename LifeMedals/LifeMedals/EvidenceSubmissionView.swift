//
//  EvidenceSubmissionView.swift
//  LifeMedals
//

import AppKit
import PhotosUI
import SwiftData
import SwiftUI

struct EvidenceSubmissionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TaskContract

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isWorking = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false

    private let verificationService = EvidenceVerificationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("证据核验", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                    Text("图片副本压缩后保存在本机；代理只在单次请求期间转发。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let latestEvidence {
                    verdictPill(latestEvidence.verdict)
                }
            }

            if sortedEvidences.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 31, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("还没有提交证据")
                        .font(.subheadline.weight(.semibold))
                    Text("选择截图，或直接使用这台 Mac 的相机拍照。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(sortedEvidences) { evidence in
                        evidenceCard(evidence)
                    }
                }
            }

            if let feedbackMessage {
                feedbackBanner(message: feedbackMessage, isError: feedbackIsError)
            }

            if task.status != .verified {
                actionArea
            }
        }
        .padding(22)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .sheet(isPresented: $isCameraPresented) {
            EvidenceCameraView { sourceData in
                Task { await saveAndVerify(sourceData) }
            }
        }
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            if hasPendingEvidence {
                Button {
                    Task { await retryPendingVerification() }
                } label: {
                    Label(
                        isWorking ? "正在核验" : "重试待核验证据",
                        systemImage: isWorking ? "hourglass" : "arrow.clockwise"
                    )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.14)).interactive(),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
            } else {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(photoActionTitle, systemImage: "photo.on.rectangle")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                        .glassEffect(
                            .regular.tint(Color.accentColor.opacity(0.14)).interactive(),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )

                        Button {
                            isCameraPresented = true
                        } label: {
                            Label("拍照", systemImage: "camera")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                        .glassEffect(
                            .regular.interactive(),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                    }
                }
            }

            if isWorking {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("本地副本已保存，正在按锁定的验收标准核验…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.3), value: isWorking)
    }

    private func evidenceCard(_ evidence: Evidence) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if
                    let imageData = evidence.imageData,
                    let image = NSImage(data: imageData)
                {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 78)
            .background(.white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    verdictPill(evidence.verdict)
                    Spacer()
                    Text(evidence.submittedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let explanation = evidence.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if evidence.verdict == .pending {
                    Text("已保存在本机，等待核验。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func verdictPill(_ verdict: EvidenceVerdict) -> some View {
        let presentation: (String, String, Color) = switch verdict {
        case .pending:
            ("Pending Verification", "hourglass", .accentColor)
        case .verified:
            ("Verified", "checkmark.circle.fill", .green)
        case .needMoreProof:
            ("Need More Proof", "photo.badge.plus", .orange)
        case .notVerified:
            ("Not Verified", "xmark.circle.fill", .red)
        }

        return Label(presentation.0, systemImage: presentation.1)
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(presentation.2.opacity(0.09)), in: Capsule())
    }

    private func feedbackBanner(message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .glassEffect(
            .regular.tint((isError ? Color.orange : .green).opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
    }

    private var sortedEvidences: [Evidence] {
        task.evidences.sorted { $0.submittedAt > $1.submittedAt }
    }

    private var latestEvidence: Evidence? {
        sortedEvidences.first
    }

    private var hasPendingEvidence: Bool {
        task.evidences.contains { $0.verdict == .pending }
    }

    private var photoActionTitle: String {
        switch task.status {
        case .needMoreProof:
            "补交证据"
        case .notVerified:
            "重新提交证据"
        default:
            "选择图片"
        }
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        feedbackMessage = nil
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                throw EvidenceImageProcessingError.unreadableImage
            }
            selectedPhoto = nil
            await saveAndVerify(sourceData)
        } catch {
            selectedPhoto = nil
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    @MainActor
    private func saveAndVerify(_ sourceData: Data) async {
        guard !isWorking else { return }
        isWorking = true
        feedbackMessage = nil
        let previousStatus = task.status
        var insertedEvidence: Evidence?

        do {
            let compressedData = try EvidenceImageProcessor.compressedJPEG(from: sourceData)
            let evidence = Evidence(imageData: compressedData)
            insertedEvidence = evidence
            modelContext.insert(evidence)
            task.evidences.append(evidence)
            task.status = .awaitingVerification
            try modelContext.save()

            await verify(evidence)
        } catch {
            if let insertedEvidence {
                modelContext.delete(insertedEvidence)
            }
            task.status = previousStatus
            feedbackMessage = "保存证据失败：\(error.localizedDescription)"
            feedbackIsError = true
        }

        isWorking = false
    }

    @MainActor
    private func retryPendingVerification() async {
        guard !isWorking else { return }
        guard let pending = sortedEvidences.first(where: { $0.verdict == .pending }) else { return }
        isWorking = true
        feedbackMessage = nil
        task.status = .awaitingVerification
        try? modelContext.save()
        await verify(pending)
        isWorking = false
    }

    @MainActor
    private func verify(_ evidence: Evidence) async {
        let images = sortedEvidences
            .prefix(4)
            .compactMap(\.imageData)

        do {
            let result = try await verificationService.verify(
                lockedRequirement: task.evidenceRequirement,
                imageData: images
            )

            evidence.explanation = result.explanation
            switch result.verdict {
            case .verified:
                evidence.verdict = .verified
                task.status = .verified
            case .needMoreProof:
                evidence.verdict = .needMoreProof
                task.status = .needMoreProof
            case .notVerified:
                evidence.verdict = .notVerified
                task.status = .notVerified
            }
            try modelContext.save()
            feedbackMessage = "核验结果已写入本机。"
            feedbackIsError = false
        } catch {
            // Keep the pending record and compressed image for a later retry.
            evidence.verdict = .pending
            task.status = .awaitingVerification
            try? modelContext.save()
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }
}
