#if os(macOS)
import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        if cornerRadius > 0 {
            view.maskImage = Self.roundedMask(cornerRadius: cornerRadius)
        }
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        if cornerRadius > 0 {
            view.maskImage = Self.roundedMask(cornerRadius: cornerRadius)
        }
    }

    private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
        let size = NSSize(width: cornerRadius * 2 + 1, height: cornerRadius * 2 + 1)
        let image = NSImage(size: size, flipped: false, drawingHandler: { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        })
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
#endif
