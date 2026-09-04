//
//  EvidenceSubmissionView.swift
//  LifeMedals
//

import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct EvidenceSubmissionView: View {
    @Environment(\.locale) private var locale

    private struct DraftImage: Identifiable {
        let id = UUID()
        let data: Data
        let slotIndex: Int
    }

    private struct EvidenceBatch: Identifiable {
        let id: UUID
        let evidences: [Evidence]

        var submittedAt: Date {
            evidences.map(\.submittedAt).max() ?? .distantPast
        }

        var verdict: EvidenceVerdict {
            evidences.first?.verdict ?? .pending
        }

        var explanation: String? {
            evidences.lazy.compactMap(\.explanation).first { !$0.isEmpty }
        }
    }

    private static let thumbnailSize = CGSize(width: 112, height: 84)

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var task: TaskContract
    let onVerificationStarted: () -> Void
    let onVerificationFinished: (EvidenceVerdict?, MonsterDiscoveryEvent?) -> Void

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var draftImages: [DraftImage] = []
    @State private var fileImportTargetSlot: Int?
    @State private var isFileImporterPresented = false
    @State private var cameraTargetSlot: Int?
    @State private var isCameraPresented = false
    @State private var isBulkDropTargeted = false
    @State private var targetedFixedSlot: Int?
    @State private var isWorking = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var cardSize: CGSize = .zero
    @State private var monsterDiscoveryEvent: MonsterDiscoveryEvent?
    @FocusState private var isDraftAreaFocused: Bool

    private let verificationService = EvidenceVerificationService()
    private let monsterVariantService = MonsterVariantService()

    init(
        task: TaskContract,
        onVerificationStarted: @escaping () -> Void = {},
        onVerificationFinished: @escaping (EvidenceVerdict?, MonsterDiscoveryEvent?) -> Void = { _, _ in }
    ) {
        self.task = task
        self.onVerificationStarted = onVerificationStarted
        self.onVerificationFinished = onVerificationFinished
    }

    var body: some View {
        let _ = locale.identifier
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                evidenceHeader

                VStack(alignment: .leading, spacing: 10) {
                    evidenceHeaderTitle
                    HStack {
                        if task.status != .verified {
                            draftImageCount
                        }
                        if let latestEvidenceBatch {
                            verdictPill(latestEvidenceBatch.verdict)
                        }
                    }
                }
            }

            if !evidenceBatches.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(evidenceBatches) { batch in
                        evidenceBatchCard(batch)
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
        .padding(isCompactLayout ? 16 : 22)
        .foregroundStyle(PixelTheme.ink)
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            cardSize = newSize
        }
        .focusable()
        .focused($isDraftAreaFocused)
        .focusEffectDisabled()
        .onMacPasteImages { providers in
            guard !isWorking, remainingDraftSlots > 0 else { return }
            importItemProviders(providers, targetSlot: nil)
        }
        // A single card-boundary drop handler routes the drop to the right slot
        // and keeps drag-and-drop behavior identical across macOS and iOS.
        .onDrop(
            of: [UTType.image, UTType.fileURL],
            delegate: EvidenceDropDelegate(
                requiredImageCount: requiredImageCount,
                cardWidth: cardSize.width,
                isWorking: isWorking,
                setHighlight: { isHovering, slot in
                    if requiredImageCount <= 2 {
                        targetedFixedSlot = isHovering ? slot : nil
                    } else {
                        isBulkDropTargeted = isHovering
                    }
                },
                performImport: { providers, slot in
                    importItemProviders(providers, targetSlot: slot)
                }
            )
        )
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            Task { await importFileResult(result, targetSlot: fileImportTargetSlot) }
        }
        .platformCameraPresentation(isPresented: $isCameraPresented) {
            EvidenceCameraView { sourceData in
                guard let targetSlot = cameraTargetSlot else { return }
                do {
                    try addDraftImage(sourceData, targetSlot: targetSlot)
                } catch {
                    showImportError(error)
                }
                cameraTargetSlot = nil
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .onAppear {
#if os(macOS)
            isDraftAreaFocused = true
#endif
        }
    }

    private var evidenceHeader: some View {
        HStack(alignment: .top) {
            evidenceHeaderTitle

            Spacer()

            if task.status != .verified {
                draftImageCount
            }

            if let latestEvidenceBatch {
                verdictPill(latestEvidenceBatch.verdict)
            }
        }
    }

    private var evidenceHeaderTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("证据核验", systemImage: "photo.on.rectangle.angled")
                .font(PixelTheme.font(.headline))
        }
    }

    /// Location-routed drop handler attached to the outer card boundary (see
    /// the comment at its call site for why it isn't attached to the
    /// individual photo slots directly).
    private struct EvidenceDropDelegate: DropDelegate {
        let requiredImageCount: Int
        let cardWidth: CGFloat
        let isWorking: Bool
        let setHighlight: (Bool, Int?) -> Void
        let performImport: ([NSItemProvider], Int?) -> Void

        private static let acceptedTypes: [UTType] = [.image, .fileURL]

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: Self.acceptedTypes)
        }

        func dropEntered(info: DropInfo) {
            setHighlight(true, targetSlot(for: info))
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            setHighlight(true, targetSlot(for: info))
            return DropProposal(operation: .copy)
        }

        func dropExited(info: DropInfo) {
            setHighlight(false, nil)
        }

        func performDrop(info: DropInfo) -> Bool {
            setHighlight(false, nil)
            guard !isWorking else { return false }
            let providers = info.itemProviders(for: Self.acceptedTypes)
            guard !providers.isEmpty else { return false }
            performImport(providers, targetSlot(for: info))
            return true
        }

        /// Only 1- and 2-image tasks map the drop location to a specific slot
        /// (left half / right half of the card); >2-image tasks just add to
        /// the next available slot regardless of where the drop lands.
        private func targetSlot(for info: DropInfo) -> Int? {
            switch requiredImageCount {
            case 1:
                return 0
            case 2:
                return cardWidth > 0 && info.location.x >= cardWidth / 2 ? 1 : 0
            default:
                return nil
            }
        }
    }

    private var actionArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            multiImageLayout

            if remainingDraftSlots > 0 {
                Button {
                    cameraTargetSlot = availableSlotIndices.first
                    isCameraPresented = cameraTargetSlot != nil
                } label: {
                    Label("拍摄照片", systemImage: "camera.fill")
                        .font(PixelTheme.font(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .foregroundStyle(.white)
                .pixelSurface(fill: PixelTheme.gold, border: PixelTheme.brown, step: 3, hasShadow: true)
            }

            Text(pasteAndDropHint)
                .font(PixelTheme.font(.caption2))
                .foregroundStyle(PixelTheme.inkMuted.opacity(0.72))

            if hasPendingEvidence && pendingEvidenceImagesAvailable && draftImages.isEmpty {
                Button {
                    Task { await retryPendingVerification() }
                } label: {
                    Label(
                        isWorking ? "正在核验" : "重试待核验证据",
                        systemImage: isWorking ? "hourglass" : "arrow.clockwise"
                    )
                    .font(PixelTheme.font(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .foregroundStyle(.white)
                .pixelSurface(fill: PixelTheme.selection, border: PixelTheme.gold, step: 3, hasShadow: true)
            } else if hasPendingEvidence && !pendingEvidenceImagesAvailable && draftImages.isEmpty {
                Label("待核验图片只保存在提交它的设备，请在本机重新添加证据。", systemImage: "internaldrive")
                    .font(PixelTheme.font(.caption))
                    .foregroundStyle(PixelTheme.inkMuted)
            }

            if !draftImages.isEmpty {
                Button {
                    Task { await submitDraftEvidence() }
                } label: {
                    Label(submitButtonTitle, systemImage: "paperplane.fill")
                        .font(PixelTheme.font(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking || !isDraftComplete)
                .opacity(isDraftComplete ? 1 : 0.52)
                .foregroundStyle(.white)
                .pixelSurface(fill: PixelTheme.selection, border: PixelTheme.goldBright, step: 3, hasShadow: true)
            }

            if isWorking {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在核验任务证据…")
                        .font(PixelTheme.font(.caption))
                        .foregroundStyle(PixelTheme.inkMuted)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isWorking)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: draftImages.count)
    }

    private var draftImageCount: some View {
        Text("\(draftImages.count)/5")
            .font(PixelTheme.statFont(size: 12))
            .foregroundStyle(PixelTheme.inkMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(PixelTheme.paper, in: PixelCornerShape(step: 2))
    }

    private var singleImageLayout: some View {
        fixedImageSlot(index: 0, sideLength: singleImageSideLength)
            .frame(maxWidth: .infinity)
    }

    private var twoImageLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(0..<2, id: \.self) { index in
                fixedImageSlot(index: index, sideLength: twoImageSideLength, expandsToFillWidth: true)
            }
        }
    }

    private var singleImageSideLength: CGFloat {
        min(360, max(240, cardSize.width - 44))
    }

    private var twoImageSideLength: CGFloat {
        min(320, max(132, (cardSize.width - 62) / 2))
    }

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var multiImageLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可提交截图、笔记、邮件对话或其他能合理说明完成情况的照片。")
                .font(PixelTheme.font(.subheadline))
                .foregroundStyle(PixelTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            bulkDraftImageArea

            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: remainingDraftSlots,
                    matching: .images
                ) {
                    Label("照片图库", systemImage: "photo.on.rectangle")
                        .font(PixelTheme.font(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking || remainingDraftSlots == 0)
                .foregroundStyle(.white)
                .pixelSurface(fill: PixelTheme.selection, border: PixelTheme.gold, step: 3)

#if os(macOS)
                Button {
                    presentFileImporter(targetSlot: nil)
                } label: {
                    Label("选择本地文件", systemImage: "folder")
                        .font(PixelTheme.font(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking || remainingDraftSlots == 0)
                .foregroundStyle(PixelTheme.ink)
                .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3)
#endif
            }
        }
    }

    private func fixedImageSlot(index: Int, sideLength: CGFloat, expandsToFillWidth: Bool = false) -> some View {
        ZStack {
            if let draftImage = draftImage(at: index) {
                PlatformImageView(data: draftImage.data)
                    .scaledToFill()
                    .frame(width: sideLength, height: sideLength)
                    .clipped()
            } else {
                if isCompactLayout && requiredImageCount == 2 {
                    compactFixedImageSlot(index: index)
                } else {
                    VStack(spacing: 14) {
                    Text(L10n.text(normalizedImageDescriptions[index]))
                        .font(PixelTheme.font(.subheadline, weight: .medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "photo.badge.plus")
                        .font(PixelTheme.font(size: 38, weight: .bold))
                        .foregroundStyle(PixelTheme.gold)

                    VStack(spacing: 10) {
                        PhotosPicker(selection: photoSelectionBinding(for: index), matching: .images) {
                            Label("照片图库", systemImage: "photo.on.rectangle")
                                .font(PixelTheme.font(.subheadline, weight: .semibold))
                                .frame(maxWidth: min(150, sideLength - 24))
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                        .foregroundStyle(.white)
                        .pixelSurface(fill: PixelTheme.selection, border: PixelTheme.gold, step: 2)

#if os(macOS)
                        Button {
                            presentFileImporter(targetSlot: index)
                        } label: {
                            Label("选择本地文件", systemImage: "folder")
                                .font(PixelTheme.font(.subheadline, weight: .semibold))
                                .frame(maxWidth: min(150, sideLength - 24))
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                        .foregroundStyle(PixelTheme.ink)
                        .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 2)
#endif
                    }
                    }
                    .padding(.horizontal, 22)
                }
            }
        }
        .frame(width: sideLength, height: sideLength)
        .background(
            targetedFixedSlot == index ? PixelTheme.selection.opacity(0.16) : PixelTheme.paperRaised,
            in: PixelCornerShape()
        )
        .clipShape(PixelCornerShape())
        .overlay {
            PixelCornerShape()
                .stroke(
                    targetedFixedSlot == index ? PixelTheme.selection : PixelTheme.gold.opacity(0.58),
                    style: StrokeStyle(lineWidth: targetedFixedSlot == index ? 2 : 1, dash: [7, 5])
                )
        }
        .overlay(alignment: .topTrailing) {
            if let draftImage = draftImage(at: index) {
                removeButton(for: draftImage)
                    .padding(10)
            }
        }
        .frame(maxWidth: expandsToFillWidth ? .infinity : sideLength)
        .contentShape(Rectangle())
        .onTapGesture {
            isDraftAreaFocused = true
        }
    }

    private func compactFixedImageSlot(index: Int) -> some View {
        VStack(spacing: 7) {
            Text("照片 \(index + 1)")
                .font(PixelTheme.font(.caption, weight: .semibold))

            Text(L10n.text(normalizedImageDescriptions[index]))
                .font(PixelTheme.font(.caption2))
                .foregroundStyle(PixelTheme.inkMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                PhotosPicker(selection: photoSelectionBinding(for: index), matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .foregroundStyle(.white)
                .pixelSurface(fill: PixelTheme.selection, border: PixelTheme.gold, step: 2)
                .accessibilityLabel("为照片 \(index + 1) 从图库选择")

#if os(macOS)
                Button {
                    presentFileImporter(targetSlot: index)
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .foregroundStyle(PixelTheme.ink)
                .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 2)
                .accessibilityLabel("为照片 \(index + 1) 选择文件")
#endif
            }
        }
        .padding(10)
    }

    private var bulkDraftImageArea: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(draftImages.sorted { $0.slotIndex < $1.slotIndex }) { draftImage in
                    draftThumbnail(draftImage)
                }

                if remainingDraftSlots > 0 {
#if os(iOS)
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: remainingDraftSlots,
                        matching: .images
                    ) {
                        bulkAddPhotoLabel
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel("添加照片，还可添加 \(remainingDraftSlots) 张")
#else
                    Button {
                        presentFileImporter(targetSlot: nil)
                    } label: {
                        bulkAddPhotoLabel
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel("添加照片，还可添加 \(remainingDraftSlots) 张")
#endif
                }
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, minHeight: Self.thumbnailSize.height + 4, alignment: .leading)
        .padding(12)
        .background(
            isBulkDropTargeted ? PixelTheme.selection.opacity(0.16) : PixelTheme.paperRaised,
            in: PixelCornerShape()
        )
        .overlay {
            PixelCornerShape()
                .stroke(
                    isBulkDropTargeted ? PixelTheme.selection : PixelTheme.gold.opacity(0.5),
                    lineWidth: isBulkDropTargeted ? 2 : 1
                )
        }
        .contentShape(PixelCornerShape())
        .onTapGesture {
            isDraftAreaFocused = true
        }
    }

    private var bulkAddPhotoLabel: some View {
        VStack(spacing: 7) {
            Image(systemName: "plus")
                .font(PixelTheme.font(.title2, weight: .medium))
            Text(
                draftImages.isEmpty
                    ? L10n.text("添加照片", english: "Add Photo")
                    : L10n.text("继续添加", english: "Add More")
            )
                .font(PixelTheme.font(.caption))
        }
        .foregroundStyle(PixelTheme.inkMuted)
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .background(PixelTheme.paperRaised)
        .overlay {
            PixelCornerShape(step: 3)
                .stroke(
                    PixelTheme.gold.opacity(0.58),
                    style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                )
        }
    }

    private func draftThumbnail(_ draftImage: DraftImage) -> some View {
        Group {
            PlatformImageView(data: draftImage.data)
                .scaledToFill()
        }
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .background(PixelTheme.paperRaised)
        .clipShape(PixelCornerShape(step: 3))
        .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.gold.opacity(0.7), lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
            removeButton(for: draftImage)
                .padding(6)
        }
    }

    private func removeButton(for draftImage: DraftImage) -> some View {
        Button {
            removeDraftImage(draftImage.id)
        } label: {
            Image(systemName: "xmark")
                .font(PixelTheme.font(.caption2, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(PixelTheme.danger, in: PixelCornerShape(step: 2))
                .overlay { PixelCornerShape(step: 2).stroke(PixelTheme.goldBright.opacity(0.72), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel("删除这张照片")
    }

    @ViewBuilder
    private func evidenceBatchCard(_ batch: EvidenceBatch) -> some View {
        Group {
            if isCompactLayout {
                VStack(alignment: .leading, spacing: 12) {
                    evidenceBatchThumbnails(batch, expands: true)
                    evidenceBatchMetadata(batch)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    evidenceBatchThumbnails(batch, expands: false)
                    evidenceBatchMetadata(batch)
                }
            }
        }
        .padding(13)
        .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold.opacity(0.72), step: 3)
    }

    private func evidenceBatchThumbnails(_ batch: EvidenceBatch, expands: Bool) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(batch.evidences) { evidence in
                    evidenceThumbnail(evidence)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(
            maxWidth: expands ? .infinity : min(CGFloat(batch.evidences.count) * 96, 288),
            minHeight: 66,
            maxHeight: 66,
            alignment: .leading
        )
    }

    private func evidenceBatchMetadata(_ batch: EvidenceBatch) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    evidenceBatchStatus(batch)
                    Spacer()
                    evidenceBatchDate(batch)
                }
                VStack(alignment: .leading, spacing: 6) {
                    evidenceBatchStatus(batch)
                    evidenceBatchDate(batch)
                }
            }

            if let explanation = batch.explanation {
                Text(explanation)
                    .font(PixelTheme.font(.subheadline))
                    .foregroundStyle(PixelTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if batch.verdict == .pending {
                Text("已保存在本机，等待核验。")
                    .font(PixelTheme.font(.subheadline))
                    .foregroundStyle(PixelTheme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func evidenceBatchStatus(_ batch: EvidenceBatch) -> some View {
        HStack(spacing: 7) {
            verdictPill(batch.verdict)
            if batch.evidences.count > 1 {
                Text("\(batch.evidences.count) 张照片")
                    .font(PixelTheme.font(.caption, weight: .medium))
                    .foregroundStyle(PixelTheme.inkMuted)
            }
        }
    }

    private func evidenceBatchDate(_ batch: EvidenceBatch) -> some View {
        Text(L10n.date(batch.submittedAt, dateStyle: .medium, timeStyle: .short))
            .font(PixelTheme.font(.caption2))
            .foregroundStyle(PixelTheme.inkMuted.opacity(0.72))
    }

    private func evidenceThumbnail(_ evidence: Evidence) -> some View {
        Group {
            if let imageData = evidence.localImageData {
                PlatformImageView(data: imageData)
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(PixelTheme.font(.title2))
                    .foregroundStyle(PixelTheme.inkMuted)
            }
        }
        .frame(width: 88, height: 66)
        .background(PixelTheme.paperRaised)
        .clipShape(PixelCornerShape(step: 3))
        .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.gold.opacity(0.7), lineWidth: 1) }
    }

    private func verdictPill(_ verdict: EvidenceVerdict) -> some View {
        let presentation: (String, String, Color) = switch verdict {
        case .pending:
            (L10n.text("等待核验", english: "Pending Verification"), "hourglass", PixelTheme.selection)
        case .verified:
            (L10n.text("已完成", english: "Verified"), "checkmark.circle.fill", PixelTheme.success)
        case .needMoreProof:
            (L10n.text("需补充证据", english: "Need More Proof"), "photo.badge.plus", PixelTheme.gold)
        case .notVerified:
            (L10n.text("未通过核验", english: "Not Verified"), "xmark.circle.fill", PixelTheme.danger)
        }

        return PixelStatusBadge(title: presentation.0, color: presentation.2)
            .accessibilityLabel(presentation.0)
    }

    private func feedbackBanner(message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? PixelTheme.gold : PixelTheme.success)
            Text(L10n.text(message))
                .font(PixelTheme.font(.subheadline))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .pixelSurface(
            fill: PixelTheme.paperRaised,
            border: isError ? PixelTheme.gold : PixelTheme.success,
            step: 3
        )
    }

    private var requiredImageCount: Int {
        // This is a capacity, not a requirement. Legacy tasks may still carry
        // a planned count, but the supportive flow accepts any 1–5 photos.
        5
    }

    // Kept for the legacy fixed-slot view helpers while existing task data is
    // migration-compatible. The active UI always uses the unified gallery.
    private var normalizedImageDescriptions: [String] {
        Array(repeating: task.evidenceRequirement, count: requiredImageCount)
    }

    private var evidenceBatches: [EvidenceBatch] {
        let taskEvidences = task.evidences ?? []
        let explicitBatches = Dictionary(
            grouping: taskEvidences.filter { $0.submissionBatchID != nil },
            by: { $0.submissionBatchID! }
        )
        .map { id, evidences in
            makeEvidenceBatch(id: id, evidences: evidences)
        }

        let legacyEvidences = taskEvidences
            .filter { $0.submissionBatchID == nil }
            .sorted { $0.submittedAt < $1.submittedAt }
        var legacyGroups: [[Evidence]] = []

        for evidence in legacyEvidences {
            if
                let lastGroup = legacyGroups.last,
                let previous = lastGroup.last,
                evidence.submittedAt.timeIntervalSince(previous.submittedAt) <= 1,
                evidence.verdict == previous.verdict,
                evidence.explanation == previous.explanation
            {
                legacyGroups[legacyGroups.count - 1].append(evidence)
            } else {
                legacyGroups.append([evidence])
            }
        }

        let legacyBatches = legacyGroups.compactMap { evidences -> EvidenceBatch? in
            guard let id = evidences.first?.id else { return nil }
            return makeEvidenceBatch(id: id, evidences: evidences)
        }

        return (explicitBatches + legacyBatches)
        .sorted { $0.submittedAt > $1.submittedAt }
    }

    private func makeEvidenceBatch(id: UUID, evidences: [Evidence]) -> EvidenceBatch {
        EvidenceBatch(
            id: id,
            evidences: evidences.sorted {
                ($0.submissionIndex ?? 0, $0.submittedAt) <
                    ($1.submissionIndex ?? 0, $1.submittedAt)
            }
        )
    }

    private var latestEvidenceBatch: EvidenceBatch? {
        evidenceBatches.first
    }

    private var hasPendingEvidence: Bool {
        evidenceBatches.contains { $0.verdict == .pending }
    }

    private var remainingDraftSlots: Int {
        max(0, requiredImageCount - draftImages.count)
    }

    private var availableSlotIndices: [Int] {
        let occupied = Set(draftImages.map(\.slotIndex))
        return (0..<requiredImageCount).filter { !occupied.contains($0) }
    }

    private var isDraftComplete: Bool {
        (1...requiredImageCount).contains(draftImages.count)
    }

    private var submitButtonTitle: String {
        if isWorking { return L10n.text("正在核验", english: "Verifying") }
        return L10n.text(
            "提交 \(draftImages.count) 张照片",
            english: "Submit \(draftImages.count) Photo(s)"
        )
    }

    private var pasteAndDropHint: String {
#if os(macOS)
        L10n.text(
            "拖放图片到上方栏框，或按 ⌘V 粘贴截图（最多 5 张）",
            english: "Drop images above or press ⌘V to paste screenshots (up to 5)"
        )
#else
        L10n.text(
            "可从照片图库选择，或直接拍摄证据照片",
            english: "Choose evidence photos from Photos or take them with the camera"
        )
#endif
    }

    private func draftImage(at slotIndex: Int) -> DraftImage? {
        draftImages.first { $0.slotIndex == slotIndex }
    }

    private func photoSelectionBinding(for slotIndex: Int) -> Binding<PhotosPickerItem?> {
        Binding(
            get: { nil },
            set: { item in
                guard let item else { return }
                Task { await importPhoto(item, targetSlot: slotIndex) }
            }
        )
    }

    private func presentFileImporter(targetSlot: Int?) {
        fileImportTargetSlot = targetSlot
        isFileImporterPresented = true
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem, targetSlot: Int) async {
        feedbackMessage = nil
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                throw EvidenceImageProcessingError.unreadableImage
            }
            try addDraftImage(sourceData, targetSlot: targetSlot)
        } catch {
            showImportError(error)
        }
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        feedbackMessage = nil
        let slots = Array(availableSlotIndices.prefix(items.count))

        for (item, slotIndex) in zip(items, slots) {
            do {
                guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                    throw EvidenceImageProcessingError.unreadableImage
                }
                try addDraftImage(sourceData, targetSlot: slotIndex)
            } catch {
                showImportError(error)
            }
        }

        selectedPhotos = []
    }

    @MainActor
    private func importFileResult(_ result: Result<[URL], Error>, targetSlot: Int?) async {
        defer { fileImportTargetSlot = nil }
        feedbackMessage = nil

        do {
            let urls = try result.get()
            let slots = targetSlot.map { [$0] } ?? Array(availableSlotIndices.prefix(urls.count))

            for (url, slotIndex) in zip(urls, slots) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                try addDraftImage(Data(contentsOf: url), targetSlot: slotIndex)
            }
        } catch {
            showImportError(error)
        }
    }

    private func importItemProviders(_ providers: [NSItemProvider], targetSlot: Int?) {
        let slots = targetSlot.map { [$0] } ?? Array(availableSlotIndices.prefix(providers.count))
        let providerAssignments = Array(zip(providers, slots))
        guard !providerAssignments.isEmpty else { return }

        feedbackMessage = nil
        for (provider, slotIndex) in providerAssignments {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    Task { @MainActor in
                        if let data {
                            do {
                                try addDraftImage(data, targetSlot: slotIndex)
                            } catch {
                                showImportError(error)
                            }
                        } else {
                            showImportError(error ?? EvidenceImageProcessingError.unreadableImage)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    Task { @MainActor in
                        guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                            showImportError(error ?? EvidenceImageProcessingError.unreadableImage)
                            return
                        }

                        do {
                            try addDraftImage(Data(contentsOf: url), targetSlot: slotIndex)
                        } catch {
                            showImportError(error)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func addDraftImage(_ sourceData: Data, targetSlot: Int) throws {
        guard (0..<requiredImageCount).contains(targetSlot) else {
            feedbackMessage = L10n.text(
                "每次可提交 1–5 张照片。",
                english: "Each submission can contain 1–5 photos."
            )
            feedbackIsError = true
            return
        }

        let compressedData = try EvidenceImageProcessor.compressedJPEG(from: sourceData)
        draftImages.removeAll { $0.slotIndex == targetSlot }
        draftImages.append(DraftImage(data: compressedData, slotIndex: targetSlot))
        draftImages.sort { $0.slotIndex < $1.slotIndex }
        feedbackMessage = nil
        isDraftAreaFocused = true
    }

    @MainActor
    private func removeDraftImage(_ id: UUID) {
        draftImages.removeAll { $0.id == id }
        feedbackMessage = nil
        isDraftAreaFocused = true
    }

    @MainActor
    private func showImportError(_ error: Error) {
        feedbackMessage = L10n.text(
            "添加照片失败：\(error.localizedDescription)",
            english: "Could not add the photo: \(error.localizedDescription)"
        )
        feedbackIsError = true
    }

    @MainActor
    private func submitDraftEvidence() async {
        guard !isWorking, isDraftComplete else { return }

        onVerificationStarted()
        isWorking = true
        feedbackMessage = nil
        var verificationVerdict: EvidenceVerdict?
        monsterDiscoveryEvent = nil
        defer {
            isWorking = false
            onVerificationFinished(verificationVerdict, monsterDiscoveryEvent)
        }
        let previousStatus = task.status
        let submittedImages = draftImages.sorted { $0.slotIndex < $1.slotIndex }
        let submissionBatchID = UUID()
        let submittedAt = Date.now
        var insertedEvidences: [Evidence] = []

        do {
            for draftImage in submittedImages {
                let evidenceID = UUID()
                try LocalImageStore.shared.save(draftImage.data, kind: .evidence, id: evidenceID)
                let evidence = Evidence(
                    id: evidenceID,
                    submittedAt: submittedAt,
                    submissionBatchID: submissionBatchID,
                    submissionIndex: draftImage.slotIndex
                )
                modelContext.insert(evidence)
                task.evidences = (task.evidences ?? []) + [evidence]
                insertedEvidences.append(evidence)
            }

            task.status = .awaitingVerification
            try modelContext.save()
            draftImages.removeAll()
            verificationVerdict = await verify(insertedEvidences)
        } catch {
            for evidence in insertedEvidences {
                modelContext.delete(evidence)
                LocalImageStore.shared.remove(kind: .evidence, id: evidence.id)
            }
            task.status = previousStatus
            try? modelContext.save()
            feedbackMessage = L10n.text(
                "保存证据失败：\(error.localizedDescription)",
                english: "Could not save the evidence: \(error.localizedDescription)"
            )
            feedbackIsError = true
        }

    }

    @MainActor
    private func retryPendingVerification() async {
        guard !isWorking else { return }
        guard let pendingBatch = evidenceBatches.first(where: { $0.verdict == .pending }) else { return }

        onVerificationStarted()
        isWorking = true
        feedbackMessage = nil
        var verificationVerdict: EvidenceVerdict?
        monsterDiscoveryEvent = nil
        defer {
            isWorking = false
            onVerificationFinished(verificationVerdict, monsterDiscoveryEvent)
        }
        task.status = .awaitingVerification
        try? modelContext.save()
        verificationVerdict = await verify(pendingBatch.evidences)
    }

    private var pendingEvidenceImagesAvailable: Bool {
        guard let pendingBatch = evidenceBatches.first(where: { $0.verdict == .pending }) else {
            return false
        }
        return !pendingBatch.evidences.isEmpty && pendingBatch.evidences.allSatisfy {
            $0.localImageData != nil
        }
    }

    @MainActor
    private func verify(_ evidences: [Evidence]) async -> EvidenceVerdict? {
        let orderedEvidences = evidences.sorted { ($0.submissionIndex ?? 0) < ($1.submissionIndex ?? 0) }
        let images = orderedEvidences.compactMap(\.localImageData)

        do {
            let result = try await verificationService.verify(
                taskTitle: task.title,
                lockedRequirement: task.evidenceRequirement,
                imageData: images
            )

            let resolvedVerdict: EvidenceVerdict
            switch result.verdict {
            case .verified:
                resolvedVerdict = .verified
            case .needMoreProof:
                resolvedVerdict = .needMoreProof
            case .notVerified:
                resolvedVerdict = .notVerified
            }

            for evidence in evidences {
                evidence.explanation = result.explanation
                evidence.verdict = resolvedVerdict
            }

            var awardEvent: XPAwardEvent?
            switch result.verdict {
            case .verified:
                await refreshMonsterArtworkBeforeDiscovery()
                task.status = .verified
                monsterDiscoveryEvent = try? MonsterDiscoveryService.recordEncounter(
                    for: task,
                    in: modelContext
                )
                if task.isSubtask {
                    awardEvent = try TaskGroupService.reconcileParent(for: task, in: modelContext)
                } else {
                    awardEvent = XPService.awardXP(for: task, in: modelContext)
                }
            case .needMoreProof:
                task.status = .needMoreProof
            case .notVerified:
                task.status = .notVerified
            }
            try modelContext.save()
            if let awardEvent {
                XPService.publishAward(awardEvent)
            }
            feedbackMessage = L10n.text("核验结果已写入本机。")
            feedbackIsError = false
            return resolvedVerdict
        } catch {
            // Roll back parent status, XPLog, badge totals, and evidence verdicts
            // together if the final atomic save fails.
            modelContext.rollback()
            monsterDiscoveryEvent = nil
            for evidence in evidences {
                evidence.verdict = .pending
            }
            task.status = .awaitingVerification
            try? modelContext.save()
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
            return nil
        }
    }

    @MainActor
    private func refreshMonsterArtworkBeforeDiscovery() async {
        guard
            let canonicalTag = task.monsterTag,
            let level = task.monsterLevel,
            let badgeKind = task.badgeCategory?.name
        else { return }

        guard let snapshot = try? await monsterVariantService.ensureVariant(
            canonicalTag: canonicalTag,
            badgeKind: badgeKind,
            level: level
        ) else { return }

        MonsterVariantSync.apply(snapshot, to: task)
    }
}
