// 红果短剧 - App 入口
//
// 一个自建解析服务的 iOS 客户端，支持两种播放模式：
//   .proxy  转发模式 —— 视频流量走服务器解密后转发
//   .direct 直连模式 —— App 直连红果 CDN + 本地 CENC 解密
import SwiftUI

@main
@MainActor
struct HongGuoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
