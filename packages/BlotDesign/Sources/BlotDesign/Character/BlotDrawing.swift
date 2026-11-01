//
//  BlotDrawing.swift
//  BlotDesign
//
//  Renders one pose. Body follows the theme (ink on light, paper on dark); eyes use the
//  surface colour; accessories and effects are grey.
//

import SwiftUI

nonisolated public enum BlotFraming: Sendable, Equatable {
    /// Free-standing pet on a 170 × 170 artboard with room for bubbles and badges.
    case stage
    /// Circle avatar: Blot rises from the bottom edge, accessories may be cropped.
    case avatar
}

/// Static Blot for a single pose.
public struct BlotDrawing: View {
    private let role: BlotRole
    private let pose: BlotPose
    private let framing: BlotFraming
    private let elapsed: Double

    nonisolated public static let stageUnits: CGFloat = 170
    nonisolated public static let stageOrigin = CGPoint(x: 25, y: 58)

    public init(role: BlotRole = .blot, pose: BlotPose = BlotPose(), framing: BlotFraming = .stage, elapsed: Double = 0) {
        self.role = role
        self.pose = pose
        self.framing = framing
        self.elapsed = elapsed
    }

    /// Eye midpoint in the coordinate space of `frame`, used for pointer tracking.
    nonisolated public static func eyeCenter(in frame: CGRect, framing: BlotFraming) -> CGPoint {
        let unit = BlotGeometry.eyeMidpoint
        switch framing {
        case .stage:
            let s = frame.width / stageUnits
            return CGPoint(x: frame.minX + (stageOrigin.x + unit.x) * s, y: frame.minY + (stageOrigin.y + unit.y) * s)
        case .avatar:
            let s = frame.width * 0.86 / 120
            return CGPoint(x: frame.minX + (frame.width - 120 * s) / 2 + unit.x * s, y: frame.minY + frame.height * 0.3 + unit.y * s)
        }
    }

    public var body: some View {
        Canvas { context, size in
            let palette = BlotInk(ink: BlotColor.text, paper: BlotColor.canvas, accent: BlotColor.accent)
            switch framing {
            case .stage:
                let s = size.width / Self.stageUnits
                context.scaleBy(x: s, y: s)
                let lift = min(1, abs(pose.y) / 30)
                context.fill(Path(ellipseIn: CGRect(x: Self.stageOrigin.x + 18 - 8 * lift, y: 160, width: 84 + 16 * lift, height: 6)),
                             with: .color(palette.ink.opacity(0.08 * (1 - 0.6 * lift))))
                context.translateBy(x: Self.stageOrigin.x, y: Self.stageOrigin.y)
            case .avatar:
                let circle = Path(ellipseIn: CGRect(origin: .zero, size: size))
                context.fill(circle, with: .color(BlotColor.fill))
                context.clip(to: circle)
                let s = size.width * 0.86 / 120
                context.translateBy(x: (size.width - 120 * s) / 2, y: size.height * 0.3)
                context.scaleBy(x: s, y: s)
            }

            context.translateBy(x: pose.x, y: pose.y)
            context.translateBy(x: 60, y: 100)
            context.rotate(by: .degrees(pose.tilt))
            context.scaleBy(x: pose.scaleX, y: pose.scaleY)
            context.translateBy(x: -60, y: -100)

            context.fill(BlotGeometry.body, with: .color(palette.ink))
            if pose.ember > 0 {
                context.fill(Path(ellipseIn: CGRect(x: 18, y: 57, width: 10, height: 10)),
                             with: .color(palette.accent.opacity(pose.ember)))
            }
            for index in 0..<2 { Self.drawEye(index, pose: pose, in: &context, palette: palette) }
            for shape in BlotGeometry.accessories[role] ?? [] { shape.draw(in: &context, palette: palette) }
            if framing == .stage { Self.drawEffects(pose: pose, elapsed: elapsed, in: &context, palette: palette) }
        }
    }

    nonisolated private static func drawEye(_ index: Int, pose: BlotPose, in context: inout GraphicsContext, palette: BlotInk) {
        let eye = palette.paper
        let x0 = BlotGeometry.eyeX[index] + pose.gazeX * 1.5
        let y0 = BlotGeometry.eyeY + pose.gazeY * 1.5
        let open = index == 0 ? pose.openL : pose.openR
        let happy = index == 0 ? pose.happyL : pose.happyR
        let stroke = StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)

