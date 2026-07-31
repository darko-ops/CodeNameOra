import XCTest

/// Cover for the places `AppCoordinator` is read across a presentation boundary.
///
/// A sheet, and a `NavigationLink` destination declared inside a `.toolbar`, only
/// inherit the environment of the view the modifier is attached to. Where the object
/// is injected below that point, the destination traps at render with
/// "No ObservableObject of type AppCoordinator found" — a crash, not a blank screen.
final class CoordinatorEnvironmentUITests: XCTestCase {

    /// Launches already signed in. `AccountStore` restores its session from
    /// UserDefaults, and launch arguments are a highest-priority defaults domain, so
    /// this skips the auth screen without a debug hook in app code. (Driving auth for
    /// real isn't possible here: the create-account field is `.newPassword`, so iOS
    /// strong-password AutoFill intercepts typing.)
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-dromo.session.email", "uitest@dromo.test"]
        app.launch()
        return app
    }

    /// The You-tab toolbar link into `MusicIntegrationsView`, which reads the
    /// coordinator. `LearnedDataView` sits beside it and doesn't, so only this one traps.
    func test_youTabOpensMusicIntegrations() {
        let app = launchSignedIn()

        let you = app.buttons["You"]
        XCTAssertTrue(you.waitForExistence(timeout: 15), "You tab never appeared")
        you.tap()

        let music = app.buttons["Music integrations"]
        XCTAssertTrue(music.waitForExistence(timeout: 8), "Music integrations toolbar item missing")
        music.tap()

        // Give it a beat to render (or trap) before asserting.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground,
                       "App died opening MusicIntegrationsView — coordinator lost across the toolbar")

        let rendered = app.staticTexts["Music"].waitForExistence(timeout: 6)
            || app.buttons.containing(NSPredicate(format: "label CONTAINS 'Apple Music'"))
                .firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(rendered, "MusicIntegrationsView did not render")
    }

    /// The sibling toolbar link, as a control: it needs no environment object, so it
    /// should open whether or not the coordinator propagates.
    func test_youTabOpensLearnedData() {
        let app = launchSignedIn()

        let you = app.buttons["You"]
        XCTAssertTrue(you.waitForExistence(timeout: 15), "You tab never appeared")
        you.tap()

        let brain = app.buttons["What Dromo has learned"]
        XCTAssertTrue(brain.waitForExistence(timeout: 8), "Learned-data toolbar item missing")
        brain.tap()

        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "App died opening LearnedDataView")
    }

    /// The post-sign-in "Add your music" popup. `authenticate` flips
    /// `showingMusicSetup` in the same turn it advances the screen, and the sheet's
    /// `MusicProviderButtons` reads the coordinator — so this exercises the sheet
    /// boundary in `RootView`.
    ///
    /// Signs in for real rather than faking the session, because the popup is only
    /// raised by `authenticate`. The account is seeded through the same defaults keys
    /// `AccountStore` persists (SHA-256 hex of the password), leaving the session key
    /// unset so the app opens on auth.
    func test_signInPresentsMusicSetupSheet() {
        let app = XCUIApplication()
        app.launchArguments = [
            // Sign-in mode marks the field .password, so typing isn't intercepted the
            // way create-account's .newPassword is.
            "-dromo.accounts",
            "{\"uitest@dromo.test\" = \"\(Self.seededPasswordHash)\";}",
            // Force the auth screen. Signing in persists a session to the app
            // container, so without this the test only passes against a pristine
            // install — it would find itself already signed in on the second run.
            "-dromo.session.email", "",
        ]
        app.launch()

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 15), "Email field missing")
        email.tap()
        email.typeText("uitest@dromo.test")

        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 5), "Password field missing")
        password.tap()
        Thread.sleep(forTimeInterval: 0.5)
        password.typeText(Self.seededPassword)

        let signIn = app.buttons["Sign In"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 3) && signIn.isEnabled,
                      "Sign In not tappable — credentials didn't land")
        signIn.tap()

        // Sign-in must land first, or nothing below is meaningful.
        XCTAssertTrue(app.buttons["You"].waitForExistence(timeout: 12),
                      "Sign-in did not reach the tabs")

        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground,
                       "App died presenting the music popup — coordinator lost across the sheet")

        let mixes = app.buttons["Start with Dromo's mixes"]
        let skip = app.buttons["Skip for now"]
        XCTAssertTrue(mixes.waitForExistence(timeout: 8) || skip.waitForExistence(timeout: 2),
                      "Music setup popup never appeared after sign-in")
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Apple Music'"))
            .firstMatch.exists, "MusicProviderButtons did not render inside the popup")
    }

    private static let seededPassword = "dromopw123"
    /// SHA-256 hex of `seededPassword`, matching `AccountStore.hash`.
    private static let seededPasswordHash =
        "56e72e0e3d1ed6cfece47feb90057caea40e094d4ee1e61c75eefcc4439700ed"

    /// The Sound tab reads the coordinator directly (not across a boundary), so it is
    /// a second control: if this fails too, the object never reaches the tabs at all.
    func test_soundTabRenders() {
        let app = launchSignedIn()

        let sound = app.buttons["Sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 15), "Sound tab never appeared")
        sound.tap()

        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "App died opening the Sound tab")
    }
}
