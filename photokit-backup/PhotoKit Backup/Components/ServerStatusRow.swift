import SwiftUI

struct ServerStatusRow: View {
  var reachable: Bool?
  var address: String
  var showsStatus: Bool

  var body: some View {
    Group {
      if showsStatus {
        VStack(alignment: .leading, spacing: 2) {
          Text(address.isEmpty ? "No server" : address)
          HStack(spacing: 6) {
            Image(systemName: "circle.fill")
              .font(.system(size: 7))
              .foregroundStyle(color)
            Text(status)
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
      } else {
        HStack(spacing: 8) {
          Image(systemName: "circle.fill")
            .font(.system(size: 8))
            .foregroundStyle(color)
          Text(address.isEmpty ? "No server" : address)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(address), \(status)")
  }

  private var status: String {
    switch reachable {
    case true:
      "Connected"
    case false:
      "Not connected"
    case nil:
      "Checking"
    }
  }

  private var color: Color {
    switch reachable {
    case true:
      .green
    case false:
      .red
    case nil:
      .secondary
    }
  }
}

#Preview("Connected") {
  ServerStatusRow(reachable: true, address: "http://192.168.1.20:8080", showsStatus: true)
    .padding()
}

#Preview("Not connected") {
  ServerStatusRow(reachable: false, address: "http://192.168.1.20:8080", showsStatus: false)
    .padding()
}
