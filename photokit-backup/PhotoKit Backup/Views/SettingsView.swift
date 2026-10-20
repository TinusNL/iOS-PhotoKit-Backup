import SwiftUI
import UIKit

struct SettingsView: View {
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
            )
          )
        } footer: {
          Text(
            "A Live Photo is stored as the original still and a movie with the same name, such as IMG_2456.HEIC and IMG_2456.MOV. Standalone videos are always uploaded."
          )
        }

        Section {
          Toggle(
            "Notifications",
            isOn: Binding(
              get: { model.notificationsEnabled },
              set: { enabled in Task { await model.setNotificationsEnabled(enabled) } }
            )
          )
          if model.notificationAuthorization == .denied {
            Button("Open iOS Settings") {
              guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
              UIApplication.shared.open(url)
            }
          }
        } footer: {
          Text(
            model.notificationAuthorization == .denied
              ? "Notifications are off for PhotoKit Backup in iOS Settings."
              : "A summary appears when files finish uploading, and when an upload fails."
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
      .task { await model.refreshNotificationAuthorization() }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

#Preview("Settings") {
  SettingsView(model: .preview())
}
