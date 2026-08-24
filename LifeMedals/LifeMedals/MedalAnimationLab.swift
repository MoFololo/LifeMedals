import SwiftUI

#if DEBUG
/// A temporary lab for tuning the bronze-to-silver erosion before the effect
/// is connected to the production medal library.
struct MedalAnimationLab: View {
    private let rank = BadgeRank.bronze
    private let erosionSeed: UInt64 = 0x4C_49_46_45_4D_45_44_41

    @State private var currentXP = 350
    @State private var particles: [MedalParticle] = []
    @State private var particleStart = Date.distantPast
    @State private var burstToken = 0

    private var progress: Double {
        guard let neededXP = rank.xpNeededForNextRank else { return 1 }
        let earnedInRank = currentXP - rank.cumulativeXPThreshold
        return min(max(Double(earnedInRank) / Double(neededXP), 0), 1)
    }

    private var xpBinding: Binding<Double> {
        Binding(
            get: { Double(currentXP) },
            set: { newValue in
                currentXP = Int(newValue.rounded())
                particles = []
            }
        )
    }

    var body: some View {
        ZStack {
            PixelBackground()

            VStack(spacing: 20) {
                ErodingMedalView(
                    progress: progress,
                    seed: erosionSeed,
                    particles: particles,
                    particleStart: particleStart
                )
                .frame(width: 380, height: 380)

                PixelPanel(fill: PixelTheme.paper, padding: PixelTheme.space16) {
                    VStack(spacing: PixelTheme.space16) {
                        Slider(
                            value: xpBinding,
                            in: Double(rank.cumulativeXPThreshold)...Double(rank.next?.cumulativeXPThreshold ?? 1_000)
                        )
                        .tint(PixelTheme.selection)
                        .frame(maxWidth: 380)
                        .accessibilityLabel("当前经验")

                        HStack(spacing: PixelTheme.space12) {
                            Button("+1% EXP") { awardXP(10) }
                                .buttonStyle(PixelButtonStyle(tone: PixelTheme.selection))

                            Button("+10% EXP") { awardXP(100) }
                                .buttonStyle(PixelButtonStyle(tone: PixelTheme.selection))

                            Button("重置") {
                                currentXP = rank.cumulativeXPThreshold
                                particles = []
                            }
                            .buttonStyle(PixelButtonStyle(tone: PixelTheme.danger))
                        }

                        Text("青铜 → 白银  ·  \(currentXP) / \(rank.next?.cumulativeXPThreshold ?? 1_000) EXP")
                            .font(PixelTheme.statFont(size: 14))
                            .foregroundStyle(PixelTheme.ink)

                        Text("当前剥落进度：\(Int((progress * 100).rounded()))%")
                            .foregroundStyle(PixelTheme.inkMuted)
                    }
                }
            }
            .padding(30)
        }
    }

    private func awardXP(_ amount: Int) {
        guard let nextThreshold = rank.next?.cumulativeXPThreshold else { return }
        let newXP = min(currentXP + amount, nextThreshold)
        let awarded = newXP - currentXP
        guard awarded > 0 else { return }

        withAnimation(.easeInOut(duration: 0.72)) {
            currentXP = newXP
        }
        emitParticles(for: awarded, at: progress)
    }

    private func emitParticles(for awardedXP: Int, at progress: Double) {
        let neededXP = rank.xpNeededForNextRank ?? 1
        let delta = Double(awardedXP) / Double(neededXP)
        let count = min(20, max(8, Int((delta * 80).rounded()) + 8))
        let eventSeed = erosionSeed ^ UInt64(currentXP &* 1_103_515_245)

        particles = MedalParticle.makeBurst(
            count: count,
            progress: progress,
            seed: eventSeed
        )
        particleStart = .now
        burstToken += 1
        let token = burstToken

        Task {
            try? await Task.sleep(for: .seconds(1))
            guard token == burstToken else { return }
            particles = []
        }
    }
}

private struct ErodingMedalView: View {
    let progress: Double
    let seed: UInt64
    let particles: [MedalParticle]
    let particleStart: Date

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.7),
                                Color(red: 0.68, green: 0.78, blue: 1).opacity(0.24),
                                .clear
                            ],
                            center: .center,
                            startRadius: side * 0.16,
                            endRadius: side * 0.62
                        )
                    )
                    .frame(width: side * 1.18, height: side * 1.18)
                    .blur(radius: 12)

                medalImage(rank: .silver)

                medalImage(rank: .bronze)
                    .mask {
                        ErosionMask(progress: progress, seed: seed)
                    }

                ErosionEdgeOverlay(progress: progress, seed: seed)
                    .mask {
                        medalImage(rank: .silver)
                    }

                MedalParticleCanvas(
                    particles: particles,
                    start: particleStart,
                    seed: seed
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("青铜到白银勋章")
        .accessibilityValue("已剥落 \(Int((progress * 100).rounded()))%")
    }

    private func medalImage(rank: BadgeRank) -> some View {
        MedalArtworkView(categoryName: BadgeKind.problemSolver.rawValue, rank: rank)
    }
}

