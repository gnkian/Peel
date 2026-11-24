import XCTest
import XCUIAutomation

@MainActor
final class PeelUITests: XCTestCase {
    func testNavigationAndCaptureBaseline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launch()
        let review = app.staticTexts["Your Instagram review space"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        capture("Review", app: app)

        for title in ["Unfollowers", "Followers", "Mutual", "Menu", "Review"] {
            let tab = app.tabBars.buttons[title]
            if tab.exists {
                tab.tap()
            } else {
                let sidebarButton = app.buttons[title].firstMatch
                XCTAssertTrue(sidebarButton.waitForExistence(timeout: 5), "Missing navigation: " + title)
                sidebarButton.tap()
            }
            if title == "Review" {
                XCTAssertTrue(review.waitForExistence(timeout: 5))
            } else {
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            }
            capture(title, app: app)
        }
    }

    func testCorruptStorageShowsRecoveryAndRetry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launchEnvironment["PEEL_UI_TEST_CORRUPT_STORE"] = "1"
        app.launch()
        let alert = app.alerts["Operation Could Not Complete"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertTrue(alert.buttons["Retry"].exists)
        XCTAssertTrue(alert.buttons["Restore Backup"].exists)
        capture("Corrupt storage recovery", app: app)
        alert.buttons["Retry"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        alert.buttons["Restore Backup"].tap()
        let cancelPicker = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelPicker.waitForExistence(timeout: 10))
        cancelPicker.tap()
        XCTAssertTrue(app.staticTexts["Your Instagram review space"].waitForExistence(timeout: 5))
    }

