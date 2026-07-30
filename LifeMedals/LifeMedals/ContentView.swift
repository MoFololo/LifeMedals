//
//  ContentView.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/29.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var badgeCategories: [BadgeCategory]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "medal.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("欢迎回来！")
                .font(.title2.bold())
            Text("勋章类别：\(badgeCategories.count)")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            BadgeCategory.self,
            UserBadge.self,
            TaskContract.self,
            Evidence.self,
            XPLog.self
        ], inMemory: true)
}
