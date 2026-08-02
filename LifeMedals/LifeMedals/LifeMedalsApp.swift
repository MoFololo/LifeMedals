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
#if DEBUG
    @Environment(\.openWindow) private var openWindow
#endif

    /// v1 登录页只是可跳过的占位 UI，不代表真实登录态；不做持久化，
    /// 也不参与任何功能权限判断。
    @State private var hasEnteredApp = false

    var body: some Scene {
        mainWindow
#if DEBUG
        medalAnimationLabWindow
#endif
    }

    private var appWindowGroup: some Scene {
        WindowGroup {
            Group {
                if hasEnteredApp {
                    ContentView()
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
        }
        .modelContainer(for: [
            BadgeCategory.self,
            UserBadge.self,
            TaskContract.self,
            Evidence.self,
            XPLog.self
        ])
    }

#if DEBUG
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
