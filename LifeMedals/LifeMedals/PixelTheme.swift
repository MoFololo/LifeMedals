import SwiftUI

enum PixelTheme {
    // MARK: Palette

    static let background = Color(red: 0.075, green: 0.055, blue: 0.052)
    static let backgroundRaised = Color(red: 0.125, green: 0.086, blue: 0.072)
    static let brown = Color(red: 0.205, green: 0.126, blue: 0.095)
    static let brownLight = Color(red: 0.315, green: 0.205, blue: 0.145)
    static let paper = Color(red: 0.945, green: 0.875, blue: 0.704)
    static let paperRaised = Color(red: 0.982, green: 0.925, blue: 0.792)
    static let ink = Color(red: 0.145, green: 0.090, blue: 0.068)
    static let inkMuted = Color(red: 0.355, green: 0.275, blue: 0.215)
    static let gold = Color(red: 0.675, green: 0.510, blue: 0.245)
    static let goldBright = Color(red: 0.865, green: 0.695, blue: 0.345)
    static let selection = Color(red: 0.075, green: 0.245, blue: 0.410)
    static let selectionBright = Color(red: 0.105, green: 0.355, blue: 0.570)
    static let danger = Color(red: 0.620, green: 0.145, blue: 0.120)
    static let success = Color(red: 0.175, green: 0.420, blue: 0.245)

    // MARK: Metrics — all layout values derive from 2 / 4 / 8.

    static let unit: CGFloat = 2
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let borderWidth: CGFloat = 2
    static let shadowOffset: CGFloat = 4
    static let cornerStep: CGFloat = 4

    static func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func statFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A compact stair-step silhouette. It reads as pixel art without turning text
/// and controls into coarse 8-bit blocks.
struct PixelCornerShape: Shape {
    var step: CGFloat = PixelTheme.cornerStep

    func path(in rect: CGRect) -> Path {
        let s = min(step, min(rect.width, rect.height) / 4)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + s * 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - s * 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - s * 2, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s * 2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + s * 2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - s * 2))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - s * 2))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.maxX - s * 2, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.maxX - s * 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + s * 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + s * 2, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - s * 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - s * 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s * 2))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s * 2))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.minX + s * 2, y: rect.minY + s))
        path.closeSubpath()
        return path
    }
}

struct PixelBackground: View {
    var body: some View {
        ZStack {
            PixelTheme.background

            Canvas { context, size in
                let tile: CGFloat = 16
                for row in 0...Int(size.height / tile) {
                    for column in 0...Int(size.width / tile) where (row + column * 3) % 7 == 0 {
                        let rect = CGRect(
                            x: CGFloat(column) * tile + 2,
                            y: CGFloat(row) * tile + 2,
                            width: 2,
                            height: 2
                        )
                        context.fill(Path(rect), with: .color(PixelTheme.brownLight.opacity(0.18)))
                    }
                }
            }
            .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, PixelTheme.brown.opacity(0.16), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct PixelPanel<Content: View>: View {
    var fill: Color = PixelTheme.paper
    var border: Color = PixelTheme.gold
    var padding: CGFloat = PixelTheme.space16
    var hasShadow = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    if hasShadow {
                        PixelCornerShape()
                            .fill(PixelTheme.background.opacity(0.92))
                            .offset(x: PixelTheme.shadowOffset, y: PixelTheme.shadowOffset)
                    }
                    PixelCornerShape().fill(fill)
                }
            }
            .overlay {
                PixelCornerShape()
                    .stroke(border, lineWidth: PixelTheme.borderWidth)
            }
            .overlay {
                PixelCornerShape(step: 2)
                    .stroke(PixelTheme.paperRaised.opacity(0.42), lineWidth: 1)
                    .padding(3)
            }
    }
}

struct PixelButtonStyle: ButtonStyle {
    var tone: Color = PixelTheme.selection
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, PixelTheme.space16)
            .padding(.vertical, PixelTheme.space12)
            .background {
                ZStack {
                    if !configuration.isPressed {
                        PixelCornerShape(step: 3)
                            .fill(PixelTheme.background.opacity(0.9))
                            .offset(x: 3, y: 3)
                    }
                    PixelCornerShape(step: 3)
                        .fill(configuration.isPressed ? tone.opacity(0.78) : tone)
                }
            }
            .overlay {
                PixelCornerShape(step: 3)
                    .stroke(PixelTheme.goldBright.opacity(configuration.isPressed ? 0.55 : 0.9), lineWidth: 2)
            }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .contentShape(PixelCornerShape(step: 3))
    }
}

struct PixelButton: View {
    let title: String
    var systemImage: String?
    var tone: Color = PixelTheme.selection
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PixelTheme.space8) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .buttonStyle(PixelButtonStyle(tone: tone))
    }
}

struct PixelIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : PixelTheme.ink)
                .frame(width: 34, height: 34)
                .background(isSelected ? PixelTheme.selection : PixelTheme.paperRaised, in: PixelCornerShape(step: 3))
                .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.gold, lineWidth: 2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct PixelTabItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

