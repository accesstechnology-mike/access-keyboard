import UIKit

public struct LayoutMetrics: Equatable {
    public var sideInset: CGFloat
    public var topInset: CGFloat
    public var bottomInset: CGFloat
    public var keySpacing: CGFloat
    public var rowSpacing: CGFloat
    public var keyHeight: CGFloat
    public var predictionBarHeight: CGFloat
    public var cornerRadius: CGFloat
    public var letterFontSize: CGFloat
    public var modifierFontSize: CGFloat
    public var symbolPointSize: CGFloat

    public var rowCount: Int

    public var preferredHeight: CGFloat {
        predictionBarHeight
            + topInset
            + CGFloat(rowCount) * keyHeight
            + CGFloat(max(rowCount - 1, 0)) * rowSpacing
            + bottomInset
    }

    public static func metrics(for layoutClass: LayoutClass, bounds: CGSize, safeBottom: CGFloat) -> LayoutMetrics {
        switch layoutClass {
        case .compact:
            return LayoutMetrics(
                sideInset: 3,
                topInset: 8,
                bottomInset: max(4, safeBottom > 0 ? 4 : 6),
                keySpacing: 6,
                rowSpacing: 12,
                keyHeight: 42,
                predictionBarHeight: 40,
                cornerRadius: 5,
                letterFontSize: 22,
                modifierFontSize: 16,
                symbolPointSize: 18,
                rowCount: 4
            )
        case .iPad:
            let landscape = bounds.width > bounds.height
            return LayoutMetrics(
                sideInset: 8,
                topInset: 10,
                bottomInset: 10,
                keySpacing: 7,
                rowSpacing: 8,
                keyHeight: landscape ? 57 : 64,
                predictionBarHeight: 48,
                cornerRadius: 8,
                letterFontSize: 24,
                modifierFontSize: 15,
                symbolPointSize: 20,
                rowCount: 4
            )
        case .iPadPro:
            let landscape = bounds.width > bounds.height
            return LayoutMetrics(
                sideInset: 6,
                topInset: 10,
                bottomInset: 10,
                keySpacing: 7,
                rowSpacing: 8,
                keyHeight: landscape ? 56 : 62,
                predictionBarHeight: 50,
                cornerRadius: 8.5,
                letterFontSize: 25,
                modifierFontSize: 15,
                symbolPointSize: 19,
                rowCount: 5
            )
        }
    }
}
