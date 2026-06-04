import Foundation

/// Equal-power crossfade gains. Using sine/cosine keeps the summed acoustic
/// power constant across the blend, avoiding the mid-fade dip you get from a
/// naive linear crossfade. Pure and isolated so it can be unit-tested.
enum CrossfadeCurve {
    /// For progress `t` in [0, 1]: outgoing fades 1→0, incoming fades 0→1, with
    /// outgoing² + incoming² == 1 at every point.
    static func gains(progress t: Double) -> (outgoing: Double, incoming: Double) {
        let clamped = min(1, max(0, t))
        let angle = clamped * .pi / 2
        return (outgoing: cos(angle), incoming: sin(angle))
    }
}
