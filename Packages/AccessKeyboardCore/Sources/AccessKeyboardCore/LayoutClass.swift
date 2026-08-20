import UIKit

public enum LayoutClassResolver {
    /// Matches Apple’s size-based software keyboard: compact when floating/narrow,
    /// expanded iPad Pro layout on 12.9"/13" (and 11" landscape), otherwise the 4-row iPad board.
    public static func resolve(size: CGSize, idiom: UIUserInterfaceIdiom) -> LayoutClass {
        guard idiom == .pad else { return .compact }
        if size.width < 540 {
            return .compact
        }
        if size.width >= 1000 {
            return .iPadPro
        }
        return .iPad
    }

    /// Prefer the view’s current width. A 1024-pt fallback always selected the 5-row
    /// Pro board, so the first layout pass was too tall and shoved host chrome under
    /// the status bar.
    public static func referenceSize(bounds: CGSize, fallback: CGSize? = nil) -> CGSize {
        if bounds.width > 1 {
            return bounds
        }
        if let fallback, fallback.width > 1 {
            return fallback
        }
        let screen = UIScreen.main.bounds.size
        return CGSize(width: screen.width, height: min(320, screen.height * 0.4))
    }
}
