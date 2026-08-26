//
//  EvidenceCameraView.swift
//  LifeMedals
//

import AVFoundation
import Combine
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct EvidenceCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @StateObject private var controller: EvidenceCameraController
    private let title: String
    private let detail: String

    init(
        title: String = "拍摄证据",
        detail: String = "照片会先压缩并仅保存到这台设备。",
        onCapture: @escaping (Data) -> Void
    ) {
        self.title = title
        self.detail = detail
        _controller = StateObject(wrappedValue: EvidenceCameraController(onCapture: onCapture))
    }

    var body: some View {
        let _ = locale.identifier
        ZStack {
            PixelBackground()

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(title))
                            .font(PixelTheme.displayFont(size: 26))
                            .foregroundStyle(PixelTheme.paperRaised)
                        Text(L10n.text(detail))
                            .font(PixelTheme.font(.subheadline))
                            .foregroundStyle(PixelTheme.paper.opacity(0.72))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(PixelTheme.font(size: 14, weight: .bold))
                            .foregroundStyle(PixelTheme.ink)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3, hasShadow: true)
                    .accessibilityLabel("关闭相机")
                }

                Group {
                    if controller.isReady {
                        CameraPreview(session: controller.session)
                            .clipShape(PixelCornerShape())
                            .overlay { PixelCornerShape().stroke(PixelTheme.gold, lineWidth: 2) }
                            .overlay(alignment: .bottom) {
                                Button {
                                    controller.capture()
                                } label: {
                                    ZStack {
                                        PixelCornerShape(step: 4)
                                            .fill(PixelTheme.paperRaised)
                                            .frame(width: 62, height: 62)
                                        PixelCornerShape(step: 4)
                                            .stroke(PixelTheme.gold, lineWidth: 2)
                                            .frame(width: 70, height: 70)
                                    }
                                    .padding(22)
                                }
                                .buttonStyle(.plain)
                                .disabled(controller.isCapturing)
                                .opacity(controller.isCapturing ? 0.55 : 1)
                                .accessibilityLabel("拍摄照片")
                            }
                    } else {
                        VStack(spacing: 14) {
                            if controller.isStarting {
                                ProgressView()
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(PixelTheme.font(size: 38, weight: .bold))
                                    .foregroundStyle(PixelTheme.gold)
                            }
                            Text(L10n.text(controller.message))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(PixelTheme.inkMuted)
                                .frame(maxWidth: 420)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(PixelTheme.space24)
                        .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: horizontalSizeClass == .compact ? 0 : 390,
                    maxHeight: .infinity
                )

                if let errorMessage = controller.errorMessage {
                    Label {
                        Text(L10n.text(errorMessage))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                        .font(PixelTheme.font(.subheadline))
                        .foregroundStyle(PixelTheme.goldBright)
                }
            }
            .padding(horizontalSizeClass == .compact ? 16 : 24)
        }
        .macOSMinimumWindowSize(width: 680, height: 540)
        .preferredColorScheme(.light)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.didCapture) { _, didCapture in
            if didCapture { dismiss() }
        }
    }
}

@MainActor
private final class EvidenceCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var isStarting = true
    @Published var isReady = false
    @Published var isCapturing = false
    @Published var didCapture = false
    @Published var message = "正在准备相机…"
    @Published var errorMessage: String?

    private let cameraSession = CameraSessionCoordinator()
    private let onCapture: (Data) -> Void
    private var startupTimeoutTask: Task<Void, Never>?

    var session: AVCaptureSession {
        cameraSession.session
    }

    init(onCapture: @escaping (Data) -> Void) {
        self.onCapture = onCapture
        super.init()
    }

    func start() {
        startupTimeoutTask?.cancel()
        isStarting = true
        isReady = false
        message = "正在准备相机…"
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            let authorization = AVCaptureDevice.authorizationStatus(for: .video)
            let allowed: Bool
            switch authorization {
            case .authorized:
                allowed = true
            case .notDetermined:
                message = "等待相机权限…"
                allowed = await AVCaptureDevice.requestAccess(for: .video)
            default:
                allowed = false
            }

            guard allowed else {
                isStarting = false
                message = "相机权限未开启。请在系统设置的“隐私与安全性 → 相机”中允许 LifeMedals 使用相机。"
                return
            }

            beginSessionStartup()
        }
    }

    func stop() {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        cameraSession.stop()
    }

    func capture() {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        errorMessage = nil
        cameraSession.capture(delegate: self)
    }

    private func beginSessionStartup() {
        message = "正在启动相机…"
        startupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.isStarting else { return }
            self.isStarting = false
            self.isReady = false
            self.message = "相机启动超时。请关闭后重试，或检查系统相机权限。"
            self.cameraSession.stop()
        }

        cameraSession.configureAndStart { [weak self] result in
            guard let self, self.isStarting else { return }
            self.startupTimeoutTask?.cancel()
            self.startupTimeoutTask = nil
            self.isStarting = false

            switch result {
            case .ready:
                self.isReady = true
                self.message = ""
            case .cameraUnavailable:
                self.isReady = false
                self.message = "没有找到可用的相机。你仍可以从照片图库选择图片。"
            case .configurationFailed:
                self.isReady = false
                self.message = "相机配置失败，请关闭后重试。"
            case .startFailed:
                self.isReady = false
                self.message = "相机启动失败，请关闭后重试。"
            }
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor [weak self] in
            guard let self else { return }
            isCapturing = false
            if let error {
                errorMessage = L10n.text(
                    "拍摄失败：\(error.localizedDescription)",
                    english: "Capture failed: \(error.localizedDescription)"
                )
                return
            }
            guard let data else {
                errorMessage = "相机没有返回可读取的照片。"
                return
            }
            onCapture(data)
            didCapture = true
        }
    }
}

private enum CameraSessionStartResult: Sendable {
    case ready
    case cameraUnavailable
    case configurationFailed
    case startFailed
}

/// AVFoundation session setup and `startRunning()` are blocking operations.
/// Keep them off the main actor so the camera sheet can always update its state.
private final class CameraSessionCoordinator: @unchecked Sendable {
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "noorg.LifeMedals.camera-session")
    private var isConfigured = false

    func configureAndStart(
        completion: @escaping @MainActor @Sendable (CameraSessionStartResult) -> Void
    ) {
        queue.async { [self] in
            if !isConfigured {
                guard let camera = AVCaptureDevice.default(for: .video) else {
                    Task { @MainActor in completion(.cameraUnavailable) }
                    return
                }

                let input: AVCaptureDeviceInput
                do {
                    input = try AVCaptureDeviceInput(device: camera)
                } catch {
                    Task { @MainActor in completion(.configurationFailed) }
                    return
                }

                session.beginConfiguration()
                session.sessionPreset = .photo
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    Task { @MainActor in completion(.configurationFailed) }
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                isConfigured = true
            }

            if !session.isRunning {
                session.startRunning()
            }
            let result: CameraSessionStartResult = session.isRunning ? .ready : .startFailed
            Task { @MainActor in completion(result) }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func capture(delegate: AVCapturePhotoCaptureDelegate) {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
    }
}

#if os(macOS)
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.previewLayer.session = session
    }
}

private final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
#elseif os(iOS)
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
