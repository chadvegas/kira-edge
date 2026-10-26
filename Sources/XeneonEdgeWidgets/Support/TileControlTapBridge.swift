import AppKit
import SwiftUI

/// Routes mouse clicks for `EdgeTileControlButton` through a local event
/// monitor instead of SwiftUI's normal hit-testing.
///
/// macOS 26+ mis-places the AppKit hit-test region of `NSViewRepresentable`
/// content: the embedded web view's event region ends up vertically mirrored
/// about the window while its pixels draw in the correct place. Because the
/// platform claim wins, clicks on the web tile's header controls (reload /
/// open in browser) are delivered to the page and the buttons never fire.
///
/// The monitor sidesteps the broken routing entirely. It compares the raw
/// `event.locationInWindow` (true base coordinates, unaffected by the bug)
/// against the buttons' true frames reported by SwiftUI's own geometry
/// (equally unaffected), after a manual y-flip to align the two spaces. On a
/// hit it runs the button's action and swallows the event, so no click is
/// ever delivered twice and behavior is identical on macOS versions without
/// the routing bug.
@MainActor
final class TileControlTapBridge {
    static let shared = TileControlTapBridge()

    struct Entry {
        /// Button frame in SwiftUI's `.global` space: top-left origin of the
        /// window, y growing down. Matches `NSEvent.locationInWindow` once
        /// flipped with `flippedPoint(base:windowHeight:)`.
        var rect: CGRect
        let action: () -> Void
    }

    private final class WeakWindowBox {
        weak var window: NSWindow?
        init(_ window: NSWindow?) { self.window = window }
    }

    private(set) var entries: [UUID: Entry] = [:]
    /// Kept separately from `entries` because the window probe and the
    /// geometry callback report at different, unpredictable times; either
    //  order must work.
    private var windows: [UUID: WeakWindowBox] = [:]
    private var pendingDownID: UUID?
    private var monitor: Any?

    /// Converts a base window point (origin bottom-left) into SwiftUI's
    /// `.global` space (origin top-left) for a window of the given height.
    nonisolated static func flippedPoint(base: CGPoint, windowHeight: CGFloat) -> CGPoint {
        CGPoint(x: base.x, y: windowHeight - base.y)
    }

    func register(id: UUID, rect: CGRect, action: @escaping () -> Void) {
        entries[id] = Entry(rect: rect, action: action)
        if windows[id] == nil { windows[id] = WeakWindowBox(nil) }
        ensureMonitor()
    }

    func setWindow(id: UUID, window: NSWindow?) {
        windows[id] = WeakWindowBox(window)
        ensureMonitor()
    }

    func unregister(id: UUID) {
        entries[id] = nil
        windows[id] = nil
        if pendingDownID == id { pendingDownID = nil }
    }

    /// Installs the shared local event monitor once, only on macOS 26+ —
    /// the first version with the misplaced platform-view hit regions, and
    /// the SDK that renamed this API. Earlier systems route clicks through
    /// SwiftUI normally and never install the monitor. AppKit invokes local
    /// event monitors synchronously while dispatching events on the main
    /// thread, so — unlike the off-main system callbacks the strict-
    /// concurrency rule calls out — asserting main-actor isolation here is
    /// safe.
    private func ensureMonitor() {
        guard monitor == nil else { return }
        guard #available(macOS 26.0, *) else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            MainActor.assumeIsolated {
                TileControlTapBridge.shared.route(event)
            } ? nil : event
        }
    }

    /// Returns true when the event was consumed and should not be dispatched.
    private func route(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        let point = Self.flippedPoint(base: event.locationInWindow, windowHeight: window.frame.height)

        switch event.type {
        case .leftMouseDown:
            guard let id = hitID(window: window, point: point) else { return false }
            pendingDownID = id
            window.makeKeyAndOrderFront(nil)
            return true
        case .leftMouseUp:
            guard let downID = pendingDownID else { return false }
            pendingDownID = nil
            if let upID = hitID(window: window, point: point),
               upID == downID,
               let entry = entries[downID] {
                entry.action()
            }
            return true
        default:
            return false
        }
    }

    private func hitID(window: NSWindow, point: CGPoint) -> UUID? {
        entries.first {
            guard let registeredWindow = windows[$0.key]?.window else { return false }
            return registeredWindow === window && $0.value.rect.contains(point)
        }?.key
    }
}

/// Reports the enclosing `NSWindow` of a SwiftUI view via a zero-footprint
/// `NSView` probe, so button registrations can be matched to their window.
private struct WindowProbe: NSViewRepresentable {
    var onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange?(window)
        }
    }
}

/// Publishes the button's true frame and window to `TileControlTapBridge`
/// so clicks can be routed around the broken platform-view hit-testing.
struct TileControlTapRegistration: View {
    let id: UUID
    let action: () -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    TileControlTapBridge.shared.register(id: id, rect: geo.frame(in: .global), action: action)
                }
                .onChange(of: geo.frame(in: .global)) { _, rect in
                    TileControlTapBridge.shared.register(id: id, rect: rect, action: action)
                }
        }
        .background(
            WindowProbe { window in
                TileControlTapBridge.shared.setWindow(id: id, window: window)
            }
        )
        .onDisappear {
            TileControlTapBridge.shared.unregister(id: id)
        }
    }
}
