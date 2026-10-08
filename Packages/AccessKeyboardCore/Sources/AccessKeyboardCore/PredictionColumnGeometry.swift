import UIKit

/// How the left-hand prediction column is carved out of an iPad keyboard.
///
/// iPhone keeps the horizontal bar. On iPad and iPad Pro, portrait and
/// landscape, the column is the home for predictions. Its width
/// stays put while someone is typing, so the keys beside it do not resize on
/// each keystroke. Every suggestion is one line: a long word shrinks, down to
/// a readable minimum, instead of wrapping or breaking. A word that still
/// cannot fit at that size is truncated with an ellipsis by the label. The
/// list shows fewer rows only when the single-line rows themselves do not fit.
public struct PredictionColumnArrangement: Equatable {
    public var columnFrame: CGRect
    public var predictionFrames: [CGRect]
    public var predictionFontSizes: [CGFloat]
    public var visibleTexts: [String]
    public var fixFrame: CGRect
    public var textInsets: UIEdgeInsets
    /// Smallest size a suggestion uses before the label truncates with an ellipsis.
    /// Rows do not wrap, and they do not go below this to stay complete.
    public var minimumReadableFontSize: CGFloat

    public var isHidden: Bool { columnFrame.width <= 0 }
}

public enum PredictionColumnGeometry {
    public static let textInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

    /// iPhone (and a narrow iPad that falls back to the compact board) uses the
    /// top bar. Every larger iPad board uses the left column.
    public static func usesVerticalColumn(_ layoutClass: LayoutClass) -> Bool {
        layoutClass != .compact
    }

    public static func arrangement(
        texts: [String],
        keyboardSize: CGSize,
        metrics: LayoutMetrics,
        layout: KeyboardLayout,
        showsPredictions: Bool
    ) -> PredictionColumnArrangement {
        let readable = minimumReadableFontSize(metrics)
        guard showsPredictions, keyboardSize.width > 1, keyboardSize.height > 1 else {
            return PredictionColumnArrangement(
                columnFrame: .zero,
                predictionFrames: [],
                predictionFontSizes: [],
                visibleTexts: [],
                fixFrame: .zero,
                textInsets: textInsets,
                minimumReadableFontSize: readable
            )
        }

        let maximum = maximumColumnWidth(
            boundsWidth: keyboardSize.width,
            metrics: metrics,
            layout: layout
        )
        let width = standardColumnWidth(boundsWidth: keyboardSize.width, maximum: maximum)

        let columnX = metrics.sideInset
        let columnY = metrics.topInset
        let columnHeight = max(0, keyboardSize.height - metrics.topInset - metrics.bottomInset)
        let fixHeight = min(metrics.keyHeight, max(columnHeight, 0))
        let columnFrame = CGRect(x: columnX, y: columnY, width: width, height: columnHeight)
        let fixFrame = CGRect(
            x: columnX,
            y: columnY + columnHeight - fixHeight,
            width: width,
            height: fixHeight
        )
        let listGap = texts.isEmpty ? CGFloat(0) : metrics.rowSpacing
        let listHeight = max(0, fixFrame.minY - listGap - columnY)
        let rows = layoutRows(
            texts: texts,
            columnWidth: width,
            listHeight: listHeight,
            metrics: metrics
        )

        var frames: [CGRect] = []
        var fonts: [CGFloat] = []
        var visible: [String] = []
        var cursorY = columnY
        frames.reserveCapacity(rows.count)
        for row in rows {
            frames.append(CGRect(x: columnX, y: cursorY, width: width, height: row.height))
            fonts.append(row.fontSize)
            visible.append(row.text)
            cursorY += row.height
        }

        return PredictionColumnArrangement(
            columnFrame: columnFrame,
            predictionFrames: frames,
            predictionFontSizes: fonts,
            visibleTexts: visible,
            fixFrame: fixFrame,
            textInsets: textInsets,
            minimumReadableFontSize: readable
        )
    }

    /// Horizontal space the key grid must leave clear, including the gap
    /// between the column and the first key. Zero when predictions are hidden.
    public static func reservedLeading(for arrangement: PredictionColumnArrangement, metrics: LayoutMetrics) -> CGFloat {
        guard arrangement.columnFrame.width > 0 else { return 0 }
        return arrangement.columnFrame.width + metrics.keySpacing
    }

