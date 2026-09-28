import UIKit

/// One point size for every single-character letter key.
///
/// `UILabel.adjustsFontSizeToFitWidth` used to shrink a wide letter such as W
/// on its own, so W looked smaller than E beside it. The size returned here is
/// the largest size at or below `intended` that still fits the widest of
/// W, w, M and m in the key's label width. Every letter key of that width uses
/// it, so they match.
public enum KeyLetterSizing {
    public static let wideLetters = ["W", "w", "M", "m"]

    public static func uniformSize(intended: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 1, intended > 1 else { return max(intended, 1) }
        if widestLetterWidth(at: intended) <= availableWidth {
            return intended
        }
        var low: CGFloat = 1
        var high = intended
        var best: CGFloat = 1
        for _ in 0..<14 {
            let mid = (low + high) / 2
            if widestLetterWidth(at: mid) <= availableWidth {
                best = mid
                low = mid
            } else {
                high = mid
            }
        }
        return best
    }

    public static func widestLetterWidth(at size: CGFloat) -> CGFloat {
        let font = LiteracyFont.uiFont(ofSize: size) ?? .systemFont(ofSize: size, weight: .light)
        let widths = wideLetters.map { letterWidth($0, font: font) }
        return widths.max() ?? 0
    }

    public static func letterWidth(_ text: String, font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
