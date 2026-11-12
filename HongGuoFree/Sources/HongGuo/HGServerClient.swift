// 解析服务客户端
//
// 服务端（server/hongguo-server.mjs）负责：
//   红果接口签名绕过 -> 拿 1080P 地址 -> CENC 逐样本解密 -> HTTP Range 输出明文 MP4
// iOS 端只做一件事：把它当成普通视频 URL 播。
//
// 部署后把 baseURL 填成你的服务器地址即可，例如：
//   http://192.168.1.10:8787      （局域网）
//   https://hg.example.com        （公网，建议套 HTTPS + ACCESS_TOKEN）
import Foundation

// MARK: - 配置

/// 解析服务地址。可在「设置」里让用户自己填。
struct ResolverConfig: Codable, Equatable {
    var baseURL: String
    var token: String

    static let `default` = ResolverConfig(baseURL: "", token: "")

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
    var playURL: String?

    var id: String { vid }

    enum CodingKeys: String, CodingKey {
        case index, vid, playable
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

    // MARK: 剧集详情（走红果鉴 rgsngdha 服务的 /episodes 接口）

    /// 红果鉴服务的分集返回结构（/episodes）
    private struct HGEpisodeRaw: Decodable {
        var index: Int
        var vid: String
        var title: String?
        var duration: Int?
        var cover: String?
    }

    private struct HGEpisodesMetaRaw: Decodable {
        var seriesID: String?
        var title: String?
        var intro: String?
        var cover: String?
        var episodeCnt: Int?

        enum CodingKeys: String, CodingKey {
            case seriesID = "series_id"
            case title, intro, cover
            case episodeCnt = "episode_cnt"
        }
    }

    private struct HGEpisodesResponse: Decodable {
        var meta: HGEpisodesMetaRaw?
        var episodes: [HGEpisodeRaw]?
    }

    func detail(seriesID: String) async throws -> HGServerDetail {
        // 走红果鉴服务：GET /episodes?series_id=xxx&api_key=token
        guard let base = config.normalized else { throw HGServeError.notConfigured }
        var baseStr = base.absoluteString
        while baseStr.hasSuffix("/") { baseStr.removeLast() }

        var items = [URLQueryItem(name: "series_id", value: seriesID)]
        if !config.token.isEmpty {
            items.append(URLQueryItem(name: "api_key", value: config.token))
        }
        guard var comps = URLComponents(string: baseStr + "/episodes") else {
            throw HGServeError.badPath("/episodes")
        }
        comps.queryItems = items
        guard let url = comps.url else { throw HGServeError.badPath("/episodes") }

        var req = URLRequest(url: url)
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await Self.session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw HGServeError.decode("不是 HTTP 响应")
            }
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw HGServeError.http(http.statusCode, String(msg.prefix(200)))
            }
            let raw = try JSONDecoder().decode(HGEpisodesResponse.self, from: data)
            let meta = raw.meta
            let eps = (raw.episodes ?? []).map {
                HGServerEpisode(index: $0.index, vid: $0.vid, playable: true, playURL: nil)
            }
            return HGServerDetail(
                ok: true,
                seriesID: meta?.seriesID ?? seriesID,
                title: meta?.title,
                intro: meta?.intro,
                cover: meta?.cover,
                freeEpisodes: meta?.episodeCnt,
                totalEpisodes: meta?.episodeCnt ?? eps.count,
                episodes: eps
            )
        } catch let e as HGServeError {
            throw e
        } catch {
            throw HGServeError.decode(error.localizedDescription)
        }
    }

    // MARK: 单集信息（走红果鉴服务 /play，注意：当前 device_register 未就绪，会返回 110001）

    func play(vid: String) async throws -> HGServerPlay {
        // 红果鉴服务 /play 接口需要 series_id + ep，这里退化为返回「未就绪」状态，
        // 避免 App 因旧 /api/play 404 报错。真实播放能力需补 device_register 后恢复。
        throw HGServeError.http(110001, "播放服务暂未就绪（需补设备注册，方案2）")
    }

    // MARK: 可直接给 AVPlayer 的 URL

    /// 服务端解密后的流地址（支持 Range，AVPlayer 直接播）
    ///
    /// 注意：红果鉴服务的播放接口（multi_video_model）当前卡在 device_register，
    /// 无法产出可播流。这里直接抛错，让播放器走「未就绪」提示。
    func streamURL(vid: String) throws -> URL {
        throw HGServeError.http(110001, "播放服务暂未就绪（需补设备注册，方案2）")
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
        // 新服务根路径返回 {"service":...,"endpoints":[...]}（非 {ok:true}），
        // 这里只要 HTTP 200 且是合法 JSON 即视为在线。
        guard let data = try? await get("/") else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    // MARK: 底层

    private func get(_ path: String) async throws -> Data {
        guard let url = absolute(path) else { throw HGServeError.notConfigured }
        var req = URLRequest(url: url)
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
}
