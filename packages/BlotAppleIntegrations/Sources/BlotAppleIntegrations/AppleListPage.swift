import BlotWorkspace
import Foundation

/// Bounds metadata pages while retaining a cursor to every remaining match.
struct AppleListPage {
    let limit: Int
    let offset: Int
    init(_ arguments: AppleArguments) throws {
        guard let limit = Int(arguments["limit"] ?? "20"), (1...50).contains(limit),
              let offset = Int(arguments["offset"] ?? "0"), (0...10000).contains(offset) else { throw AppleIntegrationError.invalidArguments }
        self.limit = limit; self.offset = offset
    }
    func result(_ rows: [[String]], names: [String]) -> ChatJSON {
        let items = rows.prefix(limit).map { row in
            appleObject(Dictionary(uniqueKeysWithValues: zip(names, row.enumerated().map { index, value in
                // List titles are previews; read returns the full item using its unchanged ID.
                index == 1 ? String(value.prefix(256)) : value
            })))
        }
        let more = rows.count > limit
        return .object(["items": .array(items), "has_more": .bool(more),
            "next_offset": more ? .string(String(offset + items.count)) : .null])
    }
}
