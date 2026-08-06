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

        context.coordinator.loadAnimation(for: categoryName)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let configuration = MedalArtworkCatalog.configuration(for: categoryName)
        if context.coordinator.loadedConfiguration != configuration {
            context.coordinator.loadAnimation(for: categoryName)
        }
        context.coordinator.sendCommandIfNeeded()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "medalAnimation")
        webView.navigationDelegate = nil
    }

    private static var animationIndexURL: URL? {
        Bundle.main.url(forResource: "MedalAnimation", withExtension: "html")
    }

    /// Replaces the HTML file's historical embedded image copies with local
    /// file references. Keeping multi-megabyte base64 images out of the inline
    /// script avoids WebKit occasionally abandoning the Canvas initialization
    /// and leaving only the dark page background visible.
    private static func animationHTML(
        using indexURL: URL,
        bronzeFileName: String,
        silverFileName: String,
        fragmentCount: Int
    ) -> String? {
        guard
            var html = try? String(contentsOf: indexURL, encoding: .utf8),
            let assetDeclarationStart = html.range(of: "window.__medalAssets="),
            let animationScriptStart = html.range(
                of: "\n(function(){",
                range: assetDeclarationStart.upperBound..<html.endIndex
            )
        else { return nil }

        let replacement = "window.__medalAssets={bronze:\"\(bronzeFileName)\",silver:\"\(silverFileName)\"};window.__medalConfig={fragmentCount:\(fragmentCount)};"
        html.replaceSubrange(
            assetDeclarationStart.lowerBound..<animationScriptStart.lowerBound,
            with: replacement
        )
        // The supplied PNGs may use either square or widescreen transparent
        // canvases. Always draw their centered square so the medal is neither
        // shrunk in SwiftUI nor stretched in Canvas.
        html = html.replacingOccurrences(
            of: "function bt(t,e,o,r,c=1){n.save(),n.globalAlpha=c,n.drawImage(t,e,o,r,r),n.restore()}",
            with: "function bt(t,e,o,r,c=1){const a=Math.min(t.naturalWidth,t.naturalHeight),l=(t.naturalWidth-a)/2,s=(t.naturalHeight-a)/2;n.save(),n.globalAlpha=c,n.drawImage(t,l,s,a,a,e,o,r,r),n.restore()}"
        )

        // Fragment geometry is a renderer detail; the configured total owns
        // award discretisation and timeline stepping. This keeps the effect
        // smooth for any business fragment count without coupling that count
        // to the current 73-cell visual mesh.
        html = html.replacingOccurrences(
            of: "const B=.42",
            with: "const B=.42,fragmentTarget=Math.max(1,Math.round(st.__medalConfig?.fragmentCount??73))"
        )
        html = html.replacingOccurrences(
            of: "let a=Math.ceil(r*M.length-1e-9);const l=Math.ceil(c*M.length-1e-9)",
            with: "let a=Math.ceil(r*fragmentTarget-1e-9);const l=Math.ceil(c*fragmentTarget-1e-9)"
        )
        html = html.replacingOccurrences(of: "J(B*a/M.length)", with: "J(B*a/fragmentTarget)")
        html = html.replacingOccurrences(of: "m=B*l/M.length", with: "m=B*l/fragmentTarget")
        html = html.replacingOccurrences(of: "l===M.length", with: "l===fragmentTarget")
        return html
    }

    /// Writes a compact animation document and its two images beside each
    /// other so `loadFileURL` can decode the artwork as ordinary resources.
    private static func preparedAnimationURL(using indexURL: URL, categoryName: String?) -> URL? {
        let artwork = MedalArtworkCatalog.configuration(for: categoryName)
        let bronzeFileName = "medal-bronze.png"
        let silverFileName = "medal-silver.png"
        guard
            let bronzeData = MedalArtworkCatalog.pngData(for: categoryName, rank: .bronze),
            let silverData = MedalArtworkCatalog.pngData(for: categoryName, rank: .silver),
            let html = animationHTML(
                using: indexURL,
                bronzeFileName: bronzeFileName,
                silverFileName: silverFileName,
                fragmentCount: artwork.fragmentCount
            )
        else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeMedals-MedalAnimation", isDirectory: true)
            .appendingPathComponent(artwork.cacheKey, isDirectory: true)
        let preparedURL = directory.appendingPathComponent("index.html")

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try bronzeData.write(
                to: directory.appendingPathComponent(bronzeFileName),
                options: .atomic
            )
            try silverData.write(
                to: directory.appendingPathComponent(silverFileName),
                options: .atomic
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
        var loadedConfiguration: MedalArtworkConfiguration?

        private var isReady = false
        private var lastCommand: MedalAnimationCommand?

        init(parent: MedalTransmutationView) {
            self.parent = parent
        }

        func loadAnimation(for categoryName: String?) {
            guard let webView else { return }
            isReady = false
            lastCommand = nil
            loadedConfiguration = MedalArtworkCatalog.configuration(for: categoryName)

            guard let indexURL = MedalTransmutationView.animationIndexURL else {
                assertionFailure("MedalAnimation.html is missing from the app bundle")
                return
            }

            let url = MedalTransmutationView.preparedAnimationURL(
                using: indexURL,
                categoryName: categoryName
            ) ?? indexURL
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
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
        MedalFragmentRules.collected(
            for: event.currentXP,
            categoryName: event.categoryName
        )
    }

    private var totalFragmentCount: Int {
        MedalFragmentRules.total(for: event.categoryName)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            toProgress >= 1
                                ? "白银觉醒"
                                : "\(BadgeKind.displayName(for: event.categoryName))正在铸造"
                        )
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
                        Text(toProgress >= 1 ? "淬炼完成，白银真身已经显露" : "已拥有 \(fragmentCount) / \(totalFragmentCount) 块甲片")
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

            MedalFragmentStatusLabel(
                currentXP: currentXP,
                categoryName: categoryName,
                wording: .collected
            )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
        }
    }
}
