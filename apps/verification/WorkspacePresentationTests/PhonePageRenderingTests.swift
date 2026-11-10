import SwiftUI
import UIKit
import XCTest

@MainActor
final class PhonePageRenderingTests: XCTestCase {
    func testRenderWorkspacePagesOnPhysicalDevice() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let samples: [(WorkspaceRoute, Bool, Int)] = [
            (.overview, false, 0), (.schedules, false, 0), (.settings, false, 0),
            (.settingsProfile, false, 0), (.files, false, 0), (.createSchedule, false, 0),
            (.createAgent, false, 0), (.schedules, false, 1), (.overview, true, 0)
        ]
        for (route, accessibility, dayOffset) in samples {
            let store = WorkspaceStore(mode: .preview, route: route)
            store.language = "ru"
            store.navigation.scheduleDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
            let host = UIHostingController(rootView: WorkspaceRootView(store: store)
                .preferredColorScheme(accessibility ? .dark : .light)
                .environment(\.dynamicTypeSize, accessibility ? .accessibility1 : .large))
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await _Concurrency.Task.sleep(for: .milliseconds(350))
            host.view.layoutIfNeeded()
            XCTAssertFalse(host.view.bounds.isEmpty)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "iPhone-\(route.rawValue)-\(dayOffset)" + (accessibility ? "-large-dark" : "")
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
