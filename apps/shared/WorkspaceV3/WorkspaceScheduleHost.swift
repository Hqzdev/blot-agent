import BlotWorkspace
import Foundation
#if os(macOS)
import AppKit
#endif

/// Owns platform wake/energy integration; execution belongs to the account's scheduler.
@MainActor
final class WorkspaceScheduleHost {
    #if os(macOS)
    private var wakeObserver: NSObjectProtocol?
    private var activity: NSObjectProtocol?
    #endif
    func start(engine: WorkspaceScheduleEngine) {
        stop()
        #if os(macOS)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak engine] _ in
            _Concurrency.Task { await engine?.wake() }
        }
        #endif
    }
    func setEnabled(_ enabled: Bool) {
        #if os(macOS)
        if enabled && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Blot scheduled tasks")
        } else if !enabled, let current = activity {
            ProcessInfo.processInfo.endActivity(current); activity = nil
        }
        #endif
    }
    func stop() {
        setEnabled(false)
        #if os(macOS)
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        #endif
    }
}
