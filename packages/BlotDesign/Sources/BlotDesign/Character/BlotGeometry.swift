//
//  BlotGeometry.swift
//  BlotDesign
//
//  Blot's shapes from agent.pen («18 · Blot — Pet, Motion & Roles»), redrawn in three tones:
//  ink (the body colour), paper (the eye colour) and a mid-grey accent that reads on both.
//  All coordinates are in the 120 × 100 body box; accessories may reach outside it.
//

import SwiftUI

/// Agent roles that have their own accessory. Raw values match the apps' role identifiers.
nonisolated public enum BlotRole: String, CaseIterable, Identifiable, Sendable {
    case blot, productLead, projectManager, techLead, backend, nativeFrontend, reviewer, qa, security, integrator

    public var id: String { rawValue }
}

/// Minimal SVG path reader for the commands Blot uses: M L H V C Q Z (absolute and relative).
nonisolated enum SVGPath {
    static func parse(_ d: String) -> Path {
        let tokens = tokenize(d)
        var path = Path()
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func number() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        func point(_ relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = first
                index += 1
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    current = start
                    continue
                }
            }
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                current = point(relative)
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"
            case "L":
                current = point(relative)
                path.addLine(to: current)
            case "H":
                let x = number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                let y = number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C":
                let c1 = point(relative), c2 = point(relative), end = point(relative)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
            case "Q":
                let control = point(relative), end = point(relative)
                path.addQuadCurve(to: end, control: control)
                current = end
            default:
                index += 1
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var number = ""
        func flush() {
            if !number.isEmpty { tokens.append(number); number = "" }
        }
        for character in d {
            if character.isLetter && character != "e" {
                flush()
                tokens.append(String(character))
            } else if character == "-" {
                if let last = number.last, last == "e" { number.append(character) }
                else { flush(); number = "-" }
            } else if character == "." {
                if number.contains(".") { flush(); number = "0." } else { number.append(character) }
            } else if character.isNumber || character == "e" {
                number.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }
}

/// The three colours a piece of artwork can use.
nonisolated enum BlotTone: Sendable {
    /// Same as the body.
    case ink
    /// Same as the eyes — the surface behind Blot.
    case paper
    /// Mid grey that stays visible on ink and on paper.
    case accent
}

/// A piece of Blot artwork: filled or stroked path, or a circle.
nonisolated struct BlotShape: Sendable {
    nonisolated enum Kind: Sendable { case path(Path), circle(CGPoint, CGFloat), arc(CGPoint, CGFloat, Double, Double) }
    let kind: Kind
    let tone: BlotTone
    var lineWidth: CGFloat = 0

    static func fill(_ d: String, _ tone: BlotTone = .accent) -> BlotShape {
        BlotShape(kind: .path(SVGPath.parse(d)), tone: tone)
    }
    static func stroke(_ d: String, _ width: CGFloat, _ tone: BlotTone = .accent) -> BlotShape {
        BlotShape(kind: .path(SVGPath.parse(d)), tone: tone, lineWidth: width)
    }
    static func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, stroke width: CGFloat = 0, _ tone: BlotTone = .accent) -> BlotShape {
        BlotShape(kind: .circle(CGPoint(x: x, y: y), r), tone: tone, lineWidth: width)
    }

    func draw(in context: inout GraphicsContext, palette: BlotInk) {
        let shape: Path
        switch kind {
        case let .path(path): shape = path
        case let .circle(center, radius):
            shape = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        case let .arc(center, radius, from, to):
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
            shape = path
        }
        let color = palette.color(tone)
        if lineWidth > 0 {
            context.stroke(shape, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        } else {
            context.fill(shape, with: .color(color))
        }
    }
}

/// Resolved colours for one drawing.
nonisolated struct BlotInk {
    let ink: Color
    let paper: Color
    let accent: Color

    func color(_ tone: BlotTone) -> Color {
        switch tone {
        case .ink: ink
        case .paper: paper
        case .accent: accent
        }
    }
}

nonisolated enum BlotGeometry {
    static let body = SVGPath.parse("M0 88V34C0 27 4 23 12 19C26 12 38 5 50 2C55 1 60 1 64 1C93 1 118 18 119 45L120 88Q120 100 108 100H12Q0 100 0 88Z")
    static let eyeX: [CGFloat] = [57, 80]
    static let eyeY: CGFloat = 23
    static let eyeSize = CGSize(width: 16, height: 21)
    /// Midpoint between the eyes, used for pointer tracking.
    static let eyeMidpoint = CGPoint(x: 77, y: 33.5)

    private static let shades = "M50 27H104V38Q104 46 96 46H86Q80 46 79 39Q78 36 76 39Q74 46 68 46H58Q50 46 50 38Z"

    /// One accessory per role — the same list as the role cards in agent.pen, in grey.
    static let accessories: [BlotRole: [BlotShape]] = [
        .blot: [],
        .productLead: [.fill("M50 6L47 -14L58 -5L65 -19L72 -5L83 -14L80 6Z")],
        .projectManager: [
            .stroke("M10 26C18 -16 108 -18 120 30", 5),
            .fill("M113 28H124Q128 28 128 32V46Q128 50 124 50H113Z"),
            .stroke("M121 50C121 60 114 64 104 64", 3),
            .dot(102, 64, 4),
        ],
        .techLead: [
            .dot(65, 33.5, 12, stroke: 3.2),
            .dot(88, 33.5, 12, stroke: 3.2),
            .stroke("M100 32L118 28", 3.2),
        ],
        .backend: [
            .fill("M38 9C44 -17 104 -17 113 22Z"),
            .stroke("M28 12L122 27", 6),
            .stroke("M72 -9V11", 3, .ink),
        ],
        .nativeFrontend: [
            .fill("M34 12C30 -8 92 -16 106 4C100 16 52 20 34 12Z"),
            .stroke("M70 -8L74 -15", 3),
        ],
        .reviewer: [
            .dot(89, 33.5, 13, stroke: 3),
            .stroke("M101 40C108 52 104 62 110 72", 1.8),
            .fill("M46 76L60 82L46 88ZM74 76L60 82L74 88Z"),
            .fill("M57 79H63V85H57Z", .paper),
        ],
        .qa: [
            .dot(131, 60, 13, stroke: 4),
            .stroke("M121 70L108 86", 6),
        ],
        .security: [
            .fill(shades, .ink),
            .stroke(shades, 1.6),
            .stroke("M60 31L66 31M88 31L94 31", 2, .paper),
            .stroke("M119 48C126 52 119 58 126 62C119 66 126 72 120 78", 1.8),
        ],
        .integrator: [
            .stroke("M100 92L124 64", 6),
            BlotShape(kind: .arc(CGPoint(x: 127, y: 56), 7.5, 200, 520), tone: .accent, lineWidth: 5),
        ],
    ]
}
