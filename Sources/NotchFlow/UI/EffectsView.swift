import SwiftUI
import QuartzCore

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let appearanceName: NSAppearance.Name?
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    init(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode,
        appearanceName: NSAppearance.Name?,
        topCornerRadius: CGFloat = 0,
        bottomCornerRadius: CGFloat = 0
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.appearanceName = appearanceName
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    func makeNSView(context: Context) -> MaskedVisualEffectView {
        let view = MaskedVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = appearanceName.flatMap(NSAppearance.init(named:))
        view.topCornerRadius = topCornerRadius
        view.bottomCornerRadius = bottomCornerRadius
        return view
    }

    func updateNSView(_ nsView: MaskedVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.appearance = appearanceName.flatMap(NSAppearance.init(named:))
        nsView.topCornerRadius = topCornerRadius
        nsView.bottomCornerRadius = bottomCornerRadius
    }
}

final class MaskedVisualEffectView: NSVisualEffectView {
    var topCornerRadius: CGFloat = 0 {
        didSet {
            updateMask()
        }
    }

    var bottomCornerRadius: CGFloat = 0 {
        didSet {
            updateMask()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    override func layout() {
        super.layout()
        updateMask()
    }

    private func updateMask() {
        guard let layer else {
            return
        }

        guard bounds.width > 0, bounds.height > 0 else {
            layer.mask = nil
            return
        }

        let maskLayer = (layer.mask as? CAShapeLayer) ?? CAShapeLayer()
        maskLayer.frame = bounds
        maskLayer.path = Self.maskPath(
            in: bounds,
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
        layer.mask = maskLayer
    }

    private static func maskPath(
        in rect: CGRect,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat
    ) -> CGPath {
        let maxRadius = min(rect.width, rect.height) / 2
        let topRadius = max(0, min(topCornerRadius, maxRadius))
        let bottomRadius = max(0, min(bottomCornerRadius, maxRadius))
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX + bottomRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bottomRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + bottomRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - topRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bottomRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}
