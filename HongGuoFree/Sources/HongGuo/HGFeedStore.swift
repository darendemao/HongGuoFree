// 真实数据源：从自建解析服务拉短剧库
//
// 替代原来的 sample-feed.json 演示数据。
// 数据全部来自红果真实剧库（App 端 multi_video_model + album_detail）。
import Foundation

// MARK: - 模型

struct HGFeedItem: Identifiable, Decodable {
    var seriesID: String
    var itemID: String?
    var title: String?
    var cover: String?
    var intro: String?
    var tags: [String]?
    var episodeText: String?
    var episodeCount: Int?
    var freeEpisodes: Int?
    var playCount: Int?
    var followedCount: Int?

    var id: String { seriesID }

    init(seriesID: String, itemID: String? = nil, title: String? = nil,
         cover: String? = nil, intro: String? = nil, tags: [String]? = nil,
         episodeText: String? = nil, episodeCount: Int? = nil,
         freeEpisodes: Int? = nil, playCount: Int? = nil,
         followedCount: Int? = nil) {
        self.seriesID = seriesID
        self.itemID = itemID
        self.title = title
        self.cover = cover
        self.intro = intro
        self.tags = tags
        self.episodeText = episodeText
        self.episodeCount = episodeCount
        self.freeEpisodes = freeEpisodes
        self.playCount = playCount
        self.followedCount = followedCount
    }

    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case itemID = "item_id"
        case title, cover, intro, tags
        case episodeText = "episode_text"
        case episodeCount = "episode_count"
        case freeEpisodes = "free_episodes"
        case playCount = "play_count"
        case followedCount = "followed_count"
    }

    /// "8.5M 次播放" / "1234 次播放"
    var playText: String {
        let n = playCount ?? 0
        guard n > 0 else { return "" }
        if n >= 100_000_000 { return String(format: "%.1f亿播放", Double(n) / 100_000_000) }
        if n >= 10_000 { return String(format: "%.1f万播放", Double(n) / 10_000) }
        return "\(n) 次播放"
    }

    /// "全 62 集"
    var episodeTextResolved: String {
        if let c = episodeCount, c > 0 { return "全 \(c) 集" }
        return episodeText ?? ""
    }
}

struct HGDiscoverResponse: Decodable {
    var ok: Bool
    var tab: Int?
    var offset: Int?
    var count: Int?
    var hasMore: Bool?
    var nextOffset: Int?
    var items: [HGFeedItem]?

    enum CodingKeys: String, CodingKey {
        case ok, tab, offset, count, items
        case hasMore = "has_more"
        case nextOffset = "next_offset"
    }
}

// MARK: - 客户端扩展

extension HGServerClient {
    /// 红果鉴服务 /rank 榜单返回结构
    private struct HGRankItemRaw: Decodable {
        var rank: Int?
        var seriesID: String?
        var title: String?
        var episodeCnt: Int?
        var score: String?
        var playCnt: Int?
        var cover: String?
        var intro: String?

        enum CodingKeys: String, CodingKey {
            case rank, title, score, cover, intro
            case seriesID = "series_id"
            case episodeCnt = "episode_cnt"
            case playCnt = "play_cnt"
        }
    }

    private struct HGRankResponse: Decodable {
        var board: String?
        var name: String?
        var items: [HGRankItemRaw]?
    }

