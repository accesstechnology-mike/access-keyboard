import UIKit

/// How the iPhone prediction bar divides its width.
///
/// Cells grow and shrink with the word. A long word gets a wider cell and the
/// shared type size shrinks so the whole spelling stays on one line. If the
/// words still cannot fit at a readable size, later suggestions are dropped.
/// A word that still overflows its cell tightens, shrinks a little further,
/// then truncates with an ellipsis instead of wrapping.
public struct PredictionBarArrangement: Equatable {
    public var fixFrame: CGRect
    public var cellFrames: [CGRect]
    public var visibleTexts: [String]
    public var fontSize: CGFloat
}

public enum PredictionBarGeometry {
    public static let horizontalInset: CGFloat = 10
    /// Preferred tap width for a short word. Ignored when honouring it would
    /// push a fully spelled word off the bar.
    public static let minimumCellWidth: CGFloat = 36

    public static func arrangement(
        texts: [String],
        barWidth: CGFloat,
        barHeight: CGFloat,
        preferredFontSize: CGFloat,
        minimumReadableFontSize: CGFloat
    ) -> PredictionBarArrangement {
        let height = max(0, barHeight)
        let width = max(0, barWidth)
        let fixWidth = min(Self.fixWidth(for: width), width)
        let fixFrame = CGRect(x: 0, y: 2, width: fixWidth, height: max(0, height - 4))
        let available = max(0, width - fixWidth)
        let preferred = max(preferredFontSize, 1)
        let readable = min(preferred, max(9, minimumReadableFontSize))
        let limit = min(texts.count, PredictionProvider.maxSuggestions)
        let candidates = Array(texts.prefix(limit))

        guard !candidates.isEmpty, available > 1, height > 1 else {
            return PredictionBarArrangement(
                fixFrame: fixFrame,
                cellFrames: [],
                visibleTexts: [],
                fontSize: preferred
            )
        }

        for count in stride(from: candidates.count, through: 1, by: -1) {
            let slice = Array(candidates.prefix(count))
            let floor = count == 1 ? min(8, readable) : readable
            var size = preferred
            while size >= floor - 0.01 {
                if let frames = place(slice, fontSize: size, available: available, height: height, originX: fixWidth) {
                    return PredictionBarArrangement(
                        fixFrame: fixFrame,
                        cellFrames: frames,
                        visibleTexts: slice,
                        fontSize: size
                    )
                }
                size -= 1
            }
        }

        let only = candidates[0]
        let size = fontFitting(only, available: available, preferred: preferred)
        return PredictionBarArrangement(
            fixFrame: fixFrame,
            cellFrames: [CGRect(x: fixWidth, y: 0, width: available, height: height)],
            visibleTexts: [only],
            fontSize: size
        )
    }

    /// Same Fix width the original bar used: a short primary button on the left.
    public static func fixWidth(for barWidth: CGFloat) -> CGFloat {
        min(92, max(72, barWidth * 0.14))
    }

    public static func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = PredictionColumnGeometry.measurementFont(ofSize: fontSize)
        return PredictionColumnGeometry.boundingSize(
            of: text,
            font: font,
            width: 10_000
        ).width
    }

    private static func place(
        _ texts: [String],
        fontSize: CGFloat,
        available: CGFloat,
        height: CGFloat,
        originX: CGFloat
    ) -> [CGRect]? {
        let content = texts.map { text -> CGFloat in
            textWidth(text, fontSize: fontSize) + horizontalInset * 2 + 2
        }
        let sum = content.reduce(0, +)
        guard sum <= available + 0.5 else { return nil }

        let raised = content.map { max($0, minimumCellWidth) }
        let raisedSum = raised.reduce(0, +)
        let widths: [CGFloat]
        if raisedSum <= available + 0.5 {
            let extra = (available - raisedSum) / CGFloat(texts.count)
            widths = raised.map { $0 + extra }
        } else {
            let extra = (available - sum) / CGFloat(texts.count)
            widths = content.map { $0 + extra }
        }

        var frames: [CGRect] = []
        var cursor = originX
        frames.reserveCapacity(widths.count)
        for width in widths {
            frames.append(CGRect(x: cursor, y: 0, width: width, height: height))
            cursor += width
        }
        return frames
    }

    /// Shrinks until `text` fits on one line in `available`. Used only when a
    /// single extreme word cannot fit at the readable minimum.
    private static func fontFitting(_ text: String, available: CGFloat, preferred: CGFloat) -> CGFloat {
        var size = preferred
        while size > 4 {
            let needed = textWidth(text, fontSize: size) + horizontalInset * 2 + 2
            if needed <= available + 0.5 {
                return size
            }
            size -= 0.5
        }
        return 4
    }
}
