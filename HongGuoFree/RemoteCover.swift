// 封面加载：封装 URL 到 UIImage 的异步加载。
// 红果封面是 .heic，iOS 原生 UIImage 能直接解码，无需额外处理。
import SwiftUI
import UIKit

/// 一个能异步加载远程封面图、带占位与缓存的 SwiftUI 视图。
struct RemoteCover: View {
    let urlString: String?
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?
    @State private var failed = false

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color(.systemGray5))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film")
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.35))
                        .foregroundColor(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil, !failed else { return }
        guard let urlString, let url = URL(string: urlString) else {
            failed = true
            return
        }

        let key = urlString as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let img = UIImage(data: data) else {
                    await MainActor.run { failed = true }
                    return
                }
                Self.cache.setObject(img, forKey: key)
                await MainActor.run { image = img }
            } catch {
                await MainActor.run { failed = true }
            }
        }
    }
}