    public static func boundingSize(of text: String, font: UIFont, width: CGFloat) -> CGSize {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    public static func measurementFont(ofSize size: CGFloat) -> UIFont {
        LiteracyFont.uiFont(ofSize: size) ?? .systemFont(ofSize: size, weight: .medium)
    }

    public static func minimumReadableFontSize(_ metrics: LayoutMetrics) -> CGFloat {
        max(13, (metrics.letterFontSize * 0.5).rounded())
    }

    public static func preferredFontSize(_ metrics: LayoutMetrics) -> CGFloat {
        max(minimumReadableFontSize(metrics), (metrics.letterFontSize * 0.72).rounded())
    }

    // MARK: - Width

    /// Share of the keyboard width used by the resting left column, before a
    /// very long word is allowed to grow it. 0.15 is about 21% narrower than
    /// the 0.19 column from the first vertical layout, so a landscape iPad
    /// gives that space to the QWERTY keys.
    static let standardWidthFraction: CGFloat = 0.15

    static func standardColumnWidth(boundsWidth: CGFloat, maximum: CGFloat) -> CGFloat {
        let proposed = (boundsWidth * standardWidthFraction).rounded()
        let minimum: CGFloat
        if boundsWidth < 360 {
            minimum = 58
        } else if boundsWidth < 700 {
            minimum = 74
        } else {
            // Floor at the 700pt breakpoint so the fraction, not an older
            // wider minimum, sets the column on every iPad size.
            minimum = (700 * standardWidthFraction).rounded()
        }
        return min(maximum, max(minimum, proposed))
    }

    /// Caps the column so the reference row of keys keeps a usable width.
    static func maximumColumnWidth(
        boundsWidth: CGFloat,
        metrics: LayoutMetrics,
        layout: KeyboardLayout
    ) -> CGFloat {
        let count = layout.referenceKeyCount ?? layout.rows.map(\.keys.count).max() ?? 1
        let weight = layout.referenceUnitWeight
            ?? layout.rows.map { KeyboardGeometry.fixedWeight(of: $0) }.max()
            ?? CGFloat(count)
        let perKey = boundsWidth / CGFloat(max(count, 1))
        let floor = min(metrics.keyHeight * 0.42, max(16, perKey * 0.55))
        let gaps = CGFloat(max(count - 1, 0)) * metrics.keySpacing
        let minKeys = floor * max(weight, 1) + gaps
        let chrome = metrics.sideInset * 2 + metrics.keySpacing
        let cap = boundsWidth - chrome - minKeys
        let fractionCap = boundsWidth * 0.34
        // Never wider than the key grid can spare. A long word shrinks onto one
        // line instead of pushing the keys aside or wrapping.
        return max(0, min(fractionCap, cap))
    }

    // MARK: - Rows

    private struct RowPlan: Equatable {
        var text: String
        var fontSize: CGFloat
        var height: CGFloat
    }

    private static func layoutRows(
        texts: [String],
        columnWidth: CGFloat,
        listHeight: CGFloat,
        metrics: LayoutMetrics
    ) -> [RowPlan] {
        guard !texts.isEmpty, listHeight > 8, columnWidth > 8 else { return [] }
        let limit = min(texts.count, PredictionProvider.maxSuggestions)
        let candidates = Array(texts.prefix(limit))
        for count in stride(from: candidates.count, through: 1, by: -1) {
            if let rows = arrange(
                Array(candidates.prefix(count)),
                columnWidth: columnWidth,
                listHeight: listHeight,
                metrics: metrics
            ) {
                return rows
            }
        }
        let text = candidates[0]
        let font = fontFittingWidth(
            text,
            columnWidth: columnWidth,
            preferred: preferredFontSize(metrics),
            floor: minimumReadableFontSize(metrics)
        )
        return [RowPlan(text: text, fontSize: font, height: listHeight)]
    }

    /// Places every word on one line. Each word uses the largest size that fits
    /// the column width, down to the readable minimum. Returns nil when those
    /// single-line rows do not fit vertically, so the caller can show fewer.
    private static func arrange(
        _ texts: [String],
        columnWidth: CGFloat,
        listHeight: CGFloat,
        metrics: LayoutMetrics
    ) -> [RowPlan]? {
        let preferred = preferredFontSize(metrics)
        let readable = minimumReadableFontSize(metrics)
        let fonts = texts.map {
            fontFittingWidth($0, columnWidth: columnWidth, preferred: preferred, floor: readable)
        }
        let heights = fonts.map { singleLineHeight($0) }
        let sum = heights.reduce(0, +)
        guard sum <= listHeight + 0.5 else { return nil }
        let extra = texts.isEmpty ? 0 : (listHeight - sum) / CGFloat(texts.count)
        return zip(texts, zip(fonts, heights)).map { text, pair in
            RowPlan(text: text, fontSize: pair.0, height: pair.1 + extra)
        }
    }

    /// Largest size at or above `floor` whose single line fits `columnWidth`.
    /// Stays at `floor` when the word is still wider; the label then ellipsizes.
    static func fontFittingWidth(
        _ text: String,
        columnWidth: CGFloat,
        preferred: CGFloat,
        floor: CGFloat
    ) -> CGFloat {
        let inner = innerWidth(columnWidth)
        var size = preferred
        let lower = min(floor, preferred)
        while size > lower + 0.01 {
            if singleLineWidth(text, fontSize: size) <= inner + 0.5 {
                return size
            }
            size -= 0.5
        }
        return lower
    }

    static func singleLineWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        boundingSize(of: text, font: measurementFont(ofSize: fontSize), width: 10_000).width
    }

    private static func singleLineHeight(_ fontSize: CGFloat) -> CGFloat {
        let font = measurementFont(ofSize: fontSize)
        // Two extra points cover UILabel's rounding so a measured word is not
        // clipped when the row is exactly the measured height.
        return ceil(font.lineHeight) + textInsets.top + textInsets.bottom + 2
    }

    private static func innerWidth(_ columnWidth: CGFloat) -> CGFloat {
        max(1, columnWidth - textInsets.left - textInsets.right)
    }

}
