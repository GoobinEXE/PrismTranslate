import SwiftUI

/// Superfície de controle que adota Liquid Glass no macOS 26 (Tahoe) e cai para
/// um preenchimento de material nos sistemas anteriores ou com transparência reduzida.
struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat
    var prominent: Bool
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        cornerRadius: CGFloat = QTDesign.Radius.medium,
        prominent: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.prominent = prominent
        self.content = content()
    }

    var body: some View {
#if PRISM_MACOS26_SDK
        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            materialBackground
        }
#else
        materialBackground
#endif
    }

    @ViewBuilder
    private var materialBackground: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }
}

#if canImport(AppKit)
import AppKit

/// Fallback AppKit vibrancy quando o painel é `NSPanel` borderless (builds sem SDK 26).
enum GlassPanelChrome {
    static func install(
        contentView: NSView,
        in window: NSWindow,
        frame: NSRect,
        cornerRadius: CGFloat
    ) {
#if PRISM_MACOS26_SDK
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            contentView.autoresizingMask = [.width, .height]
            glass.contentView = contentView
            window.contentView = glass
            return
        }
#endif
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        contentView.autoresizingMask = [.width, .height]
        effect.addSubview(contentView)
        window.contentView = effect
    }
}
#endif

/// Agrupa superfícies glass irmãs para amostragem visual consistente (Tahoe).
/// Em sistemas anteriores é transparente ao layout.
struct QTGlassGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
#if PRISM_MACOS26_SDK
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
#else
        content
#endif
    }
}
