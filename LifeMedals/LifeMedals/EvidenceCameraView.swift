//
//  EvidenceCameraView.swift
//  LifeMedals
//

import AVFoundation
import Combine
import SwiftUI

struct EvidenceCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: EvidenceCameraController

    init(onCapture: @escaping (Data) -> Void) {
        _controller = StateObject(wrappedValue: EvidenceCameraController(onCapture: onCapture))
    }

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("拍摄证据")
                            .font(.title2.bold())
                        Text("照片会先压缩并仅保存到这台设备。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("关闭相机")
                }

                Group {
                    if controller.isReady {
                        CameraPreview(session: controller.session)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(alignment: .bottom) {
                                Button {
                                    controller.capture()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 62, height: 62)
                                        Circle()
                                            .stroke(.primary.opacity(0.28), lineWidth: 2)
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
                                    .font(.system(size: 38, weight: .light))
                                    .foregroundStyle(.secondary)
                            }
                            Text(controller.message)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 420)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .frame(minHeight: 390)

                if let errorMessage = controller.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 680, minHeight: 540)
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

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let onCapture: (Data) -> Void

    init(onCapture: @escaping (Data) -> Void) {
        self.onCapture = onCapture
        super.init()
    }

    func start() {
        Task {
            let authorization = AVCaptureDevice.authorizationStatus(for: .video)
            let allowed: Bool
            switch authorization {
            case .authorized:
                allowed = true
            case .notDetermined:
                allowed = await AVCaptureDevice.requestAccess(for: .video)
            default:
                allowed = false
            }

            guard allowed else {
                isStarting = false
                message = "相机权限未开启。请在系统设置的“隐私与安全性 → 相机”中允许 LifeMedals 使用相机。"
                return
            }

            configureSession()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func capture() {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        errorMessage = nil
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard
            let camera = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input),
            session.canAddOutput(output)
        else {
            isStarting = false
            message = "没有找到可用的相机。你仍可以从照片图库选择证据。"
            return
        }

        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
        isStarting = false
        isReady = session.isRunning
        message = isReady ? "" : "相机启动失败，请重新打开后再试。"
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
                errorMessage = "拍摄失败：\(error.localizedDescription)"
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
