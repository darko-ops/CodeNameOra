import XCTest

/// Phase 0 launch smoke test.
final class DromoLaunchUITests: XCTestCase {
    func test_appLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Dromo"].waitForExistence(timeout: 10))
    }
}

/// Drives the full demo flow: Connect Spotify → Setup → Active session, and
/// verifies the music-coaching status reacts to pace. Captures a screenshot at
/// each stage (exported from the result bundle for visual verification).
final class DromoFlowUITests: XCTestCase {

    func test_connectSetupAndAdaptiveSession() {
        let app = XCUIApplication()
        app.launch()

        // 1) Connect Spotify (mock auth).
        let connect = app.buttons["Connect Spotify"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5), "Connect button missing")
        connect.tap()

        // 2) Setup screen.
        let start = app.buttons["Start run"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "Setup screen not reached")
        snapshot(app, "01-setup")
        start.tap()

        // 3) Active HUD — after the 3-2-1 countdown, on-target reads ON PACE.
        let onPace = app.staticTexts["ON PACE"]
        XCTAssertTrue(onPace.waitForExistence(timeout: 12), "Active HUD / ON PACE not shown")
        snapshot(app, "02-active-onpace")

        // 4) Slow the (simulated) runner down → Dromo should switch to PUSH.
        let slower = app.buttons["Run slower"]
        if slower.waitForExistence(timeout: 3) {
            for _ in 0..<7 { slower.tap() }
        }
        let push = app.staticTexts["PUSH"]
        XCTAssertTrue(push.waitForExistence(timeout: 18), "Did not reach PUSH after slowing down")
        snapshot(app, "03-active-push")

        // 5) End the run → post-run summary with chart + export.
        app.buttons["End"].tap()
        let complete = app.staticTexts["Run complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 6), "Summary screen not shown")
        XCTAssertTrue(app.staticTexts["PACE vs BPM"].waitForExistence(timeout: 3), "Chart missing")
        XCTAssertTrue(app.staticTexts["EXPORT"].exists, "Export section missing")
        // The row text is absorbed into the button's accessibility label.
        let strava = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Strava")).firstMatch
        let health = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Apple Health")).firstMatch
        XCTAssertTrue(strava.exists, "Strava export row missing")
        XCTAssertTrue(health.exists, "Health export row missing")
        snapshot(app, "04-summary")

        // 6) Open History → the run we just finished is persisted (GRDB).
        app.buttons["View history"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), "History not shown")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5), "Saved run not listed")
        snapshot(app, "05-history")

        // 7) Open its detail → reconstructed pace/BPM chart.
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["PACE vs BPM"].waitForExistence(timeout: 5), "Detail chart missing")
        snapshot(app, "06-detail")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
