import SwiftUI

struct ConnectView: View {
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
          StatusMessageSection(message: statusMessage)
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
      .workingOverlay(model.isWorking)
    }
  }
}

#Preview("Connect") {
  ConnectView(model: BackupModel())
}
