import Foundation

/// Independent, smoothly looping mannerisms for the welcome screen's nine agents.
enum PhoneWelcomeAgentMotion: Int, CaseIterable {
    case doubleBlink, lookAround, nod, wink, curious, sway, sleepy, bounce, peek

    struct Pose {
        var leftEye = 1.0
        var rightEye = 1.0
        var gazeX = 0.0
        var gazeY = 0.0
        var tilt = 0.0
        var lift = 0.0
        var stretch = 1.0
    }

    func pose(at time: Double) -> Pose {
        var pose = Pose()
        let seed = Double(rawValue)
        let blink = pulse(time + seed * 0.71, period: 4.7 + seed * 0.19, start: 2, duration: 0.28)
        pose.leftEye = 1 - blink * 0.92
        pose.rightEye = pose.leftEye

        switch self {
        case .doubleBlink:
            let first = pulse(time, period: 5.6, start: 1.3, duration: 0.28)
            let second = pulse(time, period: 5.6, start: 1.72, duration: 0.28)
            pose.leftEye = 1 - max(first, second) * 0.92
            pose.rightEye = pose.leftEye
            pose.tilt = 2 * sin(time * 0.9)
        case .lookAround:
            pose.gazeX = 0.11 * sin(time * 0.95)
            pose.gazeY = -0.025 * (1 - cos(time * 0.95))
            pose.tilt = 4 * sin(time * 0.95)
        case .nod:
            let nod = pulse(time, period: 4.8, start: 1, duration: 1.8)
            pose.gazeY = nod * 0.055
            pose.tilt = nod * 7
            pose.lift = nod * 0.035
            pose.stretch = 1 - nod * 0.035
        case .wink:
            pose.rightEye = min(pose.rightEye, 1 - 0.92 * pulse(time, period: 5.1, start: 1.7, duration: 0.55))
            pose.tilt = -6 * pulse(time, period: 5.1, start: 1.45, duration: 1.1)
        case .curious:
            let glance = pulse(time, period: 6.4, start: 0.8, duration: 3.6)
            pose.gazeX = glance * 0.085
            pose.gazeY = -glance * 0.07
            pose.tilt = glance * 10
            pose.leftEye *= 1 - glance * 0.2
        case .sway:
            pose.tilt = 8 * sin(time * 1.25)
            pose.gazeX = -0.055 * sin(time * 1.25)
            pose.lift = -0.015 * (1 - cos(time * 2.5))
        case .sleepy:
            let drowse = pulse(time, period: 7.2, start: 1.4, duration: 3.8)
            pose.leftEye *= 1 - drowse * 0.72
            pose.rightEye *= 1 - drowse * 0.72
            pose.gazeY = drowse * 0.035
            pose.tilt = -drowse * 8
            pose.stretch = 1 - drowse * 0.025
        case .bounce:
            let hop = pulse(time, period: 3.6, start: 0.7, duration: 1.8)
            pose.lift = -hop * 0.09
            pose.stretch = 1 + hop * 0.045
            pose.gazeY = -hop * 0.035
            pose.tilt = 3 * sin(time * 1.4)
        case .peek:
            let glance = pulse(time, period: 5.8, start: 1, duration: 2.8)
            pose.gazeX = -glance * 0.11
            pose.gazeY = glance * 0.04
            pose.tilt = -glance * 7
            pose.rightEye *= 1 - glance * 0.3
        }
        return pose
    }

    /// Raised cosine has zero velocity at both ends, including the loop seam.
    private func pulse(_ time: Double, period: Double, start: Double, duration: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: period)
        guard phase >= start, phase <= start + duration else { return 0 }
        return (1 - cos((phase - start) / duration * 2 * .pi)) / 2
    }
}
