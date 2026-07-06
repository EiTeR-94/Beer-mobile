import SwiftUI
import UIKit

@MainActor
final class BeerImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false

    private var task: Task<Void, Never>?

    func load(path: String?, api: BeerAPI) {
        task?.cancel()
        image = nil
        failed = false
        guard let path, !path.isEmpty else { return }
        task = Task {
            do {
                let data = try await api.downloadAsset(path)
                if Task.isCancelled { return }
                image = UIImage(data: data)
                failed = image == nil
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