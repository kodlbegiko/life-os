import AppKit
import XCTest

final class LifeOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        NSRunningApplication.runningApplications(withBundleIdentifier: "local.codex.lifeos").forEach { app in
            app.forceTerminate()
        }
    }

    @MainActor
    func testSidebarButtonsNavigateBetweenWorkspaces() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-LifeOSUITestMode")
        app.launch()

        let overviewHeader = app.staticTexts["section-overview-header"]
        XCTAssertTrue(overviewHeader.waitForExistence(timeout: 5))

        let tasksButton = app.buttons["sidebar-button-tasks"]
        XCTAssertTrue(tasksButton.waitForExistence(timeout: 3))
        tasksButton.click()
        XCTAssertTrue(app.staticTexts["section-tasks-header"].waitForExistence(timeout: 3))

        let ledgerButton = app.buttons["sidebar-button-ledger"]
        XCTAssertTrue(ledgerButton.waitForExistence(timeout: 3))
        ledgerButton.click()
        XCTAssertTrue(app.staticTexts["section-ledger-header"].waitForExistence(timeout: 3))

        let settingsButton = app.buttons["sidebar-button-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.click()
        XCTAssertTrue(app.staticTexts["section-settings-header"].waitForExistence(timeout: 3))
    }
}
