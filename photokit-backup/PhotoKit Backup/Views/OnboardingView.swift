import SwiftUI

struct OnboardingView: View {
  @Bindable var model: BackupModel
  @State private var showConnect = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        HStack(spacing: 10) {
          Image("LogoMark")
            .resizable()
            .interpolation(.high)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
          Text("PhotoKit Backup")
            .font(.headline)
        }
        .accessibilityElement(children: .combine)

        WelcomeHero()

        VStack(alignment: .leading, spacing: 8) {
          Text("Your photos.\nYour server.")
            .font(.largeTitle.bold())
          Text("An original home for every memory.")
            .font(.title3)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 22) {
          FeatureRow(
            systemImage: "photo",
            title: "Originals, directly to you",
            detail: "Send original photos and videos to your own server."
          )
          FeatureRow(
            systemImage: "arrow.up",
            title: "Leave the app. Keep uploading.",
            detail: "Background uploads continue after you leave."
          )
          FeatureRow(
            systemImage: "photo.on.rectangle.angled",
            title: "Your whole library, included",
            detail: "Full photo access is required for background uploading."
          )
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 12)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Color(.systemGroupedBackground))
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 10) {
        Button {
          Task {
            await model.requestNotifications()
            showConnect = true
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "arrow.right")
            Text("Get started")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isWorking)
        Text("Connect your server to begin.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 24)
      .padding(.top, 8)
      .padding(.bottom, 4)
    }
    .workingOverlay(model.isWorking)
    .navigationDestination(isPresented: $showConnect) {
      ConnectView(model: model, showsBackButton: true)
    }
  }
}

private struct WelcomeHero: View {
  var body: some View {
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color.accentColor.opacity(0.18))
          .frame(width: 72, height: 84)
          .rotationEffect(.degrees(-8))
          .offset(x: -10, y: 6)
        VStack(spacing: 10) {
          Image(systemName: "sun.max.fill")
          Image(systemName: "mountain.2.fill")
        }
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 96, height: 108)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
      .frame(width: 110, height: 120)
      Image(systemName: "arrow.right")
        .font(.title3)
        .foregroundStyle(.tertiary)
      VStack(spacing: 8) {
        Image(systemName: "server.rack")
          .font(.title2)
          .foregroundStyle(.tint)
        HStack(spacing: 4) {
          Circle()
            .fill(.green)
            .frame(width: 6, height: 6)
          Text("Your server")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      .frame(width: 92, height: 92)
      .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }
}

private struct FeatureRow: View {
  var systemImage: String
  var title: String
  var detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      IconBadge(systemImage: systemImage)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

#Preview("Onboarding") {
  NavigationStack {
    OnboardingView(model: BackupModel())
  }
}

#Preview("Feature row") {
  FeatureRow(
    systemImage: "photo",
    title: "Originals, directly to you",
    detail: "Send original photos and videos to your own server."
  )
  .padding()
}
