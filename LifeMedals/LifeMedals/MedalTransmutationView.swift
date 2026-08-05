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
    var categoryName: String? = nil
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

        if let preparedURL = Self.preparedAnimationURL(using: indexURL, categoryName: categoryName) {
            webView.loadFileURL(
                preparedURL,
                allowingReadAccessTo: preparedURL.deletingLastPathComponent()
            )
        } else {
            webView.loadFileURL(
                indexURL,
                allowingReadAccessTo: indexURL.deletingLastPathComponent()
            )
        }
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

    /// Replaces the HTML file's historical embedded image copies with the
    /// current Asset Catalog artwork. The Canvas animation and every SwiftUI
    /// screen therefore update together when either shared PNG is replaced.
    private static func animationHTML(using indexURL: URL, categoryName: String?) -> String? {
        guard
            var html = try? String(contentsOf: indexURL, encoding: .utf8),
            let bronze = MedalArtworkCatalog.dataURL(for: categoryName, rank: .bronze),
            let silver = MedalArtworkCatalog.dataURL(for: categoryName, rank: .silver),
            let assetScriptStart = html.range(of: "<script>window.__medalAssets="),
            let assetScriptEnd = html.range(
                of: "</script>",
                range: assetScriptStart.lowerBound..<html.endIndex
            )
        else { return nil }

        let replacement = "<script>window.__medalAssets={bronze:\"\(bronze)\",silver:\"\(silver)\"};</script>"
        html.replaceSubrange(assetScriptStart.lowerBound..<assetScriptEnd.upperBound, with: replacement)
        return html
    }

    /// WKWebView is more reliable with this large animation document when it
    /// is loaded as a local file. `loadHTMLString` could leave only the dark
    /// page background visible before the Canvas script initialized.
    private static func preparedAnimationURL(using indexURL: URL, categoryName: String?) -> URL? {
        guard let html = animationHTML(using: indexURL, categoryName: categoryName) else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeMedals-MedalAnimation", isDirectory: true)
        let suffix = categoryName?.hashValue ?? 0
        let preparedURL = directory.appendingPathComponent("medal-\(suffix).html")

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try html.write(to: preparedURL, atomically: true, encoding: .utf8)
            return preparedURL
        } catch {
            assertionFailure("Unable to prepare medal animation HTML: \(error)")
            return nil
        }
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
                    categoryName: event.categoryName,
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

struct MedalDetailHeroView: View {
    let categoryName: String
    let currentXP: Int
    let rank: BadgeRank

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Color(red: 0.02, green: 0.035, blue: 0.07)

                MedalArtworkView(categoryName: categoryName, rank: rank)
                    .padding(22)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }

            MedalFragmentStatusLabel(currentXP: currentXP, wording: .collected)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
        }
    }
}
