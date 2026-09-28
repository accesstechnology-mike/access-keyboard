import UIKit

public struct LayoutMetrics: Equatable {
    public var sideInset: CGFloat
    public var topInset: CGFloat
    public var bottomInset: CGFloat
    public var keySpacing: CGFloat
    public var rowSpacing: CGFloat
    public var keyHeight: CGFloat
    /// Height of the horizontal prediction bar. Zero on iPad, where predictions
    /// sit in a column beside the keys instead of a bar above them.
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
            // iPhone keeps the horizontal prediction bar and the key sizes that
            // shipped with it. The left-hand column is iPad-only.
            metrics = LayoutMetrics(
                sideInset: 3,
                topInset: 8,
                // Reserve the home-indicator safe area so the bottom toolbar row
                // never sits under it; falls back to a small pad when absent.
                bottomInset: max(6, safeBottom),
                keySpacing: 7,
                rowSpacing: 12,
                keyHeight: 52,
                predictionBarHeight: 46,
                cornerRadius: 6,
                letterFontSize: 24,
                modifierFontSize: 17,
                symbolPointSize: 19,
                rowCount: 4
            )
        case .iPad:
            let landscape = bounds.width > bounds.height
            metrics = LayoutMetrics(
                sideInset: 8,
                topInset: 8,
                bottomInset: max(10, safeBottom),
                keySpacing: 8,
                rowSpacing: 8,
                // Predictions sit beside the keys, so the height a bar would
                // have used is given to the keys.
                keyHeight: landscape ? 76 : 86,
                predictionBarHeight: 0,
                cornerRadius: 9,
                letterFontSize: 28,
                modifierFontSize: 17,
                symbolPointSize: 21,
                rowCount: 4
            )
        case .iPadPro:
            let landscape = bounds.width > bounds.height
            metrics = LayoutMetrics(
                sideInset: 6,
                topInset: 8,
                bottomInset: max(10, safeBottom),
                keySpacing: 8,
                rowSpacing: 8,
                keyHeight: landscape ? 74 : 82,
                predictionBarHeight: 0,
                cornerRadius: 9,
                letterFontSize: 30,
                modifierFontSize: 17,
                symbolPointSize: 21,
                rowCount: 5
            )
        }
        if let rowCount, rowCount != metrics.rowCount {
            let scale = CGFloat(metrics.rowCount) / CGFloat(max(rowCount, 1))
            metrics.keyHeight = max(50, (metrics.keyHeight * min(1, scale * 1.08)).rounded())
            metrics.rowSpacing = max(8, (metrics.rowSpacing * min(1, scale)).rounded())
            metrics.rowCount = rowCount
        }
        return metrics
    }
}
