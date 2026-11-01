//
//  DockIcon.swift
//  BlotMac
//
//  Keeps the Dock icon in step with the app theme (dark tile + light Blot in the dark
//  theme, light tile + dark Blot in the light theme; «System» follows macOS) and makes
//  Blot wink every few seconds. Winking is skipped when Reduce Motion is on.
//

import AppKit
import BlotDesign
import SwiftUI

struct DockIconSync: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: TaskKey(scheme: colorScheme, reduceMotion: reduceMotion || app.settings.reduceMotion, active: phase == .active)) {
                await run(scheme: colorScheme, animated: !reduceMotion && !app.settings.reduceMotion && phase == .active)
            }
    }

    private struct TaskKey: Equatable {
        let scheme: ColorScheme
        let reduceMotion: Bool
        let active: Bool
    }

    private func run(scheme: ColorScheme, animated: Bool) async {
        let base = scheme == .dark ? "DockIconDark" : "DockIconLight"
        let open = NSImage(named: base)
        let wink = NSImage(named: base + "Wink")
        NSApp.applicationIconImage = open
        guard animated, let open, let wink else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 5...9)))
            guard !Task.isCancelled else { break }
            NSApp.applicationIconImage = wink
            try? await Task.sleep(for: .milliseconds(260))
            NSApp.applicationIconImage = open
        }
        NSApp.applicationIconImage = open
    }
}