        if pose.cross {
            var path = Path()
            path.move(to: CGPoint(x: x0 + 1, y: y0 + 4)); path.addLine(to: CGPoint(x: x0 + 15, y: y0 + 18))
            path.move(to: CGPoint(x: x0 + 15, y: y0 + 4)); path.addLine(to: CGPoint(x: x0 + 1, y: y0 + 18))
            context.stroke(path, with: .color(eye), style: stroke)
            return
        }
        if happy {
            var path = Path()
            path.move(to: CGPoint(x: x0, y: y0 + 15))
            path.addLine(to: CGPoint(x: x0 + 8, y: y0 + 6))
            path.addLine(to: CGPoint(x: x0 + 16, y: y0 + 15))
            context.stroke(path, with: .color(eye), style: stroke)
            return
        }
        if pose.sad {
            let inner: CGFloat = index == 0 ? 8 : 14, outer: CGFloat = index == 0 ? 14 : 8
            var path = Path()
            path.move(to: CGPoint(x: x0, y: y0 + inner))
            path.addLine(to: CGPoint(x: x0 + 16, y: y0 + outer))
            path.addLine(to: CGPoint(x: x0 + 16, y: y0 + 19))
            path.addQuadCurve(to: CGPoint(x: x0 + 14, y: y0 + 21), control: CGPoint(x: x0 + 16, y: y0 + 21))
            path.addLine(to: CGPoint(x: x0 + 2, y: y0 + 21))
            path.addQuadCurve(to: CGPoint(x: x0, y: y0 + 19), control: CGPoint(x: x0, y: y0 + 21))
            path.closeSubpath()
            context.fill(path, with: .color(eye))
            return
        }
        if open < 0.15 {
            context.fill(Path(roundedRect: CGRect(x: x0, y: y0 + 14, width: 16, height: 4), cornerRadius: 2), with: .color(eye))
            return
        }
        let grow = pose.big
        let width = 16 + 4 * grow, height = 21 + 5 * grow
        let visible = max(4, height * open)
        let rect = CGRect(x: x0 - 2 * grow, y: y0 - 3 * grow + height - visible, width: width, height: visible)
        context.fill(Path(roundedRect: rect, cornerRadius: min(2.5 + grow * 0.5, visible / 2)), with: .color(eye))

        guard open > 0.45, grow < 0.5 else { return }
        let gx = pose.gazeX, gy = pose.gazeY
        guard max(abs(gx), abs(gy)) >= 0.3 else { return }
        let notchHeight = min(7, rect.height * 0.4)
        let notch: CGRect
        if abs(gx) >= abs(gy) {
            notch = CGRect(x: gx > 0 ? rect.minX : rect.maxX - 7, y: rect.midY - notchHeight / 2, width: 7, height: notchHeight)
        } else {
            notch = CGRect(x: rect.midX - 3.5, y: gy < 0 ? rect.maxY - 7 : rect.minY, width: 7, height: 7)
        }
        context.fill(Path(notch), with: .color(palette.ink))
    }

    nonisolated private static func drawEffects(pose: BlotPose, elapsed: Double, in context: inout GraphicsContext, palette: BlotInk) {
        if pose.sparks {
            for (cx, cy, r) in [(-8.0, 6.0, 9.0), (130.0, 22.0, 7.0)] {
                var star = Path()
                star.move(to: CGPoint(x: cx, y: cy - r))
                star.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx, y: cy))
                star.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx, y: cy))
                star.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx, y: cy))
                star.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx, y: cy))
                context.fill(star, with: .color(palette.accent))
            }
        }
        if pose.bang {
            context.fill(Path(ellipseIn: CGRect(x: 118, y: -14, width: 24, height: 24)), with: .color(palette.ink))
            var mark = Path()
            mark.move(to: CGPoint(x: 130, y: -8)); mark.addLine(to: CGPoint(x: 130, y: 0))
            mark.move(to: CGPoint(x: 130, y: 5)); mark.addLine(to: CGPoint(x: 130, y: 5.5))
            context.stroke(mark, with: .color(palette.paper), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        if pose.dots > 0 {
            context.fill(Path(ellipseIn: CGRect(x: 114, y: 0, width: 6, height: 6)), with: .color(palette.ink))
            if pose.dots > 1 { context.fill(Path(ellipseIn: CGRect(x: 121, y: -10, width: 8, height: 8)), with: .color(palette.ink)) }
            if pose.dots > 2 {
                context.fill(Path(roundedRect: CGRect(x: 118, y: -32, width: 30, height: 18), cornerRadius: 8), with: .color(palette.ink))
                for i in 0..<3 {
                    context.fill(Path(ellipseIn: CGRect(x: 124 + Double(i) * 7, y: -24.5, width: 3, height: 3)), with: .color(palette.paper))
                }
            }
        }
        if pose.sweat {
            context.fill(SVGPath.parse("M24 14C20 20 20 24 24 24C28 24 28 20 24 14Z"), with: .color(palette.accent))
        }
        if pose.asleep {
            for index in 0..<3 {
                let phase = (elapsed / 3 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                var copy = context
                copy.opacity = 1 - phase
                copy.draw(Text("z").font(.system(size: 12 + Double(index) * 3, weight: .semibold)).foregroundStyle(palette.accent),
                          at: CGPoint(x: 124 + Double(index) * 8, y: 8 - phase * 24))
            }
        }
    }
}
