import Foundation

nonisolated struct MacWorkspaceTextDiff: Sendable {
    enum Row: Identifiable, Sendable {
        case line(DiffLine)
        case unchanged([DiffLine])

        var id: Int {
            switch self {
            case .line(let line): line.id
            case .unchanged(let lines): lines[0].id
            }
        }
    }

    let rows: [Row]
    let added: Int
    let removed: Int
    let hasBaseline: Bool
    let approximate: Bool
    let truncated: Bool
    private static let previewLimit = 20_000

    init(before: String?, after: String) {
        let updated = Self.lines(after)
        guard let before else {
            rows = updated.prefix(Self.previewLimit).enumerated().map { index, text in
                .line(.init(id: index, oldNumber: nil, newNumber: index + 1, text: text, tone: .context))
            }
            added = 0
            removed = 0
            hasBaseline = false
            approximate = false
            truncated = updated.count > Self.previewLimit
            return
        }

        hasBaseline = true
        let original = Self.lines(before)
        guard original != updated else {
            rows = []
            added = 0
            removed = 0
            approximate = false
            truncated = false
            return
        }

        let edits = Self.edits(from: original, to: updated)
        added = edits.added
        removed = edits.removed
        approximate = edits.approximate
        var lines: [DiffLine] = []
        var oldIndex = 0
        var newIndex = 0
        while lines.count < Self.previewLimit && (oldIndex < original.count || newIndex < updated.count) {
            let id = lines.count
            if oldIndex < original.count && edits.isRemoval(oldIndex) {
                lines.append(.init(id: id, oldNumber: oldIndex + 1, newNumber: nil, text: original[oldIndex], tone: .removed))
                oldIndex += 1
            } else if newIndex < updated.count && edits.isInsertion(newIndex) {
                lines.append(.init(id: id, oldNumber: nil, newNumber: newIndex + 1, text: updated[newIndex], tone: .added))
                newIndex += 1
            } else {
                lines.append(.init(id: id, oldNumber: oldIndex + 1, newNumber: newIndex + 1, text: updated[newIndex], tone: .context))
                oldIndex += 1
                newIndex += 1
            }
        }
        truncated = oldIndex < original.count || newIndex < updated.count
        rows = Self.foldContext(in: lines)
    }

    private struct Edits {
        let added: Int
        let removed: Int
        let approximate: Bool
        let isInsertion: (Int) -> Bool
        let isRemoval: (Int) -> Bool
    }

    private static func edits(from old: [String], to new: [String]) -> Edits {
        if !old.isEmpty, !new.isEmpty, max(old.count, new.count) <= 2_000 {
            let difference = new.difference(from: old)
            let insertions = Set(difference.insertions.compactMap { change -> Int? in
                if case .insert(let offset, _, _) = change { return offset }
                return nil
            })
            let removals = Set(difference.removals.compactMap { change -> Int? in
                if case .remove(let offset, _, _) = change { return offset }
                return nil
            })
            return .init(added: insertions.count, removed: removals.count, approximate: false,
                         isInsertion: insertions.contains, isRemoval: removals.contains)
        }
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed()).prefix { $0 == $1 }.count
        let insertions = prefix..<(new.count - suffix)
        let removals = prefix..<(old.count - suffix)
        return .init(added: insertions.count, removed: removals.count, approximate: !old.isEmpty && !new.isEmpty,
                     isInsertion: insertions.contains, isRemoval: removals.contains)
    }

    private static func lines(_ text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func foldContext(in lines: [DiffLine]) -> [Row] {
        var rows: [Row] = []
        var contextStart = 0
        func appendContext(endingAt end: Int) {
            let context = lines[contextStart..<end]
            let leading = contextStart == 0 ? 0 : 2
            let trailing = end == lines.count ? 0 : 2
            if context.count > leading + trailing + 3 {
                rows.append(contentsOf: context.prefix(leading).map(Row.line))
                rows.append(.unchanged(Array(context.dropFirst(leading).dropLast(trailing))))
                rows.append(contentsOf: context.suffix(trailing).map(Row.line))
            } else {
                rows.append(contentsOf: context.map(Row.line))
            }
        }
        for (index, line) in lines.enumerated() where line.tone != .context {
            appendContext(endingAt: index)
            rows.append(.line(line))
            contextStart = index + 1
        }
        appendContext(endingAt: lines.count)
        return rows
    }
}
