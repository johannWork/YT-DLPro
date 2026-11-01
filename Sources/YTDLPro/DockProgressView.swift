import AppKit

@MainActor
final class DockProgressView: NSView {
    static let shared = DockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

    private var progress = 0.0

    override var isFlipped: Bool { true }

    func update(progress: Double) {
        self.progress = min(max(progress, 0), 1)
        needsDisplay = true
        NSApp.dockTile.display()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let iconHeight = bounds.height - 12
        NSApp.applicationIconImage.draw(in: NSRect(x: 8, y: 2, width: bounds.width - 16, height: iconHeight))

        let track = NSRect(x: 14, y: bounds.height - 11, width: bounds.width - 28, height: 6)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()

        if progress > 0 {
            var fill = track
            fill.size.width *= progress
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
        }
    }
}