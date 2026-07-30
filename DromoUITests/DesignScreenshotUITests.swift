import XCTest

/// Walks the restyled screens and attaches a screenshot of each, so the design-language
/// v2 pass can be checked against the reference. Not an assertion suite — it fails only
/// if a screen can't be reached at all.
final class DesignScreenshotUITests: XCTestCase {

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_captureRestyledScreens() {
        let app = XCUIApplication()
        // Launch already signed in, past the auth screen. See CoordinatorEnvironmentUITests.
        app.launchArguments = ["-dromo.session.email", "design@dromo.test"]
        app.launch()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 20), "Never reached the tabs")
        Thread.sleep(forTimeInterval: 2)   // let the launch reveal settle
        shoot(app, "01-home")

        app.buttons["Go"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "02-session-setup")

        app.buttons["Sound"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "03-sound")

        app.buttons["You"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        shoot(app, "04-you-momentum")

        // Sessions tab of the You screen.
        let sessions = app.buttons["Sessions"]
        if sessions.waitForExistence(timeout: 3) {
            sessions.tap()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "05-you-sessions")
        }

        let music = app.buttons["Music integrations"]
        if music.waitForExistence(timeout: 3) {
            music.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "06-music")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        let brain = app.buttons["What Dromo has learned"]
        if brain.waitForExistence(timeout: 3) {
            brain.tap()
            Thread.sleep(forTimeInterval: 2)
            shoot(app, "07-learned")
        }

        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The live HUD, reached by starting a run from session setup.
    func test_captureLiveHUD() {
        let app = XCUIApplication()
        app.launchArguments = ["-dromo.session.email", "design@dromo.test"]
        app.launch()

        XCTAssertTrue(app.buttons["Go"].waitForExistence(timeout: 20), "Never reached the tabs")
        app.buttons["Go"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        let start = app.buttons["Start run"]
        guard start.waitForExistence(timeout: 5), start.isEnabled else {
            XCTSkip("Start run unavailable — no library in the simulator")
            return
        }
        start.tap()
        Thread.sleep(forTimeInterval: 6)   // past the countdown, into the HUD
        shoot(app, "08-live-hud")
    }
}
