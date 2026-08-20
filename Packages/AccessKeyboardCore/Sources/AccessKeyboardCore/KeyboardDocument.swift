import UIKit

@MainActor
public protocol KeyboardDocument: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }
    var entireText: String? { get }
    func adjustTextPosition(byCharacterOffset offset: Int)
    func replaceEntireText(_ text: String) -> Bool
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

enum DocumentProxyWait {
    static func yield() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

public enum DocumentTextAssembler {
    public static func combined(
        before: String?,
        selected: String?,
        after: String?,
        fallback: String = ""
    ) -> String {
        let live = (before ?? "") + (selected ?? "") + (after ?? "")
        return preferred(live: live, shadow: fallback)
    }

    public static func preferred(live: String, shadow: String) -> String {
        let liveEmpty = live.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shadowEmpty = shadow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if liveEmpty { return shadow }
        if shadowEmpty { return live }
        if live.count >= shadow.count { return live }
        if shadow.hasSuffix(live) || shadow.contains(live) {
            return shadow
        }
        return live
    }

    public static func utf16Length(_ text: String) -> Int {
        (text as NSString).length
    }
}

@MainActor
public final class DocumentProxyAdapter: KeyboardDocument {
    private let proxy: UITextDocumentProxy
    private var shadow = ""

    public init(_ proxy: UITextDocumentProxy) {
        self.proxy = proxy
    }

    public func insertText(_ text: String) {
        proxy.insertText(text)
        shadow += text
        if let live = rawLiveText(), live.count >= shadow.count {
            shadow = live
        }
    }

    public func deleteBackward() {
        proxy.deleteBackward()
        if !shadow.isEmpty {
            shadow.removeLast()
        }
        if let live = rawLiveText() {
            shadow = DocumentTextAssembler.preferred(live: live, shadow: shadow)
        }
    }

    public var documentContextBeforeInput: String? {
        proxy.documentContextBeforeInput
    }

    public var documentContextAfterInput: String? {
        proxy.documentContextAfterInput
    }

    public var selectedText: String? {
        proxy.selectedText
    }

    public var entireText: String? {
        let assembled = DocumentTextAssembler.combined(
            before: proxy.documentContextBeforeInput,
            selected: proxy.selectedText,
            after: proxy.documentContextAfterInput,
            fallback: shadow
        )
        if !assembled.isEmpty {
            shadow = assembled
        }
        return assembled.isEmpty ? nil : assembled
    }

    public func adjustTextPosition(byCharacterOffset offset: Int) {
        proxy.adjustTextPosition(byCharacterOffset: offset)
    }

    public func replaceEntireText(_ text: String) -> Bool {
        let after = proxy.documentContextAfterInput ?? ""
        guard after.isEmpty else {
            return false
        }
        let current = entireText ?? ""
        guard !current.isEmpty else {
            proxy.insertText(text)
            shadow = text
            return true
        }
        for _ in current {
            proxy.deleteBackward()
        }
        proxy.insertText(text)
        shadow = text
        return true
    }

    private func rawLiveText() -> String? {
        let live = (proxy.documentContextBeforeInput ?? "")
            + (proxy.selectedText ?? "")
            + (proxy.documentContextAfterInput ?? "")
        return live.isEmpty ? nil : live
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

    public var documentContextAfterInput: String? {
        guard let textView else { return nil }
        guard let selected = textView.selectedTextRange,
              let range = textView.textRange(from: selected.end, to: textView.endOfDocument) else {
            return nil
        }
        return textView.text(in: range)
    }

    public var selectedText: String? {
        guard let textView, let range = textView.selectedTextRange else { return nil }
        return textView.text(in: range)
    }

    public var entireText: String? {
        textView?.text
    }

    public func adjustTextPosition(byCharacterOffset offset: Int) {
        guard let textView, let selected = textView.selectedTextRange,
              let position = textView.position(from: selected.start, offset: offset) else { return }
        textView.selectedTextRange = textView.textRange(from: position, to: position)
    }

    public func replaceEntireText(_ text: String) -> Bool {
        guard let textView else { return false }
        activate(textView)
        textView.text = text
        moveCursorToEnd(textView)
        return true
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
