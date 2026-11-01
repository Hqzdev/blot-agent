// Модели представления: фактические данные собираются из WorkspaceRecords.

import BlotDesign
import SwiftUI

// MARK: - Agents

enum AgentRole: String, CaseIterable, Identifiable {
    case blot, productLead, projectManager, techLead, backend, nativeFrontend, reviewer, qa, security, integrator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blot: "Blot"
        case .productLead: "Product Lead"
        case .projectManager: "Project Manager"
        case .techLead: "Tech Lead"
        case .backend: "Backend"
        case .nativeFrontend: "Native Frontend"
        case .reviewer: "Reviewer"
        case .qa: "QA Engineer"
        case .security: "Security"
        case .integrator: "Integrator"
        }
    }

    /// Image set in Faces.xcassets (vector PDFs exported from «Face 34 / …» in agent.pen).
    var faceAsset: String {
        switch self {
        case .blot: "FaceBlot"
        case .productLead: "FaceProductLead"
        case .projectManager: "FaceProjectManager"
        case .techLead: "FaceTechLead"
        case .backend: "FaceBackend"
        case .nativeFrontend: "FaceNativeFrontend"
        case .reviewer: "FaceReviewer"
        case .qa: "FaceQA"
        case .security: "FaceSecurity"
        case .integrator: "FaceIntegrator"
        }
    }

    var duty: String {
        switch self {
        case .blot: "Blot · main agent"
        case .productLead: "CEO · owns the goal"
        case .projectManager: "plans · assigns tasks"
        case .techLead: "architecture · ADR"
        case .backend: "builder · services & API"
        case .nativeFrontend: "SwiftUI · screens"
        case .reviewer: "code review · findings"
        case .qa: "tests · finds bugs"
        case .security: "permissions · secrets"
        case .integrator: "merges · protected main"
        }
    }
}

/// Visual state of an agent, shared by the sidebar, graph and live panel.
enum WorkState: String {
    case idle, running, done, permission, blocked, reviewing, writing

    var color: Color {
        switch self {
        case .running, .reviewing, .writing: K.success
        case .permission: K.warning
        case .idle, .done, .blocked: K.text3
        }
    }

    /// Idle, finished and blocked agents are drawn at reduced opacity.
    var dimmed: Bool { self == .idle || self == .done || self == .blocked }
}

// MARK: - Thread blocks

struct StepRow: Identifiable {
    let id = UUID()
    var icon: String
    var verb: String
    var target: String
    var meta: String = ""
    var metaColor: Color = K.text3
}

enum TerminalTone { case normal, fail, dim }

struct TerminalLine: Identifiable {
    let id = UUID()
    var text: String
    var tone: TerminalTone = .normal
}

enum PlanState { case done, active, todo }

struct PlanEntry: Identifiable {
    let id = UUID()
    var text: String
    var state: PlanState
}

struct ApprovalRequest {
    var title = "Run command with network access?"
    var command: String
    var reason: String?
    var alwaysLabel = "Always allow npm"
}

struct ChangedFile: Identifiable {
    let id = UUID()
    var path: String
    var added: Int
    var removed: Int
}

enum ThreadBlock: Identifiable {
    case user(String)
    case agent(String)
    case steps([StepRow])
    case terminal(command: String, exit: Int, lines: [TerminalLine])
    case plan(title: String, items: [PlanEntry])
    case approval(ApprovalRequest)
    case changes([ChangedFile])
    case note(icon: String, text: String)

    var id: String {
        switch self {
        case .user(let t): "user-\(t)"
        case .agent(let t): "agent-\(t)"
        case .steps(let rows): "steps-\(rows.first?.id.uuidString ?? "")"
        case .terminal(let c, let e, _): "term-\(c)-\(e)"
        case .plan(let t, _): "plan-\(t)"
        case .approval(let a): "approval-\(a.command)"
        case .changes(let f): "changes-\(f.first?.id.uuidString ?? "")"
        case .note(_, let t): "note-\(t)"
        }
    }
}

// MARK: - Blot Code

enum TaskPhase { case working, done, stopped }

struct TaskItem: Identifiable {
    let id: String
    var title: String
    var age: String
    var phase: TaskPhase
    var branch: String
    var elapsedSeconds: Int
    var thread: [ThreadBlock]

    var isRunning: Bool { phase == .working }
}

struct ProjectItem: Identifiable {
    let id: String
    var name: String
    var tasks: [TaskItem]
}

// MARK: - Blot Work

struct TeamMember: Identifiable {
    var id: AgentRole { role }
    var role: AgentRole
    var name: String
    var state: WorkState
    var stateLabel: String
}

struct WorkRun: Identifiable {
    let id: String
    var title: String
    var age: String
    var running: Bool
}

struct WorkProject: Identifiable {
    let id: String
    var name: String
    var runs: [WorkRun]
}

