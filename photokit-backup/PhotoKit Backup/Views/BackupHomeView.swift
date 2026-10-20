import Photos
import SwiftUI

struct BackupHomeView: View {
  @Bindable var model: BackupModel
  @State private var showingSettings = false

  var body: some View {
    NavigationStack {
      List {
        if model.photoStatus != .authorized {
          PhotoAccessSection {
            await model.requestPhotoAccess()
          }
        }

        if let statusMessage = model.statusMessage {
          StatusMessageSection(message: statusMessage)
        }

        PendingUploadsSection(
          items: model.pending,
          shown: model.pendingShown,
          isLoading: model.isLoadingPending,
          isComplete: model.pendingIsComplete,
          loadMore: { model.loadMorePending() }
        )

        RecentUploadsSection(
          rows: model.recentRows,
          loaded: model.recentLoaded,
          total: model.recentTotal,
          isLoadingMore: model.isLoadingMoreRecent,
          loadMore: { await model.loadMoreRecent() }
        )
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
}

#Preview("Signed in") {
  BackupHomeView(model: .preview())
}

#Preview("Needs photo access") {
  BackupHomeView(model: .preview(photoStatus: .notDetermined))
}
