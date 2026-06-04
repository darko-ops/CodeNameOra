import SwiftUI

/// Watch HUD: pace, BPM, gap, distance, time (Section 10.2). Phase 0 stub.
struct WatchSessionView: View {
    @StateObject private var vm = WatchViewModel()
    var body: some View {
        VStack(spacing: 4) {
            Text("Dromo").font(.system(size: 20, weight: .black, design: .rounded))
            Text("\(Int(vm.currentBPM)) BPM")
                .font(.system(size: 12)).foregroundColor(.gray)
        }
    }
}
