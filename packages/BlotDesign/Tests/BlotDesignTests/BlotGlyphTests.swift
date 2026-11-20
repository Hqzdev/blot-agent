import Testing
@testable import BlotDesign

@Suite struct BlotGlyphTests {
    @Test(arguments: [
        ("house", "house.fill"), ("person", "person.crop.circle.fill"),
        ("person.2", "person.3.fill"), ("envelope", "envelope.fill"),
        ("bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill"),
        ("checkmark.circle", "checkmark.circle.fill"), ("mic", "mic.fill"),
        ("xmark.circle", "xmark.circle.fill"), ("newspaper", "newspaper.fill"),
    ])
    func filledAliasesUseTheSameOutline(_ pair: (String, String)) {
        #expect(BlotGlyph.resolve(symbol: pair.0) != nil)
        #expect(BlotGlyph.resolve(symbol: pair.0) == BlotGlyph.resolve(symbol: pair.1))
    }

    @Test(arguments: [
        "sidebar.right", "person.badge.plus", "brain", "shippingbox", "clock.arrow.circlepath",
        "creditcard", "chart.bar", "arrow.up.right", "arrow.up.left", "return",
        "chevron.up.chevron.down", "hifispeaker.2", "dollarsign.circle.fill", "externaldrive.fill",
        "key.fill", "number", "n.square.fill", "a.square", "asterisk", "triangle",
        "pause.circle", "arrow.down.circle", "point.3.connected.trianglepath.dotted", "photo.badge.plus",
        "checklist", "exclamationmark.circle", "lock.shield", "newspaper.fill",
    ])
    func workspaceSymbolsHaveDedicatedGlyphs(_ symbol: String) {
        let glyph = BlotGlyph.resolve(symbol: symbol)
        #expect(glyph != nil)
        #expect(glyph != .document)
    }

    @Test func catalogNamesResolveToTheirOwnArtwork() {
        for glyph in BlotGlyph.allCases {
            #expect(BlotGlyph.resolve(symbol: glyph.rawValue) == glyph)
        }
    }

    @Test func legacyMacAndPhoneNamesResolveToRoundedArtwork() {
        #expect(BlotGlyph.resolve(symbol: "square-pen") == .compose)
        #expect(BlotGlyph.resolve(symbol: "panel-right") == .inspector)
        #expect(BlotGlyph.resolve(symbol: "iphone") == .mobile)
        #expect(BlotGlyph.resolve(symbol: "internaldrive") == .drive)
        #expect(BlotGlyph.resolve(symbol: "photo.on.rectangle") == .image)
    }

    @Test func unsupportedSymbolsCanBeDetected() {
        #expect(BlotGlyph.resolve(symbol: "unsupported.symbol") == nil)
    }
}
