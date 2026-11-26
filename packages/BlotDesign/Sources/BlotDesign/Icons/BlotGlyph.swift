import Foundation

/// Ori’s rounded template icons. Source vectors live in BlotIcons.xcassets.
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

    case minus, chevronUp, branch, link, phone, phoneEnd, unpin, record, thumbsUp, thumbsDown

    case activity, agent, arrowLeft, arrowRight, atSign, bolt, book, clock
    case expand, eye, fileAdd, flag, folderAdd, folderOpen, gauge, keyboard
    case lifebuoy, location, mobile, newWindow, pointer, pullRequest, rotateBack, running
    case server, shuffle, terminal, tray, wifiOff

    case textCursor

    public var assetName: String { "BlotIcon-" + rawValue }

    /// Existing model keys resolve to one outline family, including their former filled variants.
    public init(symbol: String) { self = Self.resolve(symbol: symbol) ?? .document }

    public static func resolve(symbol: String) -> Self? {
        switch symbol {
        case "waveform.path.ecg": return .activity
        case "a.square": return .app
        case "doc.zipper": return .archive
        case "archivebox": return .archiveBox
        case "arrow.down": return .arrowDown
        case "arrow.left": return .arrowLeft
        case "arrow.right", "arrow-right": return .arrowRight
        case "arrow.up", "arrow-up": return .arrowUp
        case "arrow.up.left": return .arrowUpLeft
        case "arrow.up.right", "arrow.up.right.square", "square-arrow-out-up-right": return .arrowUpRight
        case "at": return .atSign
        case "waveform": return .audio
        case "bell.slash": return .bellOff
        case "zap": return .bolt
        case "arrow.triangle.branch", "workflow", "git-branch": return .branch
        case "calendar.badge.clock": return .calendar
        case "calendar.badge.plus": return .calendarAdd
        case "creditcard": return .card
        case "bubble.left", "bubble.left.fill", "message-square": return .chat
        case "bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill", "messages-square": return .chats
        case "checkmark": return .check
        case "checkmark.circle", "checkmark.circle.fill", "circle-check": return .checkCircle
        case "chevron.down", "chevron-down": return .chevronDown
        case "chevron.left", "chevron-left": return .chevronLeft
        case "chevron.right", "chevron-right": return .chevronRight
        case "chevron.up", "chevron-up": return .chevronUp
        case "chevron.up.chevron.down": return .chevronsUpDown
        case "cpu": return .chip
        case "circle.fill": return .circle
        case "xmark", "x": return .close
        case "xmark.circle", "xmark.circle.fill", "xmark.octagon": return .closeCircle
        case "chevron.left.forwardslash.chevron.right": return .code
        case "square.and.pencil", "pencil", "paintbrush", "square-pen": return .compose
        case "desktopcomputer", "monitor", "display": return .computer
        case "doc.on.doc": return .copy
        case "dollarsign.circle.fill": return .currency
        case "doc", "doc.text", "text.document", "list.bullet.clipboard", "doc.badge.ellipsis", "doc.plaintext", "doc.text.magnifyingglass", "file-text": return .document
        case "arrow.down.to.line", "arrow.down.circle", "square.and.arrow.down": return .download
        case "externaldrive.fill", "internaldrive": return .drive
        case "envelope", "envelope.fill", "mail": return .email
        case "maximize-2", "arrow.up.left.and.arrow.down.right": return .expand
        case "doc.badge.plus": return .fileAdd
        case "line.3.horizontal.decrease", "list-filter": return .filter
        case "folder.fill": return .folder
        case "folder.badge.plus": return .folderAdd
        case "folder-open": return .folderOpen
        case "gauge.with.dots.needle.33percent": return .gauge
        case "square.grid.2x2", "grid-2x2": return .grid
        case "number": return .hash
        case "house", "house.fill": return .home
        case "photo", "photo.badge.plus", "photo.on.rectangle", "photo.on.rectangle.angled": return .image
        case "info.circle": return .info
        case "sidebar.right", "panel-right": return .inspector
        case "key.fill": return .key
        case "character.bubble", "rectangle.bottomthird.inset.filled": return .language
        case "laptopcomputer": return .laptop
        case "rectangle.split.2x1", "sidebar.left", "panel-left": return .layout
        case "lifepreserver": return .lifebuoy
        case "list.bullet", "checklist", "list.bullet.rectangle": return .list
        case "mappin.and.ellipse": return .location
        case "rectangle.portrait.and.arrow.right", "log-out": return .logout
        case "brain": return .memory
        case "mic", "mic.fill": return .microphone
        case "mic.slash", "mic.slash.fill": return .microphoneOff
        case "minus.circle": return .minus
        case "iphone": return .mobile
        case "ellipsis": return .more
        case "ellipsis.vertical": return .moreVertical
        case "point.3.connected.trianglepath.dotted": return .network
        case "macwindow.on.rectangle": return .newWindow
        case "newspaper.fill": return .newspaper
        case "n.square.fill": return .note
        case "triangle": return .outlineTriangle
        case "pause.circle", "pause.fill": return .pause
        case "doc.richtext": return .pdf
        case "person.2", "person.2.fill", "person.3", "person.3.fill", "users": return .people
        case "person.fill", "person.crop.circle", "person.crop.circle.fill", "person.crop.circle.badge.checkmark", "user": return .person
        case "person.badge.plus", "person.crop.circle.badge.plus", "user-plus": return .personAdd
        case "phone.fill": return .phone
        case "phone.down.fill": return .phoneEnd
        case "pin.fill": return .pin
        case "powerplug", "app.connected.to.app.below.fill": return .plug
        case "cursorarrow", "mouse-pointer-click", "cursorarrow.click": return .pointer
        case "rectangle.on.rectangle": return .presentation
        case "circle.lefthalf.filled": return .progress
        case "arrow.triangle.pull", "git-pull-request": return .pullRequest
        case "puzzlepiece.extension": return .puzzle
        case "qrcode": return .qr
        case "questionmark.circle": return .question
        case "record.circle", "smallcircle.filled.circle", "circle-dot": return .record
        case "arrow.clockwise": return .refresh
        case "arrow.uturn.backward", "arrowshape.turn.up.left": return .reply
        case "return": return .returnKey
        case "rotate-ccw", "arrow.counterclockwise": return .rotateBack
        case "clock.arrow.circlepath", "arrow.clockwise.circle": return .routine
        case "circle.dotted": return .running
        case "qrcode.viewfinder", "viewfinder", "text.viewfinder": return .scan
        case "magnifyingglass": return .search
        case "paperplane": return .send
        case "gear", "gearshape": return .settings
        case "square.and.arrow.up": return .share
        case "exclamationmark.shield", "hand.raised", "xmark.shield", "shield-alert": return .shield
        case "globe.badge.shield.half.filled", "checkmark.shield", "lock.shield", "shield-check": return .shieldCheck
        case "shippingbox", "cube": return .skill
        case "slider.horizontal.3", "sliders-horizontal": return .sliders
        case "hifispeaker.2": return .speakers
        case "tablecells": return .spreadsheet
        case "star.fill": return .star
        case "stop.fill", "square", "stop.circle": return .stop
        case "sun.max": return .sun
        case "hand.thumbsdown", "hand.thumbsdown.fill": return .thumbsDown
        case "hand.thumbsup", "hand.thumbsup.fill": return .thumbsUp
        case "trash.fill", "trash-2": return .trash
        case "pin.slash": return .unpin
        case "chart.bar", "chart-bar": return .usage
        case "film": return .video
        case "exclamationmark.triangle", "exclamationmark.circle", "exclamationmark.circle.fill", "circle-alert": return .warning
        case "wifi.slash": return .wifiOff
        case "play.fill": return .play
        case "text.cursor": return .textCursor
        default: return Self(rawValue: symbol)
        }
    }
}