struct PixelTabBar: View {
    let items: [PixelTabItem]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: PixelTheme.space4) {
            ForEach(items) { item in
                Button { onSelect(item.id) } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .font(.subheadline.weight(selection == item.id ? .bold : .medium))
                        .foregroundStyle(selection == item.id ? Color.white : PixelTheme.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, PixelTheme.space12)
                        .padding(.vertical, PixelTheme.space8)
                        .background(selection == item.id ? PixelTheme.selection : .clear, in: PixelCornerShape(step: 3))
                        .overlay {
                            if selection == item.id {
                                PixelCornerShape(step: 3).stroke(PixelTheme.gold, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item.id ? .isSelected : [])
            }
        }
        .padding(PixelTheme.space4)
        .background {
            ZStack {
                PixelCornerShape()
                    .fill(PixelTheme.background.opacity(0.9))
                    .offset(x: 3, y: 3)
                PixelCornerShape().fill(PixelTheme.backgroundRaised)
            }
        }
        .overlay { PixelCornerShape().stroke(PixelTheme.gold, lineWidth: 2) }
    }
}

struct PixelInput<Content: View>: View {
    var isFocused = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, PixelTheme.space16)
            .padding(.vertical, PixelTheme.space12)
            .background {
                ZStack {
                    PixelCornerShape()
                        .fill(PixelTheme.brown.opacity(0.32))
                        .offset(x: 3, y: 3)
                    PixelCornerShape().fill(PixelTheme.paperRaised)
                }
            }
            .overlay {
                PixelCornerShape()
                    .stroke(isFocused ? PixelTheme.selectionBright : PixelTheme.gold, lineWidth: 2)
            }
    }
}

struct PixelProgressBar: View {
    let value: Double
    var tint: Color = PixelTheme.success

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(PixelTheme.background.opacity(0.16))
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
            .overlay { Rectangle().stroke(PixelTheme.ink, lineWidth: 2) }
        }
        .frame(height: 12)
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100))%")
    }
}

struct PixelStatusBadge: View {
    let title: String
    var color: Color = PixelTheme.selection

    var body: some View {
        Text(title)
            .font(PixelTheme.statFont(size: 11))
            .foregroundStyle(.white)
            .padding(.horizontal, PixelTheme.space8)
            .padding(.vertical, PixelTheme.space4)
            .background(color, in: PixelCornerShape(step: 2))
            .overlay { PixelCornerShape(step: 2).stroke(PixelTheme.gold.opacity(0.72), lineWidth: 1) }
    }
}

struct PixelDialog<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        PixelPanel(fill: PixelTheme.paperRaised, padding: PixelTheme.space24) {
            VStack(alignment: .leading, spacing: PixelTheme.space16) {
                PixelSectionHeader(title: title)
                content
            }
        }
    }
}

struct PixelSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PixelTheme.space4) {
            HStack(spacing: PixelTheme.space8) {
                Rectangle()
                    .fill(PixelTheme.gold)
                    .frame(width: 4, height: 20)
                Text(title)
                    .font(PixelTheme.displayFont(size: 18))
                    .foregroundStyle(PixelTheme.ink)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PixelTheme.inkMuted)
            }
            Rectangle()
                .fill(PixelTheme.gold.opacity(0.45))
                .frame(height: 1)
        }
    }
}

/// Shared pixel-art surface used by cards, tiles, drop targets and compact
/// controls. Keeping the silhouette and two-tone edge in one modifier makes
/// every feature screen feel like it belongs to the same game UI.
private struct PixelSurfaceModifier: ViewModifier {
    let fill: Color
    let border: Color
    let step: CGFloat
    let hasShadow: Bool
    let innerHighlight: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if hasShadow {
                        PixelCornerShape(step: step)
                            .fill(PixelTheme.background.opacity(0.9))
                            .offset(x: 3, y: 3)
                    }
                    PixelCornerShape(step: step).fill(fill)
                }
            }
            .overlay {
                PixelCornerShape(step: step)
                    .stroke(border, lineWidth: PixelTheme.borderWidth)
            }
            .overlay {
                if innerHighlight {
                    PixelCornerShape(step: max(2, step - 1))
                        .stroke(PixelTheme.paperRaised.opacity(0.36), lineWidth: 1)
                        .padding(3)
                }
            }
            .contentShape(PixelCornerShape(step: step))
    }
}

extension View {
    func pixelSurface(
        fill: Color = PixelTheme.paper,
        border: Color = PixelTheme.gold,
        step: CGFloat = PixelTheme.cornerStep,
        hasShadow: Bool = false,
        innerHighlight: Bool = true
    ) -> some View {
        modifier(
            PixelSurfaceModifier(
                fill: fill,
                border: border,
                step: step,
                hasShadow: hasShadow,
                innerHighlight: innerHighlight
            )
        )
    }
}

struct PixelSymbolTile: View {
    let systemImage: String
    var tint: Color = PixelTheme.selection
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .pixelSurface(
                fill: PixelTheme.paperRaised,
                border: tint.opacity(0.72),
                step: 3,
                innerHighlight: false
            )
    }
}

struct PixelNotice: View {
    let systemImage: String
    let message: String
    var color: Color = PixelTheme.selection

    var body: some View {
        HStack(alignment: .top, spacing: PixelTheme.space12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PixelTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(PixelTheme.space12)
        .pixelSurface(
            fill: PixelTheme.paperRaised,
            border: color.opacity(0.72),
            step: 3,
            innerHighlight: false
        )
    }
}
