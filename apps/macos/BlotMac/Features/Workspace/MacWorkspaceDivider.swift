import AppKit
import BlotDesign
import SwiftUI

/// Resizes a single panel using a window-space drag, without animating under the pointer.
struct MacWorkspaceDivider: View {
    static let hitWidth: CGFloat = 16
    @Binding var width: Double
    let bounds: ClosedRange<Double>
    let title: String
    @State private var startingWidth: Double?
    @State private var hovering = false

    private var sizing: MacWorkspacePanelResize { .init(bounds: bounds) }

    var body: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
            Rectangle().fill(Color.blue).frame(width: 3)
                .opacity(hovering || startingWidth != nil ? 1 : 0)
                .kAnimation(KMotion.quick, value: hovering || startingWidth != nil)
        }
            .frame(width: Self.hitWidth)
            .contentShape(Rectangle())
            .onHover { value in
                guard value != hovering else { return }
                hovering = value
                if value { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let initial = startingWidth ?? width
                    startingWidth = initial
                    width = sizing.width(initial: initial, translation: value.translation.width)
                }
                .onEnded { value in
                    if let initial = startingWidth {
                        width = sizing.width(initial: initial, translation: value.translation.width)
                    }
                    startingWidth = nil
                })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                width = sizing.width(initial: MacWorkspaceLayout.defaultSidebarWidth, translation: 0)
            })
            .accessibilityElement().accessibilityLabel(title)
            .accessibilityValue("\(Int(width))")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 16.0 : -16.0
                width = sizing.width(initial: width, translation: delta)
            }
            .accessibilityIdentifier("workspace.sidebar.resize")
            .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
    }
}

nonisolated struct MacWorkspacePanelResize {
    let bounds: ClosedRange<Double>
    func width(initial: Double, translation: Double) -> Double {
        min(bounds.upperBound, max(bounds.lowerBound, initial + translation))
    }
}
