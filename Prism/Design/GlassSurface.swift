import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Quando `true`, `GlassSurface` / `QTGlassGroup` usam material em vez de
/// `.glassEffect` — obrigatório sob `NSGlassEffectView` (evitar nesting que
/// dispara `layoutSubtreeIfNeeded` recursion no AppKit).
private struct PreferMaterialOverGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var preferMaterialOverGlass: Bool {
        get { self[PreferMaterialOverGlassKey.self] }
        set { self[PreferMaterialOverGlassKey.self] = newValue }
    }
}

/// Superfície de controle que adota Liquid Glass no macOS 26 (Tahoe) e cai para
/// um preenchimento de material nos sistemas anteriores ou com transparência reduzida.
/// Use apenas na camada de controles/navegação — nunca em listas densas nem aninhado
/// sob outro glass AppKit (`preferMaterialOverGlass`).
struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat
    var prominent: Bool
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.preferMaterialOverGlass) private var preferMaterialOverGlass

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
        if #available(macOS 26.0, *), !reduceTransparency, !preferMaterialOverGlass {
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
                    .fill(.quaternary.opacity(prominent ? 0.55 : 0.4))
            )
    }
}

/// Agrupa superfícies glass irmãs para amostragem visual consistente (Tahoe).
/// Em sistemas anteriores (ou com `preferMaterialOverGlass`) é transparente ao layout.
struct QTGlassGroup<Content: View>: View {
    private let content: Content

    @Environment(\.preferMaterialOverGlass) private var preferMaterialOverGlass

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
#if PRISM_MACOS26_SDK
        if #available(macOS 26.0, *), !preferMaterialOverGlass {
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

#if canImport(AppKit)
/// Instala `NSGlassEffectView` como content view quando o SDK e o runtime suportam Tahoe.
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
        window.contentView = contentView
    }
}
#endif
