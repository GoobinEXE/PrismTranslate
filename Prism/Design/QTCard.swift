import SwiftUI

/// Cartão de conteúdo nativo e leve: preenchimento semântico do sistema + filete.
/// HIG (macOS 26): Liquid Glass fica na camada flutuante (painel de resultado, HUD,
/// onboarding), não em cada cartão de conteúdo. As cores semânticas acompanham claro,
/// escuro e Aumentar Contraste.
struct QTCard<Content: View>: View {
    var cornerRadius: CGFloat
    private let content: Content

    init(
        cornerRadius: CGFloat = QTDesign.Radius.medium,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.fill.quaternary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
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
