#if os(macOS)
import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Runs in the signed, private executor. Recording is restricted to one selected application.
@MainActor final class NativeTeachRecorder {
    private var application: NSRunningApplication?
    private var monitor: Any?
    private var timer: Timer?
    private var began: Date?
    private var paused = false
    private var steps: [WorkspaceTaughtTask.Step] = []
    private var lastField: WorkspaceTaughtTask.Target?
    private var baseline: String?
    func perform(_ operation: NativeRequest.Operation, parameters: [String: String]) throws -> ChatJSON {
        switch operation {
        case .teachApplications:
            return .array(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != "dev.blot.macos" }.compactMap { app in
                guard let id = app.bundleIdentifier else { return nil }
                return .object(["bundle_id": .string(id), "name": .string(app.localizedName ?? id)])
            })
        case .teachStart:
            guard began == nil, let id = parameters["bundle_id"], let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { throw NativeExecutionError.busy }
            try trusted(prompt: true)
            application = app; steps = []; began = Date(); paused = false; lastField = nil; baseline = nil
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                MainActor.assumeIsolated { self?.click(event.cgEvent?.location) }
            }
            guard monitor != nil else { cleanup(); throw NativeExecutionError.accessDenied }
            timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sampleField() }
            }
            app.activate(options: [])
            return state()
        case .teachStatus: return state()
        case .teachPause:
            paused = parameters["paused"] == "true"; lastField = nil; baseline = nil; return state()
        case .teachStop:
            guard let app = application, let began, let id = app.bundleIdentifier else { throw NativeExecutionError.invalidRequest }
            sampleField()
            let recording = WorkspaceTaughtTask(bundleID: id, application: app.localizedName ?? id, duration: min(3600, Date().timeIntervalSince(began)), steps: steps)
            cleanup()
            return try JSONDecoder().decode(ChatJSON.self, from: JSONEncoder().encode(recording))
        case .teachReplay:
            try trusted(prompt: false)
            guard began == nil, let raw = parameters["recording"], raw.utf8.count <= 120_000 else { throw NativeExecutionError.busy }
            let recording = try JSONDecoder().decode(WorkspaceTaughtTask.self, from: Data(raw.utf8)); try recording.validate()
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: recording.bundleID).first,
                  let rawIndex = parameters["index"], let index = Int(rawIndex) else { throw NativeExecutionError.programUnavailable }
            if index == -1 { app.activate(options: []); return .object(["state": .string("activated")]) }
            guard recording.steps.indices.contains(index) else { throw NativeExecutionError.invalidRequest }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                app.activate(options: []); throw NativeExecutionError.changed
            }
            let step = recording.steps[index], root = AXUIElementCreateApplication(app.processIdentifier)
            var matches: [AXUIElement] = []; var remaining = 2500
            find(root, target: step.target, remaining: &remaining, matches: &matches)
            guard matches.count == 1, let element = matches.first, !protected(element) else { throw NativeExecutionError.changed }
            let result: AXError
            if step.action == .press { result = AXUIElementPerformAction(element, kAXPressAction as CFString) }
            else {
                var settable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue else { throw NativeExecutionError.accessDenied }
                result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (step.value ?? "") as CFString)
            }
            guard result == .success else { throw NativeExecutionError.changed }
            return .object(["state": .string("completed"), "step": .number(Double(index + 1))])
        default: throw NativeExecutionError.invalidRequest
        }
    }
    func cleanup() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        timer?.invalidate(); timer = nil; application = nil; began = nil; lastField = nil; baseline = nil
    }
    private func trusted(prompt: Bool) throws {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary) else { throw NativeExecutionError.accessDenied }
    }
    private func active() -> Bool {
        guard let app = application, let began, !paused, steps.count < 200, Date().timeIntervalSince(began) < 3600 else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }
    private func click(_ point: CGPoint?) {
        guard active(), let point, let app = application else { return }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(app.processIdentifier), Float(point.x), Float(point.y), &element) == .success else { return }
        for _ in 0..<5 {
            guard let current = element, !protected(current) else { return }
            if let target = target(current), ["AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXPopUpButton", "AXLink"].contains(target.role) {
                steps.append(.init(action: .press, target: target)); return
            }
            element = attribute(current, kAXParentAttribute) as! AXUIElement?
        }
    }
    private func sampleField() {
        guard active(), let app = application,
              let element = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute) as! AXUIElement?,
              !protected(element), let target = target(element), ["AXTextField", "AXTextArea"].contains(target.role),
              let value = attribute(element, kAXValueAttribute) as? String, value.utf8.count <= 8000 else { lastField = nil; baseline = nil; return }
        if lastField != target { lastField = target; baseline = value; return }
        guard baseline != value else { return }; baseline = value
        if steps.last?.action == .setValue, steps.last?.target == target { steps[steps.count - 1].value = value }
        else { steps.append(.init(action: .setValue, target: target, value: value)) }
    }
    private func target(_ element: AXUIElement) -> WorkspaceTaughtTask.Target? {
        guard let role = attribute(element, kAXRoleAttribute) as? String else { return nil }
        let title = (attribute(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (attribute(element, kAXDescriptionAttribute) as? String) ?? ""
        let identifier = attribute(element, kAXIdentifierAttribute) as? String ?? ""
        guard (!title.isEmpty || !identifier.isEmpty), title.utf8.count <= 800, identifier.utf8.count <= 800 else { return nil }
        return .init(role: role, title: title, identifier: identifier)
    }
    private func protected(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXSubroleAttribute) as? String) == "AXSecureTextField" || (attribute(element, "AXProtectedContent") as? Bool) == true
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }; return result
    }
    private func find(_ element: AXUIElement, target: WorkspaceTaughtTask.Target, remaining: inout Int, matches: inout [AXUIElement], depth: Int = 0) {
        guard remaining > 0, depth < 30, matches.count < 2, !protected(element) else { return }; remaining -= 1
        if self.target(element) == target { matches.append(element) }
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { find(child, target: target, remaining: &remaining, matches: &matches, depth: depth + 1) }
    }
    private func state() -> ChatJSON {
        .object(["recording": .bool(began != nil), "paused": .bool(paused), "elapsed": .number(min(3600, began.map { Date().timeIntervalSince($0) } ?? 0)), "step_count": .number(Double(steps.count))])
    }
}
#endif
