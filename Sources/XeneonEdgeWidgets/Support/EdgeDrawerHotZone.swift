import AppKit
import SwiftUI

struct EdgeDrawerHotZone: NSViewRepresentable {
    var onReveal: () -> Void
    var onHide: () -> Void

    func makeNSView(context: Context) -> HotZoneView {
        let view = HotZoneView()
        view.onReveal = onReveal
        view.onHide = onHide
        return view
    }

    func updateNSView(_ nsView: HotZoneView, context: Context) {
        nsView.onReveal = onReveal
        nsView.onHide = onHide
    }

    final class HotZoneView: NSView {
        var onReveal: (() -> Void)?
        var onHide: (() -> Void)?

        private var mouseDownPoint: NSPoint?

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            window?.makeFirstResponder(self)
        }

        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let start = mouseDownPoint else {
                onReveal?()
                return
            }

            let deltaY = point.y - start.y
            if abs(deltaY) > 8 {
                onReveal?()
            } else {
                onReveal?()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let start = mouseDownPoint else { return }
            if abs(point.y - start.y) > 12 {
                onReveal?()
            }
        }

        override func scrollWheel(with event: NSEvent) {
            if abs(event.scrollingDeltaY) > 0 || abs(event.scrollingDeltaX) > 0 {
                onReveal?()
            }
        }

        override func swipe(with event: NSEvent) {
            if event.deltaY != 0 || event.deltaX != 0 {
                onReveal?()
            }
        }
    }
}
