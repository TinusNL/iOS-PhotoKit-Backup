import Photos
import SwiftUI
import UIKit

struct AssetThumbnail: View {
  var assetId: String
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo")
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 44, height: 44)
    .background(Color.secondary.opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .task(id: assetId) {
      image = await ThumbnailLoader.image(for: assetId)
    }
  }
}

#Preview("Thumbnail") {
  AssetThumbnail(assetId: "")
    .padding()
}

private enum ThumbnailLoader {
  private static let cache = ThumbnailCache()

  static func image(for assetId: String) async -> UIImage? {
    guard !assetId.isEmpty else { return nil }
    if let cached = cache.images[assetId] {
      return cached
    }
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
    guard let asset = assets.firstObject else { return nil }
    let gate = ResumeOnce()
    let image = await withCheckedContinuation { continuation in
      let options = PHImageRequestOptions()
      options.deliveryMode = .fastFormat
      options.resizeMode = .fast
      options.isNetworkAccessAllowed = false
      options.isSynchronous = false
      PHImageManager.default().requestImage(
        for: asset,
        targetSize: CGSize(width: 132, height: 132),
        contentMode: .aspectFill,
        options: options
      ) { image, _ in
        gate.resume(image, continuation)
      }
    }
    if let image {
      cache.images[assetId] = image
    }
    return image
  }
}

private final class ThumbnailCache: @unchecked Sendable {
  var images: [String: UIImage] = [:]
}

private final class ResumeOnce: @unchecked Sendable {
  private var resumed = false

  func resume(_ image: UIImage?, _ continuation: CheckedContinuation<UIImage?, Never>) {
    guard !resumed else { return }
    resumed = true
    continuation.resume(returning: image)
  }
}
