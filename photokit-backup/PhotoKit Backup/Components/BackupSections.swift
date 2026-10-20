import SwiftUI

struct StatusMessageSection: View {
  var message: String

  var body: some View {
    Section {
      Text(message)
        .foregroundStyle(.red)
    }
  }
}

struct LoadingLabel: View {
  var body: some View {
    HStack(spacing: 8) {
      ProgressView()
      Text("Loading")
        .foregroundStyle(.secondary)
    }
  }
}

struct PhotoAccessSection: View {
  var requestAccess: () async -> Void

  var body: some View {
    Section {
      Button("Allow Full Photo Access") {
        Task { await requestAccess() }
      }
    } footer: {
      Text("Background upload needs access to the whole library, not a selected set of photos.")
    }
  }
}

struct PendingUploadsSection: View {
  var items: [ListedUpload]
  var shown: Int
  var isLoading: Bool
  var isComplete: Bool
  var loadMore: () -> Void

  var body: some View {
    Section {
      if items.isEmpty && isLoading {
        LoadingLabel()
      } else if items.isEmpty && isComplete {
        Text("Everything in the library is already on the server.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(items.prefix(shown)) { item in
          UploadRow(item: item, detail: nil)
        }
        if shown < items.count {
          Button("Load more", action: loadMore)
        }
        if isLoading {
          LoadingLabel()
        }
      }
    } header: {
      Text(isComplete && !items.isEmpty ? "Still to upload (\(items.count))" : "Still to upload")
    }
  }
}

struct RecentUploadsSection: View {
  var rows: [ListedUpload]
  var loaded: Int
  var total: Int
  var isLoadingMore: Bool
  var loadMore: () async -> Void

  var body: some View {
    Section {
      if rows.isEmpty {
        Text("No files in the backup folder yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(rows) { item in
          UploadRow(item: item, detail: item.bytes.map(ByteText.file))
        }
        if loaded < total {
          if isLoadingMore {
            ProgressView()
          } else {
            Button("Load more") {
              Task { await loadMore() }
            }
          }
        }
      }
    } header: {
      Text("Recently uploaded")
    }
  }
}

extension View {
  func workingOverlay(_ isWorking: Bool) -> some View {
    overlay {
      if isWorking {
        ProgressView()
      }
    }
  }
}
