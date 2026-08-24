import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var accountManager: AppleAccountManager
    @EnvironmentObject private var syncMonitor: CloudSyncMonitor

    var onContinue: () -> Void

    var body: some View {
        ZStack {
            PixelBackground()

            PixelPanel(fill: PixelTheme.paper, padding: 0) {
                VStack(spacing: PixelTheme.space24) {
                    VStack(spacing: 12) {
                        Image("LifeMedalsLogo")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .padding(9)
                            .frame(width: 72, height: 72)
                            .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 4, hasShadow: true)
                            .accessibilityLabel("人生勋章")

                        VStack(spacing: 7) {
                            Text("人生勋章")
                                .font(PixelTheme.displayFont(size: 32))
                                .foregroundStyle(PixelTheme.ink)
                            Text("把想做的事，变成一份值得完成的契约。")
                                .font(PixelTheme.font(.subheadline))
                                .foregroundStyle(PixelTheme.inkMuted)
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
                            .clipShape(PixelCornerShape(step: 3))
                        } else {
                            Label("本地开发模式", systemImage: "hammer.fill")
                                .font(PixelTheme.font(.headline))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .foregroundStyle(PixelTheme.ink)
                                .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3)
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
                                    .font(PixelTheme.font(.subheadline, weight: .semibold))
                                Text(syncStatusDetail)
                                    .font(PixelTheme.font(.caption))
                                    .foregroundStyle(PixelTheme.inkMuted)
                            }

                            Spacer()

                            if LifeMedalsCloud.isEnabledForCurrentBuild {
                                Button("重试") {
                                    Task { await syncMonitor.refreshAccountStatus() }
                                }
                                .buttonStyle(.plain)
                                .font(PixelTheme.font(.caption, weight: .medium))
                                .disabled(syncMonitor.isCheckingAccount)
                            }
                        }
                        .padding(13)
                        .pixelSurface(fill: PixelTheme.paperRaised, border: syncStatusColor.opacity(0.72), step: 3)

                        Button("离线使用", action: onContinue)
                            .buttonStyle(.plain)
                            .font(PixelTheme.font(.subheadline))
                            .foregroundStyle(PixelTheme.inkMuted)
                            .padding(.vertical, 6)
                    }

                    if let errorMessage = accountManager.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(PixelTheme.font(.caption))
                            .foregroundStyle(PixelTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(loginFooter)
                        .font(PixelTheme.font(.caption))
                        .foregroundStyle(PixelTheme.inkMuted.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(34)
                .frame(maxWidth: 420)
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
            return L10n.text(
                "Debug 数据只保存在本机；Release 保留完整云端配置。",
                english: "Debug data stays on this device; Release keeps the full cloud configuration."
            )
        }
        if syncMonitor.isCheckingAccount {
            return L10n.text("正在检查设备上的 iCloud 账户…", english: "Checking the iCloud account on this device…")
        }
        if syncMonitor.isAvailable {
            return L10n.text(
                "联网时会自动同步到使用同一 iCloud 的设备。",
                english: "When online, changes sync automatically to devices using the same iCloud account."
            )
        }
        return syncMonitor.errorMessage ?? L10n.text(
            "当前更改会先安全保存在本机。",
            english: "Changes are safely stored on this device first."
        )
    }

    private var syncStatusTitle: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild {
            return L10n.text(
                "未启用 Apple 登录与 iCloud",
                english: "Sign in with Apple and iCloud are disabled"
            )
        }
        return syncMonitor.isAvailable
            ? L10n.text("iCloud 同步已就绪", english: "iCloud Sync Ready")
            : L10n.text("iCloud 同步暂不可用", english: "iCloud Sync Unavailable")
    }

    private var syncStatusColor: Color {
        if !LifeMedalsCloud.isEnabledForCurrentBuild { return PixelTheme.inkMuted }
        return syncMonitor.isAvailable ? PixelTheme.selection : PixelTheme.gold
    }

    private var loginFooter: String {
        if LifeMedalsCloud.isEnabledForCurrentBuild {
            return L10n.text(
                "Apple 登录用于应用会话；你的任务与证据通过设备上的 iCloud 私有数据库同步。离线时仍可使用。",
                english: "Apple sign-in identifies your app session. Tasks and evidence sync through your private iCloud database, and remain available offline."
            )
        }
        return L10n.text(
            "本地开发模式不需要 Apple 登录，任务、证据、勋章和 EXP 都只保存在这台设备。",
            english: "Local development mode does not require Apple sign-in. Tasks, evidence, medals, and XP stay on this device."
        )
    }
}

#Preview {
    LoginView(onContinue: {})
        .environmentObject(AppleAccountManager())
        .environmentObject(CloudSyncMonitor())
}
