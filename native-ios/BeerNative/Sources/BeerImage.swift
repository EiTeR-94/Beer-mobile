import SwiftUI
import UIKit

@MainActor
final class BeerImageCache {
    static let shared = BeerImageCache()
    private var store: [String: UIImage] = [:]
    private let imageDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        imageDir = base.appendingPathComponent("offline-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
    }

    func image(for path: String) -> UIImage? {
        if let mem = store[path] { return mem }
        let file = imageFile(for: path)
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            store[path] = img
            return img
        }
        return nil
    }

    func store(_ image: UIImage, for path: String) {
        store[path] = image
        // persist to disk
        if let data = image.jpegData(compressionQuality: 0.85) {
            let file = imageFile(for: path)
            try? data.write(to: file, options: .atomic)
        }
    }

    private func imageFile(for path: String) -> URL {
        let key = path.components(separatedBy: "/").last ?? path.replacingOccurrences(of: "/", with: "_")
        return imageDir.appendingPathComponent(key)
    }
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
                if !Task.isCancelled {
                    // On slow establishment (common on first VPN/WiFi connect or slow links), retry a few times
                    let isSlow = error.localizedDescription.contains("établissement lent") || error.localizedDescription.contains("Timeout connexion")
                    if isSlow {
                        for delay in [2, 4, 8] {  // progressive backoff
                            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                            do {
                                let data = try await api.downloadAsset(path)
                                if Task.isCancelled { return }
                                let img = UIImage(data: data)
                                if let img {
                                    BeerImageCache.shared.store(img, for: path)
                                }
                                image = img
                                failed = img == nil
                                return
                            } catch {}
                        }
                    }
                    failed = true
                }
            }
        }
    }

    deinit { task?.cancel() }

    static func prewarm(path: String?, api: BeerAPI) {
        guard let path, !path.isEmpty else { return }
        Task {
            let loader = BeerImageLoader()
            loader.load(path: path, api: api)
        }
    }
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
            } else if loader.failed || path == nil || path?.isEmpty == true || (app.networkStatus == .offline && loader.image == nil) {
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