import XCTest

final class LapCoachMobileAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchScreenshot() throws {
        let app = XCUIApplication()
        app.launch()

        let title = app.staticTexts["Lap Coach"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "launch-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
