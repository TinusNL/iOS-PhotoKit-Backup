import SwiftUI

struct CollapsingTitleModifier: ViewModifier {
  var title: String
  @Binding var progress: CGFloat

  /// A small scroll does nothing, so the fade does not start on the first nudge.
  private static let lead: CGFloat = 20
  /// Distance of the fade after that lead. Longer than the old 36pt ramp.
  private static let distance: CGFloat = 96

  func body(content: Content) -> some View {
    content
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(title)
            .font(.headline)
            .opacity(progress)
        }
      }
      .scrollEdgeEffectHidden(true, for: .top)
      .toolbarBackground(
        Color(.systemGroupedBackground).opacity(progress),
        for: .navigationBar
      )
      .toolbarBackgroundVisibility(.visible, for: .navigationBar)
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
        let traveled = max(0, scrolled - Self.lead)
        let t = min(1, traveled / Self.distance)
        // Slow at the start, so the first change is small and the fade continues.
        return t * t * (3 - 2 * t)
      } action: { _, newValue in
        progress = newValue
      }
  }
}

extension View {
  func collapsingTitle(_ title: String, progress: Binding<CGFloat>) -> some View {
    modifier(CollapsingTitleModifier(title: title, progress: progress))
  }
}
