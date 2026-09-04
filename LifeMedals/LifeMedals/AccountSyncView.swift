import SwiftUI

struct AccountSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Environment(CloudSyncMonitor.self) private var syncMonitor

    var body: some View {
        let _ = locale.identifier
        ZStack {
            PixelBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: PixelTheme.space24) {
                    header

                    statusRow(
                        icon: syncMonitor.iconName,
                        title: "iCloud 私有同步",
                        detail: cloudDetail,
                        color: syncStatusColor
                    )
                    .padding(.horizontal, 18)
                    .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)

                    if let message = syncMonitor.errorMessage {
                        Label {
                            Text(L10n.text(message))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(PixelTheme.font(.subheadline))
                        .foregroundStyle(PixelTheme.goldBright)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    syncAction

                    Text(accountFooter)
                        .font(PixelTheme.font(.caption))
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
        .task { await syncMonitor.refreshAccountStatus() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PLAYER DATA")
                    .font(PixelTheme.statFont(size: 11))
                    .foregroundStyle(PixelTheme.goldBright)
                Text("iCloud 同步")
                    .font(PixelTheme.displayFont(size: 26))
                    .foregroundStyle(PixelTheme.paperRaised)
                Text(accountAndSyncSubtitle)
                    .foregroundStyle(PixelTheme.paper.opacity(0.72))
            }

            Spacer()

            Button("完成") { dismiss() }
                .buttonStyle(.plain)
                .font(PixelTheme.font(.subheadline, weight: .bold))
                .foregroundStyle(PixelTheme.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 3, hasShadow: true)
        }
    }

    @ViewBuilder
    private var syncAction: some View {
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
                .font(PixelTheme.font(.subheadline, weight: .medium))
                .foregroundStyle(PixelTheme.success)
        }
    }

    private var cloudDetail: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild {
            return L10n.text(
                "Debug 使用本机 SwiftData，不连接 CloudKit",
                english: "Debug uses on-device SwiftData without CloudKit"
            )
        }
        if syncMonitor.isCheckingAccount {
            return L10n.text("正在检查 iCloud 账户状态…", english: "Checking iCloud account status…")
        }
        if syncMonitor.isSyncing {
            return L10n.text("正在上传或下载更改…", english: "Uploading or downloading changes…")
        }
        if let date = syncMonitor.lastSuccessfulExport {
            let formattedDate = L10n.date(date, dateStyle: .medium, timeStyle: .short)
            return L10n.text("最近上传完成：\(formattedDate)", english: "Last upload completed: \(formattedDate)")
        }
        if let date = syncMonitor.lastSuccessfulImport {
            let formattedDate = L10n.date(date, dateStyle: .medium, timeStyle: .short)
            return L10n.text("最近下载完成：\(formattedDate)", english: "Last download completed: \(formattedDate)")
        }
        if syncMonitor.isAvailable {
            return L10n.text(
                "iCloud 账户可用，正在等待首次同步完成；看到“最近上传完成”后再删除应用。",
                english: "The iCloud account is available and waiting for the first sync. Do not delete the app until Last upload completed appears."
            )
        }
        return L10n.text(
            "不可用；当前更改只保存在本机",
            english: "Unavailable; current changes are stored on this device"
        )
    }

    private var accountAndSyncSubtitle: String {
        if LifeMedalsCloud.isEnabledForCurrentBuild {
            return L10n.text(
                "使用系统设置中登录的 iCloud 私有数据库。",
                english: "Uses the private database of the iCloud account in System Settings."
            )
        }
        return L10n.text(
            "当前是无需云端 entitlement 的本地 Debug 构建。",
            english: "This is a local Debug build without cloud entitlements."
        )
    }

    private var syncStatusColor: Color {
        if !LifeMedalsCloud.isEnabledForCurrentBuild { return PixelTheme.inkMuted }
        return syncMonitor.isAvailable ? PixelTheme.selection : PixelTheme.gold
    }

    private var accountFooter: String {
        if LifeMedalsCloud.isEnabledForCurrentBuild {
            return L10n.text(
                "任务、勋章进度和怪物收集会同步到使用同一 iCloud 账户的设备。任务来源图和证据图仅保存在创建它们的设备；怪物图片会按需重新下载。",
                english: "Tasks, medal progress, and monster discoveries sync to devices using the same iCloud account. Source and evidence images stay only on the device that created them; monster artwork downloads again when needed."
            )
        }
        return L10n.text(
            "本地开发模式下，所有业务数据与图片都只保存在这台设备。",
            english: "In local development mode, all app data and images stay on this device."
        )
    }

    private func statusRow(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(PixelTheme.font(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(PixelTheme.font(.headline))
                Text(L10n.text(detail))
                    .font(PixelTheme.font(.subheadline))
                    .foregroundStyle(PixelTheme.inkMuted)
            }

            Spacer()
        }
        .padding(.vertical, 16)
    }
}
