import CoreText
import UIKit

public enum LiteracyFont {
    public static let postScriptName = "Andika"
    public static let resourceName = "Andika-Regular"
    public static let resourceExtension = "ttf"

    private static var didRegister = false

    @discardableResult
    public static func registerIfNeeded() -> Bool {
        if UIFont(name: postScriptName, size: 12) != nil {
            return true
        }
        guard !didRegister else {
            return UIFont(name: postScriptName, size: 12) != nil
        }
        didRegister = true
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: resourceExtension) else {
            return false
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return UIFont(name: postScriptName, size: 12) != nil
    }

    public static func uiFont(ofSize size: CGFloat) -> UIFont? {
        registerIfNeeded()
        return UIFont(name: postScriptName, size: size)
    }
}
