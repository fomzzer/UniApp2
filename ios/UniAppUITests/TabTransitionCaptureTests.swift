import XCTest

final class TabTransitionCaptureTests: XCTestCase {
    func testCycleTabs() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UNIAPP_UITEST_SNAPSHOT"] = Fixtures.snapshot
        app.launch()

        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs.firstMatch.waitForExistence(timeout: 20))
        sleep(3)

        // Visit every tab twice so second visits (already loaded tabs) are recorded too.
        for index in [1, 2, 3, 0, 1, 2, 3, 0, 2, 0] {
            tabs.element(boundBy: index).tap()
            sleep(2)
        }
    }
}
