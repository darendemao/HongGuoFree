// 发现页：短剧瀑布流 + 搜索 + tab 分类
import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = HGFeedStore()

    // 内置分类 tab（与服务端 /api/discover 的 tab 参数对齐）
    private let tabs: [(id: Int, name: String)] = [
        (201, "推荐"),
        (202, "古装"),
        (203, "甜宠"),
        (204, "战神"),
        (205, "逆袭"),
        (206, "都市"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isConfigured {
                    notConfiguredView
                } else {
                    contentView
                }
            }
            .navigationTitle("红果短剧")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SearchView()
                            .environmentObject(appState)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
        .task {
            await store.reload(config: appState.config)
        }
        .onChange(of: appState.config) { newConfig in
            Task { await store.reload(config: newConfig) }
        }
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                tabBar
                grid
            }
        }
        .refreshable {
            await store.reload(config: appState.config)
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(tabs, id: \.id) { tab in
                    Button {
                        Task { await store.selectTab(tab.id) }
                    } label: {
                        Text(tab.name)
                            .font(.subheadline.weight(store.tab == tab.id ? .bold : .regular))
                            .foregroundColor(store.tab == tab.id ? .primary : .secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 16) {
            ForEach(store.items) { item in
                NavigationLink {
                    DetailView(seriesID: item.seriesID, title: item.title ?? "")
                        .environmentObject(appState)
                } label: {
                    FeedCard(item: item)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if item.id == store.items.last?.id {
                        Task { await store.loadMore(config: appState.config) }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)

        if store.isLoading {
            ProgressView().padding()
        }
        if let err = store.errorText, !err.isEmpty {
            Text(err)
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding()
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("还没配置解析服务")
                .font(.headline)
            Text("请到「设置」页填写解析服务的局域网地址。\n手机和电脑需连同一个 WiFi。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - 卡片

struct FeedCard: View {
    let item: HGFeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteCover(urlString: item.cover)
                .aspectRatio(3 / 4, contentMode: .fit)

            Text(item.title ?? "未知剧名")
                .font(.footnote.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 4) {
                Text(item.episodeTextResolved)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !item.playText.isEmpty {
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.playText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
