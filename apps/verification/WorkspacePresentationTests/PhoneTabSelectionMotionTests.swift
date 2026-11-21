import SwiftUI
import UIKit
import XCTest

@MainActor
final class PhoneTabSelectionMotionTests: XCTestCase {
    func testSelectionPassesThroughIntermediatePositionsInBothDirections() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "System Reduce Motion is enabled")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let store = WorkspaceStore(mode: .preview, route: .chats)
        window.rootViewController = UIHostingController(rootView: WorkspaceRootView(store: store))
        window.makeKeyAndVisible()
        try await waitUntilActive()
        try await pause(window, milliseconds: 500)
        let track = try XCTUnwrap(selectionTrack(in: window))
        for route in [WorkspaceRoute.settings, .chats] {
            let start = track.capsule.frame.midX
            store.selectTab(route)
            var samples: [CGFloat] = []
            for _ in 0..<20 {
                try await pause(window, milliseconds: 25)
                if let frame = track.capsule.layer.presentation()?.frame { samples.append(frame.midX) }
            }
            XCTAssertTrue(selectionTrack(in: window) === track)
            let end = track.capsule.frame.midX
            XCTAssertGreaterThan(abs(end - start), 50)
            let middle = samples.filter { $0 > min(start, end) + 2 && $0 < max(start, end) - 2 }
            XCTAssertGreaterThan(Set(middle.map { Int($0.rounded()) }).count, 2, "Rendered x positions: \(samples)")
        }
    }

    private func selectionTrack(in view: UIView) -> PhoneTabSelectionIndicator.Track? {
        if let track = view as? PhoneTabSelectionIndicator.Track { return track }
        for child in view.subviews {
            if let track = selectionTrack(in: child) { return track }
        }
        return nil
    }

    private func pause(_ window: UIWindow, milliseconds: Int) async throws {
        window.layoutIfNeeded()
        try await _Concurrency.Task.sleep(for: .milliseconds(milliseconds))
        window.layoutIfNeeded()
    }

    private func waitUntilActive() async throws {
        let deadline = Date().addingTimeInterval(5)
        while UIApplication.shared.applicationState != .active && Date() < deadline {
            try await _Concurrency.Task.sleep(for: .milliseconds(100))
        }
        try XCTSkipUnless(UIApplication.shared.applicationState == .active,
                          "The physical test app must be in the foreground to capture animation")
    }

}
