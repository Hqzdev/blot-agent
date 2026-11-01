import AppKit
import BlotDesign
import SwiftUI

struct SidebarResizeHandle: View {
    @Environment(AppState.self) private var app
    @State private var start: Double?
    @State private var hovering = false
    var body: some View {
        Color.clear.frame(width: 5).contentShape(Rectangle())
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if start == nil { start = app.shell.sidebarWidth }
                app.shell.sidebarWidth = min(K.projectSidebarMax, max(K.projectSidebarMin, (start ?? K.projectSidebarMin) + value.translation.width))
            }.onEnded { _ in start = nil })
            .accessibilityLabel("Resize project sidebar")
            .accessibilityValue("\(Int(app.shell.sidebarWidth)) points")
            .accessibilityAdjustableAction { direction in
                app.shell.sidebarWidth = min(K.projectSidebarMax, max(K.projectSidebarMin, app.shell.sidebarWidth + (direction == .increment ? 16 : -16)))
            }
    }
}
