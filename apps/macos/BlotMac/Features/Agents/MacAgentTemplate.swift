import BlotDesign

struct MacAgentTemplate: Identifiable {
    let name: String
    let instructions: String
    let summary: String
    let shape: WorkspaceAvatar.ShapeKind
    let color: String
    var id: String { name }

    static let all: [Self] = [
        .init(name: "Night Shift", instructions: "Prepare a morning digest of the user’s upcoming meetings, tasks and messages. Ask before changing anything.", summary: "Works overnight and preps your morning digest", shape: .hexagon, color: "orange"),
        .init(name: "Inbox Triage", instructions: "Sort the user’s email and draft replies in their voice. Ask before sending or deleting email.", summary: "Sorts your email and drafts replies in your voice", shape: .cloud, color: "pink"),
        .init(name: "Sous Chef", instructions: "Plan dinners, explain recipes and prepare grocery lists. Ask about dietary preferences and never place an order without approval.", summary: "Plans dinners and turns recipes into grocery lists", shape: .round, color: "pink")
    ]
}
