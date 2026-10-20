import Foundation
import Photos

struct LibraryPage: Sendable {
  var uploads: [ExpectedUpload]
  var nextIndex: Int
  var total: Int
}

enum LibraryScanner {
  nonisolated static func page(start: Int, limit: Int, uploadLivePhotoMovies: Bool) -> LibraryPage {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    options.prefetchAssetExtendedMetadata = true
    let assets = PHAsset.fetchAssets(with: options)
    let total = assets.count
    let boundedStart = min(max(start, 0), total)
    let end = min(boundedStart + max(limit, 0), total)
    var uploads: [ExpectedUpload] = []
    if boundedStart < end {
      assets.enumerateObjects(at: IndexSet(integersIn: boundedStart..<end), options: []) {
        asset, _, _ in
        autoreleasepool {
          uploads.append(
            contentsOf: listedUploads(for: asset, uploadLivePhotoMovies: uploadLivePhotoMovies))
        }
      }
    }
    return LibraryPage(uploads: uploads, nextIndex: end, total: total)
  }

  private nonisolated static func listedUploads(
    for asset: PHAsset, uploadLivePhotoMovies: Bool
  ) -> [ExpectedUpload] {
    let timestamp = UploadNaming.isoTimestamp(for: asset.creationDate ?? Date())
    let original = asset.extendedMetadata.originalFilename
    if let original, !original.isEmpty {
      if asset.mediaType == .video {
        return [
          expected(asset: asset, resourceType: "video", filename: original, timestamp: timestamp)
        ]
      }
      if asset.mediaType == .image {
        var items = [
          expected(asset: asset, resourceType: "photo", filename: original, timestamp: timestamp)
        ]
        if uploadLivePhotoMovies, asset.mediaSubtypes.contains(.photoLive) {
          items.append(
            expected(
              asset: asset,
              resourceType: "pairedVideo",
              filename: UploadNaming.livePhotoMovieFilename(stillFilename: original),
              timestamp: timestamp
            ))
        }
        return items
      }
    }
    return uploads(for: asset, uploadLivePhotoMovies: uploadLivePhotoMovies).map(\.expected)
  }

  nonisolated static func uploads(for asset: PHAsset, uploadLivePhotoMovies: Bool)
    -> [LibraryUpload]
  {
    let resources = PHAssetResource.assetResources(for: asset)
    let timestamp = UploadNaming.isoTimestamp(for: asset.creationDate ?? Date())
    var items: [LibraryUpload] = []

    if let photo = resources.first(where: { $0.type == .photo }) {
      let photoFilename = resourceFilename(photo)
      items.append(
        make(
          asset: asset, resource: photo, resourceType: "photo", filename: photoFilename,
          timestamp: timestamp))
      if uploadLivePhotoMovies,
        asset.mediaSubtypes.contains(.photoLive),
        let paired = resources.first(where: { $0.type == .pairedVideo })
      {
        let filename = UploadNaming.livePhotoMovieFilename(stillFilename: photoFilename)
        items.append(
          make(
            asset: asset, resource: paired, resourceType: "pairedVideo", filename: filename,
            timestamp: timestamp))
      }
    }

    if asset.mediaType == .video, let video = resources.first(where: { $0.type == .video }) {
      items.append(
        make(
          asset: asset, resource: video, resourceType: "video", filename: resourceFilename(video),
          timestamp: timestamp))
    }

    return items
  }

  private nonisolated static func resourceFilename(_ resource: PHAssetResource) -> String {
    if let filename = resource.filename, !filename.isEmpty {
      return filename
    }
    let stem = resource.assetLocalIdentifier.replacingOccurrences(of: "/", with: "-")
    return stem + ".bin"
  }

  private nonisolated static func expected(
    asset: PHAsset,
    resourceType: String,
    filename: String,
    timestamp: String
  ) -> ExpectedUpload {
    ExpectedUpload(
      assetId: asset.localIdentifier,
      resourceType: resourceType,
      filename: filename,
      relativePath: UploadNaming.relativePath(filename: filename, isoTimestamp: timestamp),
      isoTimestamp: timestamp
    )
  }

  private nonisolated static func make(
    asset: PHAsset,
    resource: PHAssetResource,
    resourceType: String,
    filename: String,
    timestamp: String
  ) -> LibraryUpload {
    LibraryUpload(
      expected: ExpectedUpload(
        assetId: asset.localIdentifier,
        resourceType: resourceType,
        filename: filename,
        relativePath: UploadNaming.relativePath(filename: filename, isoTimestamp: timestamp),
        isoTimestamp: timestamp
      ),
      resource: resource
    )
  }
}

struct LibraryUpload {
  var expected: ExpectedUpload
  var resource: PHAssetResource
}
