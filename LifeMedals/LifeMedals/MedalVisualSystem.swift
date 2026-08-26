//
//  MedalVisualSystem.swift
//  LifeMedals
//

import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Everything the UI and animation renderer need for one medal family.
///
/// Adding or replacing artwork only requires updating the two asset names and
/// the fragment count in `MedalArtworkCatalog.builtIn` below. Feature views
/// deliberately do not know filenames or fragment totals.
struct MedalArtworkConfiguration: Equatable, Sendable {
    let bronzeAssetName: String
    let silverAssetName: String
    let fragmentCount: Int
    let cacheKey: String

    func assetName(for rank: BadgeRank) -> String {
        switch rank {
        case .bronze:
            bronzeAssetName
        case .silver, .gold, .platinum, .emerald, .diamond, .master, .grandmaster, .champion:
            silverAssetName
        }
    }
}

/// The single source of truth for medal artwork and fragment totals used by
/// both SwiftUI and the web-based transmutation animation.
enum MedalArtworkCatalog {
    private static let builtIn: [BadgeKind: MedalArtworkConfiguration] = [
        .solver: MedalArtworkConfiguration(
            bronzeAssetName: "Solver_Bronze",
            silverAssetName: "Solver_Silver",
            fragmentCount: 73,
            cacheKey: "solver"
        ),
        .builder: MedalArtworkConfiguration(
            bronzeAssetName: "Create_Bronze",
            silverAssetName: "Create_Silver",
            fragmentCount: 73,
            cacheKey: "create"
        ),
        .career: MedalArtworkConfiguration(
            bronzeAssetName: "Work_Bronze",
            silverAssetName: "Work_Silver",
            fragmentCount: 73,
            cacheKey: "work"
        ),
        .athlete: MedalArtworkConfiguration(
            bronzeAssetName: "Sport_Bronze",
            silverAssetName: "Sport_Silver",
            fragmentCount: 73,
            cacheKey: "sport"
        ),
        .life: MedalArtworkConfiguration(
            bronzeAssetName: "Create_Bronze",
            silverAssetName: "Create_Silver",
            fragmentCount: 73,
            cacheKey: "life"
        )
    ]

    /// Custom or legacy categories use the Solver family until they
    /// receive an explicit entry in `builtIn`.
    static func configuration(for categoryName: String?) -> MedalArtworkConfiguration {
        guard
            let categoryName,
            let kind = BadgeKind(rawValue: categoryName),
            let configuration = builtIn[kind]
        else {
            return builtIn[.solver]!
        }
        return configuration
    }

    static func assetName(for categoryName: String?, rank: BadgeRank) -> String {
        configuration(for: categoryName).assetName(for: rank)
    }

    /// Supplies the exact same Asset Catalog image to the HTML animation.
    /// This prevents the animation from drifting to an old embedded copy.
    static func pngData(for categoryName: String?, rank: BadgeRank) -> Data? {
        let name = assetName(for: categoryName, rank: rank)
#if os(macOS)
        guard
            let image = NSImage(named: NSImage.Name(name)),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }

        return bitmap.representation(using: .png, properties: [:])
#elseif os(iOS)
        return UIImage(named: name)?.pngData()
#endif
    }
}

/// Reusable medal artwork. Callers provide both the business category and its
/// independently queried rank; direct asset-name checks should not appear in
/// feature views.
struct MedalArtworkView: View {
    let categoryName: String?
    let rank: BadgeRank

    var body: some View {
        Image(MedalArtworkCatalog.assetName(for: categoryName, rank: rank))
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .clipped()
            .accessibilityHidden(true)
    }
}

enum MedalFragmentRules {
    /// The bronze-to-silver animation assembles all fragments across the
    /// first 42% of its timeline before the silver medal is revealed.
    static let assemblyTimelineEnd = 0.42

    static func total(for categoryName: String?) -> Int {
        MedalArtworkCatalog.configuration(for: categoryName).fragmentCount
    }

    static func collected(for currentXP: Int, categoryName: String?) -> Int {
        let total = total(for: categoryName)
        let progress = min(
            max(Double(currentXP) / Double(BadgeRank.silver.cumulativeXPThreshold), 0),
            1
        )
        return min(total, Int(ceil(progress * Double(total))))
    }
}

/// Central styling for upgrade fragments. Add another rank palette here when
/// the progression system receives gold/platinum/etc. fragment designs.
private enum MedalFragmentStyle {
    static func colors(for targetRank: BadgeRank) -> [Color] {
        switch targetRank {
        case .bronze:
            [.orange.opacity(0.95), .brown, .orange.opacity(0.7)]
        case .silver, .gold, .platinum, .emerald, .diamond, .master, .grandmaster, .champion:
            [
                Color(red: 0.96, green: 0.98, blue: 1),
                Color(red: 0.66, green: 0.72, blue: 0.78),
                Color(red: 0.86, green: 0.91, blue: 0.95),
                Color(red: 0.43, green: 0.49, blue: 0.55)
            ]
        }
    }

    static func glow(for targetRank: BadgeRank) -> Color {
        switch targetRank {
        case .bronze: .orange
        case .silver, .gold, .platinum, .emerald, .diamond, .master, .grandmaster, .champion:
            Color(red: 0.68, green: 0.84, blue: 0.98)
        }
    }
}

struct MedalFragmentIcon: View {
    let targetRank: BadgeRank

    var body: some View {
        PointedHexagon()
            .fill(
                LinearGradient(
                    colors: MedalFragmentStyle.colors(for: targetRank),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                PointedHexagon()
                    .stroke(.white.opacity(0.85), lineWidth: 1)
                    .padding(1)
            }
            .shadow(color: MedalFragmentStyle.glow(for: targetRank).opacity(0.5), radius: 3)
            .accessibilityHidden(true)
    }
}

struct MedalFragmentStatusLabel: View {
    @Environment(\.locale) private var locale

    enum Wording {
        case earned
        case collected

        var prefix: String {
            switch self {
            case .earned: L10n.text("已获得", english: "Earned")
            case .collected: L10n.text("已收集", english: "Collected")
            }
        }

        var suffix: String {
            switch self {
            case .earned: L10n.text("白银碎片", english: "Silver Fragments")
            case .collected: L10n.text("碎片", english: "Fragments")
            }
        }
    }

    let currentXP: Int
    let categoryName: String?
    let wording: Wording
    var targetRank: BadgeRank = .silver

    private var total: Int {
        MedalFragmentRules.total(for: categoryName)
    }

    private var fragmentCount: Int {
        MedalFragmentRules.collected(for: currentXP, categoryName: categoryName)
    }

    var body: some View {
        let _ = locale.identifier
        HStack(spacing: 7) {
            Text("\(wording.prefix) \(fragmentCount)/\(total) \(wording.suffix)")
                .font(PixelTheme.statFont(size: 13))
                .foregroundStyle(PixelTheme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            MedalFragmentIcon(targetRank: targetRank)
                .frame(width: 17, height: 19)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(wording.prefix) \(fragmentCount) / \(total) \(wording.suffix)")
    }
}

private struct PointedHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        for index in 0..<6 {
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 3
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
