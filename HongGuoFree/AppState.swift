// 全局应用状态：解析服务配置的持久化 + 播放模式切换
import Foundation
import SwiftUI

/// 全局状态。持有 `ResolverConfig`，负责读写到 UserDefaults。
@MainActor
final class AppState: ObservableObject {
    @Published var config: ResolverConfig {
        didSet { persist() }
    }

    private static let configKey = "hongguo.resolver.config"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(ResolverConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }

    /// 播放模式（快捷读写，绑定到 Picker 用）
    var mode: HGPlaybackMode {
        get { config.mode }
        set { config.mode = newValue }
    }

    /// 是否已配置好可用的服务地址
    var isConfigured: Bool { config.isConfigured }
}
