import AppKit

// Contours from Resources/status-bar-icon.svg, with no optical adjustments.
enum StatusBarIcon {
    static func make() -> NSImage {
        let outlines = [bucketPath(), cursorPath()]
        // AppKit redraws these vectors at the destination display's pixel density.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            for outline in outlines {
                context.addPath(outline)
                context.fillPath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cursor Wash"
        return image
    }

    static func bucketPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 14.9622, y: 2.65274))
        path.addCurve(to: CGPoint(x: 15.4466, y: 3.26211),
                      control1: CGPoint(x: 15.2639, y: 2.68714),
                      control2: CGPoint(x: 15.4808, y: 2.96046))
        path.addLine(to: CGPoint(x: 14.1468, y: 14.6615))
        path.addLine(to: CGPoint(x: 14.1458, y: 14.6606))
        path.addCurve(to: CGPoint(x: 13.6038, y: 16.2592),
                      control1: CGPoint(x: 14.0923, y: 15.286),
                      control2: CGPoint(x: 13.9554, y: 15.8519))
        path.addCurve(to: CGPoint(x: 12.0999, y: 16.85),
                      control1: CGPoint(x: 13.2238, y: 16.6992),
                      control2: CGPoint(x: 12.6906, y: 16.85))
        path.addLine(to: CGPoint(x: 5.89974, y: 16.85))
        path.addCurve(to: CGPoint(x: 4.39583, y: 16.2592),
                      control1: CGPoint(x: 5.30919, y: 16.85),
                      control2: CGPoint(x: 4.77578, y: 16.6991))
        path.addCurve(to: CGPoint(x: 3.85189, y: 14.6449),
                      control1: CGPoint(x: 4.04148, y: 15.8486),
                      control2: CGPoint(x: 3.90451, y: 15.2764))
        path.addLine(to: CGPoint(x: 2.55306, y: 3.26211))
        path.addCurve(to: CGPoint(x: 3.03743, y: 2.65274),
                      control1: CGPoint(x: 2.51888, y: 2.96052),
                      control2: CGPoint(x: 2.73585, y: 2.68721))
        path.addCurve(to: CGPoint(x: 3.64681, y: 3.13711),
                      control1: CGPoint(x: 3.33906, y: 2.61834),
                      control2: CGPoint(x: 3.61213, y: 2.83559))
        path.addLine(to: CGPoint(x: 3.76107, y: 4.14004))
        path.addCurve(to: CGPoint(x: 4.96419, y: 4.58047),
                      control1: CGPoint(x: 4.11438, y: 4.30774),
                      control2: CGPoint(x: 4.51937, y: 4.45638))
        path.addCurve(to: CGPoint(x: 5.01986, y: 4.90469),
                      control1: CGPoint(x: 4.97348, y: 4.69994),
                      control2: CGPoint(x: 4.99461, y: 4.8104))
        path.addLine(to: CGPoint(x: 5.25618, y: 5.7875))
        path.addCurve(to: CGPoint(x: 3.90365, y: 5.392),
                      control1: CGPoint(x: 4.777, y: 5.67958),
                      control2: CGPoint(x: 4.3224, y: 5.5468))
        path.addLine(to: CGPoint(x: 4.94661, y: 14.5375))
        path.addLine(to: CGPoint(x: 4.94759, y: 14.5541))
        path.addCurve(to: CGPoint(x: 5.22884, y: 15.5404),
                      control1: CGPoint(x: 4.99493, y: 15.122),
                      control2: CGPoint(x: 5.10853, y: 15.401))
        path.addCurve(to: CGPoint(x: 5.89974, y: 15.7494),
                      control1: CGPoint(x: 5.32385, y: 15.6503),
                      control2: CGPoint(x: 5.49089, y: 15.7494))
        path.addLine(to: CGPoint(x: 12.0999, y: 15.7494))
        path.addCurve(to: CGPoint(x: 12.7708, y: 15.5404),
                      control1: CGPoint(x: 12.5088, y: 15.7494),
                      control2: CGPoint(x: 12.6758, y: 15.6503))
        path.addCurve(to: CGPoint(x: 13.0521, y: 14.5541),
                      control1: CGPoint(x: 12.8912, y: 15.401),
                      control2: CGPoint(x: 13.0047, y: 15.1221))
        path.addLine(to: CGPoint(x: 13.0531, y: 14.5375))
        path.addLine(to: CGPoint(x: 14.096, y: 5.392))
        path.addCurve(to: CGPoint(x: 12.9759, y: 5.73282),
                      control1: CGPoint(x: 13.7454, y: 5.52149),
                      control2: CGPoint(x: 13.3702, y: 5.63613))
        path.addLine(to: CGPoint(x: 13.1048, y: 5.51211))
        path.addCurve(to: CGPoint(x: 13.1195, y: 5.48575),
                      control1: CGPoint(x: 13.1097, y: 5.50363),
                      control2: CGPoint(x: 13.1148, y: 5.49436))
        path.addCurve(to: CGPoint(x: 13.3509, y: 4.78164),
                      control1: CGPoint(x: 13.2164, y: 5.30734),
                      control2: CGPoint(x: 13.3232, y: 5.06337))
        path.addCurve(to: CGPoint(x: 13.347, y: 4.4877),
                      control1: CGPoint(x: 13.3597, y: 4.69192),
                      control2: CGPoint(x: 13.359, y: 4.59203))
        path.addCurve(to: CGPoint(x: 14.2386, y: 4.14297),
                      control1: CGPoint(x: 13.6705, y: 4.38521),
                      control2: CGPoint(x: 13.9697, y: 4.27023))
        path.addLine(to: CGPoint(x: 14.3538, y: 3.13711))
        path.addCurve(to: CGPoint(x: 14.9622, y: 2.65274),
                      control1: CGPoint(x: 14.3885, y: 2.83568),
                      control2: CGPoint(x: 14.6607, y: 2.61844))
        path.closeSubpath()
        return appKitPath(path)
    }

    static func cursorPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 9.45052, y: 1.84805))
        path.addCurve(to: CGPoint(x: 9.97103, y: 2.39688),
                      control1: CGPoint(x: 9.67843, y: 1.89331),
                      control2: CGPoint(x: 10.0467, y: 1.98348))
        path.addLine(to: CGPoint(x: 9.51497, y: 4.88028))
        path.addLine(to: CGPoint(x: 11.7435, y: 4.47989))
        path.addCurve(to: CGPoint(x: 12.1527, y: 4.96035),
                      control1: CGPoint(x: 12.1794, y: 4.36309),
                      control2: CGPoint(x: 12.403, y: 4.49987))
        path.addLine(to: CGPoint(x: 8.51107, y: 11.2465))
        path.addCurve(to: CGPoint(x: 7.82747, y: 11.1352),
                      control1: CGPoint(x: 8.32333, y: 11.5916),
                      control2: CGPoint(x: 7.92595, y: 11.5019))
        path.addLine(to: CGPoint(x: 6.08138, y: 4.61953))
        path.addCurve(to: CGPoint(x: 6.53157, y: 4.2045),
                      control1: CGPoint(x: 5.98316, y: 4.2526),
                      control2: CGPoint(x: 6.19635, y: 3.99932))
        path.addLine(to: CGPoint(x: 8.46907, y: 5.16055))
        path.addLine(to: CGPoint(x: 8.90072, y: 2.27871))
        path.addCurve(to: CGPoint(x: 9.45052, y: 1.84805),
                      control1: CGPoint(x: 8.94573, y: 1.97643),
                      control2: CGPoint(x: 9.19771, y: 1.79785))
        path.closeSubpath()
        return appKitPath(path)
    }

    private static func appKitPath(_ path: CGPath) -> CGPath {
        var svgToAppKit = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 18)
        return path.copy(using: &svgToAppKit)!
    }
}
