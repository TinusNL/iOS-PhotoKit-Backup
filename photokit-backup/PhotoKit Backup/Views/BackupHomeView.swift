import Photos
import SwiftUI

struct BackupHomeView: View {
  @Bindable var model: BackupModel

  var body: some View {
    NavigationStack {
      backupList
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: BackupFileList.self) { list in
          FilesView(model: model, list: list)
        }
    }
  }

  private var backupList: some View {
    List {
      Section {
        ServerStatusRow(
          reachable: model.serverReachable,
          address: model.serverField,
          showsStatus: false
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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

      if model.showsFastBackup {
        Section {
          FastBackupCard(
            phase: model.fastBackupPhase,
            subtitle: model.fastBackupSubtitle,
            fraction: model.fastBackupFraction,
            sentBytes: model.fastBackupSent,
            totalBytes: model.fastBackupShownTotalBytes,
            completed: model.fastBackupCompleted,
            total: model.fastBackupTotal,
            start: { model.startFastBackup() },
            stop: { model.stopFastBackup() },
            needsWifi: model.fastBackupNeedsWifi,
            connectWifi: { model.showSettings() },
            isScanning: !model.pendingIsComplete
          )
          .listRowBackground(Color.accentColor.opacity(0.08))
        }
      }

      PendingUploadsSection(
        items: model.pending,
        previewLimit: BackupModel.homePendingPreview,
        isLoading: model.isLoadingPending,
        isComplete: model.pendingIsComplete,
        transfers: model.fastItemProgress
      )

      RecentUploadsSection(
        rows: model.recentRows,
        previewLimit: BackupModel.homeRecentPreview
      )
    }
    .contentMargins(.top, 0, for: .scrollContent)
    .listSectionSpacing(8)
    .padding(.top, -20)
    .refreshable { await model.refresh() }
    .onAppear { model.loadIfNeeded() }
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

#Preview("Backup in progress") {
  BackupHomeView(model: .previewInProgress())
}
