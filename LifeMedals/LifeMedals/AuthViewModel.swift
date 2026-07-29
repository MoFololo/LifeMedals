//
//  AuthViewModel.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/29.
//

import Combine
import Foundation
import Supabase

/// 管理 Supabase Auth 会话状态，供 SwiftUI 视图观察。
@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var session: Session?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isAuthenticated: Bool { session != nil }

    private var authStateTask: Task<Void, Never>?

    init() {
        observeAuthChanges()
    }

    deinit {
        authStateTask?.cancel()
    }

    private func observeAuthChanges() {
        authStateTask = Task { [weak self] in
            for await (_, session) in await SupabaseManager.client.auth.authStateChanges {
                self?.session = session
            }
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await SupabaseManager.client.auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await SupabaseManager.client.auth.signUp(email: email, password: password)
            if response.session == nil {
                errorMessage = "注册成功！请检查邮箱完成验证后再登录。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await SupabaseManager.client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
