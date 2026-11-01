import BlotDesign
import SwiftUI

enum ProfileMenuAction {
    case profile, usage, pet, invitation, settings, shortcuts, guide, about, logOut
}

enum ProfileSheet: String, Identifiable {
    case invitation, guide, about
    var id: String { rawValue }
}

extension AppState {
    func openPet() {
        openSection(.blot)
    }

    func openProfileSettings(_ section: SettingsSection) {
        profileVisible = false
        settings.section = section
        showingSettings = true
    }
}
