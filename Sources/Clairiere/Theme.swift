import AppKit
import SwiftUI

enum Theme {
    @MainActor static weak var store: MemoryStore?

    static var light: Bool {
        MainActor.assumeIsolated { store?.lightTheme ?? false }
    }

    static var scheme: ColorScheme { light ? .light : .dark }
    static var bg: Color { light ? meadow : night }
    static var card: Color { light ? paper : bark }
    static var cardRaised: Color { light ? moss : raised }
    static var line: Color { light ? Color.black.opacity(0.08) : Color.white.opacity(0.07) }
    static var wash: Color { light ? Color.black.opacity(0.06) : Color.white.opacity(0.06) }
    static var text: Color { light ? ink : cream }
    static var muted: Color { light ? sage : dusk }
    static var leaf: Color { light ? leafDeep : leafBright }
    static var gold: Color { light ? goldDeep : goldBright }
    static var coral: Color { light ? coralDeep : coralBright }
    static var sky: Color { light ? skyDeep : skyBright }
    static var lilac: Color { light ? lilacDeep : lilacBright }

    static let night = Color(red: 0.067, green: 0.071, blue: 0.059)
    static let bark = Color(red: 0.110, green: 0.118, blue: 0.098)
    static let raised = Color(red: 0.145, green: 0.155, blue: 0.125)
    static let cream = Color(red: 0.95, green: 0.94, blue: 0.90)
    static let dusk = Color(red: 0.62, green: 0.64, blue: 0.55)
    static let leafBright = Color(red: 0.78, green: 0.95, blue: 0.43)
    static let goldBright = Color(red: 0.94, green: 0.76, blue: 0.48)
    static let coralBright = Color(red: 1.0, green: 0.55, blue: 0.48)
    static let skyBright = Color(red: 0.60, green: 0.84, blue: 1.0)
    static let lilacBright = Color(red: 0.78, green: 0.70, blue: 0.96)

    static let meadow = Color(red: 0.965, green: 0.949, blue: 0.906)
    static let paper = Color(red: 0.996, green: 0.988, blue: 0.965)
    static let moss = Color(red: 0.886, green: 0.929, blue: 0.835)
    static let ink = Color(red: 0.133, green: 0.176, blue: 0.122)
    static let sage = Color(red: 0.380, green: 0.431, blue: 0.345)
    static let leafDeep = Color(red: 0.176, green: 0.478, blue: 0.275)
    static let goldDeep = Color(red: 0.659, green: 0.420, blue: 0.122)
    static let coralDeep = Color(red: 0.769, green: 0.294, blue: 0.259)
    static let skyDeep = Color(red: 0.165, green: 0.435, blue: 0.639)
    static let lilacDeep = Color(red: 0.431, green: 0.353, blue: 0.651)

    static let nightNS = NSColor(srgbRed: 0.067, green: 0.071, blue: 0.059, alpha: 1)
    static let meadowNS = NSColor(srgbRed: 0.965, green: 0.949, blue: 0.906, alpha: 1)
}

struct WindowChrome: NSViewRepresentable {
    var light: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let light = light
        DispatchQueue.main.async {
            configure(view, coordinator: context.coordinator)
            apply(view, light: light)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView, coordinator: context.coordinator)
        apply(nsView, light: light)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var configured = false
    }

    private func configure(_ view: NSView, coordinator: Coordinator) {
        guard let window = view.window, !coordinator.configured else { return }
        coordinator.configured = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 1100, height: 720)
        window.tabbingMode = .disallowed
        if window.frame.width < 1100 || window.frame.height < 720 {
            window.setContentSize(NSSize(width: 1280, height: 840))
            window.center()
        }
    }

    private func apply(_ view: NSView, light: Bool) {
        guard let window = view.window else { return }
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        window.backgroundColor = light ? Theme.meadowNS : Theme.nightNS
    }
}
