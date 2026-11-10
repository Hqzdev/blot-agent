import BlotDesign
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PhoneTabIconMotionTests: XCTestCase {
    func testEachIconMovesReplaysAndSettles() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Motion is disabled by the device accessibility setting")
        let previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let kinds: [PhoneTabIcon.Kind] = [.chats, .calendar, .overview, .settings]
        for (index, kind) in kinds.enumerated() {
            let probe = PhoneIconMotionProbe()
            window.rootViewController = nil
            let host = UIHostingController(rootView: PhoneIconMotionFixture(kind: kind, probe: probe))
            window.rootViewController = host
            host.loadViewIfNeeded()
            window.makeKeyAndVisible()
            try await waitUntilActive()
            try await pause(window, milliseconds: 250)
            let idle = capture(window)
            probe.activation += 1
            try await pause(window, milliseconds: 230)
            let moving = capture(window)
            XCTAssertNotEqual(idle.pngData(), moving.pngData(), "Icon \(index) must animate its artwork")
            attach(moving, name: "Tab icon \(index) · impact")
            probe.activation += 1
            try await pause(window, milliseconds: 220)
            attach(capture(window), name: "Tab icon \(index) · repeated selection")
            try await pause(window, milliseconds: 900)
            let settled = capture(window)
            try await pause(window, milliseconds: 140)
            XCTAssertEqual(settled.pngData(), capture(window).pngData(), "Icon \(index) must stop after selection")
            probe.activation += 1
            try await pause(window, milliseconds: 230)
            XCTAssertNotEqual(settled.pngData(), capture(window).pngData(), "Icon \(index) must replay on another tap")
        }
    }

    func testAppReducedMotionKeepsIconsStill() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let probe = PhoneIconMotionProbe()
        window.rootViewController = UIHostingController(rootView: PhoneIconMotionFixture(kind: .overview, probe: probe,
            appReduceMotion: true))
        window.makeKeyAndVisible()
        try await waitUntilActive()
        try await pause(window, milliseconds: 150)
        let idle = capture(window)
        probe.activation += 1
        try await pause(window, milliseconds: 230)
        XCTAssertEqual(idle.pngData(), capture(window).pngData())
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

    private func capture(_ window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor @Observable
private final class PhoneIconMotionProbe {
    var activation = 0
}

private struct PhoneIconMotionFixture: View {
    let kind: PhoneTabIcon.Kind
    let probe: PhoneIconMotionProbe
    var appReduceMotion = false

    var body: some View {
        PhoneTabIcon(kind: kind, activation: probe.activation).scaleEffect(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.black).background(.white)
            .environment(\.blotReduceMotion, appReduceMotion)
    }
}
