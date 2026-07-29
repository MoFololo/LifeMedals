//
//  SupabaseManager.swift
//  LifeMedals
//
//  Created by David Da Lian on 2026/7/29.
//

import Foundation
import Supabase

/// 全局唯一的 Supabase 客户端入口。
enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: Secrets.supabaseURL,
        supabaseKey: Secrets.supabaseAnonKey
    )
}
