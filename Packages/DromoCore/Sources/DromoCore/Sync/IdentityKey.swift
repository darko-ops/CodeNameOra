import Foundation

/// A track's identity for the Global Track Table (ARCHITECTURE §6): ISRC preferred,
/// acoustic fingerprint fallback. Never artist+title.
public struct IdentityKey: Codable, Equatable, Sendable {
    public var isrc: String?
    public var fingerprint: String?

    public init(isrc: String? = nil, fingerprint: String? = nil) {
        self.isrc = isrc
        self.fingerprint = fingerprint
    }

    public var isValid: Bool { isrc != nil || fingerprint != nil }
}

/// A track in the user's library, reduced to its local id + identity key. This is
/// all the sync layer needs — no titles, nothing personal leaves the device (§5).
public struct SyncItem: Sendable, Equatable {
    public let localID: String
    public let key: IdentityKey

    public init(localID: String, key: IdentityKey) {
        self.localID = localID
        self.key = key
    }
}
