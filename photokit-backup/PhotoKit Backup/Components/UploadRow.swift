import Foundation
import Photos
import SwiftUI

struct UploadRow: View {
  var item: ListedUpload
  var transfer: FastItemProgress?
  @State private var loadedBytes: Int?

  var body: some View {
    HStack(alignment: transfer == nil ? .center : .top, spacing: 12) {
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
          if transfer != nil {
            Spacer(minLength: 8)
            sizeLabel
          }
        }
        Text(item.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let transfer {
          HStack(spacing: 8) {
            ProgressView(value: transfer.fraction)
              .tint(.accentColor)
              .frame(maxWidth: .infinity)
            Text("\(transfer.percent)%")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.tint)
          }
          .padding(.top, 4)
        }
      }
      if transfer == nil {
        Spacer(minLength: 8)
        sizeLabel
      }
    }
    .task(id: item.assetId) {
      guard item.bytes == nil, loadedBytes == nil else { return }
      loadedBytes = await FileSizeLoader.bytes(assetId: item.assetId, isLivePhoto: item.isLivePhoto)
    }
  }

  @ViewBuilder
  private var sizeLabel: some View {
    if let sizeText {
      Text(sizeText)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
  }

  private var sizeText: String? {
    if let transfer {
      let total = transfer.total > 0 ? transfer.total : Int64(item.bytes ?? loadedBytes ?? 0)
      guard total > 0 else { return nil }
      return ByteText.fraction(sent: transfer.sent, total: total)
    }
    guard let bytes = item.bytes ?? loadedBytes else { return nil }
    return ByteText.file(bytes)
  }
}

private enum FileSizeLoader {
  static func bytes(assetId: String, isLivePhoto: Bool) async -> Int? {
    guard !assetId.isEmpty else { return nil }
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
    guard let asset = assets.firstObject else { return nil }
    var total = 0
    var found = false
    for resource in PHAssetResource.assetResources(for: asset) {
      guard let dataSize = resource.dataSize else { continue }
      switch resource.type {
      case .photo, .video:
        total += dataSize
        found = true
      case .pairedVideo where isLivePhoto:
        total += dataSize
        found = true
      default:
        break
      }
    }
    return found ? total : nil
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
    UploadRow(
      item: PreviewUploads.video,
      transfer: FastItemProgress(sent: 2_700_000, total: 4_500_000)
    )
  }
}

nonisolated enum ByteText {
  static func file(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  static func fraction(sent: Int64, total: Int64) -> String {
    guard total > 0 else { return file(Int(max(sent, 0))) }
    let units = units(for: total)
    let sentText = amount(max(sent, 0), units: units, includesUnit: false)
    let totalText = amount(total, units: units, includesUnit: true)
    return "\(sentText) of \(totalText)"
  }

  private static func amount(
    _ bytes: Int64, units: ByteCountFormatter.Units, includesUnit: Bool
  ) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = units
    formatter.includesUnit = includesUnit
    formatter.zeroPadsFractionDigits = false
    return formatter.string(fromByteCount: bytes).trimmingCharacters(in: .whitespaces)
  }

  private static func units(for bytes: Int64) -> ByteCountFormatter.Units {
    switch bytes {
    case 1_000_000_000_000...:
      .useTB
    case 1_000_000_000...:
      .useGB
    case 1_000_000...:
      .useMB
    case 1_000...:
      .useKB
    default:
      .useBytes
    }
  }
}