    /// 发现页：走红果鉴服务的 /rank 榜单接口（tab 映射到 board）
    /// 201 推荐 → recommend，202 热播 → hot，203 榜单 → recommend，204 新剧 → new
    func discover(tab: Int = 201, offset: Int = 0, count: Int = 20) async throws -> HGDiscoverResponse {
        guard let base = config.normalized else { throw HGServeError.notConfigured }
        var baseStr = base.absoluteString
        while baseStr.hasSuffix("/") { baseStr.removeLast() }

        let board: String
        switch tab {
        case 202: board = "hot"
        case 204: board = "new"
        default:  board = "recommend"
        }

        var items = [
            URLQueryItem(name: "board", value: board),
            URLQueryItem(name: "limit", value: String(count)),
        ]
        if !config.token.isEmpty {
            items.append(URLQueryItem(name: "api_key", value: config.token))
        }
        guard var comps = URLComponents(string: baseStr + "/rank") else {
            throw HGServeError.badPath("/rank")
        }
        comps.queryItems = items
        guard let url = comps.url else { throw HGServeError.badPath("/rank") }

        var req = URLRequest(url: url)
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw HGServeError.decode("不是 HTTP 响应")
            }
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw HGServeError.http(http.statusCode, String(msg.prefix(200)))
            }
            let raw = try JSONDecoder().decode(HGRankResponse.self, from: data)
            let sourceItems: [HGRankItemRaw] = raw.items ?? []
            let mapped = sourceItems.map { it -> HGFeedItem in
                HGFeedItem(
                    seriesID: it.seriesID ?? "",
                    itemID: nil,
                    title: it.title,
                    cover: it.cover,
                    intro: it.intro,
                    tags: nil,
                    episodeText: nil,
                    episodeCount: it.episodeCnt,
                    freeEpisodes: nil,
                    playCount: it.playCnt,
                    followedCount: nil
                )
            }.filter { !$0.seriesID.isEmpty }
            return HGDiscoverResponse(
                ok: true, tab: tab, offset: 0, count: mapped.count,
                hasMore: false, nextOffset: nil, items: mapped
            )
        } catch let e as HGServeError {
            throw e
        } catch {
            throw HGServeError.decode(error.localizedDescription)
        }
    }
}

// MARK: - 状态容器

@MainActor
final class HGFeedStore: ObservableObject {
    @Published private(set) var items: [HGFeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var hasMore = true
    @Published var tab: Int = 201

    private var offset = 0
    private let pageSize = 20
    private var loadedTabs: [Int: (items: [HGFeedItem], offset: Int, hasMore: Bool)] = [:]

    /// 切换 tab 时恢复各自的分页状态
    func selectTab(_ newTab: Int) async {
        // 先把当前 tab 的进度存起来
        loadedTabs[tab] = (items, offset, hasMore)
        tab = newTab
        if let saved = loadedTabs[newTab] {
            items = saved.items
            offset = saved.offset
            hasMore = saved.hasMore
        } else {
            items = []
            offset = 0
            hasMore = true
            await reload(config: nil)
        }
    }

    func reload(config: ResolverConfig?) async {
        guard let config, config.isConfigured else {
            items = []
            errorText = "还没配置解析服务。请到「我的 → 解析服务」填写地址。"
            return
        }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let client = HGServerClient(config: config)
            let resp = try await client.discover(tab: tab, offset: 0, count: pageSize)
            items = resp.items ?? []
            offset = resp.nextOffset ?? items.count
            hasMore = resp.hasMore ?? false
        } catch {
            errorText = error.localizedDescription
        }
    }

    func loadMore(config: ResolverConfig?) async {
        guard !isLoading, hasMore, let config, config.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let client = HGServerClient(config: config)
            let resp = try await client.discover(tab: tab, offset: offset, count: pageSize)
            let fresh = (resp.items ?? []).filter { new in
                !items.contains(where: { $0.seriesID == new.seriesID })
            }
            items.append(contentsOf: fresh)
            // 服务端给的是上游真实 offset，不能自己累加（会有重复被过滤）
            offset = resp.nextOffset ?? (offset + (resp.items ?? []).count)
            hasMore = (resp.hasMore ?? false) && !fresh.isEmpty
        } catch {
            errorText = error.localizedDescription
            hasMore = false
        }
    }

    func clear() {
        items = []
        offset = 0
        hasMore = true
        errorText = nil
        loadedTabs.removeAll()
    }
}


// MARK: - 搜索

struct HGSearchResponse: Decodable {
    var ok: Bool
    var q: String?
    var count: Int?
    var total: Int?
    var totalPages: Int?
    var hasMore: Bool?
    var recommended: Bool?
    var items: [HGFeedItem]?

    enum CodingKeys: String, CodingKey {
        case ok, q, count, total, recommended, items
        case totalPages = "total_pages"
        case hasMore = "has_more"
    }
}

extension HGServerClient {
    func search(_ query: String, page: Int = 1) async throws -> HGSearchResponse {
        // 搜索接口（/reading/bookapi/search/tab/v）当前签名后返回空 body，
        // 与播放一样卡在 device_register。这里明确抛「搜索暂不可用」，
        // 避免 App 打旧 /api/search 404。可先用首页榜单浏览。
        throw HGServeError.http(110001, "搜索暂不可用（红果风控，需补设备注册）。请先用首页榜单浏览。")
    }
}
