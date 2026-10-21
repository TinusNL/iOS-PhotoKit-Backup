import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var model: BackupModel

  init() {
    _model = State(initialValue: BackupModel())
  }

  init(model: BackupModel) {
    _model = State(initialValue: model)
  }

  var body: some View {
    Group {
      if model.isSignedIn {
        BackupTabView(model: model)
      } else {
        NavigationStack {
          if model.didCompleteOnboarding {
            ConnectView(model: model)
          } else {
            OnboardingView(model: model)
          }
        }
      }
    }
    .onAppear { model.restore() }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .background:
        model.notifyFastBackupNeedsAppOpen()
      case .active:
        model.clearFastBackupNeedsAppOpenNotice()
      default:
        break
      }
    }
  }
}

struct BackupTabView: View {
  @Bindable var model: BackupModel

  var body: some View {
    TabView {
      Tab("Backup", systemImage: "icloud") {
        BackupHomeView(model: model)
      }
      Tab("Settings", systemImage: "slider.horizontal.3") {
        SettingsView(model: model)
      }
    }
  }
}

#Preview("Welcome") {
  ContentView(model: previewModel(onboarded: false, signedIn: false))
}

#Preview("Connect flow") {
  ContentView(model: previewModel(onboarded: true, signedIn: false))
}

#Preview("Backup") {
  ContentView(model: .preview())
}

#Preview("Tabs") {
  BackupTabView(model: .preview())
}

private func previewModel(onboarded: Bool, signedIn: Bool) -> BackupModel {
  let model = BackupModel()
  model.isPreview = true
  model.didCompleteOnboarding = onboarded
  model.isSignedIn = signedIn
  return model
}
