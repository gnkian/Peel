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
        capture("Sample relationships", app: app)
        let search = app.textFields["Search usernames"]
        search.tap()
        search.typeText("apple")
        XCTAssertTrue(app.staticTexts["@apple"].waitForExistence(timeout: 5))
        select("Review")
        app.buttons["Exit Demo"].tap()
        app.alerts["Exit Demo Mode?"].buttons["Exit Without Sample Lists"].tap()
        select("Menu")
        XCTAssertFalse(app.buttons["importSampleArchive"].exists)
        select("Mutual")
        XCTAssertTrue(app.staticTexts["Your accounts will appear here after comparing lists."].exists)
    }

    func testSampleRetentionAndRestrictedActionAlerts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launch()
        func select(_ title: String) {
            let tab = app.tabBars.buttons[title]
            (tab.exists ? tab : app.buttons[title].firstMatch).tap()
        }
        XCTAssertTrue(app.buttons["demoLogo"].waitForExistence(timeout: 15))
        app.buttons["demoLogo"].press(forDuration: 5.2)
        app.buttons["importLists"].tap()
        let restricted = app.alerts["Demo Mode"]
        XCTAssertTrue(restricted.waitForExistence(timeout: 5))
        XCTAssertTrue(restricted.staticTexts["To use this functionality, please exit Demo Mode first."].exists)
        restricted.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Exit Demo"].exists)
        select("Menu")
        app.buttons["Restore Progress"].tap()
        XCTAssertTrue(restricted.waitForExistence(timeout: 5))
        restricted.buttons["Cancel"].tap()
        app.buttons["importSampleArchive"].tap()
        select("Mutual")
        XCTAssertTrue(app.staticTexts["0 of 15 reviewed"].waitForExistence(timeout: 10))
        app.buttons["Start Review"].tap()
        XCTAssertTrue(restricted.waitForExistence(timeout: 5))
        restricted.buttons["Exit Demo Mode"].tap()
        let exit = app.alerts["Exit Demo Mode?"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.buttons["Cancel"].tap()
        select("Review")
        XCTAssertTrue(app.buttons["Exit Demo"].exists)
        app.buttons["Exit Demo"].tap()
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.buttons["Keep Sample Lists"].tap()
        XCTAssertTrue(app.buttons["Login to Instagram"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Exit Demo"].exists)
        XCTAssertTrue(app.staticTexts["20"].firstMatch.waitForExistence(timeout: 5))
        select("Mutual")
        XCTAssertTrue(app.staticTexts["Your accounts will appear here after comparing lists."].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["demoLogo"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["20"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["demoLogo"].press(forDuration: 5.2)
        select("Menu")
        app.buttons["importSampleArchive"].tap()
        select("Mutual")
        XCTAssertTrue(app.staticTexts["0 of 15 reviewed"].waitForExistence(timeout: 10))
        select("Review")
        app.buttons["Exit Demo"].tap()
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        XCTAssertFalse(exit.buttons["Keep Sample Lists"].exists)
        exit.buttons["Exit Without Sample Lists"].tap()
        XCTAssertTrue(app.staticTexts["20"].firstMatch.waitForExistence(timeout: 5))
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

    func testExclusionsAndNumberColumnStayConsistentAcrossTabs() {
        verifyExclusionsAndNumberColumn(contentSize: nil)
    }

    func testAccountRowsAtAccessibilityTextSize() {
        verifyExclusionsAndNumberColumn(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func verifyExclusionsAndNumberColumn(contentSize: String?) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        XCTAssertTrue(app.buttons["demoLogo"].waitForExistence(timeout: 15))
        app.buttons["demoLogo"].press(forDuration: 5.2)
        func select(_ title: String) {
            let tab = app.tabBars.buttons[title]
            (tab.exists ? tab : app.buttons[title].firstMatch).tap()
        }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 {
                if element.exists && element.isHittable { return }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(element.exists && element.isHittable)
        }
        var previousUsernameX: CGFloat?
        for (title, user) in [("Unfollowers", "peeldemo_unfollow8"),
                              ("Followers", "peeldemo_follower5"),
                              ("Mutual", "peeldemo_mutual7")] {
            select(title)
            let actions = app.buttons["Actions for @" + user]
            reveal(actions)
            let usernameX = app.staticTexts["@" + user].frame.minX
            if let previousUsernameX { XCTAssertEqual(usernameX, previousUsernameX, accuracy: 0.5) }
            previousUsernameX = usernameX
            actions.tap()
            app.buttons["Exclude Account"].tap()
            XCTAssertFalse(app.staticTexts["@" + user].exists)
            let filter = app.buttons["accountFilter"]
            for _ in 0..<8 {
                if filter.exists && filter.isHittable { break }
                app.scrollViews.firstMatch.swipeDown()
            }
            filter.tap()
            app.buttons["Excluded"].tap()
            reveal(app.staticTexts["@" + user])
            XCTAssertTrue(app.staticTexts["@" + user].exists)
            capture("Excluded account recoverable in " + title, app: app)
        }
        select("Unfollowers")
        let filter = app.buttons["accountFilter"]
        for _ in 0..<8 {
            if filter.exists && filter.isHittable { break }
            app.scrollViews.firstMatch.swipeDown()
        }
        filter.tap()
        app.buttons["All"].tap()
        let first = app.staticTexts["@peeldemo_unfollow1"]
        reveal(first)
        let firstX = first.frame.minX
        let tenth = app.staticTexts["@peeldemo_unfollow10"]
        reveal(tenth)
        XCTAssertEqual(tenth.frame.minX, firstX, accuracy: 0.5)
        capture("Aligned one and two digit account numbers", app: app)
    }

    func testPhotoCacheClearRequiresConfirmationAndCanBeCancelled() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["demoLogo"].waitForExistence(timeout: 15))
        let menu = app.tabBars.buttons["Menu"].exists ? app.tabBars.buttons["Menu"] : app.buttons["Menu"].firstMatch
        menu.tap()
        XCTAssertFalse(app.buttons["Reset Lists"].exists)
        app.buttons["Reset Data"].tap()
        XCTAssertTrue(app.navigationBars["Reset Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reset Lists"].exists)
        let session = app.buttons["instagramSessionAction"]
        XCTAssertEqual(session.label, "Login to Instagram")
        XCTAssertTrue(session.isEnabled)
        XCTAssertGreaterThan(session.frame.minY, app.buttons["clearPhotoCache"].frame.minY)
        let cache = app.buttons["clearPhotoCache"]
        for _ in 0..<5 {
            if cache.exists && cache.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(cache.waitForExistence(timeout: 10))
        let calculated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Calculating…"])
        XCTAssertEqual(XCTWaiter.wait(for: [calculated], timeout: 10), .completed)
        let initialLabel = cache.label
        cache.tap()
        let explanation = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Clearing the cache will require Peel")).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertEqual(explanation.label, "Clearing the cache will require Peel to reindex the profile photo library.")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(explanation.exists)
        XCTAssertEqual(cache.label, initialLabel)
        cache.tap()
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        app.buttons["Clear Cache"].tap()
        XCTAssertFalse(explanation.exists)
        XCTAssertTrue(cache.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Could Not Update Photo Cache"].exists)
        capture("Photo cache cleared after confirmation", app: app)
    }

    func testLogoutBecomesWorkingLoginAfterSigningOut() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launchArguments += ["-peel-instagram-login-confirmed", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["demoLogo"].waitForExistence(timeout: 15))
        let menu = app.tabBars.buttons["Menu"].exists ? app.tabBars.buttons["Menu"] : app.buttons["Menu"].firstMatch
        menu.tap()
        app.buttons["Reset Data"].tap()
        let logout = app.buttons["instagramSessionAction"]
        XCTAssertTrue(logout.waitForExistence(timeout: 5))
        XCTAssertTrue(logout.isEnabled)
        logout.tap()
        app.buttons["Log Out"].tap()
        let login = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND label == %@", "Login to Instagram"), object: logout)
        XCTAssertEqual(XCTWaiter.wait(for: [login], timeout: 15), .completed)
        XCTAssertEqual(logout.label, "Login to Instagram")
        XCTAssertGreaterThan(logout.frame.minY, app.buttons["clearPhotoCache"].frame.minY)
        logout.tap()
        XCTAssertTrue(app.navigationBars["Sign in to Instagram"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Reset Data"].waitForExistence(timeout: 5))
        XCTAssertEqual(logout.label, "Login to Instagram")
        capture("Login available after signing out", app: app)
    }

    func testResetDataLoginUsesTheReviewLoginGuideAndCanBeClosed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PEEL_UI_TEST_STORAGE_DOMAIN"] = "PeelUITests." + UUID().uuidString
        app.launch()
        let reviewLogin = app.buttons["Login to Instagram"]
        XCTAssertTrue(reviewLogin.waitForExistence(timeout: 15))
        reviewLogin.tap()
        XCTAssertTrue(app.navigationBars["Sign in to Instagram"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Login complete"].exists)
        app.buttons["Close"].tap()
        let menu = app.tabBars.buttons["Menu"].exists ? app.tabBars.buttons["Menu"] : app.buttons["Menu"].firstMatch
        menu.tap()
        app.buttons["Reset Data"].tap()
        let session = app.buttons["instagramSessionAction"]
        XCTAssertEqual(session.label, "Login to Instagram")
        XCTAssertTrue(session.isEnabled)
        session.tap()
        XCTAssertTrue(app.navigationBars["Sign in to Instagram"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Login complete"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Reset Data"].waitForExistence(timeout: 5))
        XCTAssertEqual(session.label, "Login to Instagram")
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
