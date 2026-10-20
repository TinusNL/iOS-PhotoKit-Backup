import Foundation
import SwiftUI

struct UploadRow: View {
  var item: ListedUpload
  var detail: String?

  var body: some View {
    HStack(spacing: 12) {
      AssetThumbnail(assetId: item.assetId)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
        Text(item.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

nonisolated enum ByteText {
  static func file(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
}
