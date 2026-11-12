// 发现页：推荐 tab 为竖向全屏信息流（红果式），其余分类为瀑布流
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
                } else if store.tab == 201 {
                    // 推荐页：竖向全屏信息流
                    recommendFeed
                } else {
                    contentView
                }
            }
            .navigationTitle("红果短剧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SearchView().environmentObject(appState)
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

    // MARK: 推荐页 —— 竖向全屏信息流

    private var recommendFeed: some View {
        TabView {
            ForEach(store.items) { item in
                RecommendCard(item: item)
                    .tag(item.id)
                    .onAppear {
                        if item.id == store.items.last?.id {
                            Task { await store.loadMore(config: appState.config) }
                        }
                    }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .refreshable {
            await store.reload(config: appState.config)
        }
    }

    // MARK: 分类页 —— 瀑布流

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

    @ViewBuilder
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

// MARK: - 推荐页单屏卡片（全屏封面 + 信息 + 选集入口）

struct RecommendCard: View {
    @EnvironmentObject private var appState: AppState
    let item: HGFeedItem

    var body: some View {
        NavigationLink {
            DetailView(seriesID: item.seriesID, title: item.title ?? "")
                .environmentObject(appState)
        } label: {
            ZStack(alignment: .bottom) {
                // 全屏封面
                RemoteCover(urlString: item.cover)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .clear, .black.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 底部信息区
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title ?? "未知剧名")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        if !item.episodeTextResolved.isEmpty {
                            Text(item.episodeTextResolved)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        if !item.playText.isEmpty {
                            Text(item.playText)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }

                    if let intro = item.intro, !intro.isEmpty {
                        Text(intro)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(2)
                    }

                    // 选集/观看按钮
                    HStack(spacing: 12) {
                        Label("选集观看", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .clipShape(Capsule())

                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 瀑布流卡片

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
