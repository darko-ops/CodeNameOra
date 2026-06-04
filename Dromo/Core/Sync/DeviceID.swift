import Foundation

/// A stable, anonymous per-install id used as the `client_id` for objective feedback
/// (Phase 6 A1 anti-poisoning: one vote per client). It identifies an install, not a
/// person — no PII, and it never identifies the user to the Global Track Table.
enum DeviceID {
    private static let key = "dromo.clientID"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
