import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindowIfNeeded()
    }
}

final class WindowAccessorView: NSView {
    var onResolve: ((NSWindow) -> Void)?
    private weak var resolvedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindowIfNeeded()
    }

    func resolveWindowIfNeeded() {
        guard let window, resolvedWindow !== window else { return }
        resolvedWindow = window
        onResolve?(window)
    }
}
