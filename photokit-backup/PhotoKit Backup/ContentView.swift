import SwiftUI

struct ContentView: View {
  @State private var model = BackupModel()

  var body: some View {
    Group {
      if !model.didCompleteOnboarding {
        OnboardingView(model: model)
      } else if model.isSignedIn {
        BackupHomeView(model: model)
      } else {
        ConnectView(model: model)
      }
    }
    .onAppear { model.restore() }
  }
}
