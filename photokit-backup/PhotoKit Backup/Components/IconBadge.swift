import SwiftUI

struct IconBadge: View {
  var systemImage: String
  var side: CGFloat = 36

  var body: some View {
    Image(systemName: systemImage)
      .font(side > 44 ? .title2 : .body)
      .foregroundStyle(.tint)
      .frame(width: side, height: side)
      .background(
        Color.accentColor.opacity(0.12),
        in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
      )
  }
}

#Preview("Icon badge") {
  IconBadge(systemImage: "server.rack", side: 52)
    .padding()
}
