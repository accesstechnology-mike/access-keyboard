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

    public static func metrics(
        for layoutClass: LayoutClass,
        bounds: CGSize,
        safeBottom: CGFloat,
        rowCount: Int? = nil
    ) -> LayoutMetrics {
        var metrics: LayoutMetrics
        switch layoutClass {
        case .compact:
            metrics = LayoutMetrics(
                sideInset: 3,
                topInset: 8,
                bottomInset: max(4, safeBottom > 0 ? 4 : 6),
                keySpacing: 7,
                rowSpacing: 12,
                keyHeight: 56,
                predictionBarHeight: 48,
                cornerRadius: 6,
                letterFontSize: 26,
                modifierFontSize: 18,
                symbolPointSize: 20,
                rowCount: 4
            )
        case .iPad:
            let landscape = bounds.width > bounds.height
            metrics = LayoutMetrics(
                sideInset: 8,
                topInset: 10,
                bottomInset: 10,
                keySpacing: 9,
                rowSpacing: 10,
                keyHeight: landscape ? 80 : 88,
                predictionBarHeight: 56,
                cornerRadius: 10,
                letterFontSize: 30,
                modifierFontSize: 18,
                symbolPointSize: 22,
                rowCount: 4
            )
        case .iPadPro:
            let landscape = bounds.width > bounds.height
            metrics = LayoutMetrics(
                sideInset: 6,
                topInset: 10,
                bottomInset: 10,
                keySpacing: 9,
                rowSpacing: 10,
                keyHeight: landscape ? 80 : 86,
                predictionBarHeight: 58,
                cornerRadius: 10,
                letterFontSize: 32,
                modifierFontSize: 18,
                symbolPointSize: 22,
                rowCount: 5
            )
        }
        if let rowCount, rowCount != metrics.rowCount {
            let scale = CGFloat(metrics.rowCount) / CGFloat(max(rowCount, 1))
            metrics.keyHeight = max(56, (metrics.keyHeight * min(1, scale * 1.08)).rounded())
            metrics.rowSpacing = max(8, (metrics.rowSpacing * min(1, scale)).rounded())
            metrics.rowCount = rowCount
        }
        return metrics
    }
}
