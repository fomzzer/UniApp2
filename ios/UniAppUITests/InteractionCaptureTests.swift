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

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons["BackButton"]
        if back.exists {
            back.tap()
        } else {
            app.swipeRight()
        }
    }

    func testMailFlow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UNIAPP_UITEST_SNAPSHOT"] = Fixtures.snapshot
        app.launchEnvironment["UNIAPP_UITEST_MAIL"] = "1"
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-settings.language", "ru"]
        app.launch()

        let mailButton = app.buttons["home.mail"]
        XCTAssertTrue(mailButton.waitForExistence(timeout: 20))
        sleep(2)
        mailButton.tap()

        let password = app.secureTextFields["mail.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["mail.username"].value as? String, "ivan@tu-sofia.bg")
        sleep(2)
        password.tap()
        password.typeText("123456")
        app.buttons["mail.signIn"].tap()

        let row = app.buttons["mail.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(3)
        app.buttons.matching(identifier: "mail.row").element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["mail.attachment"].waitForExistence(timeout: 10))
        sleep(3)
        goBack(app)
        sleep(2)
        app.buttons.matching(identifier: "mail.row").element(boundBy: 0).tap()
        sleep(3)
        goBack(app)
        sleep(2)
        app.swipeUp()
        sleep(2)
        app.swipeDown()
        sleep(2)
        app.navigationBars.staticTexts.firstMatch.tap()
        sleep(2)
    }

    func testOpenSchedule() throws {
        let app = launch(signedIn: true)
        let open = app.buttons["home.openSchedule"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        sleep(3)
        app.swipeUp()
        sleep(2)
        open.press(forDuration: 1.2)
        sleep(3)
    }
}
