import XCTest

final class InteractionCaptureTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(signedIn: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        if signedIn {
            app.launchEnvironment["UNIAPP_UITEST_SNAPSHOT"] = Fixtures.snapshot
        }
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-settings.language", "ru"]
        app.launch()
        return app
    }

    func testHoldAboutTile() throws {
        let app = launch(signedIn: true)
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 20))
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

    func testSecretReveal() throws {
        let app = launch(signedIn: false)
        let secret = app.secureTextFields["login.secret"]
        XCTAssertTrue(secret.waitForExistence(timeout: 20))
        secret.tap()
        secret.typeText("481516")
        sleep(1)

        let reveal = app.buttons["login.reveal"]
        reveal.tap()
        sleep(1)
        let shown = app.textFields["login.secret"]
        XCTAssertTrue(shown.waitForExistence(timeout: 3))
        XCTAssertEqual(shown.value as? String, "481516")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        shown.typeText("2")
        XCTAssertEqual(shown.value as? String, "4815162")

        reveal.tap()
        sleep(1)
        XCTAssertTrue(app.secureTextFields["login.secret"].waitForExistence(timeout: 3))
        app.secureTextFields["login.secret"].typeText("3")
        reveal.tap()
        sleep(1)
        XCTAssertEqual(app.textFields["login.secret"].value as? String, "48151623")
        sleep(1)
    }

    func testPasteFromClipboard() throws {
        UIPasteboard.general.string = "121221089"
        let app = launch(signedIn: false)
        let facultyNo = app.textFields["login.facultyNo"]
        XCTAssertTrue(facultyNo.waitForExistence(timeout: 20))
        let paste = app.buttons["login.pasteFacultyNo"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        sleep(1)
        paste.tap()
        sleep(2)
        XCTAssertEqual(facultyNo.value as? String, "121221089")

        UIPasteboard.general.string = "secret42"
        let pasteSecret = app.buttons["login.pasteSecret"]
        XCTAssertTrue(pasteSecret.waitForExistence(timeout: 5))
        pasteSecret.tap()
        sleep(1)
        app.buttons["login.reveal"].tap()
        sleep(1)
        XCTAssertEqual(app.textFields["login.secret"].value as? String, "secret42")
        sleep(1)
    }

    func testOpenSchedule() throws {
        let app = launch(signedIn: true)
        let open = app.buttons["home.openSchedule"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        for _ in 0..<4 where !open.isHittable {
            app.swipeUp()
        }
        sleep(4)
        open.press(forDuration: 0.6)
        sleep(3)
    }
}
