import Foundation

/// A reviewed recording contains accessibility targets, never raw keyboard events or screenshots.
public struct WorkspaceTaughtTask: Codable, Equatable, Sendable {
    public struct Target: Codable, Equatable, Sendable {
        public let role: String
        public let title: String
        public let identifier: String
        public init(role: String, title: String, identifier: String) { self.role = role; self.title = title; self.identifier = identifier }
    }
    public struct Step: Codable, Equatable, Sendable, Identifiable {
        public enum Action: String, Codable, Sendable { case press, setValue }
        public var id: UUID
        public var action: Action
        public var target: Target
        public var value: String?
        public init(id: UUID = UUID(), action: Action, target: Target, value: String? = nil) { self.id = id; self.action = action; self.target = target; self.value = value }
    }
    public let format: String
    public let bundleID: String
    public let application: String
    public let duration: Double
    public var steps: [Step]
    public init(bundleID: String, application: String, duration: Double, steps: [Step]) {
        format = "blot.teach.v1"; self.bundleID = bundleID; self.application = application; self.duration = duration; self.steps = steps
    }
    public func validate() throws {
        guard format == "blot.teach.v1", bundleID.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]{1,250}$"#, options: .regularExpression) != nil,
              !application.isEmpty, application.utf8.count <= 800, duration.isFinite, (0...3600).contains(duration),
              (1...200).contains(steps.count), Set(steps.map(\.id)).count == steps.count else { throw WorkspaceStorageError.invalidParameters }
        for step in steps {
            guard ["AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXPopUpButton", "AXTextField", "AXTextArea", "AXLink"].contains(step.target.role),
                  !step.target.title.isEmpty || !step.target.identifier.isEmpty,
                  step.target.title.utf8.count <= 800, step.target.identifier.utf8.count <= 800,
                  step.action == .setValue ? ["AXTextField", "AXTextArea"].contains(step.target.role) && step.value != nil && step.value!.utf8.count <= 8000 : step.value == nil else {
                throw WorkspaceStorageError.invalidParameters
            }
        }
    }
}
