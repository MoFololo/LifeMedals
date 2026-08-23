import AuthenticationServices
import SwiftUI

struct AccountSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var accountManager: AppleAccountManager
    @EnvironmentObject private var syncMonitor: CloudSyncMonitor

    var onSignOut: () -> Void

    var body: some View {
        ZStack {
            PixelBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: PixelTheme.space24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PLAYER DATA")
                        .font(PixelTheme.statFont(size: 11))
                        .foregroundStyle(PixelTheme.goldBright)
                    Text("账户与同步")
                        .font(PixelTheme.displayFont(size: 26))
                        .foregroundStyle(PixelTheme.paperRaised)
                    Text(accountAndSyncSubtitle)
                        .foregroundStyle(PixelTheme.paper.opacity(0.72))
                }

                Spacer()

                Button("完成") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PixelTheme.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3, hasShadow: true)
            }

            VStack(spacing: 0) {
                statusRow(
                    icon: accountManager.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle",
                    title: "Apple 登录",
                    detail: appleAccountDetail,
                    color: accountManager.isSignedIn ? PixelTheme.success : PixelTheme.inkMuted
                )

                Divider().padding(.leading, 54)

                statusRow(
                    icon: syncMonitor.iconName,
                    title: "iCloud 同步",
                    detail: cloudDetail,
                    color: syncStatusColor
                )
            }
            .padding(.horizontal, 18)
            .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)

            if let message = syncMonitor.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(PixelTheme.goldBright)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = accountManager.errorMessage {
                Label(message, systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(PixelTheme.goldBright)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    primaryAccountAction
                    Spacer()
                    secondaryAccountAction
                }

                VStack(alignment: .leading, spacing: 16) {
                    primaryAccountAction
                    secondaryAccountAction
                }
            }

            Text(accountFooter)
                .font(.caption)
                .foregroundStyle(PixelTheme.paper.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(horizontalSizeClass == .compact ? 20 : 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .platformSheetWidth(510)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await syncMonitor.refreshAccountStatus()
        }
    }

    @ViewBuilder
    private var primaryAccountAction: some View {
                if LifeMedalsCloud.isEnabledForCurrentBuild {
                    Button {
                        Task { await syncMonitor.refreshAccountStatus() }
                    } label: {
                        Label("重新检查 iCloud", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(syncMonitor.isCheckingAccount)
                    .foregroundStyle(PixelTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3, hasShadow: true)
                } else {
                    Label("本机存储已启用", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PixelTheme.success)
                }
    }

    @ViewBuilder
    private var secondaryAccountAction: some View {
                if accountManager.isSignedIn {
                    Button("退出应用账户", role: .destructive) {
                        accountManager.signOut()
                        onSignOut()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PixelTheme.danger)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.danger, step: 3)
                } else if LifeMedalsCloud.isEnabledForCurrentBuild {
                    SignInWithAppleButton(.signIn) { request in
                        accountManager.prepare(request)
                    } onCompletion: { result in
                        accountManager.complete(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(width: 210, height: 40)
                    .clipShape(PixelCornerShape(step: 3))
                } else {
                    Text("Debug 仅本机")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PixelTheme.paper.opacity(0.72))
                }
    }

    private var appleAccountDetail: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild {
            return "本地开发模式未启用 Apple 登录"
        }
        if accountManager.isSignedIn {
            return accountManager.displayName.map { "已登录 · \($0)" } ?? "已登录"
        }
        return "未登录；本地功能仍可使用"
    }

    private var cloudDetail: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild {
            return "Debug 使用本机 SwiftData，不连接 CloudKit"
        }
        if syncMonitor.isCheckingAccount { return "正在检查账户状态…" }
        if syncMonitor.isSyncing { return "正在上传或下载更改…" }
        if let date = syncMonitor.lastSuccessfulSync {
            return "最近完成：\(date.formatted(date: .abbreviated, time: .shortened))"
        }
        if syncMonitor.isAvailable { return "已连接；更改会自动同步" }
        return "不可用；当前更改只保存在本机"
    }

    private var accountAndSyncSubtitle: String {
        LifeMedalsCloud.isEnabledForCurrentBuild
            ? "iCloud 可用时，数据会保存到你的私有数据库。"
            : "当前是无需付费开发者团队的本地 Debug 构建。"
    }

    private var syncStatusColor: Color {
        if !LifeMedalsCloud.isEnabledForCurrentBuild { return PixelTheme.inkMuted }
        return syncMonitor.isAvailable ? PixelTheme.selection : PixelTheme.gold
    }

    private var accountFooter: String {
        LifeMedalsCloud.isEnabledForCurrentBuild
            ? "Apple 登录用于识别你在 LifeMedals 中的会话；跨设备数据由这台设备登录的 iCloud 账户负责。退出应用账户不会删除本机或 iCloud 中的数据。"
            : "这个模式专供本机开发和调试。切换到带云端 entitlement 的构建后，才会启用 Apple 登录和 CloudKit。"
    }

    private func statusRow(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(PixelTheme.inkMuted)
            }

            Spacer()
        }
        .padding(.vertical, 16)
    }
}
