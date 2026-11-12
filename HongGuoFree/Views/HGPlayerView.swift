// 自定义全屏播放器：AVPlayerLayer + resizeAspectFill 铺满 + 开启音频会话
//
// 相比 SwiftUI 自带的 VideoPlayer，这里解决两个关键问题：
//   1. 没有声音 —— VideoPlayer 在某些场景下音频会话未激活；
//      这里显式 AVAudioSession 设 playback 类别并激活。
//   2. 画面不协调（黑边/比例不对）—— 用 AVPlayerLayer，
//      videoGravity = .resizeAspectFill，竖屏视频铺满整个屏幕。
import SwiftUI
import AVFoundation
import UIKit

/// 一个用 AVPlayerLayer 渲染的全屏播放器视图。
/// 把 AVPlayer 注入进来即可，自动铺满并保持 9:16 竖屏裁切。
struct HGPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = .resizeAspectFill
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

/// 音频会话管理：确保 App 播放时能出声（尤其静音拨片、后台、蓝牙场景）。
enum HGAudioSession {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            // 忽略失败，不影响视频画面
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
