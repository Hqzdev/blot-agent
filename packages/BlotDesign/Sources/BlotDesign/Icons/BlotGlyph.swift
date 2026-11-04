import Foundation

/// Blot's thin, rounded outline icons. Source vectors live in BlotIcons.xcassets.
nonisolated public enum BlotGlyph: String, CaseIterable, Sendable {
    case home, chat, chats, person, people, folder, settings, sliders, search, plus
    case close, closeCircle, chevronLeft, chevronRight, chevronDown, arrowUp, arrowDown
    case download, compose, calendar, calendarAdd, computer, laptop, camera, image, paperclip
    case document, pdf, code, spreadsheet, presentation, archive, audio, video, copy
    case check, checkCircle, shield, shieldCheck, warning, info, question, circle, progress
    case refresh, play, pause, stop, more, moreVertical, star, pin, bell, bellOff, sun, moon, globe, language
    case filter, list, grid, layout, plug, puzzle, chip, sparkle, share, send, email
    case microphone, microphoneOff, logout, lock, network, qr, scan, heart, bookmark, reply, archiveBox, trash

    case newspaper, inspector, personAdd, memory, skill, routine, card, usage, arrowUpRight, arrowUpLeft, returnKey, chevronsUpDown, speakers, currency, drive, key, hash, note, app, asterisk, outlineTriangle

    public var assetName: String { "BlotIcon-" + rawValue }

    /// Existing model keys resolve to one outline family, including their former filled variants.
    public init(symbol: String) { self = Self.resolve(symbol: symbol) ?? .document }

    public static func resolve(symbol: String) -> Self? {
        switch symbol {
        case "house", "house.fill": return .home
        case "bubble.left", "bubble.left.fill": return .chat
        case "bubble.left.and.bubble.right": return .chats
        case "person", "person.fill", "person.crop.circle": return .person
        case "person.2", "person.2.fill": return .people
        case "folder", "folder.fill": return .folder
        case "gear", "gearshape": return .settings
        case "sliders", "slider.horizontal.3": return .sliders
        case "line.3.horizontal.decrease": return .filter
        case "magnifyingglass": return .search
        case "plus": return .plus
        case "xmark": return .close
        case "xmark.circle", "xmark.circle.fill", "xmark.octagon": return .closeCircle
        case "chevron.left": return .chevronLeft
        case "chevron.right": return .chevronRight
        case "chevron.down": return .chevronDown
        case "arrow.up": return .arrowUp
        case "arrow.down": return .arrowDown
        case "arrow.down.to.line": return .download
        case "square.and.pencil", "pencil": return .compose
        case "calendar", "calendar.badge.clock": return .calendar
        case "calendar.badge.plus": return .calendarAdd
        case "desktopcomputer": return .computer
        case "laptopcomputer": return .laptop
        case "camera": return .camera
        case "photo": return .image
        case "paperclip": return .paperclip
        case "doc", "doc.text", "text.document", "list.bullet.clipboard", "doc.badge.ellipsis": return .document
        case "doc.richtext": return .pdf
        case "chevron.left.forwardslash.chevron.right", "terminal": return .code
        case "tablecells": return .spreadsheet
        case "rectangle.on.rectangle": return .presentation
        case "doc.zipper": return .archive
        case "waveform": return .audio
        case "film": return .video
        case "doc.on.doc": return .copy
        case "arrowshape.turn.up.left": return .reply
        case "archivebox": return .archiveBox
        case "trash", "trash.fill": return .trash
        case "checkmark": return .check
        case "checkmark.circle": return .checkCircle
        case "checkmark.shield": return .shieldCheck
        case "exclamationmark.shield": return .shield
        case "exclamationmark.triangle": return .warning
        case "info.circle": return .info
        case "questionmark.circle": return .question
        case "circle": return .circle
        case "circle.lefthalf.filled", "gauge": return .progress
        case "arrow.clockwise": return .refresh
        case "play": return .play
        case "pause": return .pause
        case "stop", "stop.fill", "square": return .stop
        case "ellipsis": return .more
        case "ellipsis.vertical": return .moreVertical
        case "star.fill": return .star
        case "pin": return .pin
        case "bell": return .bell
        case "bell.slash": return .bellOff
        case "sun.max": return .sun
        case "moon": return .moon
        case "globe": return .globe
        case "character.bubble", "rectangle.bottomthird.inset.filled": return .language
        case "list.bullet": return .list
        case "square.grid.2x2": return .grid
        case "rectangle.split.2x1", "sidebar.left": return .layout
        case "powerplug": return .plug
        case "puzzlepiece.extension": return .puzzle
        case "cpu": return .chip
        case "sparkle": return .sparkle
        case "square.and.arrow.up": return .share
        case "paperplane": return .send
        case "envelope": return .email
        case "mic", "mic.fill": return .microphone
        case "mic.slash": return .microphoneOff
        case "rectangle.portrait.and.arrow.right": return .logout
        case "lock": return .lock
        case "network": return .network
        case "qrcode": return .qr
        case "qrcode.viewfinder", "viewfinder": return .scan
        case "heart": return .heart
        case "bookmark": return .bookmark
        case "paintbrush": return .compose
        case "sidebar.right": return .inspector
        case "person.badge.plus": return .personAdd
        case "person.3", "person.3.fill": return .people
        case "person.crop.circle.fill": return .person
        case "brain": return .memory
        case "shippingbox": return .skill
        case "clock.arrow.circlepath", "arrow.clockwise.circle": return .routine
        case "creditcard": return .card
        case "chart.bar": return .usage
        case "arrow.up.right": return .arrowUpRight
        case "arrow.up.left": return .arrowUpLeft
        case "return": return .returnKey
        case "chevron.up.chevron.down": return .chevronsUpDown
        case "hifispeaker.2": return .speakers
        case "dollarsign.circle.fill": return .currency
        case "externaldrive.fill": return .drive
        case "key.fill", "key": return .key
        case "number": return .hash
        case "n.square.fill": return .note
        case "a.square": return .app
        case "asterisk": return .asterisk
        case "triangle": return .outlineTriangle
        case "envelope.fill": return .email
        case "bubble.left.and.bubble.right.fill": return .chats
        case "checkmark.circle.fill": return .checkCircle
        case "pause.circle": return .pause
        case "arrow.down.circle": return .download
        case "point.3.connected.trianglepath.dotted": return .network
        case "photo.badge.plus": return .image
        case "checklist": return .list
        case "exclamationmark.circle": return .warning
        case "lock.shield": return .shieldCheck
        case "star": return .star
        case "doc.plaintext", "doc.text.magnifyingglass": return .document
        case "newspaper", "newspaper.fill": return .newspaper
        default: return nil
        }
    }
}
