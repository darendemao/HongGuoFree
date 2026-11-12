// 解析服务客户端
//
// 服务端（server/hongguo-server.mjs）负责：
//   红果接口签名绕过 -> 拿 1080P 地址 -> CENC 逐样本解密 -> HTTP Range 输出明文 MP4
// iOS 端只做一件事：把它当成普通视频 URL 播。
//
// 两种播放模式：
//   .proxy  转发模式 —— 视频流量走服务器 /api/stream（简单，吃服务器带宽）
//   .direct 直连模式 —— App 直连红果 CDN + 本地解密（省带宽，需 /api/keys）
//
// 部署后把 baseURL 填成你的服务器地址即可，例如：
//   http://192.168.1.10:8787      （局域网）
//   https://hg.example.com        （公网，建议套 HTTPS + ACCESS_TOKEN）
import Foundation

// MARK: - 播放模式

/// 播放模式：转发（服务器解密后转发）或直连（App 自己解 CENC）
enum HGPlaybackMode: String, Codable, CaseIterable, Identifiable {
    case proxy
    case direct

    var id: String { rawValue }

    var label: String {
        switch self {
        case .proxy: return "转发模式"
        case .direct: return "直连模式"
        }
    }

    var detail: String {
        switch self {
        case .proxy:
            return "视频流量走服务器解密后转发，简单稳定，但消耗服务器带宽。"
        case .direct:
            return "App 直连红果 CDN 并本地解密，省服务器带宽（约省 30 倍）。"
        }
    }
}

// MARK: - 配置

/// 解析服务地址。可在「设置」里让用户自己填。
struct ResolverConfig: Codable, Equatable {
    var baseURL: String
    var token: String
    var mode: HGPlaybackMode

    static let `default` = ResolverConfig(baseURL: "", token: "", mode: .proxy)

    init(baseURL: String, token: String, mode: HGPlaybackMode = .proxy) {
        self.baseURL = baseURL
        self.token = token
        self.mode = mode
    }

    var normalized: URL? {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    var isConfigured: Bool { normalized != nil }
}

// MARK: - 模型

struct HGServerEpisode: Decodable, Identifiable {
    var index: Int
    var vid: String
    var playable: Bool?
    var title: String?
    var duration: Int?
    var playURL: String?

    var id: String { vid }

    enum CodingKeys: String, CodingKey {
        case index, vid, playable, title, duration
        case playURL = "play_url"
    }
}

struct HGServerDetail: Decodable {
    var ok: Bool
    var seriesID: String?
    var title: String?
    var intro: String?
    var cover: String?
    var freeEpisodes: Int?
    var totalEpisodes: Int?
    var episodes: [HGServerEpisode]?

    enum CodingKeys: String, CodingKey {
        case ok, title, intro, cover, episodes
        case seriesID = "series_id"
        case freeEpisodes = "free_episodes"
        case totalEpisodes = "total_episodes"
    }
}

struct HGServerPlay: Decodable {
    var ok: Bool
    var vid: String?
    var quality: String?
    var duration: Double?
    var totalBytes: Int64?
    var encrypted: Bool?
    var cdnURL: String?
    var cencKeyHex: String?
    var streamURL: String?
    var downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case ok, vid, quality, duration, encrypted
        case totalBytes = "total_bytes"
        case cdnURL = "cdn_url"
        case cencKeyHex = "cenc_key_hex"
        case streamURL = "stream_url"
        case downloadURL = "download_url"
    }
}

// MARK: - 错误

enum HGServeError: LocalizedError {
    case notConfigured
    case badPath(String)
    case http(Int, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "还没配置解析服务地址。请到「我的 → 解析服务」填写。"
        case .badPath(let p):
            return "接口地址无效：\(p)"
        case .http(let code, let msg):
            return "解析服务返回 HTTP \(code)：\(msg)"
        case .decode(let m):
            return "解析服务响应格式异常：\(m)"
        }
    }
}

// MARK: - 客户端

struct HGServerClient {
    let config: ResolverConfig

    private static var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    init(config: ResolverConfig) {
        self.config = config
    }

