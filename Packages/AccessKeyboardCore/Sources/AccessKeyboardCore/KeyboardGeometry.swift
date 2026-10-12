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
        if let columns = layout.gridColumns, columns > 0 {
            let gaps = CGFloat(columns - 1) * metrics.keySpacing
            return (usableWidth - gaps) / CGFloat(columns)
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
    ///
    /// Motor-plan rule: on a full-width (non-docked) board, a modifier at the
    /// start of a row is pinned to the left edge and a modifier at the end is
    /// pinned to the right edge, with the character keys centred between them.
    /// So `delete`, `return`, `shift` and their page-switch stand-ins sit at
    /// exactly the same place on every page (letters / 123 / #+=), whatever the
    /// number of character keys in between.
    public static func framesForRow(
        _ row: KeyboardRow,
        y: CGFloat,
        usableWidth: CGFloat,
        unit: CGFloat,
        metrics: LayoutMetrics,
        contentLeading: CGFloat,
        leftDocked: Bool,
        grid: Bool = false
    ) -> [CGRect] {
        let gap = metrics.keySpacing
        let count = row.keys.count
        let gaps = CGFloat(max(count - 1, 0)) * gap
        let flexibleCount = row.keys.filter { $0.width == .flexible }.count

        func fixedWidth(_ spec: KeySpec) -> CGFloat {
            let w = weight(of: spec.width)
            return grid ? unit * w + max(w - 1, 0) * gap : unit * w
        }
        let fixedTotal = row.keys.reduce(CGFloat(0)) { sum, spec in
            spec.width == .flexible ? sum : sum + fixedWidth(spec)
        }
        let leftover = usableWidth - fixedTotal - gaps
        let flexWidth = flexibleCount > 0 ? max(unit, leftover / CGFloat(flexibleCount)) : 0
        let widths = row.keys.map { $0.width == .flexible ? flexWidth : fixedWidth($0) }

        var xs = Array(repeating: CGFloat(0), count: count)
        if flexibleCount > 0 || count == 0 {
            var cursor = contentLeading
            for i in 0..<count { xs[i] = cursor; cursor += widths[i] + gap }
        } else if leftDocked {
            var cursor = contentLeading + row.leadingInsetUnits * unit
            for i in 0..<count { xs[i] = cursor; cursor += widths[i] + gap }
        } else {
            let pinFirst = count > 1 && row.keys[0].style != .letter
            let pinLast = count > 1 && row.keys[count - 1].style != .letter
            let lo = pinFirst ? 1 : 0
            let hi = pinLast ? count - 1 : count
            if pinFirst { xs[0] = contentLeading }
            if pinLast { xs[count - 1] = contentLeading + usableWidth - widths[count - 1] }
            let spanStart = pinFirst ? contentLeading + widths[0] + gap : contentLeading
            let spanEnd = pinLast ? contentLeading + usableWidth - widths[count - 1] - gap : contentLeading + usableWidth
            if hi > lo {
                let middle = widths[lo..<hi].reduce(0, +) + CGFloat(hi - lo - 1) * gap
                var cursor = spanStart + max(0, (spanEnd - spanStart - middle) / 2) + row.leadingInsetUnits * unit
                for i in lo..<hi { xs[i] = cursor; cursor += widths[i] + gap }
            }
        }
        return (0..<count).map { CGRect(x: xs[$0], y: y, width: widths[$0], height: metrics.keyHeight) }
    }

    /// Lays out an entire board, returning one frame array per row. Mirrors the
    /// order `KeyboardView.layoutKeys` places its buttons in.
    ///
    /// `reservedLeading` is the iPad prediction column plus the gap before the
    /// first key. `reservedTop` is the iPhone prediction bar: keys start below
    /// it. Compact boards pass a top reserve and no leading reserve; iPad
    /// boards do the opposite.
    public static func frames(
        for layout: KeyboardLayout,
        metrics: LayoutMetrics,
        boundsWidth: CGFloat,
        reservedLeading: CGFloat = 0,
        reservedTop: CGFloat = 0
    ) -> [[CGRect]] {
        let contentLeading = metrics.sideInset + max(0, reservedLeading)
        let usableWidth = boundsWidth - contentLeading - metrics.sideInset
        let unit = unitWidth(in: layout, usableWidth: usableWidth, metrics: metrics)
        var y = metrics.topInset + max(0, reservedTop)
        var rows: [[CGRect]] = []
        for row in layout.rows {
            rows.append(
                framesForRow(
                    row,
                    y: y,
                    usableWidth: usableWidth,
                    unit: unit,
                    metrics: metrics,
                    contentLeading: contentLeading,
                    leftDocked: layout.leftDocked,
                    grid: layout.gridColumns != nil
                )
            )
            y += metrics.keyHeight + metrics.rowSpacing
        }
        return rows
    }
}
