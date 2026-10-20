import Foundation
import Photos

enum LibraryScanner {
  static func expected(uploadLivePhotoMovies: Bool) -> [ExpectedUpload] {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    let assets = PHAsset.fetchAssets(with: options)
    var result: [ExpectedUpload] = []
    assets.enumerateObjects { asset, _, _ in
      result.append(
        contentsOf: uploads(for: asset, uploadLivePhotoMovies: uploadLivePhotoMovies).map(
          \.expected))
    }
    return result
  }

  static func uploads(for asset: PHAsset, uploadLivePhotoMovies: Bool) -> [LibraryUpload] {
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

  private static func resourceFilename(_ resource: PHAssetResource) -> String {
    if let filename = resource.filename, !filename.isEmpty {
      return filename
    }
    let stem = resource.assetLocalIdentifier.replacingOccurrences(of: "/", with: "-")
    return stem + ".bin"
  }

  private static func make(
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
