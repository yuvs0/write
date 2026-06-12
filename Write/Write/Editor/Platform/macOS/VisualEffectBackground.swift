#if os(macOS)
import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// The editor's surface: mostly the window background color over a thin
/// material, so the page reads bright and paper-like with only a hint of
/// behind-window depth. The sidebar keeps the system's own material.
struct EditorBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VisualEffectBackground(material: .underWindowBackground)
            .overlay(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.55 : 0.65)
            )
    }
}
#endif