    func testDashboardLargeTextAndRotation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["demoLogo"].waitForExistence(timeout: 15))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let progress = app.otherElements["reviewProgress"]
            XCTAssertTrue(progress.waitForExistence(timeout: 5))
            for _ in 0..<6 {
                let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
                if progress.frame.minY >= app.frame.minY && progress.frame.maxY <= bottom { break }
                let content = app.scrollViews["dashboardScroll"]
                if progress.frame.minY < app.frame.minY { content.swipeDown() } else { content.swipeUp() }
            }
            XCTAssertGreaterThanOrEqual(progress.frame.minY, app.frame.minY)
            XCTAssertLessThanOrEqual(progress.frame.maxY, app.frame.maxY)
            capture("Large text dashboard \(orientation.rawValue)", app: app)
            // Informational progress remains exposed even with login-dependent actions disabled.
            XCTAssertTrue(app.staticTexts["Progress"].exists)
            XCTAssertFalse(app.buttons["importLists"].isEnabled)
            if !app.tabBars.firstMatch.exists {
                XCTAssertLessThanOrEqual(app.buttons["Unfollowers"].firstMatch.frame.height, 160,
                                         "Sidebar labels must not break into many word fragments.")
            }
        }
    }

    func testDemoGestureAndPopulatedLists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launch()
        let logo = app.buttons["demoLogo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 15))
        logo.press(forDuration: 1)
        XCTAssertFalse(app.buttons["Exit Demo"].exists)
        logo.press(forDuration: 5.2)
        XCTAssertTrue(app.buttons["Exit Demo"].waitForExistence(timeout: 5))
        let destination = app.tabBars.buttons["Unfollowers"].exists
            ? app.tabBars.buttons["Unfollowers"] : app.buttons["Unfollowers"].firstMatch
        destination.tap()
        XCTAssertTrue(app.navigationBars["Unfollowers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mass Unfollow"].exists)
        let openAccount = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unfollow @peeldemo_")).firstMatch
        XCTAssertTrue(openAccount.exists)
        XCTAssertGreaterThanOrEqual(openAccount.frame.height, 44 - 0.001)
        XCTAssertLessThanOrEqual(openAccount.frame.height, 48, "The default-size action label must fit on one line.")
        capture("Fictional populated accounts", app: app)
        // Inspect only; never open Instagram or perform account actions.
    }

    func testSampleArchiveMenuAndImportedRelationships() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launch()
        func select(_ title: String) {
            let tab = app.tabBars.buttons[title]
            let destination = tab.exists ? tab : app.buttons[title].firstMatch
            XCTAssertTrue(destination.waitForExistence(timeout: 15))
            destination.tap()
        }
        select("Menu")
        XCTAssertFalse(app.buttons["importSampleArchive"].exists)
        select("Review")
        let logo = app.buttons["demoLogo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 5))
        logo.press(forDuration: 5.2)
        XCTAssertTrue(app.buttons["Exit Demo"].waitForExistence(timeout: 5))
        select("Menu")
        let sample = app.buttons["importSampleArchive"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        select("Mutual")
        XCTAssertTrue(app.staticTexts["0 of 15 reviewed"].waitForExistence(timeout: 10))
        let search = app.textFields["Search usernames"]
        search.tap()
        search.typeText("apple")
        XCTAssertTrue(app.staticTexts["@apple"].waitForExistence(timeout: 5))
        select("Review")
        app.buttons["Exit Demo"].tap()
        select("Menu")
        XCTAssertFalse(app.buttons["importSampleArchive"].exists)
        select("Mutual")
        XCTAssertTrue(app.staticTexts["Your accounts will appear here after comparing lists."].exists)
    }

    func testDocumentPickerCancellationAndRepeat() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        // Simulate the existing user-confirmed login flag without opening Instagram.
        app.launchArguments += ["-peel-instagram-login-confirmed", "YES"]
        app.launch()
        let archive = app.buttons["importLists"]
        XCTAssertTrue(archive.waitForExistence(timeout: 15))
        XCTAssertTrue(archive.isEnabled)
        for _ in 0..<2 {
            archive.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            XCTAssertTrue(archive.waitForExistence(timeout: 5))
            XCTAssertTrue(archive.isHittable)
            XCTAssertFalse(app.alerts["Operation Could Not Complete"].exists)
        }

        let menu = app.tabBars.buttons["Menu"].exists ? app.tabBars.buttons["Menu"] : app.buttons["Menu"].firstMatch
        menu.tap()
        let restore = app.buttons["Restore Progress"]
        for _ in 0..<2 {
            XCTAssertTrue(restore.waitForExistence(timeout: 5))
            restore.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            XCTAssertTrue(restore.waitForExistence(timeout: 5))
            XCTAssertTrue(restore.isHittable)
            XCTAssertFalse(app.alerts["Operation Could Not Complete"].exists)
            XCTAssertFalse(app.staticTexts["Working…"].exists)
        }
    }

    func testPrivacyInformationNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launch()
        let menu = app.tabBars.buttons["Menu"].exists ? app.tabBars.buttons["Menu"] : app.buttons["Menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        let privacy = app.buttons["Privacy & Storage"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy & Storage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Instagram website sessions"].exists)
        capture("Privacy and storage explanation", app: app)
    }

    func testBackupShareCancellationAndRepeat() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launch()
        let menu = app.tabBars.buttons["Menu"].exists ? app.tabBars.buttons["Menu"] : app.buttons["Menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()

        for _ in 0..<2 {
            let save = app.buttons["Save Progress"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            save.tap()
            let export = app.buttons["Export JSON Backup"]
            XCTAssertTrue(export.waitForExistence(timeout: 5))
            export.tap()

            // UIKit may present a popover on iPhone as well as iPad.
            // Select cancellation from the actual presentation, not the device idiom.
            let popover = app.popovers.firstMatch
            let close = app.buttons["Close"]
            let presented = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in popover.exists || close.exists }, object: app
            )
            XCTAssertEqual(XCTWaiter.wait(for: [presented], timeout: 5), .completed)
            if popover.exists {
                let outside = CGPoint(x: app.frame.minX + 8, y: app.frame.midY)
                XCTAssertFalse(popover.frame.contains(outside), "Cancellation must tap outside the actual popover.")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                    .withOffset(CGVector(dx: outside.x - app.frame.minX, dy: outside.y - app.frame.minY)).tap()
                let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: popover)
                XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            } else {
                XCTAssertTrue(close.exists)
                close.tap()
                let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
                XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            }
            XCTAssertTrue(save.isHittable, "Cancellation must restore the Menu for the next export.")
        }
        capture("Repeated fictional backup cancellation", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
