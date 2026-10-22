import XCTest

final class InteractionCaptureTests: XCTestCase {
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UNIAPP_UITEST_SNAPSHOT"] = Fixtures.snapshot
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    func testHoldAboutTile() throws {
        let app = launchSignedIn()
        app.tabBars.buttons.element(boundBy: 3).tap()
        let about = app.buttons["profile.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        for _ in 0..<6 where !about.isHittable {
            app.swipeUp()
        }
        sleep(2)
        about.press(forDuration: 4)
        sleep(2)
    }
}
