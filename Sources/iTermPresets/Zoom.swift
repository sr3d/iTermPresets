import AppKit
import SwiftUI

enum Zoom {
    static let storageKey = "uiZoom"
    static let levels: [Double] = [0.75, 0.85, 1, 1.15, 1.3, 1.5, 1.75, 2, 2.25, 2.5, 3]

    static func step(_ current: Double, by direction: Int) -> Double {
        if direction > 0 { return levels.first { $0 > current + 0.001 } ?? levels.last! }
        return levels.last { $0 < current - 0.001 } ?? levels.first!
    }
}

/// Lays the content out at the logical size (window ÷ zoom) and scales it up, so the
/// layout reflows at every zoom level instead of being magnified and clipped.
/// `scaleEffect` keeps SwiftUI's hit testing right; `SharpLayers` keeps the text crisp.
struct ZoomedContainer<Content: View>: View {
    let scale: Double
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(SharpLayers(scale: scale))
    }
}

/// `scaleEffect` alone stretches bitmaps rendered at 1× zoom, which blurs text. This re-renders
/// every layer in the window at `backingScaleFactor × zoom` so text and shapes stay sharp.
private struct SharpLayers: NSViewRepresentable {
    let scale: Double

    func makeNSView(context: Context) -> SharpLayersView { SharpLayersView() }
    func updateNSView(_ view: SharpLayersView, context: Context) { view.zoom = scale }
}

private final class SharpLayersView: NSView {
    var zoom: CGFloat = 1
    private var observer: CFRunLoopObserver?
    private var appliedScale: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { CFRunLoopObserverInvalidate(observer) }
        observer = nil
        guard window != nil else { return }
        // SwiftUI creates layers and resets their scale as it updates, so re-apply the scale
        // on every pass of the run loop — just before Core Animation commits the frame.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue,
                                                          true, 1_999_000) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyScale() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    deinit {
        if let observer { CFRunLoopObserverInvalidate(observer) }
    }

    private func applyScale() {
        guard let window, let root = window.contentView?.layer else { return }
        let scale = window.backingScaleFactor * zoom
        // At 1× nothing needs changing once the layers have been reset after zooming back.
        if zoom == 1, appliedScale == scale { return }
        appliedScale = scale
        Self.apply(scale, to: root)
    }

    private static func apply(_ scale: CGFloat, to layer: CALayer) {
        // Image layers hold a ready-made bitmap; redrawing them would leave them empty.
        if NSStringFromClass(type(of: layer)).hasSuffix("ImageLayer") { return }
        if layer.contentsScale != scale {
            layer.contentsScale = scale
            if layer.delegate != nil { layer.setNeedsDisplay() }
        }
        layer.sublayers?.forEach { apply(scale, to: $0) }
    }
}
