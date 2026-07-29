//
//  Secrets.swift
//  LifeMedals
//
//  本文件不提交到 git（见 .gitignore）。
//  请在 Supabase Dashboard → Project Settings → API 中找到 Project URL 和 anon/public key，
//  填入下面两个常量。参考模板见 Secrets.example.txt。
//

import Foundation

enum Secrets {
    /// Supabase Project URL，例如 https://xxxxx.supabase.co
    static let supabaseURL = URL(string: "https://hepiycfngqtkwdzqijwq.supabase.co")!

    /// Supabase anon/public key（客户端可见，受 RLS 保护，不是 service_role key）
    static let supabaseAnonKey = "sb_publishable_rGi4rjkJsqWPmqckHa0WsQ_YDU3gEpH"
}
