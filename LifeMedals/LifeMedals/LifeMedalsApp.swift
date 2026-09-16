//
//  LifeMedalsApp.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/29.
//

import SwiftUI
import SwiftData

@main
struct LifeMedalsApp: App {
#if DEBUG && os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.simplifiedChinese.rawValue
    @State private var syncMonitor = CloudSyncMonitor()
    private let modelContainer: ModelContainer

    init() {
        PixelTheme.prepareFonts()

        let schema = Schema([
            BadgeCategory.self,
            UserBadge.self,
            TaskContract.self,
            MonsterDiscovery.self,
            Evidence.self,
            XPLog.self
        ])
        let configuration: ModelConfiguration
        if LifeMedalsCloud.isEnabledForCurrentBuild {
            configuration = ModelConfiguration(
                cloudKitDatabase: .private(LifeMedalsCloud.containerIdentifier)
            )
        } else {
            configuration = ModelConfiguration(cloudKitDatabase: .none)
        }

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法载入 LifeMedals 数据库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        mainWindow
#if DEBUG && os(macOS)
        medalAnimationLabWindow
#endif
    }

    private var appWindowGroup: some Scene {
        WindowGroup {
            ContentView()
            .font(PixelTheme.font())
            .environment(\.locale, resolvedLanguage.locale)
            .preferredColorScheme(.light)
            .environment(syncMonitor)
            .task {
                LocalImageMigration.migrateLegacyCloudImages(in: modelContainer.mainContext)
                await syncMonitor.refreshAccountStatus()
            }
            .onChange(of: syncMonitor.lastSuccessfulSync) { _, _ in
                LocalImageMigration.migrateLegacyCloudImages(in: modelContainer.mainContext)
            }
        }
        .modelContainer(modelContainer)
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .simplifiedChinese
    }

#if DEBUG && os(macOS)
    private var mainWindow: some Scene {
        appWindowGroup.commands {
            CommandMenu("调试") {
                Button("打开勋章揭露实验") {
                    openWindow(id: "medal-animation-lab")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }

    private var medalAnimationLabWindow: some Scene {
        Window("勋章揭露实验", id: "medal-animation-lab") {
            MedalAnimationLab()
                .font(PixelTheme.font())
        }
        .defaultSize(width: 520, height: 600)
    }
#else
    private var mainWindow: some Scene {
        appWindowGroup
    }
#endif
}
