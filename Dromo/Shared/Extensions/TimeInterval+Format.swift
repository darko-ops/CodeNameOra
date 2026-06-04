import Foundation

extension TimeInterval {
    /// Formats an elapsed interval as "m:ss" (or "h:mm:ss" past an hour).
    var elapsedFormatted: String {
        let t = Int(self)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
