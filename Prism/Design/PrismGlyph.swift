import AppKit
import SwiftUI

/// Glifo de prisma óptico (triângulo + feixe) para menu bar, onboarding e Sobre.
/// Traço único, pensado para template monocromático em ~16–18 pt.
struct PrismGlyph: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        PrismGlyphShape()
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .aspectRatio(1, contentMode: .fit)
    }
}

/// Ícone da barra de menus: `NSImage` template. `MenuBarExtra` não rasteriza
/// `Shape` SwiftUI — o botão aparece, o traço não.
enum PrismMenuBarImage {
    static let pointSize: CGFloat = 18

    static let prism: NSImage = {
        let size = NSSize(width: pointSize, height: pointSize)
        // flipped: true = origem no topo, igual ao SwiftUI Path.
        let image = NSImage(size: size, flipped: true) { rect in
            let inset = rect.insetBy(dx: 1.5, dy: 1.5)
            let path = PrismGlyphGeometry.bezierPath(in: inset)
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

struct PrismGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        PrismGlyphGeometry.path(in: rect)
    }
}

enum PrismGlyphGeometry {
    static func path(in rect: CGRect) -> Path {
        let p = points(in: rect)
        var path = Path()
        path.move(to: p.apex)
        path.addLine(to: p.left)
        path.addLine(to: p.right)
        path.closeSubpath()
        path.move(to: p.apex)
        path.addLine(to: p.back)
        path.addLine(to: p.right)
        path.move(to: p.beamIn)
        path.addLine(to: p.beamHit)
        path.move(to: p.fanOrigin)
        path.addLine(to: p.fanTop)
        path.move(to: p.fanOrigin)
        path.addLine(to: p.fanMid)
        path.move(to: p.fanOrigin)
        path.addLine(to: p.fanBottom)
        return path
    }

    static func bezierPath(in rect: CGRect) -> NSBezierPath {
        let p = points(in: rect)
        let path = NSBezierPath()
        path.move(to: p.apex)
        path.line(to: p.left)
        path.line(to: p.right)
        path.close()
        path.move(to: p.apex)
        path.line(to: p.back)
        path.line(to: p.right)
        path.move(to: p.beamIn)
        path.line(to: p.beamHit)
        path.move(to: p.fanOrigin)
        path.line(to: p.fanTop)
        path.move(to: p.fanOrigin)
        path.line(to: p.fanMid)
        path.move(to: p.fanOrigin)
        path.line(to: p.fanBottom)
        return path
    }

    private struct Points {
        var apex, left, right, back: CGPoint
        var beamIn, beamHit, fanOrigin, fanTop, fanMid, fanBottom: CGPoint
    }

    private static func points(in rect: CGRect) -> Points {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        func pt(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: x + w * u, y: y + h * v)
        }
        return Points(
            apex: pt(0.44, 0.12),
            left: pt(0.14, 0.84),
            right: pt(0.66, 0.84),
            back: pt(0.76, 0.56),
            beamIn: pt(0.00, 0.48),
            beamHit: pt(0.26, 0.52),
            fanOrigin: pt(0.68, 0.52),
            fanTop: pt(0.98, 0.28),
            fanMid: pt(0.98, 0.52),
            fanBottom: pt(0.98, 0.76)
        )
    }
}
