//
//  LoginView.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/29.
//

import SwiftUI

/// 登录 / 注册页面，使用 macOS 26 Liquid Glass 风格。
struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel

    private enum Mode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password, confirmPassword
    }

    private var isFormValid: Bool {
        guard email.contains("@"), password.count >= 6 else { return false }
        if mode == .register { return password == confirmPassword }
        return true
    }

    var body: some View {
        ZStack {
            backgroundView

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 22) {
                    titleSection
                    modeSwitcher
                    fieldsSection
                    if let message = authViewModel.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    submitButton
                }
                .padding(32)
                .frame(width: 380)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.2), value: authViewModel.errorMessage)
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
            Text(mode == .login ? "登录以继续你的任务契约" : "创建账号，开始记录你的成长")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { item in
                Text(item.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(mode == item ? Color.primary : Color.secondary)
                    .background {
                        if mode == item {
                            Capsule()
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard mode != item else { return }
                        mode = item
                        authViewModel.errorMessage = nil
                    }
            }
        }
        .padding(4)
        .glassEffect(.clear, in: Capsule())
    }

    private var fieldsSection: some View {
        VStack(spacing: 14) {
            glassField(
                placeholder: "邮箱",
                text: $email,
                systemImage: "envelope"
            )
            .focused($focusedField, equals: .email)

            glassSecureField(
                placeholder: "密码（至少 6 位）",
                text: $password,
                systemImage: "lock"
            )
            .focused($focusedField, equals: .password)

            if mode == .register {
                glassSecureField(
                    placeholder: "确认密码",
                    text: $confirmPassword,
                    systemImage: "lock.rotation"
                )
                .focused($focusedField, equals: .confirmPassword)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func glassField(placeholder: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func glassSecureField(placeholder: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if authViewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(mode == .login ? "登录" : "创建账号")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(.accentColor).interactive(),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .disabled(!isFormValid || authViewModel.isLoading)
        .opacity(isFormValid ? 1 : 0.5)
    }

    // MARK: - Actions

    private func submit() async {
        focusedField = nil
        switch mode {
        case .login:
            await authViewModel.signIn(email: email, password: password)
        case .register:
            await authViewModel.signUp(email: email, password: password)
        }
    }
}

#Preview {
    LoginView(authViewModel: AuthViewModel())
}
