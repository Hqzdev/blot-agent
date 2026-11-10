#if os(macOS)
import AppKit
import Carbon
import BlotWorkspace

/// NSAppleScript is main-thread-only. Model text is passed only as Apple event descriptors.
@MainActor
final class AppleAutomation {
    func authorized(_ plugin: ApplePluginID, request: Bool = false) async -> Bool {
        guard [.mail, .notes].contains(plugin) else { return false }
        // Automation requires a ready process, not a window opened by the user.
        do { try await prepareApplication(plugin) }
        catch { return false }
        let bundleID = plugin.bundleID
        // Consent can wait indefinitely. Never block the app's main thread.
        return await _Concurrency.Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, request) == noErr
        }.value
    }
    func resources(_ plugin: ApplePluginID) async throws -> [AppleResource] {
        try _Concurrency.Task.checkCancellation()
        guard await authorized(plugin) else { throw AppleIntegrationError.permissionDenied }
        try _Concurrency.Task.checkCancellation()
        let result = try run(plugin, values: ["resources"])
        return rows(result).compactMap { row in
            guard row.count >= 2 else { return nil }
            return .init(id: row[0], name: row[1])
        }
    }
    func execute(_ tool: AppleTool, arguments a: AppleArguments, preview: Bool = false) async throws -> ChatJSON {
        try _Concurrency.Task.checkCancellation()
        guard await authorized(tool.plugin) else { throw AppleIntegrationError.permissionDenied }
        try _Concurrency.Task.checkCancellation()
        var body = a["body"] ?? ""
        if tool.plugin == .notes { body = Self.html((a["title"] ?? "") + "\n" + body) }
        let page = try AppleListPage(a)
        let values = [preview ? (tool.plugin == .mail && tool.operation == "send" ? "preview" : "read") : tool.operation, a["resource_id"] ?? "", a["id"] ?? "", a["query"] ?? "",
                      a["title"] ?? a["subject"] ?? "", body, a["destination"] ?? "", a["recipient"] ?? "", String(page.limit + 1), String(page.offset)]
        let result = try run(tool.plugin, values: values)
        let names = tool.plugin == .notes ? ["id", "title", "body"] : ["id", "subject", "sender", "recipient", "body"]
        if tool.operation == "list" { return page.result(rows(result), names: names) }
        let objects = rows(result).map { row in appleObject(Dictionary(uniqueKeysWithValues: zip(names, row))) }
        return objects.first ?? appleObject(["state": "succeeded"])
    }
    func compileScripts() throws {
        for source in [Self.notesScript, Self.mailScript] {
            guard let script = NSAppleScript(source: source) else { throw AppleIntegrationError.unavailable }
            var error: NSDictionary?
            guard script.compileAndReturnError(&error) else { throw AppleIntegrationError.system(error?.description ?? "AppleScript compilation failed") }
        }
    }
    private func prepareApplication(_ plugin: ApplePluginID) async throws {
        let application: NSRunningApplication
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: plugin.bundleID).first(where: { !$0.isTerminated }) {
            application = running
        } else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: plugin.bundleID) else { throw AppleIntegrationError.unavailable }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            application = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        let deadline = Date().addingTimeInterval(10)
        while !application.isFinishedLaunching {
            guard !application.isTerminated, Date() < deadline else { throw AppleIntegrationError.unavailable }
            try await _Concurrency.Task.sleep(for: .milliseconds(100))
        }
        guard !application.isTerminated else { throw AppleIntegrationError.unavailable }
    }
    private func run(_ plugin: ApplePluginID, values: [String]) throws -> NSAppleEventDescriptor {
        guard [.mail, .notes].contains(plugin), let script = NSAppleScript(source: plugin == .notes ? Self.notesScript : Self.mailScript) else { throw AppleIntegrationError.unavailable }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { throw AppleIntegrationError.system(error?.description ?? "AppleScript compilation failed") }
        let input = NSAppleEventDescriptor.list()
        for (index, value) in values.enumerated() { input.insert(NSAppleEventDescriptor(string: value), at: index + 1) }
        let parameters = NSAppleEventDescriptor.list(); parameters.insert(input, at: 1)
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "blot"), forKeyword: AEKeyword(keyASSubroutineName))
        event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code == -1743 { throw AppleIntegrationError.permissionDenied }
            if code == -1712 { throw AppleIntegrationError.uncertainResult }
            throw AppleIntegrationError.system(error[NSAppleScript.errorMessage] as? String ?? "Ошибка автоматизации приложения.")
        }
        return result
    }
    private func rows(_ descriptor: NSAppleEventDescriptor) -> [[String]] {
        guard descriptor.numberOfItems > 0 else { return [] }
        return (1...min(100, descriptor.numberOfItems)).compactMap { index in
            guard let row = descriptor.atIndex(index), row.numberOfItems > 0 else { return nil }
            return (1...row.numberOfItems).map { String((row.atIndex($0)?.stringValue ?? "").prefix(24000)) }
        }
    }
    private static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
    }
    static let notesScript = """
    on blot(a)
        set op to item 1 of a
        tell application "/System/Applications/Notes.app"
            with timeout of 30 seconds
                if op is "resources" then
                    set output to {}
                    repeat with f in every folder
                        set end of output to {id of f as text, (name of container of f as text) & " · " & (name of f as text)}
                    end repeat
                    return output
                end if
                set f to folder id (item 2 of a)
                if op is "list" then
                    set output to {}
                    set skipped to 0
                    repeat with n in notes of f
                        if password protected of n is false then
                            if item 4 of a is "" or name of n contains item 4 of a or plaintext of n contains item 4 of a then
                                if skipped < (item 10 of a as integer) then
                                    set skipped to skipped + 1
                                else
                                    set end of output to {id of n as text, name of n as text, ""}
                                    if count of output is (item 9 of a as integer) then exit repeat
                                end if
                            end if
                        end if
                    end repeat
                    return output
                end if
                if op is "create" then
                    set n to make new note at f with properties {body:item 6 of a}
                else
                    set n to note id (item 3 of a) of f
                    if password protected of n then error "Заметка заблокирована."
                end if
                if op is "delete" then
                    delete n
                    return {}
                end if
                if op is "update" then set body of n to item 6 of a
                return {{id of n as text, name of n as text, plaintext of n as text}}
            end timeout
        end tell
    end blot
    """
    static let mailScript = """
    on blot(a)
        set op to item 1 of a
        tell application "/System/Applications/Mail.app"
            with timeout of 30 seconds
                if op is "resources" then
                    set output to {}
                    repeat with acc in every account
                        set end of output to {id of acc as text, name of acc as text}
                    end repeat
                    return output
                end if
                set acc to account id (item 2 of a)
                set addresses to email addresses of acc
                if count of addresses is 0 then error "У аккаунта нет адреса отправителя."
                if op is "create" then
                    set m to make new outgoing message with properties {subject:item 5 of a, content:item 6 of a, sender:item 1 of addresses, visible:false}
                    tell m to make new to recipient at end of to recipients with properties {address:item 8 of a}
                    save m
                    return {{id of m as text, subject of m as text, sender of m as text, item 8 of a, content of m as text}}
                end if
                if op is "send" or op is "preview" then
                    set m to outgoing message id ((item 3 of a) as integer)
                    set senderAddress to extract address from (sender of m)
                    if addresses does not contain senderAddress then error "Черновик принадлежит другому аккаунту."
                    set recipientsText to ""
                    repeat with r in to recipients of m
                        set recipientsText to recipientsText & address of r & "; "
                    end repeat
                    repeat with r in cc recipients of m
                        set recipientsText to recipientsText & "CC: " & address of r & "; "
                    end repeat
                    repeat with r in bcc recipients of m
                        set recipientsText to recipientsText & "BCC: " & address of r & "; "
                    end repeat
                    set output to {{id of m as text, subject of m as text, sender of m as text, recipientsText, content of m as text}}
                    if op is "send" then
                        set sentOK to send m
                        if sentOK is false then error "Почта не приняла письмо для отправки."
                    end if
                    return output
                end if
                set output to {}
                set skipped to 0
                repeat with box in every mailbox of acc
                    repeat with m in messages of box
                        if op is "list" then
                            if item 4 of a is "" or subject of m contains item 4 of a or sender of m contains item 4 of a then
                                if skipped < (item 10 of a as integer) then
                                    set skipped to skipped + 1
                                else
                                    set end of output to {id of m as text, subject of m as text, sender of m as text, "", ""}
                                    if count of output is (item 9 of a as integer) then return output
                                end if
                            end if
                        else if (id of m as text) is item 3 of a then
                            if op is "delete" then
                                delete m
                                return {}
                            else if op is "move" then
                                move m to mailbox (item 7 of a) of acc
                                return {}
                            else if op is "reply" then
                                set draftMessage to reply m opening window no
                                set content of draftMessage to item 6 of a
                                set sender of draftMessage to item 1 of addresses
                                save draftMessage
                                return {{id of draftMessage as text, subject of draftMessage as text, sender of draftMessage as text, "", content of draftMessage as text}}
                            else
                                return {{id of m as text, subject of m as text, sender of m as text, "", content of m as text}}
                            end if
                        end if
                    end repeat
                end repeat
                if op is not "list" then error "Письмо не найдено в выбранном аккаунте."
                return output
            end timeout
        end tell
    end blot
    """
}
#endif
