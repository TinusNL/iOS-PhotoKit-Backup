import Foundation
import SwiftUI

struct UploadRow: View {
  var item: ListedUpload

  var body: some View {
    HStack(spacing: 12) {
      AssetThumbnail(assetId: item.assetId)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(item.title)
          if item.isLivePhoto {
            Image(systemName: "livephoto")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityLabel("Live Photo")
          }
        }
        Text(item.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      if let bytes = item.bytes {
        Text(ByteText.file(bytes))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

enum PreviewUploads {
  static let livePhoto = ListedUpload(
    id: "live",
    assetId: "preview-live",
    title: "IMG_3102.HEIC",
    subtitle: "2026/10/IMG_3102.HEIC",
    bytes: 5_700_000,
    isLivePhoto: true
  )
  static let video = ListedUpload(
    id: "video",
    assetId: "preview-video",
    title: "IMG_3104.MP4",
    subtitle: "2026/10/IMG_3104.MP4",
    bytes: 18_000_000
  )
  static let recentPhoto = ListedUpload(
    id: "recent",
    assetId: "preview-uploaded",
    title: "IMG_2450.JPG",
    subtitle: "2019/03/IMG_2450.JPG",
    bytes: 3_102_884
  )
}

#Preview("Upload row") {
  List {
    UploadRow(item: PreviewUploads.livePhoto)
    UploadRow(item: PreviewUploads.video)
  }
}

nonisolated enum ByteText {
  static func file(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
}
