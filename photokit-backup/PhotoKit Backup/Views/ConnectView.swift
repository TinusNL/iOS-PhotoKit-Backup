import SwiftUI

struct ConnectView: View {
  @Bindable var model: BackupModel
  var showsBackButton = false
  @Environment(\.dismiss) private var dismiss

  private var canConnect: Bool {
    !model.serverField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !model.apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if showsBackButton {
          Button {
            dismiss()
          } label: {
            Image(systemName: "chevron.backward")
              .font(.body.weight(.semibold))
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.circle)
        }

        IconBadge(systemImage: "server.rack", side: 52)

        VStack(alignment: .leading, spacing: 8) {
          Text("Connect your server")
            .font(.largeTitle.bold())
          Text("Add your server address and API key to give your originals a place to go.")
            .font(.body)
            .foregroundStyle(.secondary)
        }

        CredentialCard(model: model)

        Text("Use the API key configured on your server.")
          .font(.footnote)
          .foregroundStyle(.secondary)

        if let statusMessage = model.statusMessage {
          Text(statusMessage)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 12)
      .padding(.bottom, 24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Color(.systemGroupedBackground))
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom) {
      Button {
        Task { await model.connect() }
      } label: {
        Text("Connect to server")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!canConnect || model.isWorking)
      .padding(.horizontal, 24)
      .padding(.top, 8)
      .padding(.bottom, 4)
    }
    .workingOverlay(model.isWorking)
  }
}

private struct CredentialCard: View {
  @Bindable var model: BackupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Server address")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      TextField("192.168.1.20:8080", text: $model.serverField)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.URL)
      Divider()
      Text("API key")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      SecureField("Required", text: $model.apiKeyField)
    }
    .padding(16)
    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

#Preview("Connect") {
  NavigationStack {
    ConnectView(model: connectPreviewModel(), showsBackButton: true)
  }
}

private func connectPreviewModel() -> BackupModel {
  let model = BackupModel()
  model.isPreview = true
  model.serverField = "http://192.168.1.20:8080"
  model.apiKeyField = "preview-key"
  return model
}