    /// 拼一个绝对 URL（服务端返回的是相对路径 /api/stream?vid=xxx）
    ///
    /// 注意：不能用 `appendingPathComponent` —— 它会把整串当成单个路径段，
    /// 把 `?` 编码成 `%3F`，服务端就匹配不上路由了（表现为 404 未知接口）。
    /// 这里直接拼字符串，只对 token 做转义。
    func absolute(_ path: String) -> URL? {
        guard let base = config.normalized else { return nil }

        var s = path
        if s.hasPrefix("/") { s.removeFirst() }

        var baseStr = base.absoluteString
        while baseStr.hasSuffix("/") { baseStr.removeLast() }

        var full = baseStr + "/" + s

        if !config.token.isEmpty {
            let sep = full.contains("?") ? "&" : "?"
            let escaped = config.token
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                ?? config.token
            full += "\(sep)token=\(escaped)"
        }

        return URL(string: full)
    }

    // MARK: 剧集详情

    /// 走服务端 /api/detail，返回完整详情 + 分集清单
    func detail(seriesID: String) async throws -> HGServerDetail {
        let url = try apiURL("/api/detail", query: [("series_id", seriesID)])
        let data = try await requestData(url: url, timeout: 40)
        return try decodeOrThrow(HGServerDetail.self, data)
    }

    // MARK: 单集信息

    /// 走服务端 /api/play，返回播放模型（质量 / 时长 / 是否 CENC / 密钥等）
    func play(vid: String) async throws -> HGServerPlay {
        let url = try apiURL("/api/play", query: [("vid", vid)])
        let data = try await requestData(url: url, timeout: 40)
        return try decodeOrThrow(HGServerPlay.self, data)
    }

    // MARK: 可直接给 AVPlayer 的 URL（转发模式）

    /// 服务端解密后的流地址（支持 Range，AVPlayer 直接播）
    func streamURL(vid: String) throws -> URL {
        guard let url = absolute("/api/stream?vid=\(vid)") else {
            throw HGServeError.notConfigured
        }
        return url
    }

    /// 完整下载地址
    func downloadURL(vid: String) throws -> URL {
        guard let url = absolute("/api/download?vid=\(vid)") else {
            throw HGServeError.notConfigured
        }
        return url
    }

    // MARK: 健康检查

    @discardableResult
    func health() async -> Bool {
        // 服务端根路径返回 {"service":...,"endpoints":[...]}（非 {ok:true}），
        // 这里只要 HTTP 200 且是合法 JSON 即视为在线。
        guard let data = try? await get("/") else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    // MARK: 底层

    /// 用 query 参数构造 /api 接口 URL（自动带上 token）
    /// 注意：必须用 internal（不能 private），因为其它文件的 extension 也要调用。
    func apiURL(_ path: String, query: [(String, String)]) throws -> URL {
        guard let base = config.normalized else { throw HGServeError.notConfigured }
        var baseStr = base.absoluteString
        while baseStr.hasSuffix("/") { baseStr.removeLast() }

        var comps = URLComponents(string: baseStr + path)
        var items = comps?.queryItems ?? []
        for (k, v) in query {
            items.append(URLQueryItem(name: k, value: v))
        }
        if !config.token.isEmpty {
            items.append(URLQueryItem(name: "token", value: config.token))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { throw HGServeError.badPath(path) }
        return url
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = absolute(path) else { throw HGServeError.notConfigured }
        return try await requestData(url: url, timeout: 30)
    }

    func requestData(url: URL, timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !config.token.isEmpty {
            req.setValue(config.token, forHTTPHeaderField: "X-Auth-Token")
        }
        do {
            let (data, response) = try await Self.session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw HGServeError.decode("不是 HTTP 响应")
            }
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw HGServeError.http(http.statusCode, String(msg.prefix(200)))
            }
            return data
        } catch let e as HGServeError {
            throw e
        } catch {
            throw HGServeError.http(-1, error.localizedDescription)
        }
    }

    private func decodeOrThrow<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HGServeError.decode(error.localizedDescription)
        }
    }
}
