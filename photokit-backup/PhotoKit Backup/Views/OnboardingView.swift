import SwiftUI

struct OnboardingView: View {
  @Bindable var model: BackupModel

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            "Original photos and videos are backed up to your server. The phone keeps uploading after you leave the app."
          )
        }

        Section {
          LabeledContent("Photos", value: "Whole library")
          LabeledContent("Notifications", value: "When files finish or fail")
        } footer: {
          Text(
            "Photo access is required for background upload. Notifications are a summary when files finish, and a notice when an upload fails."
          )
        }
      }
      .navigationTitle("PhotoKit Backup")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Continue") {
            Task { await model.completeOnboarding() }
          }
          .disabled(model.isWorking)
        }
      }
      .workingOverlay(model.isWorking)
    }
  }
}

#Preview("Onboarding") {
  OnboardingView(model: BackupModel())
}
