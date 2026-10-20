import Photos
import SwiftUI

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
          if model.pending.isEmpty {
            Text("Everything in the library is already on the server.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(model.pending) { item in
              VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                Text(item.relativePath)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text("Still to upload (\(model.pending.count))")
        }

        Section {
          if model.recent.isEmpty {
            Text("No files in the backup folder yet.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(model.recent) { file in
              VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                Text(file.relativePath)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text(byteCount(file.bytes))
                  .font(.caption)
                  .foregroundStyle(.secondary)
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
