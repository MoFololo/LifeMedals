import SwiftData
import SwiftUI

struct UnknownMonsterView: View {
    var showsQuestionMark = true
    var accessibilityText = L10n.text("尚未发现的怪物", english: "Undiscovered monster")

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    pixel(width: 18, height: 14, opacity: 0)
                    pixel(width: 18, height: 14)
                    pixel(width: 18, height: 14)
                    pixel(width: 18, height: 14, opacity: 0)
                }
                HStack(spacing: 0) {
                    pixel(width: 18, height: 18)
                    pixel(width: 18, height: 18)
                    pixel(width: 18, height: 18)
                    pixel(width: 18, height: 18)
                }
                HStack(spacing: 0) {
                    pixel(width: 14, height: 28)
                    pixel(width: 22, height: 28)
                    pixel(width: 22, height: 28)
                    pixel(width: 14, height: 28)
                }
                HStack(spacing: 8) {
                    pixel(width: 18, height: 18)
                    pixel(width: 18, height: 18)
                }
            }
            .foregroundStyle(PixelTheme.background)
            .shadow(color: PixelTheme.background.opacity(0.32), radius: 0, x: 4, y: 4)

            if showsQuestionMark {
                Text("?")
                    .font(PixelTheme.displayFont(size: 38))
                    .foregroundStyle(PixelTheme.goldBright)
                    .shadow(color: PixelTheme.background, radius: 0, x: 2, y: 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func pixel(width: CGFloat, height: CGFloat, opacity: Double = 1) -> some View {
        Rectangle()
            .fill(PixelTheme.background.opacity(opacity))
            .frame(width: width, height: height)
    }
}

struct MonsterCachedImageView: View {
    let imageURL: String

    @State private var imageData: Data?
    @State private var didFail = false

    var body: some View {
        Group {
            if let imageData {
                PlatformImageView(data: imageData)
                    .scaledToFit()
            } else if didFail {
                UnknownMonsterView(
                    showsQuestionMark: false,
                    accessibilityText: L10n.text("怪物图片暂时不可用", english: "Monster artwork is temporarily unavailable")
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(PixelTheme.gold)
            }
        }
        .task(id: imageURL) {
            imageData = nil
            didFail = false
            guard let url = URL(string: imageURL), url.scheme == "https" else {
                didFail = true
                return
            }
            do {
                imageData = try await MonsterImageCache.shared.data(for: url)
            } catch {
                didFail = true
            }
        }
    }
}

struct MonsterArtworkView: View {
    let imageURL: String?
    let isDiscovered: Bool

    var body: some View {
        Group {
            if isDiscovered, let imageURL, !imageURL.isEmpty {
                MonsterCachedImageView(imageURL: imageURL)
            } else {
                UnknownMonsterView(
                    accessibilityText: isDiscovered
                        ? L10n.text("怪物正在显形", english: "Monster materializing")
                        : L10n.text("尚未发现的怪物", english: "Undiscovered monster")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MonsterRevealOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let event: MonsterDiscoveryEvent
    let onContinue: () -> Void

    @State private var isRevealed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: PixelTheme.space24) {
                ZStack {
                    UnknownMonsterView()
                        .opacity(event.isFirstDiscovery && !isRevealed ? 1 : 0)

                    MonsterArtworkView(imageURL: event.imageURL, isDiscovered: true)
                        .opacity(isRevealed || !event.isFirstDiscovery ? 1 : 0)
                        .scaleEffect(isRevealed || !event.isFirstDiscovery ? 1 : 0.82)
                }
                .frame(width: 188, height: 188)
                .padding(PixelTheme.space12)
                .background(PixelTheme.background.opacity(0.1), in: PixelCornerShape(step: 6))
                .overlay { PixelCornerShape(step: 6).stroke(PixelTheme.goldBright, lineWidth: 3) }

                VStack(spacing: PixelTheme.space8) {
                    Text(title)
                        .font(PixelTheme.displayFont(size: 27))
                        .foregroundStyle(event.isFirstDiscovery ? PixelTheme.goldBright : PixelTheme.success)

                    Text(MonsterTaxonomy.categoryLabel(for: event.canonicalTag))
                        .font(PixelTheme.displayFont(size: 22))
                        .foregroundStyle(PixelTheme.ink)

                    Text(L10n.text("等级 \(event.level)", english: "Level \(event.level)"))
                        .font(PixelTheme.statFont(size: 14))
                        .foregroundStyle(PixelTheme.inkMuted)

                    if event.imageURL == nil {
                        Text(L10n.text("发现已保存，怪物正在显形。", english: "Discovery saved. The monster is materializing."))
                            .font(PixelTheme.font(.caption))
                            .foregroundStyle(PixelTheme.inkMuted)
                    }
                }
                .multilineTextAlignment(.center)

                Button(action: onContinue) {
                    Text(L10n.text("继续", english: "Continue"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(tone: PixelTheme.selection))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
            .frame(maxWidth: 380)
            .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.goldBright, step: 6, hasShadow: true)
            .padding(.horizontal, 22)
        }
        .task {
            guard event.isFirstDiscovery else {
                isRevealed = true
                return
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 520))
            withAnimation(reduceMotion ? .linear(duration: 0.18) : .snappy(duration: 0.62)) {
                isRevealed = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        event.isFirstDiscovery
            ? L10n.text("发现新怪物！", english: "New Monster Discovered!")
            : L10n.text("再次击败！", english: "Defeated Again!")
    }
}

struct MonsterAtlasView: View {
    private struct Species: Identifiable {
        let canonicalTag: String
        let discoveries: [MonsterDiscovery]

        var id: String { canonicalTag }
        var categoryLabel: String { MonsterTaxonomy.categoryLabel(for: canonicalTag) }
        var encounterCount: Int { discoveries.reduce(0) { $0 + max($1.discoveryCount, 1) } }
        var discoveredLevelCount: Int { Set(discoveries.map(\.level)).count }
        var firstDiscoveredAt: Date { discoveries.map(\.discoveredAt).min() ?? .now }
        var badgeKind: String { discoveries.first?.badgeKindRawValue ?? "" }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \MonsterDiscovery.discoveredAt) private var discoveries: [MonsterDiscovery]
    @State private var selectedTag: String?

    private let variantService = MonsterVariantService()

    var body: some View {
        Group {
            if let selectedTag, let species = species.first(where: { $0.canonicalTag == selectedTag }) {
                speciesDetail(species)
            } else if species.isEmpty {
                emptyState
            } else {
                speciesGrid
            }
        }
        .task(id: pendingRefreshKey) {
            await refreshPendingArtworkUntilSettled()
        }
    }

    private var species: [Species] {
        Dictionary(grouping: discoveries, by: \MonsterDiscovery.canonicalTag)
            .map { Species(canonicalTag: $0.key, discoveries: $0.value) }
            .sorted { $0.firstDiscoveredAt < $1.firstDiscoveredAt }
    }

    private var pendingRefreshKey: String {
        discoveries
            .filter {
                $0.imageURL == nil || !MonsterArtworkFormat.isCurrent($0.styleVersion)
            }
            .map { "\($0.canonicalTag):\($0.level)" }
            .sorted()
            .joined(separator: "|")
    }

    private var speciesGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .compact ? 150 : 210), spacing: 14)],
            spacing: 14
        ) {
            ForEach(species) { item in
                Button {
                    withAnimation(.smooth(duration: 0.32)) {
                        selectedTag = item.canonicalTag
                    }
                } label: {
                    speciesCard(item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func speciesCard(_ species: Species) -> some View {
        let highest = species.discoveries.max { $0.level < $1.level }
        return VStack(alignment: .leading, spacing: PixelTheme.space12) {
            MonsterArtworkView(imageURL: currentArtworkURL(for: highest), isDiscovered: true)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(PixelTheme.space8)
                .background(PixelTheme.background.opacity(0.08), in: PixelCornerShape(step: 4))

            Text(species.categoryLabel)
                .font(PixelTheme.displayFont(size: 17))
                .foregroundStyle(PixelTheme.ink)
                .lineLimit(1)

            Text(L10n.text(
                "发现 \(species.discoveredLevelCount)/9 · 击败 \(species.encounterCount) 次",
                english: "\(species.discoveredLevelCount)/9 found · \(species.encounterCount) defeats"
            ))
                .font(PixelTheme.font(.caption))
                .foregroundStyle(PixelTheme.inkMuted)
                .lineLimit(2)
        }
        .padding(PixelTheme.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
        .accessibilityElement(children: .combine)
    }

    private func speciesDetail(_ species: Species) -> some View {
        let byLevel = Dictionary(grouping: species.discoveries, by: \MonsterDiscovery.level)
            .mapValues { values in values.max { $0.discoveredAt < $1.discoveredAt }! }

        return VStack(alignment: .leading, spacing: PixelTheme.space16) {
            Button {
                withAnimation(.smooth(duration: 0.3)) { selectedTag = nil }
            } label: {
                Label(L10n.text("返回图鉴", english: "Back to Atlas"), systemImage: "chevron.left")
            }
            .buttonStyle(PixelButtonStyle(tone: PixelTheme.brown))

            VStack(alignment: .leading, spacing: PixelTheme.space8) {
                Text(species.categoryLabel)
                    .font(PixelTheme.displayFont(size: 28))
                    .foregroundStyle(PixelTheme.paperRaised)
                Text(BadgeKind.displayName(for: species.badgeKind))
                    .font(PixelTheme.font(.subheadline))
                    .foregroundStyle(PixelTheme.paper.opacity(0.72))
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .compact ? 92 : 120), spacing: 12)],
                spacing: 12
            ) {
                ForEach(1...9, id: \.self) { level in
                    evolutionCard(level: level, discovery: byLevel[level])
                }
            }
        }
    }

    private func evolutionCard(level: Int, discovery: MonsterDiscovery?) -> some View {
        VStack(spacing: PixelTheme.space8) {
            MonsterArtworkView(
                imageURL: currentArtworkURL(for: discovery),
                isDiscovered: discovery != nil
            )
                .frame(height: horizontalSizeClass == .compact ? 78 : 100)

            Text(L10n.text("等级 \(level)", english: "Level \(level)"))
                .font(PixelTheme.statFont(size: 11))
                .foregroundStyle(discovery == nil ? PixelTheme.inkMuted : PixelTheme.ink)

            if let discovery {
                Text(L10n.text("击败 \(discovery.discoveryCount) 次", english: "\(discovery.discoveryCount) defeats"))
                    .font(PixelTheme.font(.caption2))
                    .foregroundStyle(PixelTheme.inkMuted)
            } else {
                Label(L10n.text("未发现", english: "Locked"), systemImage: "lock.fill")
                    .font(PixelTheme.font(.caption2))
                    .foregroundStyle(PixelTheme.inkMuted)
            }
        }
        .padding(PixelTheme.space12)
        .frame(maxWidth: .infinity)
        .pixelSurface(
            fill: discovery == nil ? PixelTheme.paper.opacity(0.82) : PixelTheme.paperRaised,
            border: discovery == nil ? PixelTheme.inkMuted.opacity(0.35) : PixelTheme.gold,
            step: 3
        )
    }

    private var emptyState: some View {
        VStack(spacing: PixelTheme.space12) {
            UnknownMonsterView()
                .frame(width: 150, height: 150)
            Text(L10n.text("怪物图鉴还是空的", english: "Your Monster Atlas Is Empty"))
                .font(PixelTheme.displayFont(size: 19))
                .foregroundStyle(PixelTheme.ink)
            Text(L10n.text(
                "完成任务并通过证据核验后，会在这里发现怪物。",
                english: "Complete tasks and pass evidence verification to discover monsters here."
            ))
                .font(PixelTheme.font(.subheadline))
                .foregroundStyle(PixelTheme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(PixelTheme.space24)
        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
    }

    @MainActor
    private func refreshPendingArtworkUntilSettled() async {
        guard await ensurePendingArtwork() else { return }
        for _ in 0..<60 {
            guard !Task.isCancelled else { return }
            let hasInProgressArtwork = await refreshPendingArtwork()
            guard hasInProgressArtwork else { return }
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
        }
    }

    @MainActor
    private func ensurePendingArtwork() async -> Bool {
        let pending = discoveries.filter {
            $0.imageURL == nil || !MonsterArtworkFormat.isCurrent($0.styleVersion)
        }
        guard !pending.isEmpty else { return false }

        var changed = false
        var hasInProgressArtwork = false
        for discovery in pending {
            guard let snapshot = try? await variantService.ensureVariant(
                canonicalTag: discovery.canonicalTag,
                badgeKind: discovery.badgeKindRawValue,
                level: discovery.level
            ) else { continue }
            if snapshot.status == .ready, snapshot.imageURL != nil {
                MonsterVariantSync.apply(snapshot, to: discovery)
                changed = true
            } else if snapshot.status == .pending || snapshot.status == .generating {
                hasInProgressArtwork = true
            }
        }
        if changed { try? modelContext.save() }
        return hasInProgressArtwork
    }

    @MainActor
    private func refreshPendingArtwork() async -> Bool {
        let pending = discoveries.filter {
            $0.imageURL == nil || !MonsterArtworkFormat.isCurrent($0.styleVersion)
        }
        guard !pending.isEmpty else { return false }

        var changed = false
        var hasInProgressArtwork = false
        for discovery in pending {
            guard let snapshot = try? await variantService.fetchVariant(
                canonicalTag: discovery.canonicalTag,
                level: discovery.level
            ) else { continue }
            if snapshot.status == .ready, snapshot.imageURL != nil {
                MonsterVariantSync.apply(snapshot, to: discovery)
                changed = true
            } else if snapshot.status == .pending || snapshot.status == .generating {
                hasInProgressArtwork = true
            }
        }
        if changed { try? modelContext.save() }
        return hasInProgressArtwork
    }

    private func currentArtworkURL(for discovery: MonsterDiscovery?) -> String? {
        guard MonsterArtworkFormat.isCurrent(discovery?.styleVersion) else { return nil }
        return discovery?.imageURL
    }
}
