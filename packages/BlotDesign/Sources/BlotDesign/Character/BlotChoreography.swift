import Foundation

/// Small authored scenes. Randomness affects expression direction, never the pacing.
nonisolated struct BlotChoreography {
    nonisolated struct Beat {
        let state: BlotState
        let duration: Double
    }

    private var index = 0
    private let beats: [Beat] = [
        // Notices something, leans closer, smiles and settles.
        .init(state: .glance, duration: 1.6), .init(state: .curious, duration: 1.7),
        .init(state: .happy, duration: 1.1), .init(state: .idle, duration: 0.9),
        .init(state: .nod, duration: 1.0), .init(state: .idle, duration: 0.9),
        // Stretches, checks the landing, hops and winks.
        .init(state: .stretch, duration: 2.0), .init(state: .glance, duration: 1.6),
        .init(state: .jump, duration: 0.9), .init(state: .idle, duration: 1.0),
        .init(state: .wink, duration: 0.9), .init(state: .idle, duration: 0.8),
        // Looks around, tilts and gives a playful wiggle.
        .init(state: .planning, duration: 2.4), .init(state: .curious, duration: 1.7),
        .init(state: .wiggle, duration: 1.1), .init(state: .idle, duration: 0.9),
        .init(state: .glance, duration: 1.6), .init(state: .idle, duration: 0.8),
        // Peeks out, then acknowledges the user before starting over.
        .init(state: .nod, duration: 1.0), .init(state: .glance, duration: 1.6),
        .init(state: .peekaboo, duration: 1.8), .init(state: .idle, duration: 0.9),
        .init(state: .wink, duration: 0.9), .init(state: .idle, duration: 0.9),
    ]

    var next: Beat { beats[index] }

    mutating func advance() { index = (index + 1) % beats.count }
}
