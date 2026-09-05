import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CloudSyncMonitor.self) private var syncMonitor

    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.simplifiedChinese.rawValue
    var body: some View {
        ZStack {
            PixelBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: PixelTheme.space24) {
                    header

                    settingsSection(title: "通用") {
                        VStack(alignment: .leading, spacing: PixelTheme.space12) {
                            Label("语言", systemImage: "globe")
                                .font(PixelTheme.font(.headline))
                                .foregroundStyle(PixelTheme.ink)

                            HStack(spacing: PixelTheme.space8) {
                                ForEach(AppLanguage.allCases) { language in
                                    languageButton(language)
                                }
                            }

                            Text("更改后会立即应用到界面，并在下次启动时保留。")
                                .font(PixelTheme.font(.caption))
                                .foregroundStyle(PixelTheme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsSection(title: "同步") {
                        HStack(spacing: PixelTheme.space12) {
                            PixelSymbolTile(
                                systemImage: syncMonitor.iconName,
                                tint: syncMonitor.errorMessage == nil
                                    ? (syncMonitor.isAvailable ? PixelTheme.success : PixelTheme.selection)
                                    : PixelTheme.danger,
                                size: 42
                            )

                            VStack(alignment: .leading, spacing: PixelTheme.space4) {
                                Text("iCloud 同步")
                                    .font(PixelTheme.font(.headline))
                                    .foregroundStyle(PixelTheme.ink)
                                Text(syncDetail)
                                    .font(PixelTheme.font(.caption))
                                    .foregroundStyle(syncMonitor.errorMessage == nil ? PixelTheme.inkMuted : PixelTheme.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: PixelTheme.space8)
                        }
                    }
                }
                .padding(horizontalSizeClass == .compact ? 20 : 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .platformSheetWidth(540)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SETTINGS")
                    .font(PixelTheme.statFont(size: 11))
                    .foregroundStyle(PixelTheme.goldBright)
                Text("设置")
                    .font(PixelTheme.displayFont(size: 28))
                    .foregroundStyle(PixelTheme.paperRaised)
                Text("管理语言与 iCloud 同步状态。")
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

    private func settingsSection<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PixelTheme.space8) {
            Text(title)
                .font(PixelTheme.statFont(size: 11))
                .foregroundStyle(PixelTheme.goldBright)

            content()
                .padding(PixelTheme.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)
        }
    }

    private func languageButton(_ language: AppLanguage) -> some View {
        let isSelected = selectedLanguage == language.rawValue

        return Button {
            selectedLanguage = language.rawValue
        } label: {
            HStack(spacing: PixelTheme.space8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.white : PixelTheme.inkMuted)
                Text(language.nativeName)
                    .lineLimit(1)
            }
            .font(PixelTheme.font(.subheadline, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? Color.white : PixelTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PixelTheme.space12)
            .padding(.vertical, PixelTheme.space12)
            .background(isSelected ? PixelTheme.selection : PixelTheme.paperRaised, in: PixelCornerShape(step: 3))
            .overlay {
                PixelCornerShape(step: 3)
                    .stroke(isSelected ? PixelTheme.selectionBright : PixelTheme.gold, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var syncDetail: String {
        guard LifeMedalsCloud.isEnabledForCurrentBuild else {
            return L10n.text("本地开发模式", english: "Local development mode")
        }
        if let errorMessage = syncMonitor.errorMessage {
            return errorMessage
        }
        if syncMonitor.isCheckingAccount {
            return L10n.text("检查 iCloud", english: "Checking iCloud")
        }
        if syncMonitor.isSyncing {
            return L10n.text("正在同步", english: "Syncing")
        }
        if syncMonitor.isAvailable, let date = syncMonitor.lastSuccessfulSync {
            let formattedDate = L10n.date(date, dateStyle: .medium, timeStyle: .short)
            return L10n.text(
                "iCloud 已同步 · \(formattedDate)",
                english: "iCloud Synced · \(formattedDate)"
            )
        }
        return syncMonitor.shortTitle
    }
}
