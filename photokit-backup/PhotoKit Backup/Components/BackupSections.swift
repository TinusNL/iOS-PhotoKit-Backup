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

struct CountedSectionHeader: View {
  var title: String
  var count: Int?
  var browse: BackupFileList?

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
      if let count {
        Text(ItemCount.phrase(count))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
      }
      Spacer(minLength: 8)
      if let browse {
        NavigationLink(value: browse) {
          HStack(spacing: 2) {
            Text("View all")
            Image(systemName: "chevron.right")
              .font(.caption2.weight(.bold))
          }
          .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
      }
    }
    .textCase(nil)
  }
}

struct PhotoAccessSection: View {
  var waitingCount: Int?
  var requestAccess: () async -> Void

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          IconBadge(systemImage: "photo.on.rectangle.angled")
          VStack(alignment: .leading, spacing: 2) {
            Text("Photo access needed")
              .font(.headline)
            if let waitingCount, waitingCount > 0 {
              RisingCount(value: waitingCount) { "\(ItemCount.phrase($0)) waiting for access" }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
        }
        Text(
          "Allow full library access so iOS can upload your photos and videos in the background."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        Button {
          Task { await requestAccess() }
        } label: {
          Text("Allow full photo access")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
      .padding(.vertical, 4)
    }
  }
}

struct PendingUploadsSection: View {
  var items: [ListedUpload]
  var previewLimit: Int
  var isLoading: Bool
  var isComplete: Bool
  var transfers: [String: FastBackupItemProgress] = [:]

  var body: some View {
    Section {
      if items.isEmpty && isLoading {
        LoadingLabel()
      } else if items.isEmpty && isComplete {
        Text("Everything in the library is already on the server.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(items.prefix(previewLimit)) { item in
          UploadRow(item: item, transfer: transfers[item.id])
        }
        if isLoading {
          LoadingLabel()
        }
      }
    } header: {
      CountedSectionHeader(
        title: "Pending",
        count: items.isEmpty ? nil : items.count,
        browse: items.isEmpty ? nil : .pending
      )
      .padding(.top, -8)
    }
  }
}

struct RecentUploadsSection: View {
  var rows: [ListedUpload]
  var previewLimit: Int

  var body: some View {
    Section {
      if rows.isEmpty {
        Text("No files in the backup folder yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(rows.prefix(previewLimit)) { item in
          UploadRow(item: item)
        }
      }
    } header: {
      CountedSectionHeader(
        title: "Recently uploaded",
        browse: rows.isEmpty ? nil : .recent
      )
    }
  }
}

enum ItemCount {
  nonisolated static func phrase(_ count: Int) -> String {
    count == 1 ? "1 item" : "\(count) items"
  }
}

/// Follows `value` one step at a time so a batch of results counts up instead of jumping.
struct RisingCount: View {
  var value: Int
  var text: (Int) -> String
  @State private var displayed = 0
  @State private var hasShown = false

  var body: some View {
    Text(text(hasShown ? displayed : value))
      .contentTransition(.numericText())
      .task(id: value) {
        await follow(value)
      }
  }

  private func follow(_ target: Int) async {
    if !hasShown {
      displayed = target
      hasShown = true
      return
    }
    while displayed != target {
      if Task.isCancelled { return }
      let gap = target - displayed
      let magnitude = abs(gap)
      let step = magnitude > 80 ? max(1, magnitude / 40) : 1
      displayed += gap > 0 ? step : -step
      try? await Task.sleep(for: .milliseconds(magnitude > 80 ? 16 : 28))
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

#Preview("Status message") {
  List {
    StatusMessageSection(message: "Could not reach the server.")
  }
}

#Preview("Loading") {
  LoadingLabel()
    .padding()
}

#Preview("Section header") {
  NavigationStack {
    CountedSectionHeader(title: "Pending", count: 2, browse: .pending)
      .padding()
  }
}

#Preview("Photo access") {
  List {
    PhotoAccessSection(waitingCount: 2) {}
  }
}

#Preview("Pending") {
  List {
    PendingUploadsSection(
      items: [PreviewUploads.livePhoto, PreviewUploads.video],
      previewLimit: 2,
      isLoading: false,
      isComplete: true
    )
  }
}

#Preview("Recently uploaded") {
  List {
    RecentUploadsSection(
      rows: [PreviewUploads.livePhoto, PreviewUploads.recentPhoto],
      previewLimit: 2
    )
  }
}
