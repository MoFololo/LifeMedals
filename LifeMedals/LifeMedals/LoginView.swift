//
//  LoginView.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/29.
//

import SwiftUI

/// v1 登录占位页：只用来预留品牌、布局和未来账户入口的视觉位置。
///
/// - Important: 这里不接 Sign in with Apple，不创建真实账户，不保存任何凭据，
///   也不参与任何权限判断。"登录" 和 "跳过" 在 v1 中效果完全相同——两者都直接
///   进入本地主界面，不影响 SwiftData 或 AI 功能。真实账户与会员体系推迟到 v2。
struct LoginView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            backgroundView

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 22) {
                    titleSection
                    placeholderSignInButton
                    skipButton
                }
                .padding(32)
                .frame(width: 380)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.16),
                    Color(red: 0.10, green: 0.06, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.purple.opacity(0.55))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -220, y: -200)
            Circle()
                .fill(Color.blue.opacity(0.5))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 240, y: 200)
            Circle()
                .fill(Color.pink.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 130)
                .offset(x: 220, y: -220)
        }
        .ignoresSafeArea()
    }

    // MARK: - Sections

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text("🏅")
                .font(.system(size: 44))
            Text("人生勋章")
                .font(.title.bold())
            Text("账户与会员功能将在后续版本开放，本版本可直接跳过")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var placeholderSignInButton: some View {
        Button(action: onContinue) {
            HStack {
                Image(systemName: "applelogo")
                Text("使用 Apple 登录（即将推出）")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var skipButton: some View {
        Button("跳过，直接使用", action: onContinue)
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    LoginView(onContinue: {})
}
