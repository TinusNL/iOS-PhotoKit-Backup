import SwiftUI
import UIKit

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
    .onAppear {
      model.restore()
      model.updateScreenAwake()
      if model.isSignedIn {
        model.loadIfNeeded()
      }
    }
    .onChange(of: model.fastBackupPhase) { _, _ in
      model.updateScreenAwake()
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .inactive, .background:
        model.notifyFastBackupNeedsAppOpen()
      case .active:
        model.clearFastBackupNeedsAppOpenNotice()
        model.updateScreenAwake()
      @unknown default:
        break
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
    ) { _ in
      model.notifyFastBackupNeedsAppOpen()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
    ) { _ in
      model.notifyFastBackupNeedsAppOpen()
    }
  }
}

enum BackupTab: Hashable {
  case backup
  case settings
}

struct BackupTabView: View {
  @Bindable var model: BackupModel

  var body: some View {
    TabView(selection: $model.selectedTab) {
      Tab("Backup", systemImage: "icloud", value: BackupTab.backup) {
        BackupHomeView(model: model)
      }
      Tab("Settings", systemImage: "slider.horizontal.3", value: BackupTab.settings) {
        SettingsView(model: model)
      }
    }
    .task { model.loadIfNeeded() }
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
