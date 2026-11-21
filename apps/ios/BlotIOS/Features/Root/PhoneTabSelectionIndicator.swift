import BlotDesign
import SwiftUI
import UIKit

struct PhoneTabSelectionBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

/// The track stays mounted while the capsule moves to the selected button's measured frame.
struct PhoneTabSelectionIndicator: UIViewRepresentable {
    let target: CGRect
    let color: Color
    let reduceMotion: Bool

    func makeUIView(context: Context) -> Track { Track() }

    func updateUIView(_ track: Track, context: Context) {
        track.move(to: target, color: UIColor(color), reduceMotion: reduceMotion)
    }

    final class Track: UIView {
        let capsule = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            addSubview(capsule)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func move(to target: CGRect, color: UIColor, reduceMotion: Bool) {
            capsule.backgroundColor = color
            capsule.layer.cornerRadius = target.height / 2
            let layer = capsule.layer
            if reduceMotion { layer.removeAnimation(forKey: "selection") }
            guard capsule.frame != target else { return }

            let previous = layer.presentation()?.frame ?? capsule.frame
            let shouldSlide = !reduceMotion && !capsule.frame.isEmpty && !previous.isEmpty && !target.isEmpty
            UIView.performWithoutAnimation { self.capsule.frame = target }
            guard shouldSlide else {
                layer.removeAnimation(forKey: "selection")
                return
            }

            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = CGPoint(x: previous.midX, y: previous.midY)
            position.toValue = layer.position
            let bounds = CABasicAnimation(keyPath: "bounds.size")
            bounds.fromValue = previous.size
            bounds.toValue = target.size
            let slide = CAAnimationGroup()
            slide.animations = [position, bounds]
            slide.duration = BlotInterfaceMotion.Duration.quick
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(slide, forKey: "selection")
        }
    }
}
