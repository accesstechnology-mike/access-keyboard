import UIKit

/// How the left-hand prediction column is carved out of the keyboard.
///
/// The column is the standard home for predictions on every layout. Its width
/// stays put while someone is typing ordinary words, so the keys beside it do
/// not resize on each keystroke. A very long word may widen the column, up to
/// a cap that still leaves tappable keys. Inside the column, row heights and
/// type size fluctuate with the word so the full spelling is visible: long
/// words get a taller row and, if needed, a smaller size, and the list shows
/// fewer rows when that is the only way to keep every visible word complete.
public struct PredictionColumnArrangement: Equatable {
    public var columnFrame: CGRect
    public var predictionFrames: [CGRect]
    public var predictionFontSizes: [CGFloat]
    public var visibleTexts: [String]
    public var fixFrame: CGRect
    public var textInsets: UIEdgeInsets
    /// Smallest size treated as comfortably readable. A single extreme word may
    /// go below this rather than be clipped; ordinary rows do not.
    public var minimumReadableFontSize: CGFloat

    public var isHidden: Bool { columnFrame.width <= 0 }
}

public enum PredictionColumnGeometry {
    public static let textInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

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
        let standard = standardColumnWidth(boundsWidth: keyboardSize.width, maximum: maximum)
        let width = widenedWidth(
            texts: texts,
            standard: standard,
            maximum: maximum,
            metrics: metrics
        )

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

    static func standardColumnWidth(boundsWidth: CGFloat, maximum: CGFloat) -> CGFloat {
        let proposed = (boundsWidth * 0.19).rounded()
        let minimum: CGFloat
        if boundsWidth < 360 {
            minimum = 58
        } else if boundsWidth < 700 {
            minimum = 74
        } else {
            minimum = 132
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
        // Never wider than the key grid can spare. A narrow phone would rather
        // keep tappable keys than a roomy column; long words then wrap.
        return max(0, min(fractionCap, cap))
    }

    private static func widenedWidth(
        texts: [String],
        standard: CGFloat,
        maximum: CGFloat,
        metrics: LayoutMetrics
    ) -> CGFloat {
        guard maximum > standard + 1 else { return min(standard, maximum) }
        guard let longest = texts.max(by: { $0.count < $1.count }), longest.count >= 12 else {
            return min(standard, maximum)
        }
        let font = measurementFont(ofSize: minimumReadableFontSize(metrics))
        if lineCount(longest, font: font, width: innerWidth(standard)) <= 2 {
            return standard
        }
        var width = standard
        while width < maximum {
            let next = min(maximum, width + 8)
            if next <= width { break }
            width = next
            if lineCount(longest, font: font, width: innerWidth(width)) <= 2 {
                return width
            }
        }
        return min(width, maximum)
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
        let font = fontFitting(
            text,
            columnWidth: columnWidth,
            maxRowHeight: listHeight,
            preferred: preferredFontSize(metrics),
            floor: 9
        )
        return [RowPlan(text: text, fontSize: font, height: listHeight)]
    }

    /// Places every word at the largest comfortable size that still shows it in
    /// full. Tall (long) words shrink first. Returns nil when the words cannot
    /// all fit at the readable minimum, so the caller can show fewer of them.
    private static func arrange(
        _ texts: [String],
        columnWidth: CGFloat,
        listHeight: CGFloat,
        metrics: LayoutMetrics
    ) -> [RowPlan]? {
        let preferred = preferredFontSize(metrics)
        let readable = minimumReadableFontSize(metrics)
        var fonts = Array(repeating: preferred, count: texts.count)
        for _ in 0..<400 {
            let heights = zip(texts, fonts).map { neededHeight($0, fontSize: $1, columnWidth: columnWidth) }
            let sum = heights.reduce(0, +)
            if sum <= listHeight + 0.5 {
                let extra = texts.isEmpty ? 0 : (listHeight - sum) / CGFloat(texts.count)
                return zip(texts, zip(fonts, heights)).map { text, pair in
                    RowPlan(text: text, fontSize: pair.0, height: pair.1 + extra)
                }
            }
            var tallest: Int?
            var tallestHeight: CGFloat = -1
            for index in fonts.indices where fonts[index] > readable + 0.01 {
                let height = heights[index]
                if height > tallestHeight {
                    tallestHeight = height
                    tallest = index
                }
            }
            guard let tallest else { return nil }
            fonts[tallest] = max(readable, fonts[tallest] - 1)
        }
        return nil
    }

    private static func fontFitting(
        _ text: String,
        columnWidth: CGFloat,
        maxRowHeight: CGFloat,
        preferred: CGFloat,
        floor: CGFloat
    ) -> CGFloat {
        var size = preferred
        let lower = min(floor, preferred)
        while size > lower + 0.01 {
            if neededHeight(text, fontSize: size, columnWidth: columnWidth) <= maxRowHeight + 0.5 {
                return size
            }
            size -= 0.5
        }
        return lower
    }

    private static func neededHeight(_ text: String, fontSize: CGFloat, columnWidth: CGFloat) -> CGFloat {
        let font = measurementFont(ofSize: fontSize)
        let size = boundingSize(of: text, font: font, width: innerWidth(columnWidth))
        // Two extra points cover UILabel's rounding so a measured word is not
        // clipped when the row is exactly the measured height.
        return size.height + textInsets.top + textInsets.bottom + 2
    }

    private static func innerWidth(_ columnWidth: CGFloat) -> CGFloat {
        max(1, columnWidth - textInsets.left - textInsets.right)
    }

    private static func lineCount(_ text: String, font: UIFont, width: CGFloat) -> Int {
        let height = boundingSize(of: text, font: font, width: width).height
        let line = max(font.lineHeight, 1)
        return max(1, Int((height / line).rounded(.up)))
    }
}
