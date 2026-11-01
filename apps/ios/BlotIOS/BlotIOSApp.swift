//
//  BlotIOSApp.swift
//  blot-agent
//
//  Created by Yaroslav Fairfieldd on 10/11/26.
//

import BlotDesign
import SwiftUI

@main
struct BlotIOSApp: App {
    /// Stored on this iPhone only; the Mac keeps its own choice.
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .system

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .blotTheme(theme)
                .tint(BlotColor.inverse)
        }
    }
}
