//
//  ContentView.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/29.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "medal.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("欢迎回来！")
                .font(.title2.bold())
            Button("退出登录") {
                Task { await authViewModel.signOut() }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
    }
}

#Preview {
    ContentView(authViewModel: AuthViewModel())
}
