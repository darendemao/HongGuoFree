// 根视图：Tab 结构（发现 / 设置）
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem {
                    Label("发现", systemImage: "play.rectangle.on.rectangle")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}
