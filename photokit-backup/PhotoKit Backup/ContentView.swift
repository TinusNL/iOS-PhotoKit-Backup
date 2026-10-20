import Photos
import SwiftUI
import UIKit

struct ContentView: View {
  @State private var model = BackupModel()

  var body: some View {
    Group {
      if model.isSignedIn {
        BackupHomeView(model: model)
      } else {
        ConnectView(model: model)
      }
    }
    .onAppear { model.restore() }
  }
}

private struct ConnectView: View {
  @Bindable var model: BackupModel

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Server", text: $model.serverField, prompt: Text("192.168.1.20:8080"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
          SecureField("API key", text: $model.apiKeyField)
        } footer: {
          Text(
            "Original photos and videos are sent to this proxy. The phone keeps uploading after you leave the app."
          )
        }

        if let statusMessage = model.statusMessage {
          Section {
            Text(statusMessage)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("PhotoKit Backup")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Connect") {
            Task { await model.connect() }
          }
          .disabled(model.isWorking)
        }
      }
      .overlay {
        if model.isWorking {
          ProgressView()
        }
      }
    }
  }
}

private struct BackupHomeView: View {
  @Bindable var model: BackupModel
  @State private var showingSettings = false

  var body: some View {
    NavigationStack {
      List {
        if model.photoStatus != .authorized {
          Section {
            Button("Allow Full Photo Access") {
              Task { await model.requestPhotoAccess() }
            }
          } footer: {
            Text(
              "Background upload needs access to the whole library, not a selected set of photos.")
          }
        }

        if let statusMessage = model.statusMessage {
          Section {
            Text(statusMessage)
              .foregroundStyle(.red)
          }
        }

        Section {
          if model.pending.isEmpty && model.isLoadingPending {
            HStack(spacing: 8) {
              ProgressView()
              Text("Loading")
                .foregroundStyle(.secondary)
            }
          } else if model.pending.isEmpty && model.pendingIsComplete {
            Text("Everything in the library is already on the server.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(model.pending.prefix(model.pendingShown)) { item in
              UploadRow(item: item, detail: nil)
            }
            if model.pendingShown < model.pending.count {
              Button("Load more") {
                model.loadMorePending()
              }
            }
            if model.isLoadingPending {
              HStack(spacing: 8) {
                ProgressView()
                Text("Loading")
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text(
            model.pendingIsComplete && !model.pending.isEmpty
              ? "Still to upload (\(model.pending.count))" : "Still to upload")
        }

        Section {
          if model.recentRows.isEmpty {
            Text("No files in the backup folder yet.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(model.recentRows) { item in
              UploadRow(item: item, detail: item.bytes.map(byteCount))
            }
            if model.recentLoaded < model.recentTotal {
              if model.isLoadingMoreRecent {
                ProgressView()
              } else {
                Button("Load more") {
                  Task { await model.loadMoreRecent() }
                }
              }
            }
          }
        } header: {
          Text("Recently uploaded")
        }
      }
      .navigationTitle(model.accountName.isEmpty ? "Backup" : model.accountName)
      .refreshable { await model.refresh() }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") {
            showingSettings = true
          }
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView(model: model)
      }
      .task { await model.refresh() }
    }
  }

  private func byteCount(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
}

private struct UploadRow: View {
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

private struct AssetThumbnail: View {
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

private struct SettingsView: View {
  @Bindable var model: BackupModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle(
            "Upload Live Photo movies",
            isOn: Binding(
              get: { model.uploadLivePhotoMovies },
              set: { model.setUploadLivePhotoMovies($0) }
            ))
        } footer: {
          Text(
            "A Live Photo is stored as the original still and a movie with the same name, such as IMG_2456.HEIC and IMG_2456.MOV. Standalone videos are always uploaded."
          )
        }

        Section {
          LabeledContent("Server", value: model.serverField)
        }

        Section {
          Button("Sign Out", role: .destructive) {
            model.signOut()
            dismiss()
          }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

#Preview("Signed in") {
  BackupHomeView(model: .preview())
}

#Preview("Needs photo access") {
  BackupHomeView(model: .preview(photoStatus: .notDetermined))
}

#Preview("Settings") {
  SettingsView(model: .preview())
}
