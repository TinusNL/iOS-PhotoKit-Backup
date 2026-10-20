import Photos
import SwiftUI

struct BackupHomeView: View {
  @Bindable var model: BackupModel
  @State private var titleProgress: CGFloat = 0

  var body: some View {
    NavigationStack {
      backupList
        .background(Color(.systemGroupedBackground))
        .collapsingTitle("Backup", progress: $titleProgress)
        .navigationDestination(for: BackupFileList.self) { list in
          FilesView(model: model, list: list)
        }
    }
  }

  private var backupList: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 2) {
          Text("Backup")
            .font(.largeTitle.bold())
            .opacity(1 - titleProgress)
          ServerStatusRow(
            reachable: model.serverReachable,
            address: model.serverField,
            showsStatus: false
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .opacity(1 - min(1, titleProgress * 1.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }

      if model.photoStatus != .authorized {
        PhotoAccessSection(waitingCount: waitingCount) {
          await model.requestPhotoAccess()
        }
      }

      if let statusMessage = model.statusMessage {
        StatusMessageSection(message: statusMessage)
      }

      PendingUploadsSection(
        items: model.pending,
        previewLimit: BackupModel.homePendingPreview,
        isLoading: model.isLoadingPending,
        isComplete: model.pendingIsComplete
      )

      RecentUploadsSection(
        rows: model.recentRows,
        previewLimit: BackupModel.homeRecentPreview
      )
    }
    .contentMargins(.top, 0, for: .scrollContent)
    .refreshable { await model.refresh() }
    .task { await model.refresh() }
  }

  private var waitingCount: Int? {
    model.pending.isEmpty ? nil : model.pending.count
  }
}

#Preview("Signed in") {
  BackupHomeView(model: .preview())
}

#Preview("Needs photo access") {
  BackupHomeView(model: .preview(photoStatus: .notDetermined))
}
