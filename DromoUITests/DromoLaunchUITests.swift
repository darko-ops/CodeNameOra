import XCTest

/// Phase 0 launch smoke test.
final class DromoLaunchUITests: XCTestCase {
    /// The app comes up and puts its own name on screen.
    ///
    /// Matches any element type rather than a `staticText` specifically: the brand
    /// appears as plain text on the auth screen but as the mark-and-wordmark lockup once
    /// signed in, where the visible string is "DROMO" and "Dromo" is the accessibility
    /// label on the element wrapping it. Which of those a launch lands on depends on
    /// whether a session is stored, and this test is about the app starting at all.
    func test_appLaunches() {
        let app = XCUIApplication()
        app.launch()

        let branded = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] 'Dromo'")).firstMatch
        XCTAssertTrue(branded.waitForExistence(timeout: 10),
                      "Launched without showing the app's name anywhere")
        XCTAssertEqual(app.state, .runningForeground)
    }
}

/// Drives a run the way the app actually runs one: set a target, start, coach, end.
///
/// The previous version tested a flow that no longer exists — it opened by tapping
/// "Connect Spotify", which the app stopped offering, and then asserted its way through
/// `ActiveSessionView` and `PostRunSummaryView`. Those are reached only when
/// `AppCoordinator.screen` becomes `.session`, which `startSession()` alone sets, and
/// `startSession()` has no callers: `SessionSetupView` presents `LiveHUDView` as a full
/// screen cover instead. So every assertion after the first was aimed at unreachable
/// code, and the test failed on the first line for an unrelated reason — which is how it
/// stayed red without anyone learning anything from it.
final class DromoFlowUITests: XCTestCase {

    func test_setupAndRun() {
        let app = XCUIApplication()
        // Past the auth screen. Signing in for real isn't drivable here — the
        // create-account field is `.newPassword`, so iOS AutoFill intercepts typing.
        app.launchArguments = ["-dromo.session.email", "flow@dromo.test"]
        app.launch()

        // 1) Session setup.
        XCTAssertTrue(app.buttons["Go"].waitForExistence(timeout: 20), "Never reached the tabs")
        app.buttons["Go"].tap()
        let start = app.buttons["Start run"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "Setup screen not reached")
        XCTAssertTrue(app.staticTexts["Set your target"].exists, "Setup header missing")
        snapshot(app, "01-setup")

        guard start.isEnabled else {
            // No library on this simulator, so there is nothing to pace a run with.
            // Skipping beats asserting against a state the device can't produce.
            XCTSkip("Start run disabled — no music library available here")
            return
        }
        start.tap()

        // 2) The live HUD. Which coaching state shows depends on the simulated pace, so
        //    the assertion is that it is coaching at all, not which way it leans.
        let coaching = app.staticTexts.matching(
            NSPredicate(format: "label IN {'ON PACE', 'SPEED UP', 'EASE'}")).firstMatch
        XCTAssertTrue(coaching.waitForExistence(timeout: 20),
                      "Live HUD never showed a coaching state")
        XCTAssertTrue(app.staticTexts["CADENCE"].exists, "HUD is missing its cadence readout")
        snapshot(app, "02-live-hud")

        // 3) End it. With no track responses recorded the HUD dismisses straight back to
        //    setup rather than presenting the run summary.
        app.buttons["End"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "Ending the run did not return to setup")
        XCTAssertEqual(app.state, .runningForeground)
        snapshot(app, "03-back-to-setup")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
