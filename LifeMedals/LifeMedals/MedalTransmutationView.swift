import Foundation
import SwiftUI
import WebKit

struct MedalAnimationCommand: Equatable {
    enum Action: Equatable {
        /// Immediately seek the complete bronze-to-silver timeline (0...1).
        case seek(progress: Double)
        /// Animate any timeline range. Duration is expressed in seconds.
        case play(from: Double, to: Double, duration: TimeInterval)
        case playAll(duration: TimeInterval)
        case pause
        case resume
        case reset
        case award(from: Double, to: Double, transmuteWhenFull: Bool)
        case replayFragments(to: Double)
    }

    let action: Action
    let token: Int
}

/// Hosts the original Canvas/JavaScript medal animation inside SwiftUI.
/// Commands are intentionally small: Swift owns EXP and rank state, while
/// JavaScript owns only rendering and animation timing.
struct MedalTransmutationView: NSViewRepresentable {
    let command: MedalAnimationCommand
    var onFinished: () -> Void = {}
    var onProgress: (Double) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "medalAnimation")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        guard let indexURL = Self.animationIndexURL else {
            assertionFailure("MedalAnimation.html is missing from the app bundle")
            return webView
        }

        webView.loadFileURL(
            indexURL,
            allowingReadAccessTo: indexURL.deletingLastPathComponent()
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sendCommandIfNeeded()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "medalAnimation")
        webView.navigationDelegate = nil
    }

    private static var animationIndexURL: URL? {
        Bundle.main.url(forResource: "MedalAnimation", withExtension: "html")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MedalTransmutationView
        weak var webView: WKWebView?

        private var isReady = false
        private var lastCommand: MedalAnimationCommand?

        init(parent: MedalTransmutationView) {
            self.parent = parent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard
                message.name == "medalAnimation",
                let body = message.body as? [String: Any],
                let event = body["event"] as? String
            else { return }

            if let progress = body["progress"] as? Double {
                parent.onProgress(progress)
            }

            switch event {
            case "ready":
                isReady = true
                sendCommandIfNeeded(force: true)
            case "finished":
                parent.onFinished()
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
        }

        func sendCommandIfNeeded(force: Bool = false) {
            guard isReady, let webView else { return }
            guard force || lastCommand != parent.command else { return }

            lastCommand = parent.command
            webView.evaluateJavaScript(javaScript(for: parent.command))
        }

        private func javaScript(for command: MedalAnimationCommand) -> String {
            switch command.action {
            case let .seek(progress):
                return "window.medalAnimation.setProgress(\(progress));"
            case let .play(from, to, duration):
                return "window.medalAnimation.play(\(from), \(to), \(duration * 1000));"
            case let .playAll(duration):
                return "window.medalAnimation.playAll(\(duration * 1000));"
            case .pause:
                return "window.medalAnimation.pause();"
            case .resume:
                return "window.medalAnimation.resume();"
            case .reset:
                return "window.medalAnimation.reset();"
            case let .award(from, to, transmuteWhenFull):
                return "window.medalAnimation.playAward(\(from), \(to), \(transmuteWhenFull ? "true" : "false"));"
            case let .replayFragments(to):
                return "window.medalAnimation.replayFragments(\(to));"
            }
        }
    }
}

struct MedalAwardAnimationOverlay: View {
    let event: XPAwardEvent
    let onDismiss: () -> Void

    @State private var isFinished = false

    private var fromProgress: Double {
        min(max(Double(event.previousXP) / Double(BadgeRank.silver.cumulativeXPThreshold), 0), 1)
    }

    private var toProgress: Double {
        min(max(Double(event.currentXP) / Double(BadgeRank.silver.cumulativeXPThreshold), 0), 1)
    }

    private var fragmentCount: Int {
        min(73, Int(ceil(toProgress * 73)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(toProgress >= 1 ? "白银觉醒" : "解题勋章正在铸造")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("+\(event.amount) EXP · \(event.currentXP) / \(BadgeRank.silver.cumulativeXPThreshold)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.64))
                    }

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Label(
                            isFinished ? "关闭" : "跳过动画",
                            systemImage: isFinished ? "xmark" : "forward.end.fill"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(isFinished ? "关闭" : "跳过动画")
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)

                MedalTransmutationView(
                    command: MedalAnimationCommand(
                        action: .award(
                            from: fromProgress,
                            to: toProgress,
                            transmuteWhenFull: true
                        ),
                        token: event.id.hashValue
                    )
                ) {
                    withAnimation(.smooth(duration: 0.25)) {
                        isFinished = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(toProgress >= 1 ? "100% · 白银勋章" : "\(Int((toProgress * 100).rounded()))% · 青铜勋章")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                        Text(toProgress >= 1 ? "淬炼完成，白银真身已经显露" : "已拥有 \(fragmentCount) / 73 块甲片")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
            .frame(maxWidth: 780, maxHeight: 640)
            .background(Color(red: 0.02, green: 0.035, blue: 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 48, y: 20)
            .padding(28)
        }
    }
}

struct ProblemSolverMedalDetailView: View {
    let currentXP: Int
    let rank: BadgeRank

    @State private var replayToken = 0

    private var isSilver: Bool {
        rank >= .silver
    }

    private var bronzeProgress: Double {
        min(max(Double(currentXP) / Double(BadgeRank.silver.cumulativeXPThreshold), 0), 1)
    }

    private var fragmentCount: Int {
        min(73, Int(ceil(bronzeProgress * 73)))
    }

    private var command: MedalAnimationCommand {
        if isSilver {
            return MedalAnimationCommand(action: .seek(progress: 1), token: replayToken)
        }
        if replayToken > 0 {
            return MedalAnimationCommand(action: .replayFragments(to: bronzeProgress), token: replayToken)
        }
        return MedalAnimationCommand(action: .seek(progress: 0), token: 0)
    }

    var body: some View {
        HStack(spacing: 22) {
            MedalTransmutationView(command: command)
                .frame(width: 340, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text(isSilver ? "100%" : "0%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(isSilver ? "白银勋章" : "青铜勋章")
                    .font(.title3.bold())

                Text(isSilver
                     ? "青铜甲片已经全部淬炼并四散，白银真身永久解锁。"
                     : "当前已积累 \(currentXP) EXP，对应 \(fragmentCount) / 73 块甲片。平时保持青铜原貌，需要时可回放已有甲片的附着过程。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isSilver, bronzeProgress > 0 {
                    Button {
                        replayToken += 1
                    } label: {
                        Label("回放当前碎片", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 20)
        }
        .background(Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .onChange(of: currentXP) { _, _ in
            replayToken = 0
        }
    }
}
