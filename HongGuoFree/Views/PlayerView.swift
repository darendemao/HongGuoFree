// 播放器页：用 HGPlaybackCoordinator 统一走转发/直连两种模式
import SwiftUI
import AVKit

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    let vid: String
    let title: String

    @State private var player: AVPlayer?
    @State private var progressText = ""
    @State private var errorText: String?
    @State private var isLoading = true

    var body: some View {
        VStack {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxHeight: 400)
            } else if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    if !progressText.isEmpty {
                        Text(progressText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 400)
            }

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }

            // 模式提示
            Text("当前播放模式：\(appState.mode.label)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Spacer()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .onDisappear {
            player?.pause()
            HGPlaybackSessionHolder.shared.detach()
        }
    }

    private func prepare() async {
        isLoading = true
        errorText = nil
        progressText = ""

        do {
            let coordinator = HGPlaybackCoordinator(config: appState.config)
            let item = try await coordinator.prepare(vid: vid) { p in
                Task { @MainActor in
                    let pct = Int(p.fraction * 100)
                    progressText = "\(p.phase)… \(pct)%"
                }
            }
            let p = AVPlayer(playerItem: item)
            player = p
            p.play()
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
