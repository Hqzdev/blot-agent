enum PhoneAgentDefaults {
    static let tools = ["file_read", "document_create", "memory_candidate"]

    static func includingBuiltInTools(_ tools: [String]) -> [String] {
        Array(Set(tools).union(Self.tools)).sorted()
    }
}
