import AppKit
import SwiftUI

/// Glifo do Prism (cartão `A 文` + 3 faixas espectrais do `PrismTranslate.icon`)
/// para menu bar, onboarding e Sobre. Alinhado à grade de 18×18 pt.
struct PrismGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / PrismGlyphGeometry.gridSize
            ZStack {
                PrismGlyphPartShape(part: .card)
                    .stroke(style: StrokeStyle(lineWidth: 1.35 * unit, lineCap: .round, lineJoin: .round))
                PrismGlyphPartShape(part: .letterA)
                    .stroke(style: StrokeStyle(lineWidth: 1.2 * unit, lineCap: .round, lineJoin: .round))
                PrismGlyphPartShape(part: .letterWen)
                    .stroke(style: StrokeStyle(lineWidth: 1.15 * unit, lineCap: .round, lineJoin: .round))
                PrismGlyphPartShape(part: .bands)
                    .fill()
            }
        }
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
            let unit = min(rect.width, rect.height) / PrismGlyphGeometry.gridSize
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let card = PrismGlyphGeometry.bezierPath(for: .card, in: rect)
            card.lineWidth = 1.35 * unit
            card.lineCapStyle = .round
            card.lineJoinStyle = .round
            card.stroke()

            let letterA = PrismGlyphGeometry.bezierPath(for: .letterA, in: rect)
            letterA.lineWidth = 1.2 * unit
            letterA.lineCapStyle = .round
            letterA.lineJoinStyle = .round
            letterA.stroke()

            let letterWen = PrismGlyphGeometry.bezierPath(for: .letterWen, in: rect)
            letterWen.lineWidth = 1.15 * unit
            letterWen.lineCapStyle = .round
            letterWen.lineJoinStyle = .round
            letterWen.stroke()

            PrismGlyphGeometry.bezierPath(for: .bands, in: rect).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct PrismGlyphPartShape: Shape {
    let part: PrismGlyphGeometry.Part

    func path(in rect: CGRect) -> Path {
        PrismGlyphGeometry.path(for: part, in: rect)
    }
}

enum PrismGlyphGeometry {
    static let gridSize: CGFloat = 18

    enum Part {
        case card
        case letterA
        case letterWen
        case bands
    }

    static func path(for part: Part, in rect: CGRect) -> Path {
        var path = Path()
        switch part {
        case .card:
            let cardRect = scaledRect(x: 0.7, y: 3.5, width: 12.3, height: 11, in: rect)
            let radius = 2 * min(rect.width, rect.height) / gridSize
            path.addRoundedRect(in: cardRect, cornerSize: CGSize(width: radius, height: radius))

        case .letterA:
            path.move(to: pt(2.5, 11.5, in: rect))
            path.addLine(to: pt(4.2, 6.5, in: rect))
            path.addLine(to: pt(4.6, 6.5, in: rect))
            path.addLine(to: pt(6.3, 11.5, in: rect))
            path.move(to: pt(3.1, 9.8, in: rect))
            path.addLine(to: pt(5.7, 9.8, in: rect))

        case .letterWen:
            path.move(to: pt(9.6, 6.3, in: rect))
            path.addLine(to: pt(9.6, 7.3, in: rect))
            path.move(to: pt(7.4, 7.7, in: rect))
            path.addLine(to: pt(11.8, 7.7, in: rect))
            path.move(to: pt(11.0, 7.9, in: rect))
            path.addCurve(
                to: pt(7.7, 11.6, in: rect),
                control1: pt(10.6, 9.8, in: rect),
                control2: pt(9.5, 10.9, in: rect)
            )
            path.move(to: pt(8.2, 7.9, in: rect))
            path.addCurve(
                to: pt(11.5, 11.6, in: rect),
                control1: pt(8.6, 9.8, in: rect),
                control2: pt(9.7, 10.9, in: rect)
            )

        case .bands:
            let radius = 0.5 * min(rect.width, rect.height) / gridSize
            for y in [4.5, 8.0, 11.5] as [CGFloat] {
                let bandRect = scaledRect(x: 14.2, y: y, width: 3.3, height: 2, in: rect)
                path.addRoundedRect(in: bandRect, cornerSize: CGSize(width: radius, height: radius))
            }
        }
        return path
    }

    static func bezierPath(for part: Part, in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        switch part {
        case .card:
            let cardRect = scaledRect(x: 0.7, y: 3.5, width: 12.3, height: 11, in: rect)
            let radius = 2 * min(rect.width, rect.height) / gridSize
            path.appendRoundedRect(cardRect, xRadius: radius, yRadius: radius)

        case .letterA:
            path.move(to: pt(2.5, 11.5, in: rect))
            path.line(to: pt(4.2, 6.5, in: rect))
            path.line(to: pt(4.6, 6.5, in: rect))
            path.line(to: pt(6.3, 11.5, in: rect))
            path.move(to: pt(3.1, 9.8, in: rect))
            path.line(to: pt(5.7, 9.8, in: rect))

        case .letterWen:
            path.move(to: pt(9.6, 6.3, in: rect))
            path.line(to: pt(9.6, 7.3, in: rect))
            path.move(to: pt(7.4, 7.7, in: rect))
            path.line(to: pt(11.8, 7.7, in: rect))
            path.move(to: pt(11.0, 7.9, in: rect))
            path.curve(
                to: pt(7.7, 11.6, in: rect),
                controlPoint1: pt(10.6, 9.8, in: rect),
                controlPoint2: pt(9.5, 10.9, in: rect)
            )
            path.move(to: pt(8.2, 7.9, in: rect))
            path.curve(
                to: pt(11.5, 11.6, in: rect),
                controlPoint1: pt(8.6, 9.8, in: rect),
                controlPoint2: pt(9.7, 10.9, in: rect)
            )

        case .bands:
            let radius = 0.5 * min(rect.width, rect.height) / gridSize
            for y in [4.5, 8.0, 11.5] as [CGFloat] {
                let bandRect = scaledRect(x: 14.2, y: y, width: 3.3, height: 2, in: rect)
                path.appendRoundedRect(bandRect, xRadius: radius, yRadius: radius)
            }
        }
        return path
    }

    private static func pt(_ u: CGFloat, _ v: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * (u / gridSize),
            y: rect.minY + rect.height * (v / gridSize)
        )
    }

    private static func scaledRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + rect.width * (x / gridSize),
            y: rect.minY + rect.height * (y / gridSize),
            width: rect.width * (width / gridSize),
            height: rect.height * (height / gridSize)
        )
    }
}
