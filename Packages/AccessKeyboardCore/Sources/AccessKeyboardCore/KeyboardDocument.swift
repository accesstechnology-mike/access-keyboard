import UIKit

@MainActor
public protocol KeyboardDocument: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    var documentContextBeforeInput: String? { get }
    var selectedText: String? { get }
}

@MainActor
public protocol KeyboardHost: AnyObject {
    func advanceToNextInputMode()
    func dismissKeyboard()
    var needsInputModeSwitchKey: Bool { get }
}

public struct KeyboardTraits: Equatable {
    public var autocapitalizationType: UITextAutocapitalizationType
    public var keyboardType: UIKeyboardType
    public var returnKeyType: UIReturnKeyType
    public var isSecureTextEntry: Bool

    public init(
        autocapitalizationType: UITextAutocapitalizationType = .sentences,
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .default,
        isSecureTextEntry: Bool = false
    ) {
        self.autocapitalizationType = autocapitalizationType
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.isSecureTextEntry = isSecureTextEntry
    }

    public static func from(_ traits: UITextInputTraits) -> KeyboardTraits {
        KeyboardTraits(
            autocapitalizationType: traits.autocapitalizationType ?? .sentences,
            keyboardType: traits.keyboardType ?? .default,
            returnKeyType: traits.returnKeyType ?? .default,
            isSecureTextEntry: traits.isSecureTextEntry ?? false
        )
    }
}

@MainActor
public final class DocumentProxyAdapter: KeyboardDocument {
    private let proxy: UITextDocumentProxy

    public init(_ proxy: UITextDocumentProxy) {
        self.proxy = proxy
    }

    public func insertText(_ text: String) {
        proxy.insertText(text)
    }

    public func deleteBackward() {
        proxy.deleteBackward()
    }

    public var documentContextBeforeInput: String? {
        proxy.documentContextBeforeInput
    }

    public var selectedText: String? {
        proxy.selectedText
    }
}

@MainActor
public final class TextViewDocument: KeyboardDocument {
    private weak var textView: UITextView?

    public init(textView: UITextView) {
        self.textView = textView
    }

    public func insertText(_ text: String) {
        guard let textView else { return }
        activate(textView)
        if let selected = textView.selectedTextRange {
            textView.replace(selected, withText: text)
            return
        }
        textView.text = (textView.text ?? "") + text
        moveCursorToEnd(textView)
    }

    public func deleteBackward() {
        guard let textView else { return }
        activate(textView)
        if let selected = textView.selectedTextRange {
            if selected.start != selected.end {
                textView.replace(selected, withText: "")
                return
            }
            if let from = textView.position(from: selected.start, offset: -1),
               let range = textView.textRange(from: from, to: selected.start) {
                textView.replace(range, withText: "")
                return
            }
        }
        guard let text = textView.text, !text.isEmpty else { return }
        textView.text = String(text.dropLast())
        moveCursorToEnd(textView)
    }

    public var documentContextBeforeInput: String? {
        guard let textView else { return nil }
        guard let selected = textView.selectedTextRange,
              let range = textView.textRange(from: textView.beginningOfDocument, to: selected.start) else {
            return textView.text
        }
        return textView.text(in: range)
    }

    public var selectedText: String? {
        guard let textView, let range = textView.selectedTextRange else { return nil }
        return textView.text(in: range)
    }

    private func activate(_ textView: UITextView) {
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }

    private func moveCursorToEnd(_ textView: UITextView) {
        let end = textView.endOfDocument
        textView.selectedTextRange = textView.textRange(from: end, to: end)
    }
}