/// A deterministic vector approximation of an erosion field. The broad path
/// supplies vertical XP progress; fixed seeded waves and bites remove the
/// mechanical straight edge without changing between launches.
private struct ErosionMask: View, Animatable {
    var progress: Double
    let seed: UInt64

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let fraction = CGFloat(min(max(progress, 0), 1))
            guard fraction < 1 else { return }

            context.fill(
                ErosionGeometry.remainingBronzePath(
                    progress: fraction,
                    size: size,
                    seed: seed
                ),
                with: .color(.white)
            )

            guard fraction > 0 else { return }
            context.blendMode = .destinationOut

            for bite in ErosionGeometry.bites(
                progress: fraction,
                size: size,
                seed: seed
            ) {
                context.fill(bite, with: .color(.white))
            }
        }
    }
}

private struct ErosionEdgeOverlay: View, Animatable {
    var progress: Double
    let seed: UInt64

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let fraction = CGFloat(min(max(progress, 0), 1))
            guard fraction > 0.002, fraction < 0.998 else { return }

            let edge = ErosionGeometry.edgePath(
                progress: fraction,
                size: size,
                seed: seed
            )

            context.drawLayer { glow in
                glow.addFilter(.blur(radius: max(3, size.width * 0.012)))
                glow.stroke(
                    edge,
                    with: .color(Color(red: 0.72, green: 0.86, blue: 1).opacity(0.95)),
                    lineWidth: max(5, size.width * 0.018)
                )
            }

