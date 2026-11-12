// 详情页：剧集封面/简介 + 分集列表
import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var appState: AppState
    let seriesID: String
    let title: String

    @State private var detail: HGServerDetail?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中…")
            } else if let errorText {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(errorText)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let detail {
                detailContent(detail)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func detailContent(_ d: HGServerDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    RemoteCover(urlString: d.cover)
                        .frame(width: 110, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(d.title ?? title)
                            .font(.headline)

                        if let total = d.totalEpisodes, total > 0 {
                            Text("全 \(total) 集")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let free = d.freeEpisodes, free > 0 {
                            Text("免费 \(free) 集")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)

                if let intro = d.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                        .padding(.horizontal)
                }

                Divider()

                episodeList(d)
            }
        }
    }

    private func episodeList(_ d: HGServerDetail) -> some View {
        let eps = d.episodes ?? []
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                         spacing: 10) {
            ForEach(eps) { ep in
                NavigationLink {
                    PlayerView(vid: ep.vid, title: "\(d.title ?? title) 第\(ep.index)集")
                        .environmentObject(appState)
                } label: {
                    Text("\(ep.index)")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private func load() async {
        isLoading = true
        errorText = nil
        do {
            let client = HGServerClient(config: appState.config)
            detail = try await client.detail(seriesID: seriesID)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
