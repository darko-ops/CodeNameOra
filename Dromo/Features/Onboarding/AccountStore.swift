import Foundation
import CryptoKit

/// Local-only account store (mock auth). Persists accounts and the signed-in
/// session on-device so the create-account / sign-in UX is fully functional
/// without a backend. This is a deliberate stand-in for real auth — the surface
/// (`createAccount` / `signIn` / `signOut` / `currentEmail`) is what a Supabase
/// implementation would expose too, so it can be swapped in behind this API later.
///
/// Passwords are never stored in plaintext: only a SHA-256 hash is kept. (For a
/// real backend this would move server-side with a proper KDF — this is enough to
/// avoid plaintext at rest in a local mock.)
@MainActor
final class AccountStore: ObservableObject {

    /// The email of the currently signed-in account, or nil when signed out.
    @Published private(set) var currentEmail: String?

    var isSignedIn: Bool { currentEmail != nil }

    private let defaults: UserDefaults
    private let accountsKey = "dromo.accounts"        // [email: passwordHash]
    private let sessionKey = "dromo.session.email"    // signed-in email (restored on launch)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.currentEmail = defaults.string(forKey: sessionKey)
    }

    enum AuthError: LocalizedError, Equatable {
        case invalidEmail
        case weakPassword
        case emailTaken
        case noSuchAccount
        case wrongPassword

        var errorDescription: String? {
            switch self {
            case .invalidEmail:  return "Enter a valid email address."
            case .weakPassword:  return "Password must be at least 6 characters."
            case .emailTaken:    return "An account already exists for this email. Sign in instead."
            case .noSuchAccount: return "No account found for this email. Create one first."
            case .wrongPassword: return "Incorrect password. Try again."
            }
        }
    }

    /// Create a new local account and sign in. Throws on invalid input or a duplicate.
    func createAccount(email: String, password: String) throws {
        let email = normalize(email)
        try validate(email: email, password: password)

        var accounts = storedAccounts()
        guard accounts[email] == nil else { throw AuthError.emailTaken }
        accounts[email] = hash(password)
        save(accounts)
        beginSession(email)
    }

    /// Sign in to an existing local account. Throws if missing or the password is wrong.
    func signIn(email: String, password: String) throws {
        let email = normalize(email)
        guard !email.isEmpty else { throw AuthError.invalidEmail }

        let accounts = storedAccounts()
        guard let stored = accounts[email] else { throw AuthError.noSuchAccount }
        guard stored == hash(password) else { throw AuthError.wrongPassword }
        beginSession(email)
    }

    func signOut() {
        defaults.removeObject(forKey: sessionKey)
        currentEmail = nil
    }

    // MARK: - Internals

    private func validate(email: String, password: String) throws {
        // Deliberately lightweight — enough to catch obvious mistakes in a local mock.
        guard email.contains("@"), email.contains("."), email.count >= 5 else {
            throw AuthError.invalidEmail
        }
        guard password.count >= 6 else { throw AuthError.weakPassword }
    }

    private func beginSession(_ email: String) {
        defaults.set(email, forKey: sessionKey)
        currentEmail = email
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func hash(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(password.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func storedAccounts() -> [String: String] {
        defaults.dictionary(forKey: accountsKey) as? [String: String] ?? [:]
    }

    private func save(_ accounts: [String: String]) {
        defaults.set(accounts, forKey: accountsKey)
    }
}