            context.stroke(
                edge,
                with: .linearGradient(
                    Gradient(colors: [.white, Color(red: 0.64, green: 0.78, blue: 1), .white]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: max(1.2, size.width * 0.004)
            )

            for crack in ErosionGeometry.cracks(
                progress: fraction,
                size: size,
                seed: seed
            ) {
                context.stroke(
                    crack,
                    with: .color(Color(red: 0.16, green: 0.08, blue: 0.035).opacity(0.72)),
                    lineWidth: max(0.8, size.width * 0.0025)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MedalParticleCanvas: View {
    let particles: [MedalParticle]
    let start: Date
    let seed: UInt64

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: particles.isEmpty)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)

                for particle in particles where elapsed >= 0 && elapsed < particle.lifetime {
                    let t = CGFloat(elapsed)
                    let lifeFraction = min(t / CGFloat(particle.lifetime), 1)
                    let originY = ErosionGeometry.boundaryY(
                        x: particle.originX * size.width,
                        progress: CGFloat(particle.originProgress),
                        size: size,
                        seed: seed
                    )
                    let position = CGPoint(
                        x: particle.originX * size.width + particle.horizontalVelocity * t,
                        y: originY + particle.verticalVelocity * t + size.height * 0.52 * t * t
                    )

                    context.drawLayer { fragment in
                        fragment.opacity = Double(1 - lifeFraction * lifeFraction)
                        fragment.translateBy(x: position.x, y: position.y)
                        fragment.rotate(by: .radians(particle.initialRotation + particle.angularVelocity * t))
                        fragment.fill(
                            particle.path,
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color(red: 0.93, green: 0.57, blue: 0.25),
                                    Color(red: 0.42, green: 0.19, blue: 0.07)
                                ]),
                                startPoint: CGPoint(x: -particle.size, y: -particle.size),
                                endPoint: CGPoint(x: particle.size, y: particle.size)
                            )
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MedalParticle: Identifiable {
    let id: Int
    let originX: CGFloat
    let originProgress: Double
    let horizontalVelocity: CGFloat
    let verticalVelocity: CGFloat
    let initialRotation: CGFloat
    let angularVelocity: CGFloat
    let lifetime: TimeInterval
    let size: CGFloat
    let path: Path

    static func makeBurst(count: Int, progress: Double, seed: UInt64) -> [Self] {
        var random = SeededRandom(seed: seed)

        return (0..<count).map { index in
            let size = random.cgFloat(in: 4.5...10)
            let isTriangle = random.nextUnit() < 0.58
            let path: Path

            if isTriangle {
                path = Path { shape in
                    shape.move(to: CGPoint(x: -size * 0.55, y: -size * 0.35))
                    shape.addLine(to: CGPoint(x: size * 0.62, y: -size * 0.12))
                    shape.addLine(to: CGPoint(x: -size * 0.15, y: size * 0.68))
                    shape.closeSubpath()
                }
            } else {
                path = Path { shape in
                    shape.move(to: CGPoint(x: -size * 0.58, y: -size * 0.22))
                    shape.addLine(to: CGPoint(x: size * 0.2, y: -size * 0.55))
                    shape.addLine(to: CGPoint(x: size * 0.64, y: size * 0.18))
                    shape.addLine(to: CGPoint(x: -size * 0.18, y: size * 0.62))
                    shape.closeSubpath()
                }
            }

            return MedalParticle(
                id: index,
                originX: random.cgFloat(in: 0.14...0.86),
                originProgress: progress,
                horizontalVelocity: random.cgFloat(in: -34...34),
                verticalVelocity: random.cgFloat(in: 18...72),
                initialRotation: random.cgFloat(in: 0...(2 * .pi)),
                angularVelocity: random.cgFloat(in: -7...7),
                lifetime: random.double(in: 0.5...0.9),
                size: size,
                path: path
            )
        }
    }
}

private enum ErosionGeometry {
    private static let edgeSampleCount = 72

    static func remainingBronzePath(progress: CGFloat, size: CGSize, seed: UInt64) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: boundaryY(x: 0, progress: progress, size: size, seed: seed)))

            for index in 1...edgeSampleCount {
                let x = size.width * CGFloat(index) / CGFloat(edgeSampleCount)
                path.addLine(to: CGPoint(x: x, y: boundaryY(x: x, progress: progress, size: size, seed: seed)))
            }

            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
    }

    static func edgePath(progress: CGFloat, size: CGSize, seed: UInt64) -> Path {
        Path { path in
            for index in 0...edgeSampleCount {
                let x = size.width * CGFloat(index) / CGFloat(edgeSampleCount)
                let point = CGPoint(x: x, y: boundaryY(x: x, progress: progress, size: size, seed: seed))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }

    static func boundaryY(x: CGFloat, progress: CGFloat, size: CGSize, seed: UInt64) -> CGFloat {
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return size.height }

        let normalizedX = x / max(size.width, 1)
        let phaseA = unit(seed: seed, index: 1) * 2 * .pi
        let phaseB = unit(seed: seed, index: 2) * 2 * .pi
        let broadWave = sin(normalizedX * 5.2 * .pi + phaseA) * 0.012
        let fineWave = sin(normalizedX * 17.0 * .pi + phaseB) * 0.006

        let latticePosition = normalizedX * 18
        let latticeIndex = Int(floor(latticePosition))
        let interpolation = smoothStep(latticePosition - CGFloat(latticeIndex))
        let left = signedUnit(seed: seed, index: 100 + latticeIndex)
        let right = signedUnit(seed: seed, index: 101 + latticeIndex)
        let fixedNoise = (left + (right - left) * interpolation) * 0.014
        let endpointDamping = sin(.pi * progress)
        let normalizedY = progress + (broadWave + fineWave + fixedNoise) * endpointDamping

        return min(max(normalizedY, 0), 1) * size.height
    }

    static func bites(progress: CGFloat, size: CGSize, seed: UInt64) -> [Path] {
        (0..<22).map { index in
            let x = unit(seed: seed, index: 300 + index) * size.width
            let radiusX = (0.008 + unit(seed: seed, index: 400 + index) * 0.018) * size.width
            let radiusY = (0.007 + unit(seed: seed, index: 500 + index) * 0.02) * size.height
            let depth = unit(seed: seed, index: 600 + index) * size.height * 0.028
            let y = boundaryY(x: x, progress: progress, size: size, seed: seed) + depth
            let rect = CGRect(x: x - radiusX, y: y - radiusY, width: radiusX * 2, height: radiusY * 2)
            return Path(ellipseIn: rect)
        }
    }

    static func cracks(progress: CGFloat, size: CGSize, seed: UInt64) -> [Path] {
        (0..<9).flatMap { index -> [Path] in
            let x = (0.1 + unit(seed: seed, index: 700 + index) * 0.8) * size.width
            let startY = boundaryY(x: x, progress: progress, size: size, seed: seed) + size.height * 0.006
            let lean = signedUnit(seed: seed, index: 800 + index)
            let length = (0.035 + unit(seed: seed, index: 900 + index) * 0.07) * size.height
            let middle = CGPoint(x: x + lean * size.width * 0.018, y: startY + length * 0.48)
            let end = CGPoint(x: x - lean * size.width * 0.025, y: startY + length)

            let trunk = Path { path in
                path.move(to: CGPoint(x: x, y: startY))
                path.addLine(to: middle)
                path.addLine(to: end)
            }
            let branch = Path { path in
                path.move(to: middle)
                path.addLine(to: CGPoint(
                    x: middle.x + signedUnit(seed: seed, index: 1_000 + index) * size.width * 0.03,
                    y: middle.y + length * 0.22
                ))
            }
            return [trunk, branch]
        }
    }

    private static func smoothStep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }

    private static func signedUnit(seed: UInt64, index: Int) -> CGFloat {
        unit(seed: seed, index: index) * 2 - 1
    }

    private static func unit(seed: UInt64, index: Int) -> CGFloat {
        var value = seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return CGFloat(Double(value) / Double(UInt64.max))
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value) / Double(UInt64.max)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextUnit()
    }

    mutating func cgFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(nextUnit())
    }
}

#Preview("Medal erosion lab") {
    MedalAnimationLab()
        .frame(width: 540, height: 610)
}
#endif
