import SwiftUI

/// Home tab — intentionally blank for now (placeholder). Future: dashboard / recent
/// activity / quick-start.
struct HomeView: View {
    var body: some View {
        ZStack {
            Color.oraBackground.ignoresSafeArea()
            Text("Dromo")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.oraTextMuted)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    HomeView()
}
