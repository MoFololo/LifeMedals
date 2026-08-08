import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var accountManager: AppleAccountManager
    @EnvironmentObject private var syncMonitor: CloudSyncMonitor

    var onContinue: () -> Void

    var body: some View {
        ZStack {
            GlassBackground()

            GlassEffectContainer(spacing: 18) {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "medal.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 72, height: 72)
                            .glassEffect(.regular.tint(.orange.opacity(0.12)), in: Circle())

                        VStack(spacing: 7) {
                            Text("人生勋章")
                                .font(.largeTitle.bold())
                            Text("把想做的事，变成一份值得完成的契约。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 14) {
                        if LifeMedalsCloud.isEnabledForCurrentBuild {
                            SignInWithAppleButton(.continue) { request in
                                accountManager.prepare(request)
                            } onCompletion: { result in
                                if accountManager.complete(result) {
                                    onContinue()
                                }
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Label("本地开发模式", systemImage: "hammer.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .foregroundStyle(.primary)
                                .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 12))
                        }

                        HStack(spacing: 9) {
                            if syncMonitor.isCheckingAccount {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: syncMonitor.iconName)
                                    .foregroundStyle(syncStatusColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(syncStatusTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(syncStatusDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if LifeMedalsCloud.isEnabledForCurrentBuild {
                                Button("重试") {
                                    Task { await syncMonitor.refreshAccountStatus() }
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.medium))
                                .disabled(syncMonitor.isCheckingAccount)
                            }
                        }
                        .padding(13)
                        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                        Button("离线使用", action: onContinue)
                            .buttonStyle(.plain)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }

                    if let errorMessage = accountManager.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(loginFooter)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(34)
                .frame(maxWidth: 420)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
            .padding(.horizontal, 20)
        }
        .macOSMinimumWindowSize(width: 720, height: 560)
        .preferredColorScheme(.light)
        .task {
            await syncMonitor.refreshAccountStatus()
        }
    }

    private var syncStatusDetail: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild {
            return "Debug 数据只保存在本机；Release 保留完整云端配置。"
        }
        if syncMonitor.isCheckingAccount { return "正在检查设备上的 iCloud 账户…" }
        if syncMonitor.isAvailable { return "联网时会自动同步到使用同一 iCloud 的设备。" }
        return syncMonitor.errorMessage ?? "当前更改会先安全保存在本机。"
    }

    private var syncStatusTitle: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild { return "未启用 Apple 登录与 iCloud" }
        return syncMonitor.isAvailable ? "iCloud 同步已就绪" : "iCloud 同步暂不可用"
    }

    private var syncStatusColor: Color {
        if !LifeMedalsCloud.isEnabledForCurrentBuild { return .secondary }
        return syncMonitor.isAvailable ? .blue : .orange
    }

    private var loginFooter: String {
        LifeMedalsCloud.isEnabledForCurrentBuild
            ? "Apple 登录用于应用会话；你的任务与证据通过设备上的 iCloud 私有数据库同步。离线时仍可使用。"
            : "本地开发模式不需要 Apple 登录，任务、证据、勋章和 EXP 都只保存在这台设备。"
    }
}

#Preview {
    LoginView(onContinue: {})
        .environmentObject(AppleAccountManager())
        .environmentObject(CloudSyncMonitor())
}
