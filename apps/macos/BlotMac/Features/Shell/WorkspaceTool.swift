import BlotDesign
import Foundation

enum WorkspaceTool: String, CaseIterable, Identifiable {
    case projects = "Projects", images = "Images", sites = "Sites", maps = "Maps"
    case gpts = "GPTs", codeReview = "Code Review", security = "Security"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .projects: "folder"
        case .images: "photo.on.rectangle.angled"
        case .sites: "square.grid.2x2"
        case .maps: "mappin.and.ellipse"
        case .gpts: "cube"
        case .codeReview: "git-pull-request"
        case .security: "shield"
        }
    }
}

extension AppState {
    func openTool(_ tool: WorkspaceTool) {
        profileVisible = false
        activeTool = tool
        showingSettings = false
        paletteVisible = false
        reviewVisible = false
        inspectorVisible = false
        shell.previewSource = nil
    }
}
