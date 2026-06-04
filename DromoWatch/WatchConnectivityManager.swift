import Foundation
import WatchConnectivity

/// WCSession wiring shared in spirit with the iPhone side (Section 10.1). Phase 0 stub.
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    private override init() { super.init() }
    // TODO(Phase 4): activate WCSession and decode live session payloads.
}
