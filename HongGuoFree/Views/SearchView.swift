// 搜索页：调服务端 /api/search，按标题/分类匹配
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var results: [HGFeedItem] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if results.isEmpty && !isLoading && errorText == nil {
                emptyView
            } else {
                resultList
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("搜索短剧名称", text: $query)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .autocorrectionDisabled()

            Button("搜索") { runSearch() }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("输入剧名开始搜索")
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var resultList: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ForEach(results) { item in
                NavigationLink {
                    DetailView(seriesID: item.seriesID, title: item.title ?? "")
                        .environmentObject(appState)
                } label: {
                    HStack(spacing: 12) {
                        RemoteCover(urlString: item.cover)
                            .frame(width: 56, height: 76)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title ?? "未知剧名")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            if let intro = item.intro, !intro.isEmpty {
                                Text(intro)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            if !item.episodeTextResolved.isEmpty {
                                Text(item.episodeTextResolved)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isLoading = true
        errorText = nil
        results = []

        Task {
            do {
                let client = HGServerClient(config: appState.config)
                let resp = try await client.search(q)
                results = resp.items ?? []
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }
}
