import SwiftUI
import UIKit

struct SettingsView: View {
  @Bindable var model: BackupModel

  var body: some View {
    NavigationStack {
      Form {
        Section {
          PreferenceToggle(
            title: "Require Wi-Fi",
            systemImage: "wifi",
            detail: model.requireWifi
              ? "Background uploads run only on Wi-Fi, not on mobile data. Fast Backup starts only while this iPhone is on Wi-Fi."
              : "Background uploads and Fast Backup can use Wi-Fi or mobile data.",
            isOn: Binding(
              get: { model.requireWifi },
              set: { model.setRequireWifi($0) }
            )
          )
          PreferenceToggle(
            title: "Live Photo movies",
            systemImage: "livephoto",
            detail:
              "Include the movie paired with each Live Photo. Standalone videos always upload, even when this is off.",
            isOn: Binding(
              get: { model.uploadLivePhotoMovies },
              set: { model.setUploadLivePhotoMovies($0) }
            )
          )
          PreferenceStepper(
            title: "Concurrent uploads",
            systemImage: "square.stack.3d.up",
            detail: concurrencyDetail,
            value: Binding(
              get: { model.fastBackupConcurrency },
              set: { model.setFastBackupConcurrency($0) }
            ),
            range: 1...BackupSettings.fastBackupConcurrencyLimit
          )
        } header: {
          Text("Backup preferences")
        }

        Section {
          PreferenceToggle(
            title: "Notifications",
            systemImage: "bell",
            detail: model.notificationAuthorization == .denied
              ? "Notifications are off for PhotoKit Backup in iOS Settings."
              : "Get a summary when files finish uploading, and a notice when one fails.",
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
        }

        Section("Your server") {
          HStack(spacing: 12) {
            IconBadge(systemImage: "server.rack")
            ServerStatusRow(
              reachable: model.serverReachable,
              address: model.serverField,
              showsStatus: true
            )
          }
        }

        Section {
          Button(role: .destructive) {
            model.signOut()
          } label: {
            Text("Disconnect")
              .frame(maxWidth: .infinity)
          }
        }
      }
      .navigationTitle("Settings")
      .task { await model.refreshNotificationAuthorization() }
    }
  }

  private var concurrencyDetail: String {
    let count = model.fastBackupConcurrency
    let files = count == 1 ? "1 file" : "\(count) files"
    return "Fast Backup uploads \(files) at the same time."
  }
}

private struct PreferenceToggle: View {
  var title: String
  var systemImage: String
  var detail: String
  @Binding var isOn: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(isOn: $isOn) {
        Label {
          Text(title)
        } icon: {
          IconBadge(systemImage: systemImage)
        }
      }
      Text(detail)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}

private struct PreferenceStepper: View {
  var title: String
  var systemImage: String
  var detail: String
  @Binding var value: Int
  var range: ClosedRange<Int>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Stepper(value: $value, in: range) {
        Label {
          Text(title)
        } icon: {
          IconBadge(systemImage: systemImage)
        }
      }
      Text(detail)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}

#Preview("Settings") {
  SettingsView(model: .preview())
}
