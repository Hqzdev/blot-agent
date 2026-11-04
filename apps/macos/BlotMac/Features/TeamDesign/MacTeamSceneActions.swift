import SwiftUI

struct MacTeamSceneActions {
    let createAgent: @MainActor () -> Void
    let settings: @MainActor () -> Void
    let back: @MainActor () -> Void
    let search: @MainActor () -> Void
    let canSearch: Bool
}

private struct MacTeamSceneActionsKey: FocusedValueKey {
    typealias Value = MacTeamSceneActions
}

extension FocusedValues {
    var teamSceneActions: MacTeamSceneActions? {
        get { self[MacTeamSceneActionsKey.self] }
        set { self[MacTeamSceneActionsKey.self] = newValue }
    }
}
