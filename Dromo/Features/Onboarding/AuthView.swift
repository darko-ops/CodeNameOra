import SwiftUI

/// App entry — create an account or sign in. Local mock auth (see `AccountStore`):
/// no network, credentials stored on-device. On success the coordinator advances to
/// the main tabs and presents the "Add your music" popup. Real auth (e.g. Supabase)
/// can be swapped in behind `AppCoordinator.authenticate` without changing this view.
struct AuthView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    enum Mode {
        case signIn, createAccount

        var title: String { self == .signIn ? "Welcome back" : "Create your account" }
        var cta: String { self == .signIn ? "Sign In" : "Create Account" }
        var togglePrompt: String {
            self == .signIn ? "New to Dromo?" : "Already have an account?"
        }
        var toggleAction: String { self == .signIn ? "Create one" : "Sign in" }
        var toggled: Mode { self == .signIn ? .createAccount : .signIn }
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !busy
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.sm) {
                Text("Dromo")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.oraTextPrimary)
                Text("Run to the beat. Hit your pace.")
                    .font(.system(size: 15))
                    .foregroundColor(.oraTextSecondary)
            }

            VStack(spacing: Spacing.md) {
                Text(mode.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.oraTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                field("Email", text: $email, field: .email,
                      keyboard: .emailAddress, content: .username, secure: false)
                field("Password", text: $password, field: .password,
                      keyboard: .default,
                      content: mode == .signIn ? .password : .newPassword, secure: true)

                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.oraDestructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    HStack(spacing: Spacing.sm) {
                        if busy { ProgressView().tint(.black) }
                        Text(busy ? "Please wait…" : mode.cta)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSubmit ? Color.zoneSteady : Color.zoneSteady.opacity(0.4))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSubmit)
            }

            HStack(spacing: Spacing.xs) {
                Text(mode.togglePrompt)
                    .foregroundColor(.oraTextSecondary)
                Button(mode.toggleAction) {
                    withAnimation { mode = mode.toggled; error = nil }
                }
                .foregroundColor(.zoneSteady)
                .fontWeight(.semibold)
            }
            .font(.system(size: 14))

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.screen)
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, field: Field,
                       keyboard: UIKeyboardType, content: UITextContentType,
                       secure: Bool) -> some View {
        Group {
            if secure {
                SecureField("", text: text, prompt: prompt(placeholder))
            } else {
                TextField("", text: text, prompt: prompt(placeholder))
            }
        }
        .focused($focused, equals: field)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(keyboard)
        .textContentType(content)
        .foregroundColor(.oraTextPrimary)
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(focused == field ? Color.zoneSteady : .clear, lineWidth: 1)
        )
        .submitLabel(field == .email ? .next : .go)
        .onSubmit {
            if field == .email { focused = .password } else { submit() }
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundColor(.oraTextMuted)
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        error = nil
        busy = true
        // Local mock auth is synchronous; the brief async hop keeps the spinner honest
        // and matches where a real network call would sit.
        Task {
            let result = coordinator.authenticate(
                create: mode == .createAccount, email: email, password: password)
            busy = false
            if case .failure(let err) = result {
                error = err.localizedDescription
            }
        }
    }
}
