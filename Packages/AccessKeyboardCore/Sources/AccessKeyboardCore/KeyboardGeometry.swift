import UIKit

/// Pure key-frame geometry for the keyboard.
///
/// This is the width math that turns a `KeyboardLayout` plus `LayoutMetrics`
/// into per-key rectangles. It used to live privately inside `KeyboardView`,
/// but that made it impossible to test the one property that matters most on
/// iPhone: a compact board must never overflow a narrow screen. Lifting it into
/// a `UIView`-free type lets `LayoutStabilityTests` assert every row fits inside
/// the usable width at real iPhone sizes, while `KeyboardView` keeps calling the
/// exact same functions, so the on-device layout is unchanged.
public enum KeyboardGeometry {
    public static func weight(of width: KeyWidth) -> CGFloat {
        switch width {
        case .unit(let value):
            return value
        case .flexible:
            return 4.5
        }
    }

    public static func fixedWeight(of row: KeyboardRow) -> CGFloat {
        row.keys.reduce(0) { $0 + weight(of: $1.width) }
    }

    /// The width of a single layout unit for the given board and usable width.
    public static func unitWidth(
        in layout: KeyboardLayout,
        usableWidth: CGFloat,
        metrics: LayoutMetrics
    ) -> CGFloat {
        // Left-docked frequency board: square keys sized by row height, but never
        // wider than a fill would allow (so narrow devices still fit the block).
        if layout.leftDocked {
            let maxWeight = layout.rows.map { fixedWeight(of: $0) }.max() ?? 1
            let maxCount = layout.rows.map { $0.keys.count }.max() ?? 1
            let gaps = CGFloat(max(maxCount - 1, 0)) * metrics.keySpacing
            let fillUnit = (usableWidth - gaps) / max(maxWeight, 1)
            return min(metrics.keyHeight, fillUnit)
        }
        // Fixed frame reference (numeric/symbols reuse the alphabetic frame) so
        // key size stays constant across pages.
        if let refWeight = layout.referenceUnitWeight, let refCount = layout.referenceKeyCount {
            let gaps = CGFloat(max(refCount - 1, 0)) * metrics.keySpacing
            return (usableWidth - gaps) / max(refWeight, 1)
        }
        let reference = layout.rows.max { lhs, rhs in
            fixedWeight(of: lhs) < fixedWeight(of: rhs)
        } ?? layout.rows[0]
        let gaps = CGFloat(max(reference.keys.count - 1, 0)) * metrics.keySpacing
        let weight = max(fixedWeight(of: reference), 1)
        return (usableWidth - gaps) / weight
    }

    /// The frames for one row, positioned at vertical offset `y`.
    public static func framesForRow(
        _ row: KeyboardRow,
        y: CGFloat,
        usableWidth: CGFloat,
        unit: CGFloat,
        metrics: LayoutMetrics,
        leftDocked: Bool
    ) -> [CGRect] {
        let gap = metrics.keySpacing
        let gaps = CGFloat(max(row.keys.count - 1, 0)) * gap
        let flexibleCount = row.keys.filter { $0.width == .flexible }.count
        let fixed = row.keys.reduce(CGFloat(0)) { sum, spec in
            if spec.width == .flexible { return sum }
            return sum + weight(of: spec.width)
        }

        let leftover = usableWidth - fixed * unit - gaps
        let flexWidth: CGFloat
        let leading: CGFloat
        if flexibleCount > 0 {
            flexWidth = max(unit, leftover / CGFloat(flexibleCount))
            leading = metrics.sideInset
        } else {
            flexWidth = 0
            let rowWidth = fixed * unit + gaps
            if leftDocked {
                // Flush left; leaves the right-hand area empty for scanners.
                leading = metrics.sideInset + row.leadingInsetUnits * unit
            } else {
                leading = metrics.sideInset + max(0, (usableWidth - rowWidth) / 2) + row.leadingInsetUnits * unit
            }
        }

        var cursor = leading
        var frames: [CGRect] = []
        for spec in row.keys {
            let keyWidth: CGFloat
            if spec.width == .flexible {
                keyWidth = flexWidth
            } else {
                keyWidth = unit * weight(of: spec.width)
            }
            frames.append(CGRect(x: cursor, y: y, width: keyWidth, height: metrics.keyHeight))
            cursor += keyWidth + gap
        }
        return frames
    }

    /// Lays out an entire board, returning one frame array per row. Mirrors the
    /// order `KeyboardView.layoutKeys` places its buttons in.
    public static func frames(
        for layout: KeyboardLayout,
        metrics: LayoutMetrics,
        boundsWidth: CGFloat,
        showsPredictions: Bool
    ) -> [[CGRect]] {
        let usableWidth = boundsWidth - metrics.sideInset * 2
        let unit = unitWidth(in: layout, usableWidth: usableWidth, metrics: metrics)
        var y = metrics.topInset + (showsPredictions ? metrics.predictionBarHeight : 0)
        var rows: [[CGRect]] = []
        for row in layout.rows {
            rows.append(
                framesForRow(
                    row,
                    y: y,
                    usableWidth: usableWidth,
                    unit: unit,
                    metrics: metrics,
                    leftDocked: layout.leftDocked
                )
            )
            y += metrics.keyHeight + metrics.rowSpacing
        }
        return rows
    }
}
