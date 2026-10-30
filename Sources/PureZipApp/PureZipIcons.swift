import AppKit
import SwiftUI

public enum PureZipIcons {
    /// Generates the crisp monochrome template icon for the macOS Menu Bar matching the in-app "shippingbox.fill" logo
    public static var menuBarPureShelfIcon: NSImage {
        if let sym = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "PureZip") {
            let conf = NSImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)
            let configured = sym.withSymbolConfiguration(conf) ?? sym
            configured.isTemplate = true
            return configured
        }

        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let strokeColor = NSColor.black
            strokeColor.setStroke()
            strokeColor.setFill()

            // Outer isometric hexagon outline
            let path = NSBezierPath()
            path.lineWidth = 1.3
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let top = NSPoint(x: 9.0, y: 15.5)
            let rightTop = NSPoint(x: 15.2, y: 12.0)
            let rightBottom = NSPoint(x: 15.2, y: 5.5)
            let bottom = NSPoint(x: 9.0, y: 2.0)
            let leftBottom = NSPoint(x: 2.8, y: 5.5)
            let leftTop = NSPoint(x: 2.8, y: 12.0)
            let center = NSPoint(x: 9.0, y: 8.8)

            path.move(to: top)
            path.line(to: rightTop)
            path.line(to: rightBottom)
            path.line(to: bottom)
            path.line(to: leftBottom)
            path.line(to: leftTop)
            path.close()
            path.stroke()

            // Inner Y lines separating the 3 isometric facets
            let inner = NSBezierPath()
            inner.lineWidth = 1.2
            inner.lineCapStyle = .round
            inner.lineJoinStyle = .round

            inner.move(to: center)
            inner.line(to: top)
            inner.move(to: center)
            inner.line(to: leftBottom)
            inner.move(to: center)
            inner.line(to: rightBottom)
            inner.stroke()

            // Subtle dot on the top facet
            let dot = NSBezierPath(ovalIn: NSRect(x: 8.1, y: 11.2, width: 1.8, height: 1.8))
            dot.fill()

            return true
        }
        img.isTemplate = true
        return img
    }

    public static var menuBarArchIcon: NSImage {
        menuBarPureShelfIcon
    }
}
