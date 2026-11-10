import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class PhoneWorkspaceNavigation {
    var filesQuery = ""
    var scheduleDate = Date()
    private(set) var tabActivationCount = 0
    private var tabActivations: [WorkspaceRoute: Int] = [:]
    private let selectionFeedback = UISelectionFeedbackGenerator()
    #if DEBUG
    let tabInteractionRecorder = PhoneTabInteractionRecorder()
    #endif
    private var positions: [WorkspaceRoute: ScrollPosition] = [:]
    private var offsets: [WorkspaceRoute: CGFloat] = [:]

    func activation(for route: WorkspaceRoute) -> Int { tabActivations[route, default: 0] }

    func activateTab(_ route: WorkspaceRoute) {
        tabActivations[route, default: 0] += 1
        tabActivationCount += 1
        #if DEBUG
        tabInteractionRecorder?.tapped(route, sequence: tabActivationCount)
        #endif
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
        #if DEBUG
        tabInteractionRecorder?.requestedFeedback(route, sequence: tabActivationCount)
        #endif
    }

    #if DEBUG
    func recordRouteFeedback(_ route: WorkspaceRoute) {
        tabInteractionRecorder?.requestedFeedback(route, sequence: tabActivationCount)
    }
    #endif

    func position(for route: WorkspaceRoute) -> Binding<ScrollPosition> {
        Binding(get: { self.positions[route] ?? ScrollPosition(edge: .top) },
                set: { self.positions[route] = $0 })
    }

    func recordOffset(_ offset: CGFloat, for route: WorkspaceRoute) { offsets[route] = offset }

    func restorePosition(for route: WorkspaceRoute) {
        guard let offset = offsets[route] else { return }
        var position = ScrollPosition(edge: .top)
        position.scrollTo(y: offset)
        positions[route] = position
    }

    func reset() { positions = [:]; offsets = [:]; filesQuery = ""; scheduleDate = Date() }
}
