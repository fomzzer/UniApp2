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

    private func edgeSwipe(_ app: XCUIApplication) {
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        edge.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0)
    }

    func testSwipeBackAbout() throws {
        let app = launch(signedIn: true)
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons.element(boundBy: 3).tap()
        let about = app.buttons["profile.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        for _ in 0..<6 where !about.isHittable {
            app.swipeUp()
        }
        about.tap()
        sleep(2)
        edgeSwipe(app)
        sleep(2)
        XCTAssertTrue(about.isHittable, "about swipe back: " + tree(app))
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["nav.back"]
        if back.exists {
            back.tap()
        } else {
            app.swipeRight()
        }
    }

    private func tree(_ app: XCUIApplication) -> String {
        app.debugDescription
            .split(separator: "\n")
            .filter { $0.contains("Button") || $0.contains("NavigationBar") || $0.contains("StaticText") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " | ")
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
        let second = app.buttons.matching(identifier: "mail.row").element(boundBy: 1)
        XCTAssertTrue(second.isHittable, "hittable: " + tree(app))
        second.tap()
        XCTAssertTrue(app.buttons["mail.attachment"].waitForExistence(timeout: 10), "opened: " + tree(app))
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
        app.buttons["mail.folders"].tap()
        sleep(2)
    }

    func testMailOpenClose() throws {
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
        password.tap()
        password.typeText("123456")
        app.buttons["mail.signIn"].tap()
        XCTAssertTrue(app.buttons["mail.row"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        goBack(app)
        for _ in 0..<2 {
            XCTAssertTrue(mailButton.waitForExistence(timeout: 10))
            sleep(2)
            mailButton.tap()
            XCTAssertTrue(app.buttons["mail.row"].firstMatch.waitForExistence(timeout: 10))
            sleep(2)
            goBack(app)
        }
        XCTAssertTrue(mailButton.waitForExistence(timeout: 10))
        sleep(2)
        mailButton.tap()
        XCTAssertTrue(app.buttons["mail.row"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        edgeSwipe(app)
        sleep(2)
        XCTAssertFalse(app.buttons["nav.back"].exists, "swipe back: " + tree(app))
    }

    func testMailActions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UNIAPP_UITEST_SNAPSHOT"] = Fixtures.snapshot
        app.launchEnvironment["UNIAPP_UITEST_MAIL"] = "1"
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-settings.language", "ru"]
        app.launch()

        let mailButton = app.buttons["home.mail"]
        XCTAssertTrue(mailButton.waitForExistence(timeout: 20))
        mailButton.tap()
        let password = app.secureTextFields["mail.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        password.tap()
        password.typeText("123456")
        app.buttons["mail.signIn"].tap()
        let rows = app.buttons.matching(identifier: "mail.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        sleep(2)

        app.buttons["mail.compose"].tap()
        let to = app.textFields["compose.to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10), "compose: " + tree(app))
        to.tap()
        to.typeText("pgeorgiev@tu-sofia.bg")
        app.textFields["compose.subject"].tap()
        app.textFields["compose.subject"].typeText("Въпрос за курсовата")
        app.textViews["compose.body"].tap()
        app.textViews["compose.body"].typeText("Здравейте, кога е консултацията?")
        sleep(1)
        app.buttons["compose.send"].tap()
        XCTAssertTrue(to.waitForNonExistence(timeout: 10), "compose stayed open: " + tree(app))
        sleep(2)

        let before = rows.count
        rows.element(boundBy: 1).press(forDuration: 1.2)
        let delete = app.buttons["Удалить"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "menu: " + tree(app))
        delete.tap()
        sleep(2)
        XCTAssertEqual(rows.count, before - 1)

        rows.element(boundBy: 0).tap()
        let flag = app.buttons["message.flag"]
        XCTAssertTrue(flag.waitForExistence(timeout: 10))
        flag.tap()
        sleep(1)
        app.buttons["message.reply"].tap()
        let reply = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ответить", "message.reply")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "reply menu: " + tree(app))
        reply.tap()
        XCTAssertTrue(app.textFields["compose.to"].waitForExistence(timeout: 10))
        sleep(2)
        XCTAssertEqual(app.textFields["compose.to"].value as? String, "pgeorgiev@tu-sofia.bg")
        app.buttons["compose.send"].tap()
        XCTAssertTrue(app.textFields["compose.to"].waitForNonExistence(timeout: 10))
        sleep(2)
    }

    func testNativeTimetable() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UNIAPP_UITEST_SNAPSHOT"] = Fixtures.snapshot
        app.launchEnvironment["UNIAPP_UITEST_TIMETABLE"] = TimetableFixture.json
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-settings.language", "ru"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 20))
        sleep(3)
        app.tabBars.buttons.element(boundBy: 2).tap()
        let now = app.descendants(matching: .any)["timetable.now"].firstMatch
        XCTAssertTrue(now.waitForExistence(timeout: 30), "timetable: " + tree(app))
        sleep(2)
        let chip = app.buttons.matching(identifier: "timetable.group").matching(NSPredicate(format: "label == %@", "37б")).firstMatch
        if chip.waitForExistence(timeout: 5) {
            chip.tap()
            sleep(2)
        }
        let days = app.buttons.matching(identifier: "timetable.day")
        for index in [0, 1, 3] where index < days.count {
            days.element(boundBy: index).tap()
            sleep(2)
        }
        app.segmentedControls.buttons["Чётная"].firstMatch.tap()
        sleep(2)
        app.swipeUp()
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
