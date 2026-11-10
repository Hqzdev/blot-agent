@preconcurrency import Contacts
import BlotWorkspace
import Foundation

@MainActor
final class AppleContactStore {
    private let store = CNContactStore()
    private var keys: [CNKeyDescriptor] {
        [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey].map { $0 as CNKeyDescriptor }
    }
    var authorized: Bool { CNContactStore.authorizationStatus(for: .contacts) == .authorized || limited }
    var limited: Bool {
        #if os(iOS)
        CNContactStore.authorizationStatus(for: .contacts) == .limited
        #else
        false
        #endif
    }
    func authorize() async throws { guard try await store.requestAccess(for: .contacts) else { throw AppleIntegrationError.permissionDenied } }
    func preview(_ a: AppleArguments) throws -> ChatJSON {
        appleObject(fields(try store.unifiedContact(withIdentifier: a.required("id"), keysToFetch: keys)))
    }
    func execute(_ tool: AppleTool, arguments a: AppleArguments) throws -> ChatJSON {
        guard authorized, a["resource_id"] == "contacts" else { throw AppleIntegrationError.permissionDenied }
        if tool.operation == "list" {
            let query = a["query"] ?? ""
            var result: [ChatJSON] = []
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, stop in
                let data = self.fields(contact)
                if query.isEmpty || data.values.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { result.append(appleObject(data)) }
                if result.count >= 100 { stop.pointee = true }
            }
            return .array(result)
        }
        let contact: CNMutableContact
        if tool.operation == "create" { contact = CNMutableContact() }
        else {
            let existing = try store.unifiedContact(withIdentifier: a.required("id"), keysToFetch: keys)
            guard let mutable = existing.mutableCopy() as? CNMutableContact else { throw AppleIntegrationError.missingResource }
            contact = mutable
        }
        let request = CNSaveRequest()
        if tool.operation == "delete" { request.delete(contact) }
        else {
            if let given = a["given_name"] { contact.givenName = given }
            if let family = a["family_name"] { contact.familyName = family }
            if let email = a["email"] { contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)] }
            if let phone = a["phone"] { contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))] }
            if tool.operation == "create" { request.add(contact, toContainerWithIdentifier: nil) } else { request.update(contact) }
        }
        try store.execute(request)
        return tool.operation == "delete" ? appleObject(["state": "deleted"]) : appleObject(fields(contact))
    }
    private func fields(_ contact: CNContact) -> [String: String] {
        ["id": contact.identifier, "name": contact.givenName + " " + contact.familyName, "given_name": contact.givenName, "family_name": contact.familyName,
         "email": contact.emailAddresses.map { $0.value as String }.joined(separator: ", "),
         "phone": contact.phoneNumbers.map { $0.value.stringValue }.joined(separator: ", ")]
    }
}
