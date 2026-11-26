enum PhoneAgentDefaults {
    static let tools = ["file_read", "document_create", "memory_candidate", "page_list", "page_read", "page_create", "page_update"]

    static func includingBuiltInTools(_ tools: [String]) -> [String] {
        Array(Set(tools).union(Self.tools)).sorted()
    }
}
