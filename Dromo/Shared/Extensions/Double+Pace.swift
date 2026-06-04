import Foundation

extension Double {
    /// Formats a pace in seconds/km as "m:ss/km", e.g. 360 -> "6:00/km".
    var paceFormatted: String {
        guard self > 0 else { return "--:--/km" }
        let total = Int(self.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }
}
