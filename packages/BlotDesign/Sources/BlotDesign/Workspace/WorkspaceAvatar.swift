import SwiftUI

/// Grok Bot appearance is independent of an agent's role and permissions.
public struct WorkspaceAvatar: View {
    public enum ShapeKind: String, CaseIterable, Sendable { case round, triangle, tall, square, drop, pill, oval, hexagon, cloud, star }
    let shape: ShapeKind
    let color: Color
    let size: CGFloat
    let showsEyes: Bool
    @Environment(\.colorScheme) private var scheme
    public init(shape: ShapeKind = .round, color: Color = .primary, size: CGFloat = 44, showsEyes: Bool = true) {
        self.shape = shape; self.color = color; self.size = size; self.showsEyes = showsEyes
    }
    public var body: some View {
        ZStack {
            silhouette.fill(color)
            if showsEyes {
                eyes
                .foregroundStyle(color == .white || (color == .primary && scheme == .dark) ? Color.black : Color.white)
                .position(x: size * faceCenter.x, y: size * faceCenter.y)
            }
        }.frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var eyes: some View {
        HStack(spacing: size * 0.08) {
            Capsule().frame(width: size * 0.095, height: size * 0.22)
                .rotationEffect(.degrees(shape == .drop ? 15 : -25))
            Capsule().frame(width: size * 0.08, height: size * 0.18)
                .rotationEffect(.degrees(shape == .drop ? 15 : -25)).offset(y: -size * 0.035)
        }
    }

    /// Normalized face positions follow the usable interior of each silhouette.
    private var faceCenter: CGPoint {
        switch shape {
        case .round, .square: CGPoint(x: 0.56, y: 0.43)
        case .tall: CGPoint(x: 0.53, y: 0.45)
        case .pill, .oval: CGPoint(x: 0.54, y: 0.50)
        case .hexagon: CGPoint(x: 0.53, y: 0.46)
        case .cloud: CGPoint(x: 0.43, y: 0.61)
        case .star: CGPoint(x: 0.52, y: 0.48)
        case .drop: CGPoint(x: 0.54, y: 0.63)
        case .triangle: CGPoint(x: 0.50, y: 0.63)
        }
    }
    private var silhouette: Path {
        Path { p in
            let r = CGRect(x: size * 0.05, y: size * 0.05, width: size * 0.9, height: size * 0.9)
            switch shape {
            case .round: p.addEllipse(in: r)
            case .oval: p.addEllipse(in: r.insetBy(dx: 0, dy: size * 0.10))
            case .tall: p.addRoundedRect(in: r.insetBy(dx: size * 0.13, dy: 0), cornerSize: CGSize(width: size * 0.25, height: size * 0.25))
            case .pill: p.addRoundedRect(in: r.insetBy(dx: 0, dy: size * 0.18), cornerSize: CGSize(width: size * 0.27, height: size * 0.27))
            case .square: p.addRoundedRect(in: r, cornerSize: CGSize(width: size * 0.22, height: size * 0.22))
            case .hexagon:
                let points = (0..<6).map { index in
                    let angle = Double(index) * .pi / 3 - .pi / 2
                    return CGPoint(x: size * (0.5 + 0.46 * cos(angle)), y: size * (0.5 + 0.46 * sin(angle)))
                }
                for index in points.indices {
                    let previous = points[(index + 5) % 6]
                    let corner = points[index]
                    let next = points[(index + 1) % 6]
                    let entry = CGPoint(x: corner.x * 0.84 + previous.x * 0.16, y: corner.y * 0.84 + previous.y * 0.16)
                    let exit = CGPoint(x: corner.x * 0.84 + next.x * 0.16, y: corner.y * 0.84 + next.y * 0.16)
                    if index == 0 { p.move(to: entry) } else { p.addLine(to: entry) }
                    p.addQuadCurve(to: exit, control: corner)
                }
                p.closeSubpath()
            case .cloud:
                // Collinear incoming/outgoing tangents keep every lobe and the closing seam smooth.
                p.move(to: CGPoint(x: size * 0.50, y: size * 0.17))
                p.addCurve(to: CGPoint(x: size * 0.78, y: size * 0.12), control1: CGPoint(x: size * 0.56, y: size * 0.12), control2: CGPoint(x: size * 0.72, y: size * 0.08))
                p.addCurve(to: CGPoint(x: size * 0.89, y: size * 0.41), control1: CGPoint(x: size * 0.84, y: size * 0.16), control2: CGPoint(x: size * 0.94, y: size * 0.30))
                p.addCurve(to: CGPoint(x: size * 0.91, y: size * 0.76), control1: CGPoint(x: size * 0.84, y: size * 0.52), control2: CGPoint(x: size * 1.00, y: size * 0.66))
                p.addCurve(to: CGPoint(x: size * 0.53, y: size * 0.93), control1: CGPoint(x: size * 0.82, y: size * 0.86), control2: CGPoint(x: size * 0.69, y: size * 0.96))
                p.addCurve(to: CGPoint(x: size * 0.17, y: size * 0.88), control1: CGPoint(x: size * 0.37, y: size * 0.90), control2: CGPoint(x: size * 0.25, y: size * 0.96))
                p.addCurve(to: CGPoint(x: size * 0.10, y: size * 0.52), control1: CGPoint(x: size * 0.09, y: size * 0.80), control2: CGPoint(x: size * 0.02, y: size * 0.65))
                p.addCurve(to: CGPoint(x: size * 0.24, y: size * 0.18), control1: CGPoint(x: size * 0.18, y: size * 0.39), control2: CGPoint(x: size * 0.13, y: size * 0.21))
                p.addCurve(to: CGPoint(x: size * 0.50, y: size * 0.17), control1: CGPoint(x: size * 0.35, y: size * 0.15), control2: CGPoint(x: size * 0.44, y: size * 0.22))
                p.closeSubpath()
            case .star:
                p.move(to: CGPoint(x: size * 0.50, y: size * 0.03))
                p.addCurve(to: CGPoint(x: size * 0.97, y: size * 0.50), control1: CGPoint(x: size * 0.70, y: size * 0.03), control2: CGPoint(x: size * 0.69, y: size * 0.31))
                p.addCurve(to: CGPoint(x: size * 0.50, y: size * 0.97), control1: CGPoint(x: size * 0.97, y: size * 0.70), control2: CGPoint(x: size * 0.69, y: size * 0.69))
                p.addCurve(to: CGPoint(x: size * 0.03, y: size * 0.50), control1: CGPoint(x: size * 0.30, y: size * 0.97), control2: CGPoint(x: size * 0.31, y: size * 0.69))
                p.addCurve(to: CGPoint(x: size * 0.50, y: size * 0.03), control1: CGPoint(x: size * 0.03, y: size * 0.30), control2: CGPoint(x: size * 0.31, y: size * 0.31))
                p.closeSubpath()
            case .drop:
                p.move(to: CGPoint(x: size * 0.50, y: size * 0.03))
                p.addCurve(to: CGPoint(x: size * 0.94, y: size * 0.60), control1: CGPoint(x: size * 0.56, y: size * 0.03), control2: CGPoint(x: size * 0.94, y: size * 0.40))
                p.addCurve(to: CGPoint(x: size * 0.50, y: size * 0.97), control1: CGPoint(x: size * 0.99, y: size * 0.83), control2: CGPoint(x: size * 0.76, y: size * 0.97))
                p.addCurve(to: CGPoint(x: size * 0.06, y: size * 0.60), control1: CGPoint(x: size * 0.24, y: size * 0.97), control2: CGPoint(x: size * 0.01, y: size * 0.83))
                p.addCurve(to: CGPoint(x: size * 0.50, y: size * 0.03), control1: CGPoint(x: size * 0.06, y: size * 0.40), control2: CGPoint(x: size * 0.44, y: size * 0.03))
                p.closeSubpath()
            case .triangle:
                p.move(to: CGPoint(x: size * 0.42, y: size * 0.12))
                p.addQuadCurve(to: CGPoint(x: size * 0.58, y: size * 0.12), control: CGPoint(x: size * 0.50, y: size * 0.01))
                p.addLine(to: CGPoint(x: size * 0.94, y: size * 0.78))
                p.addQuadCurve(to: CGPoint(x: size * 0.84, y: size * 0.92), control: CGPoint(x: size * 1.01, y: size * 0.92))
                p.addLine(to: CGPoint(x: size * 0.16, y: size * 0.92))
                p.addQuadCurve(to: CGPoint(x: size * 0.06, y: size * 0.78), control: CGPoint(x: -size * 0.01, y: size * 0.92))
                p.closeSubpath()
            }
        }
    }
}
