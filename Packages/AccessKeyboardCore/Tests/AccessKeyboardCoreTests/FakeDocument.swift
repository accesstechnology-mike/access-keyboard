@testable import AccessKeyboardCore

@MainActor
final class FakeDocument: KeyboardDocument {
    var text: String
    var cursor: Int

    init(text: String, cursor: Int? = nil) {
        self.text = text
        self.cursor = cursor ?? text.count
    }

    func insertText(_ text: String) {
        let index = self.text.index(self.text.startIndex, offsetBy: cursor)
        self.text.insert(contentsOf: text, at: index)
        cursor += text.count
    }

    func deleteBackward() {
        guard cursor > 0 else { return }
        let index = text.index(text.startIndex, offsetBy: cursor - 1)
        text.remove(at: index)
        cursor -= 1
    }

    var documentContextBeforeInput: String? { String(text.prefix(cursor)) }
    var documentContextAfterInput: String? { String(text.dropFirst(cursor)) }
    var selectedText: String? { nil }
    var entireText: String? { text }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursor = min(max(0, cursor + offset), text.count)
    }

    func replaceEntireText(_ text: String) -> Bool {
        self.text = text
        cursor = text.count
        return true
    }
}
