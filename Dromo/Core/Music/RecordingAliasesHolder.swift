import Foundation
import DromoCore

/// The app-wide alias map, refreshed by `AppCoordinator` whenever sources change.
///
/// Most consumers get aliases injected (the live session, the coverage card). This
/// exists for the ones constructed with no arguments long before any source connects
/// — `NowPlayingController` in `RootView` — which need the CURRENT map at read time,
/// not whatever existed when they were built.
@MainActor
enum RecordingAliasesHolder {
    static var current = RecordingAliases()
}
