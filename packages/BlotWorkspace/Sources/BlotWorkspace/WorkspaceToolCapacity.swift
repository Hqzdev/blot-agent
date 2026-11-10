import Foundation

/// Built-in browser and session files do not consume the user's 100 assigned-tool slots.
enum WorkspaceToolCapacity {
    static func accepts(_ tools: Set<String>) -> Bool {
        tools.subtracting(WorkspaceBrowserCatalog.toolIDs).subtracting(WorkspaceSessionFileCatalog.toolIDs).subtracting(["file_read", "document_create"]).count <= 100
    }
}
