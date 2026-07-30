import SwiftUI

/// Greyscale appearance for `Picker(.segmented)`, applied app-wide per the handoff:
/// track `oraSurface` with a hairline, selected segment `oraSurfaceElevated`, unselected
/// text `oraTextMuted`.
///
/// `UISegmentedControl` has no SwiftUI styling hook for its track or selection, so this
/// sets the UIKit appearance proxy once at launch rather than per-view. Call
/// `DromoAppearance.apply()` from the app entry point.
enum DromoAppearance {
    static func apply() {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(Color.oraSurfaceElevated)
        segmented.backgroundColor = UIColor(Color.oraSurface)
        segmented.setTitleTextAttributes([
            .foregroundColor: UIColor(Color.oraTextMuted),
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
        ], for: .normal)
        segmented.setTitleTextAttributes([
            .foregroundColor: UIColor(Color.oraTextPrimary),
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        ], for: .selected)

        // The wheel pickers on session setup read against oraSurface, not the default
        // grouped-table grey.
        UIDatePicker.appearance().backgroundColor = .clear

        // Nav bars: oraSurface with a hairline bottom, matching the site's header.
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Color.oraSurface)
        nav.shadowColor = UIColor(Color.oraBorder)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Color.oraTextPrimary)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.oraTextPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}
