// 播放协调器：统一封装两种播放模式
//
//   .proxy  转发模式 —— 直接拿服务端 /api/stream 的 URL 给 AVPlayer
//   .direct 直连模式 —— /api/keys 拿密钥 -> EpisodeCache 整集下载+解密 -> LocalStreamServer 本地播
//
// 用法（在播放 ViewModel 里）：
//   let coordinator = HGPlaybackCoordinator(config: config)
//   let item = try await coordinator.prepare(vid: vid, progress: { p in ... })
//   player.replaceCurrentItem(with: item)   // item 是本地/远程 AVPlayerItem
//
// 两种模式返回的都是一个可给 AVPlayer 的 AVPlayerItem：
//   - 转发模式：AVPlayerItem(url: remoteStreamURL)
//   - 直连模式：AVPlayerItem(url: localHostURL)（本地解密文件，微秒级响应）
import Foundation
import AVFoundation

// MARK: - 播放协调器

final class HGPlaybackCoordinator {

    private let config: ResolverConfig
    private let client: HGServerClient
    private let cache = EpisodeCache()

    init(config: ResolverConfig) {
        self.config = config
        self.client = HGServerClient(config: config)
    }

    /// 准备一个可播放的 AVPlayerItem。
    /// - Parameters:
    ///   - vid: 单集 vid
    ///   - progress: 直连模式下会回调下载/解密进度；转发模式不回调（直接返回）
    /// - Returns: 可给 AVPlayer 的 AVPlayerItem
    func prepare(vid: String,
                 progress: @escaping @Sendable (EpisodeCache.Progress) -> Void = { _ in })
        async throws -> AVPlayerItem {

        switch config.mode {
        case .proxy:
            return try await prepareProxy(vid: vid)

        case .direct:
            return try await prepareDirect(vid: vid, progress: progress)
        }
    }

    // MARK: 转发模式

    private func prepareProxy(vid: String) async throws -> AVPlayerItem {
        // 直接给服务端解密流 URL。服务端支持 Range，AVPlayer 边下边播。
        let url = try client.streamURL(vid: vid)
        let asset = AVURLAsset(url: url)
        return AVPlayerItem(asset: asset)
    }

    // MARK: 直连模式

    private func prepareDirect(vid: String,
                               progress: @escaping @Sendable (EpisodeCache.Progress) -> Void)
        async throws -> AVPlayerItem {

        // 1) 拿密钥包（key + header + 每样本 IV + 空洞）
        let bundle = try await client.keys(vid: vid)
        guard bundle.ok else {
            throw HGServeError.decode("密钥包获取失败")
        }

        // 2) 整集下载 + 本地解密
        let localURL = try await cache.prepare(vid: vid, bundle: bundle, progress: progress)

        // 3) 启动本地 HTTP 服务，返回 localhost URL
        let server = LocalStreamServer()
        let port = try await server.start(fileURL: localURL)
        // 注意：LocalStreamServer 需要在播放期间保持存活。
        // 这里把 server 挂到全局持有（见 HGPlaybackSessionHolder），
        // 避免本地作用域释放导致 AVPlayer 拉不到数据。
        HGPlaybackSessionHolder.shared.attach(server)

        let url = URL(string: "http://127.0.0.1:\(port)/\(vid).mp4")!
        return AVPlayerItem(url: url)
    }
}

// MARK: - 本地服务会话持有

/// 持有当前直连播放的 LocalStreamServer，避免其被提前释放。
/// 切集或退出播放时调用 detach() 释放。
final class HGPlaybackSessionHolder: @unchecked Sendable {
    static let shared = HGPlaybackSessionHolder()

    private var server: LocalStreamServer?
    private let lock = NSLock()

    func attach(_ s: LocalStreamServer) {
        lock.lock(); defer { lock.unlock() }
        server?.stop()   // 释放上一个
        server = s
    }

    func detach() {
        lock.lock(); defer { lock.unlock() }
        server?.stop()
        server = nil
    }
}
