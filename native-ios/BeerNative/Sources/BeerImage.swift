import SwiftUI
import UIKit

@MainActor
final class BeerImageCache {
    static let shared = BeerImageCache()
    private var store: [String: UIImage] = [:]

    func image(for path: String) -> UIImage? { store[path] }
    func store(_ image: UIImage, for path: String) { store[path] = image }
}

@MainActor
final class BeerImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false

    private var task: Task<Void, Never>?
    private var loadedPath: String?

    func load(path: String?, api: BeerAPI) {
        guard let path, !path.isEmpty else {
            task?.cancel()
            image = nil
            failed = false
            loadedPath = nil
            return
        }
        if loadedPath == path, image != nil { return }
        if let cached = BeerImageCache.shared.image(for: path) {
            loadedPath = path
            image = cached
            failed = false
            return
        }
        task?.cancel()
        image = nil
        failed = false
        loadedPath = path
        task = Task {
            do {
                let data = try await api.downloadAsset(path)
                if Task.isCancelled { return }
                let img = UIImage(data: data)
                if let img {
                    BeerImageCache.shared.store(img, for: path)
                }
                image = img
                failed = img == nil
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    deinit { task?.cancel() }
}

struct BeerImage: View {
    let path: String?
    var contentMode: ContentMode = .fill

    @EnvironmentObject private var app: AppModel
    @StateObject private var loader = BeerImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loader.failed || path == nil || path?.isEmpty == true {
                placeholder
            } else {
                placeholder.overlay { ProgressView().tint(Theme.muted) }
            }
        }
        .onAppear { loader.load(path: path, api: app.api) }
        .onChange(of: path, perform: { loader.load(path: $0, api: app.api) })
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.bg)
            .overlay(
                Text("📷")
                    .font(.title2)
                    .foregroundStyle(Theme.muted)
            )
    }
}