//
//  EvidenceSubmissionView.swift
//  LifeMedals
//

import AppKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct EvidenceSubmissionView: View {
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
    @Bindable var task: TaskContract

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var draftImages: [DraftImage] = []
    @State private var fileImportTargetSlot: Int?
    @State private var isFileImporterPresented = false
    @State private var isBulkDropTargeted = false
    @State private var targetedFixedSlot: Int?
    @State private var isWorking = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var cardSize: CGSize = .zero
    @FocusState private var isDraftAreaFocused: Bool

    private let verificationService = EvidenceVerificationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("证据核验", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                    Text("图片副本压缩后保存在本机；只有点击提交后才会发送核验。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let latestEvidenceBatch {
                    verdictPill(latestEvidenceBatch.verdict)
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
        .padding(22)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            cardSize = newSize
        }
        .focusable()
        .focused($isDraftAreaFocused)
        .focusEffectDisabled()
        .onPasteCommand(of: [.image]) { providers in
            guard !isWorking, remainingDraftSlots > 0 else { return }
            importItemProviders(providers, targetSlot: nil)
        }
        // Registered here, outside/after `.glassEffect(...)`, rather than on the
        // individual photo slots. Liquid Glass rendering was found to swallow
        // `onDrop` hit-testing for any descendant nested inside a
        // `.glassEffect`-wrapped view, so a single delegate-based onDrop on the
        // card's own boundary (routed to the right slot via drop location) is
        // used instead.
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
            allowsMultipleSelection: fileImportTargetSlot == nil
        ) { result in
            Task { await importFileResult(result, targetSlot: fileImportTargetSlot) }
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .onAppear {
            isDraftAreaFocused = true
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
            HStack {
                Text("待提交照片")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(draftImages.count)/\(requiredImageCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            switch requiredImageCount {
            case 1:
                singleImageLayout
            case 2:
                twoImageLayout
            default:
                multiImageLayout
            }

            Text(pasteAndDropHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if hasPendingEvidence && draftImages.isEmpty {
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
            }

            if !draftImages.isEmpty {
                Button {
                    Task { await submitDraftEvidence() }
                } label: {
                    Label(submitButtonTitle, systemImage: isDraftComplete ? "paperplane.fill" : "photo.badge.plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking || !isDraftComplete)
                .opacity(isDraftComplete ? 1 : 0.52)
                .glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.18)).interactive(),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
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
        .animation(.smooth(duration: 0.25), value: draftImages.count)
    }

    private var singleImageLayout: some View {
        fixedImageSlot(index: 0, sideLength: 360)
            .frame(maxWidth: .infinity)
    }

    private var twoImageLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(0..<2, id: \.self) { index in
                fixedImageSlot(index: index, sideLength: 320, expandsToFillWidth: true)
            }
        }
    }

    private var multiImageLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(normalizedImageDescriptions[0])
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            bulkDraftImageArea

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: remainingDraftSlots,
                        matching: .images
                    ) {
                        Label("照片图库", systemImage: "photo.on.rectangle")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || remainingDraftSlots == 0)
                    .glassEffect(
                        .regular.tint(Color.accentColor.opacity(0.14)).interactive(),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )

                    Button {
                        presentFileImporter(targetSlot: nil)
                    } label: {
                        Label("选择本地文件", systemImage: "folder")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || remainingDraftSlots == 0)
                    .glassEffect(
                        .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                }
            }
        }
    }

    private func fixedImageSlot(index: Int, sideLength: CGFloat, expandsToFillWidth: Bool = false) -> some View {
        ZStack {
            if let draftImage = draftImage(at: index), let image = NSImage(data: draftImage.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: sideLength, height: sideLength)
                    .clipped()
            } else {
                VStack(spacing: 14) {
                    Text(normalizedImageDescriptions[index])
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        PhotosPicker(selection: photoSelectionBinding(for: index), matching: .images) {
                            Label("照片图库", systemImage: "photo.on.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 150)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                        .glassEffect(
                            .regular.tint(Color.accentColor.opacity(0.14)).interactive(),
                            in: Capsule()
                        )

                        Button {
                            presentFileImporter(targetSlot: index)
                        } label: {
                            Label("选择本地文件", systemImage: "folder")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 150)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                }
                .padding(.horizontal, 22)
            }
        }
        .frame(width: sideLength, height: sideLength)
        .background(
            targetedFixedSlot == index ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.28),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    targetedFixedSlot == index ? Color.accentColor : Color.secondary.opacity(0.22),
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

    private var bulkDraftImageArea: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(draftImages.sorted { $0.slotIndex < $1.slotIndex }) { draftImage in
                    draftThumbnail(draftImage)
                }

                if remainingDraftSlots > 0 {
                    Button {
                        presentFileImporter(targetSlot: nil)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.medium))
                            Text(draftImages.isEmpty ? "添加照片" : "继续添加")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                        .background(.white.opacity(0.28))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    Color.secondary.opacity(0.34),
                                    style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel("添加照片，还可添加 \(remainingDraftSlots) 张")
                }
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, minHeight: Self.thumbnailSize.height + 4, alignment: .leading)
        .padding(12)
        .background(
            isBulkDropTargeted ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.18),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isBulkDropTargeted ? Color.accentColor : Color.secondary.opacity(0.18),
                    lineWidth: isBulkDropTargeted ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            isDraftAreaFocused = true
        }
    }

    private func draftThumbnail(_ draftImage: DraftImage) -> some View {
        Group {
            if let image = NSImage(data: draftImage.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .background(.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.68), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel("删除这张照片")
    }

    private func evidenceBatchCard(_ batch: EvidenceBatch) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(batch.evidences) { evidence in
                        evidenceThumbnail(evidence)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(
                width: min(CGFloat(batch.evidences.count) * 96, 288),
                height: 66,
                alignment: .leading
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    verdictPill(batch.verdict)
                    if batch.evidences.count > 1 {
                        Text("\(batch.evidences.count) 张照片")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(batch.submittedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let explanation = batch.explanation {
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if batch.verdict == .pending {
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

    private func evidenceThumbnail(_ evidence: Evidence) -> some View {
        Group {
            if let imageData = evidence.imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 66)
        .background(.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var requiredImageCount: Int {
        if task.evidenceImageCount != nil {
            return task.requiredEvidenceImageCount
        }

        // The immediately preceding client stored each image independently,
        // but images from one submit are only milliseconds apart. Preserve the
        // intended count for those already-created tasks during migration.
        return min(max(evidenceBatches.map { $0.evidences.count }.max() ?? 1, 1), 5)
    }

    private var normalizedImageDescriptions: [String] {
        let descriptions = task.evidenceImageDescriptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if requiredImageCount <= 2 {
            return (0..<requiredImageCount).map { index in
                descriptions.indices.contains(index) ? descriptions[index] : task.evidenceRequirement
            }
        }
        return [descriptions.first ?? task.evidenceRequirement]
    }

    private var evidenceBatches: [EvidenceBatch] {
        let explicitBatches = Dictionary(
            grouping: task.evidences.filter { $0.submissionBatchID != nil },
            by: { $0.submissionBatchID! }
        )
        .map { id, evidences in
            makeEvidenceBatch(id: id, evidences: evidences)
        }

        let legacyEvidences = task.evidences
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
        draftImages.count == requiredImageCount
    }

    private var submitButtonTitle: String {
        if isWorking { return "正在核验" }
        if isDraftComplete { return "提交 \(requiredImageCount) 张照片" }
        return "还需添加 \(remainingDraftSlots) 张照片"
    }

    private var pasteAndDropHint: String {
        requiredImageCount <= 2
            ? "可拖放到指定图片框；⌘V 会从第一个空位开始添加截图"
            : "拖放图片到上方栏框，或按 ⌘V 粘贴截图"
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
            feedbackMessage = "本任务需要提交 \(requiredImageCount) 张照片。"
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
        feedbackMessage = "添加照片失败：\(error.localizedDescription)"
        feedbackIsError = true
    }

    @MainActor
    private func submitDraftEvidence() async {
        guard !isWorking, isDraftComplete else { return }

        isWorking = true
        feedbackMessage = nil
        let previousStatus = task.status
        let submittedImages = draftImages.sorted { $0.slotIndex < $1.slotIndex }
        let submissionBatchID = UUID()
        let submittedAt = Date.now
        var insertedEvidences: [Evidence] = []

        do {
            for draftImage in submittedImages {
                let evidence = Evidence(
                    imageData: draftImage.data,
                    submittedAt: submittedAt,
                    submissionBatchID: submissionBatchID,
                    submissionIndex: draftImage.slotIndex
                )
                modelContext.insert(evidence)
                task.evidences.append(evidence)
                insertedEvidences.append(evidence)
            }

            task.status = .awaitingVerification
            try modelContext.save()
            draftImages.removeAll()
            await verify(insertedEvidences)
        } catch {
            for evidence in insertedEvidences {
                modelContext.delete(evidence)
            }
            task.status = previousStatus
            try? modelContext.save()
            feedbackMessage = "保存证据失败：\(error.localizedDescription)"
            feedbackIsError = true
        }

        isWorking = false
    }

    @MainActor
    private func retryPendingVerification() async {
        guard !isWorking else { return }
        guard let pendingBatch = evidenceBatches.first(where: { $0.verdict == .pending }) else { return }

        isWorking = true
        feedbackMessage = nil
        task.status = .awaitingVerification
        try? modelContext.save()
        await verify(pendingBatch.evidences)
        isWorking = false
    }

    @MainActor
    private func verify(_ evidences: [Evidence]) async {
        let orderedEvidences = evidences.sorted { ($0.submissionIndex ?? 0) < ($1.submissionIndex ?? 0) }
        let images = orderedEvidences.compactMap(\.imageData)

        do {
            let result = try await verificationService.verify(
                lockedRequirement: task.evidenceRequirement,
                expectedImageCount: requiredImageCount,
                imageDescriptions: normalizedImageDescriptions,
                imageData: images
            )

            for evidence in evidences {
                evidence.explanation = result.explanation
                switch result.verdict {
                case .verified:
                    evidence.verdict = .verified
                case .needMoreProof:
                    evidence.verdict = .needMoreProof
                case .notVerified:
                    evidence.verdict = .notVerified
                }
            }

            switch result.verdict {
            case .verified:
                task.status = .verified
                XPService.awardXP(for: task, in: modelContext)
            case .needMoreProof:
                task.status = .needMoreProof
            case .notVerified:
                task.status = .notVerified
            }
            try modelContext.save()
            feedbackMessage = "核验结果已写入本机。"
            feedbackIsError = false
        } catch {
            for evidence in evidences {
                evidence.verdict = .pending
            }
            task.status = .awaitingVerification
            try? modelContext.save()
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }
}
