import Foundation

@main struct VerifyMessageBlocks {
    static func main() {
        let parser = WorkspaceMarkdownBlocks()
        let source = "# Result\n\n```swift\n  let value = 1\n\nprint(value)\n```\n\n| File | State |\n| :--- | ---: |\n| main.swift | Done |"
        let expected: [WorkspaceMarkdownBlock] = [
            .heading(level: 1, text: "Result"),
            .code(language: "swift", text: "  let value = 1\n\nprint(value)"),
            .table(headers: ["File", "State"], rows: [["main.swift", "Done"]]),
        ]
        precondition(parser.parse(source) == expected)
        precondition(parser.parse("```\n<untrusted>\n") == [.code(language: "", text: "<untrusted>\n")])
        precondition(parser.parse("A | B\nnot | a separator") == [.text("A | B\nnot | a separator")])
        precondition(parser.parse("| A | B |\n| --- | --- |\n| `x|y` | z |") == [.table(headers: ["A", "B"], rows: [["`x|y`", "z"]])])
        let large = String(repeating: "x", count: 262145)
        precondition(parser.parse(large) == [.text(large)])
        print("PASS: native Markdown blocks, code whitespace, tables, unclosed fences and bounded input")
    }
}
