import XCTest

@MainActor
final class PhoneTabBarInteractionTests: XCTestCase {
    func testTabsAndRepeatedTaps() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "yaroslavstrelkov.blot-agent.ios")
        app.launchArguments = ["--workspace-preview", "--screen", "07-all-chats", "--ru", "--tab-interaction-probe"]
        app.launch()
        let allTabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workspace.tab."))
        XCTAssertTrue(app.buttons["workspace.tab.chats"].waitForExistence(timeout: 10))
        let routes = ["schedules", "overview", "settings", "chats", "chats", "settings",
                      "overview", "schedules", "chats", "overview", "settings", "chats"]
        var expected: [String: Int] = [:]
        for route in routes {
            XCTAssertEqual(allTabs.count, 4)
            let button = app.buttons["workspace.tab." + route]
            XCTAssertTrue(button.isHittable)
            button.tap()
            expected[route, default: 0] += 1
            XCTAssertTrue(button.isSelected)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "workspace.screen." + route)
                .firstMatch.waitForExistence(timeout: 3))
        }
        for route in ["chats", "settings", "overview", "schedules"] {
            app.buttons["workspace.tab." + route].doubleTap()
            expected[route, default: 0] += 2
            XCTAssertTrue(app.buttons["workspace.tab." + route].isSelected)
            XCTAssertEqual(allTabs.count, 4)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Tab bar after switching and repeated taps"
        attachment.lifetime = .keepAlways
        add(attachment)
        let encoded = try JSONSerialization.data(withJSONObject: expected, options: .sortedKeys)
        print("BLOT_TAB_UI_EXPECTED_COUNTS=" + String(decoding: encoded, as: UTF8.self))
    }
}
