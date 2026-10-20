import SwiftUI

enum BackupFileList: Hashable {
  case pending
  case recent
}

struct FilesView: View {
  @Bindable var model: BackupModel
  @State private var selection: BackupFileList
  @State private var titleProgress: CGFloat = 0

  init(model: BackupModel, list: BackupFileList) {
    self.model = model
    _selection = State(initialValue: list)
  }

  var body: some View {
    fileList
      .background(Color(.systemGroupedBackground))
      .collapsingTitle(compactTitle, progress: $titleProgress)
      .onChange(of: selection) { _, _ in
        titleProgress = 0
      }
      .task(id: selection) {
        await model.prepareFileBrowse(selection)
      }
  }

  private var compactTitle: String {
    switch selection {
    case .pending:
      "Files - Pending"
    case .recent:
      "Files - Recently uploaded"
    }
  }

  private var fileList: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 12) {
          Text("Files")
            .font(.largeTitle.bold())
            .opacity(1 - titleProgress)
          VStack(alignment: .leading, spacing: 6) {
            Picker("Files", selection: $selection) {
              Text("Pending").tag(BackupFileList.pending)
              Text("Recently uploaded").tag(BackupFileList.recent)
            }
            .pickerStyle(.segmented)
            Group {
              if selection == .pending {
                RisingCount(value: totalCount) { "\($0) Total" }
              } else {
                Text("\(totalCount) Total")
              }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }

      Section {
        if rows.isEmpty {
          emptyState
        } else {
          ForEach(rows) { item in
            UploadRow(item: item)
              .onAppear {
                guard item.id == rows.last?.id, hasMore else { return }
                Task { await model.loadNextFilePage(selection) }
              }
          }
        }
        if showsLoading {
          LoadingLabel()
        }
      }
    }
    .id(selection)
    .contentMargins(.top, 0, for: .scrollContent)
    .listSectionMargins(.top, 0)
    .listSectionSpacing(8)
    .refreshable {
      await model.refresh()
      await model.prepareFileBrowse(selection)
    }
  }

  private var rows: [ListedUpload] {
    switch selection {
    case .pending:
      Array(model.pending.prefix(model.browsePendingShown))
    case .recent:
      Array(model.recentRows.prefix(model.browseRecentShown))
    }
  }

  private var hasMore: Bool {
    switch selection {
    case .pending:
      model.browsePendingShown < model.pending.count || !model.pendingIsComplete
    case .recent:
      model.browseRecentShown < model.recentRows.count || model.recentLoaded < model.recentTotal
    }
  }

  private var showsLoading: Bool {
    guard !rows.isEmpty else { return false }
    switch selection {
    case .pending:
      return model.isLoadingPending && model.browsePendingShown >= model.pending.count
        && !model.pendingIsComplete
    case .recent:
      return model.isLoadingMoreRecent
    }
  }

  private var totalCount: Int {
    switch selection {
    case .pending:
      model.pending.count
    case .recent:
      model.recentTotal
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    switch selection {
    case .pending where model.pendingIsComplete:
      Text("Everything in the library is already on the server.")
        .foregroundStyle(.secondary)
    case .pending:
      LoadingLabel()
    case .recent:
      Text("No files in the backup folder yet.")
        .foregroundStyle(.secondary)
    }
  }
}

#Preview("Files") {
  NavigationStack {
    FilesView(model: .preview(), list: .recent)
  }
}

#Preview("Loading next page") {
  let model = BackupModel.preview()
  model.isLoadingMoreRecent = true
  model.recentTotal = 120
  return NavigationStack {
    FilesView(model: model, list: .recent)
  }
}
