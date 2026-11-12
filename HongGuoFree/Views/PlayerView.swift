// 播放器页：全屏沉浸式，上下滑动切换集数（红果/抖音式交互）
//
// - 全屏铺满，无黑边（HGPlayerView + resizeAspectFill）
// - 开启音频会话（解决没声音）
// - 竖向 TabView 翻页：上滑下一集、下滑上一集
// - 顶部返回 + 剧名/集数，右侧选集面板
import SwiftUI
import AVFoundation

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// 分集清单（从详情页带入）
    let episodes: [HGServerEpisode]
    /// 初始播放的集索引（在 episodes 里的下标）
    let initialIndex: Int
    /// 剧名
    let title: String

    /// 当前集下标
    @State private var currentIndex: Int

    /// 每集的播放器实例（懒加载缓存，翻回上一集可续播）
    @State private var players: [Int: AVPlayer] = [:]
    /// 每集的加载/错误状态
    @State private var states: [Int: EpisodeState] = [:]
    /// 是否显示选集面板
    @State private var showEpisodeSheet = false
    /// 是否显示顶部/底部 UI（点击画面切换）
    @State private var showControls = true

    init(episodes: [HGServerEpisode], initialIndex: Int, title: String) {
        self.episodes = episodes
        self.initialIndex = initialIndex
        self.title = title
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var currentEpisode: HGServerEpisode? {
        guard episodes.indices.contains(currentIndex) else { return nil }
        return episodes[currentIndex]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // 竖向翻页：一页一集
                TabView(selection: $currentIndex) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                        episodePage(idx, ep)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                // 顶部：返回 + 标题 + 集数
                if showControls {
                    VStack {
                        topBar
                        Spacer()
                        bottomBar
                    }
                    .transition(.opacity)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        .onAppear {
            HGAudioSession.activate()
            playCurrent()
        }
        .onChange(of: currentIndex) { idx in
            playCurrent()
        }
        .onDisappear {
            pauseAll()
            HGAudioSession.deactivate()
            HGPlaybackSessionHolder.shared.detach()
        }
        .sheet(isPresented: $showEpisodeSheet) {
            episodeSheet
        }
    }

    // MARK: 单集页面

    @ViewBuilder
    private func episodePage(_ idx: Int, _ ep: HGServerEpisode) -> some View {
        ZStack {
            Color.black

            if let player = players[idx] {
                HGPlayerView(player: player)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                    }
            } else if let st = states[idx], st.isError {
                errorView(st)
            } else {
                loadingView(idx)
            }
        }
    }

    @ViewBuilder
    private func loadingView(_ idx: Int) -> some View {
        VStack(spacing: 14) {
            ProgressView().tint(.white)
            if let st = states[idx], !st.text.isEmpty {
                Text(st.text)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func errorView(_ st: EpisodeState) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.8))
            Text(st.text.isEmpty ? "播放失败" : st.text)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("重试") {
                Task { await load(index: currentIndex) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: 顶部栏

    private var topBar: some View {
        HStack {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let ep = currentEpisode {
                    Text("第 \(ep.index) 集")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Spacer()

            Button {
                showEpisodeSheet = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 24) {
            // 上一集
            Button {
                goPrevious()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 20, weight: .semibold))
                    Text("上一集")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(currentIndex > 0 ? 0.95 : 0.3))
            }
            .disabled(currentIndex <= 0)

            // 播放/暂停
            Button {
                togglePlay()
            } label: {
                Image(systemName: (players[currentIndex]?.timeControlStatus == .playing) ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }

            // 下一集
            Button {
                goNext()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                    Text("下一集")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(currentIndex < episodes.count - 1 ? 0.95 : 0.3))
            }
            .disabled(currentIndex >= episodes.count - 1)
        }
        .padding(.bottom, 32)
    }

    // MARK: 选集面板

    private var episodeSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                          spacing: 10) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                        Button {
                            jump(to: idx)
                            showEpisodeSheet = false
                        } label: {
                            Text("\(ep.index)")
                                .font(.subheadline.weight(idx == currentIndex ? .bold : .regular))
                                .foregroundColor(idx == currentIndex ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(idx == currentIndex ? Color.red : Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { showEpisodeSheet = false }
                }
            }
        }
    }

    // MARK: 播放控制

    private func playCurrent() {
        guard let idx = episodes.indices.contains(currentIndex) ? currentIndex : nil else { return }
        if players[idx] == nil {
            Task { await load(index: idx) }
        } else {
            players[idx]?.play()
        }
    }

    private func load(index: Int) async {
        guard episodes.indices.contains(index) else { return }
        let ep = episodes[index]
        states[index] = EpisodeState(isLoading: true, text: "")

        do {
            let coordinator = HGPlaybackCoordinator(config: appState.config)
            let item = try await coordinator.prepare(vid: ep.vid) { p in
                Task { @MainActor in
                    let pct = Int(p.fraction * 100)
                    states[index] = EpisodeState(isLoading: true, text: "\(p.phase)… \(pct)%")
                }
            }
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .pause
            players[index] = player
            states[index] = EpisodeState(isLoading: false, text: "")
            // 只有当前页才自动播
            if index == currentIndex {
                player.play()
            }
        } catch {
            states[index] = EpisodeState(isLoading: false, text: error.localizedDescription, isError: true)
        }
    }

    private func goNext() {
        guard currentIndex < episodes.count - 1 else { return }
        withAnimation { currentIndex += 1 }
    }

    private func goPrevious() {
        guard currentIndex > 0 else { return }
        withAnimation { currentIndex -= 1 }
    }

    private func jump(to idx: Int) {
        guard episodes.indices.contains(idx) else { return }
        withAnimation { currentIndex = idx }
    }

    private func togglePlay() {
        guard let p = players[currentIndex] else { return }
        if p.timeControlStatus == .playing { p.pause() } else { p.play() }
    }

    private func pauseAll() {
        for p in players.values { p.pause() }
    }

    private func goBack() {
        pauseAll()
        HGAudioSession.deactivate()
        HGPlaybackSessionHolder.shared.detach()
        dismiss()
    }
}

/// 单集加载状态
struct EpisodeState {
    var isLoading: Bool = false
    var text: String = ""
    var isError: Bool = false
}
