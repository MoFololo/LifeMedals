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

    @AppStorage("hasEnteredApp") private var hasEnteredApp = false
    @StateObject private var accountManager = AppleAccountManager()
    @StateObject private var syncMonitor = CloudSyncMonitor()
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            BadgeCategory.self,
            UserBadge.self,
            TaskContract.self,
            Evidence.self,
            XPLog.self
        ])
        let configuration: ModelConfiguration
#if LIFEMEDALS_LOCAL_DEVELOPMENT
        configuration = ModelConfiguration(cloudKitDatabase: .none)
#else
        configuration = ModelConfiguration(
            cloudKitDatabase: .private(LifeMedalsCloud.containerIdentifier)
        )
#endif

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
            Group {
                if hasEnteredApp {
                    ContentView {
                        withAnimation(.smooth(duration: 0.4)) {
                            hasEnteredApp = false
                        }
                    }
                        .transition(.opacity.combined(with: .scale(scale: 1.015)))
                } else {
                    LoginView {
                        withAnimation(.smooth(duration: 0.52)) {
                            hasEnteredApp = true
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .preferredColorScheme(.light)
            .animation(.smooth(duration: 0.52), value: hasEnteredApp)
            .environmentObject(accountManager)
            .environmentObject(syncMonitor)
            .task {
                async let validateAccount: Void = accountManager.validateStoredCredential()
                async let checkCloud: Void = syncMonitor.refreshAccountStatus()
                _ = await (validateAccount, checkCloud)
                if accountManager.isSignedIn {
                    hasEnteredApp = true
                }
            }
            .onChange(of: accountManager.requiresReauthentication) { _, requiresReauthentication in
                if requiresReauthentication {
                    hasEnteredApp = false
                }
            }
        }
        .modelContainer(modelContainer)
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
        }
        .defaultSize(width: 520, height: 600)
    }
#else
    private var mainWindow: some Scene {
        appWindowGroup
    }
#endif
}
