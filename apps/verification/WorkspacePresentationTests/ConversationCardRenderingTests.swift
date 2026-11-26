import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ConversationCardRenderingTests: XCTestCase {
    func testAllElevenProductionCardsOnPhysicalIPhone() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This verification requires the owner's physical iPhone.")
        #else
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let samples = try ConversationCardSamples.samples()
        XCTAssertEqual(samples.count, 11)
        XCTAssertEqual(Set(samples.map(\.name)).count, 11)
        for (index, sample) in samples.enumerated() {
            for dark in [false, true] {
                let store = try ConversationCardSamples.store()
                let card = try ConversationCardSamples.card(sample, index: index)
                let root = ScrollView {
                    WorkspaceConversationCardView(card: card, fallback: sample.name).padding(16)
                }.environment(store).preferredColorScheme(dark ? .dark : .light)
                    .environment(\.dynamicTypeSize, dark ? .accessibility1 : .large)
                let host = UIHostingController(rootView: root)
                window.rootViewController = host; window.makeKeyAndVisible()
                try await _Concurrency.Task.sleep(for: .milliseconds(250))
                host.view.layoutIfNeeded()
                XCTAssertFalse(host.view.bounds.isEmpty)
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = sample.reference + "-iPhone-" + sample.name + (dark ? "-dark-accessibility" : "-light")
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        #endif
    }
}
