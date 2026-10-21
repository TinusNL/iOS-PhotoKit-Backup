import SwiftUI

struct FastBackupCard: View {
  var phase: FastBackupPhase
  var subtitle: String
  var fraction: Double
  var sentBytes: Int64
  var totalBytes: Int64
  var completed: Int
  var total: Int
  var start: () -> Void
  var stop: () -> Void
  var isScanning = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        IconBadge(systemImage: "icloud.and.arrow.up", side: 44)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline)
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if phase == .idle {
        Text(
          "Start a fast backup now to upload large batches of photos and videos faster. Otherwise files will be backed up slowly by iOS in the background."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        if isScanning {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 44)
        } else {
          Button(action: start) {
            Text("Start backup")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }
      } else {
        HStack(alignment: .firstTextBaseline) {
          Text(min(1, max(0, fraction)), format: .percent.precision(.fractionLength(1)))
            .font(.largeTitle.bold())
            .monospacedDigit()
            .foregroundStyle(.tint)
          Spacer(minLength: 8)
          if totalBytes > 0 {
            Text("\(ByteText.file(Int(sentBytes))) of \(ByteText.file(Int(totalBytes)))")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        ProgressView(value: min(1, max(0, fraction)))
          .tint(.accentColor)
        HStack(alignment: .center) {
          Text(FastBackupCopy.completedLine(done: completed, total: total))
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer(minLength: 8)
          Button(action: stop) {
            Label("Stop backup", systemImage: "stop.fill")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.tint)
          }
          .buttonStyle(.borderless)
        }
      }
    }
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var title: String {
    switch phase {
    case .idle:
      "Ready to back up"
    case .running:
      "Backup in progress"
    }
  }
}

#Preview("Ready") {
  List {
    FastBackupCard(
      phase: .idle,
      subtitle: "2 videos waiting to upload",
      fraction: 0,
      sentBytes: 0,
      totalBytes: 0,
      completed: 0,
      total: 2,
      start: {},
      stop: {}
    )
    .listRowBackground(Color.accentColor.opacity(0.08))
  }
}

#Preview("In progress") {
  List {
    FastBackupCard(
      phase: .running,
      subtitle: "Uploading 2 videos",
      fraction: 0.45,
      sentBytes: 180_000_000,
      totalBytes: 400_000_000,
      completed: 0,
      total: 2,
      start: {},
      stop: {}
    )
    .listRowBackground(Color.accentColor.opacity(0.08))
  }
}
