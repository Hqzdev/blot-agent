import Foundation
import SwiftUI
import Testing
@testable import BlotDesign

@Suite struct ThemePreferenceTests {
    private func defaults() -> (UserDefaults, String) {
        let suite = "blot.design.tests." + UUID().uuidString
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func defaultsToSystem() {
        let (store, suite) = defaults()
        defer { store.removePersistentDomain(forName: suite) }
        #expect(ThemeStore.load(from: store) == .system)
    }

    @Test(arguments: ThemePreference.allCases)
    func savesAndLoads(_ preference: ThemePreference) {
        let (store, suite) = defaults()
        defer { store.removePersistentDomain(forName: suite) }
        ThemeStore.save(preference, to: store)
        #expect(ThemeStore.load(from: store) == preference)
    }

    @Test func unknownValueFallsBackToSystem() {
        let (store, suite) = defaults()
        defer { store.removePersistentDomain(forName: suite) }
        store.set("Sepia", forKey: ThemeStore.defaultsKey)
        #expect(ThemeStore.load(from: store) == .system)
    }

    @Test func choosingSystemClearsTheStoredValue() {
        let (store, suite) = defaults()
        defer { store.removePersistentDomain(forName: suite) }
        ThemeStore.save(.dark, to: store)
        ThemeStore.save(.system, to: store)
        #expect(store.string(forKey: ThemeStore.defaultsKey) == nil)
    }

    @Test func colorSchemes() {
        #expect(ThemePreference.system.colorScheme == nil)
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
    }
}

@Suite struct PaletteContrastTests {
    private func contrast(_ foreground: BlotColorPair, on background: BlotColorPair, dark: Bool) -> Double {
        let back = BlotRGBA(dark ? background.dark : background.light)
        let front = BlotRGBA(dark ? foreground.dark : foreground.light).over(back)
        return BlotRGBA.contrast(front, back)
    }

    @Test(arguments: [false, true])
    func readableTextOnEverySurface(dark: Bool) {
        for surface in [BlotPalette.canvas, BlotPalette.sidebar, BlotPalette.panel, BlotPalette.fill, BlotPalette.tag] {
            #expect(contrast(BlotPalette.text, on: surface, dark: dark) >= 7)
            #expect(contrast(BlotPalette.textSecondary, on: surface, dark: dark) >= 4.5)
        }
        #expect(contrast(BlotPalette.onInverse, on: BlotPalette.inverse, dark: dark) >= 7)
    }

    @Test(arguments: [false, true])
    func focusRingStandsOut(dark: Bool) {
        #expect(contrast(BlotPalette.focusRing, on: BlotPalette.canvas, dark: dark) >= 3)
        #expect(contrast(BlotPalette.focusRing, on: BlotPalette.sidebar, dark: dark) >= 3)
    }

    @Test(arguments: [false, true])
    func accessoriesReadOnInkAndPaper(dark: Bool) {
        #expect(contrast(BlotPalette.accent, on: BlotPalette.text, dark: dark) >= 2.5)
        #expect(contrast(BlotPalette.accent, on: BlotPalette.canvas, dark: dark) >= 3)
    }
}
