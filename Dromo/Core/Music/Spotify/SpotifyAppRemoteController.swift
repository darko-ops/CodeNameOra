import Foundation

#if canImport(SpotifyiOS)
import SpotifyiOS

/// In-app playback control via the Spotify App Remote SDK (Section 6.3).
///
/// This file only compiles once `SpotifyiOS.xcframework` is present and linked
/// (drop it into `Frameworks/` and uncomment the dependency in `project.yml`).
/// Until then `canImport(SpotifyiOS)` is false and the app uses the Web API
/// playback fallback instead — no other code changes.
final class SpotifyAppRemoteController: NSObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {

    private let appRemote: SPTAppRemote
    private var pendingURI: String?

    init(accessToken: String) {
        let configuration = SPTConfiguration(
            clientID: SpotifyConfig.clientID,
            redirectURL: URL(string: SpotifyConfig.redirectURI)!
        )
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .info)
        super.init()
        appRemote.connectionParameters.accessToken = accessToken
        appRemote.delegate = self
    }

    func connect() { appRemote.connect() }
    func disconnect() { appRemote.disconnect() }

    /// Plays a track URI, connecting first if needed.
    func play(trackID: String) {
        let uri = "spotify:track:\(trackID)"
        if appRemote.isConnected {
            appRemote.playerAPI?.play(uri, callback: nil)
        } else {
            pendingURI = uri
            appRemote.connect()
        }
    }

    // MARK: - SPTAppRemoteDelegate

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: nil)
        if let uri = pendingURI {
            appRemote.playerAPI?.play(uri, callback: nil)
            pendingURI = nil
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {}
    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {}

    // MARK: - SPTAppRemotePlayerStateDelegate

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {}
}
#endif
