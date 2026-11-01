import BlotDesign
import SwiftUI

enum RailIcon {
    case home, symbol(String)

    @ViewBuilder func image(color: Color) -> some View {
        switch self {
        case .home:
            RoundedHomeGlyph().fill(color).frame(width: 20, height: 20)
        case .symbol(let name): KIcon(name, size: 20, color: color)
        }
    }
}

private struct RoundedHomeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 10.7, y: 2.1))
        path.addQuadCurve(to: CGPoint(x: 13.3, y: 2.1), control: CGPoint(x: 12, y: 1))
        path.addLine(to: CGPoint(x: 22, y: 9.6))
        path.addQuadCurve(to: CGPoint(x: 20.4, y: 12), control: CGPoint(x: 23.7, y: 12.3))
        path.addLine(to: CGPoint(x: 20.4, y: 19.5))
        path.addQuadCurve(to: CGPoint(x: 18, y: 22), control: CGPoint(x: 20.4, y: 22))
        path.addLine(to: CGPoint(x: 14.5, y: 22))
        path.addLine(to: CGPoint(x: 14.5, y: 16.5))
        path.addQuadCurve(to: CGPoint(x: 13.5, y: 15.5), control: CGPoint(x: 14.5, y: 15.5))
        path.addLine(to: CGPoint(x: 10.5, y: 15.5))
        path.addQuadCurve(to: CGPoint(x: 9.5, y: 16.5), control: CGPoint(x: 9.5, y: 15.5))
        path.addLine(to: CGPoint(x: 9.5, y: 22))
        path.addLine(to: CGPoint(x: 6, y: 22))
        path.addQuadCurve(to: CGPoint(x: 3.6, y: 19.5), control: CGPoint(x: 3.6, y: 22))
        path.addLine(to: CGPoint(x: 3.6, y: 12))
        path.addQuadCurve(to: CGPoint(x: 2, y: 9.6), control: CGPoint(x: 0.3, y: 12.3))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
