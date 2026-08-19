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
}
