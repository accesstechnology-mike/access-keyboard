import UIKit

@MainActor
public final class KeyboardEngine {
    public var document: KeyboardDocument?
    public weak var host: KeyboardHost?

    public var traits = KeyboardTraits() {
        didSet {
            if oldValue != traits {
                applyKeyboardTypeHint()
                notify()
            }
        }
    }

    public private(set) var mode: KeyboardMode = .alphabetic
    public private(set) var shift: ShiftState = .off

    public var needsInputModeSwitchKey: Bool = true {
        didSet { if oldValue != needsInputModeSwitchKey { notify() } }
    }

    public var showsPredictions: Bool = true {
        didSet { if oldValue != showsPredictions { notify() } }
    }

    public var onChange: (() -> Void)?

    private var undoStack: [UndoRecord] = []
    private var redoStack: [UndoRecord] = []
    private var lastShiftTap: TimeInterval = 0
    private let memory: PredictionMemory

    public convenience init() {
        self.init(memory: .shared)
    }

    init(memory: PredictionMemory) {
        self.memory = memory
    }

    public func documentDidChange() {
        applyAutocapitalization()
        applyKeyboardTypeHint()
        notify()
    }

    public func handle(_ action: KeyAction) {
        switch action {
        case .character(let text):
            if text.contains(where: { $0.isPunctuation || $0.isNewline }) {
                learnCurrentWord()
            }
            insert(text)
            consumeOneShotShift()
            applyAutocapitalization()
        case .space:
            learnCurrentWord()
            insert(" ")
            consumeOneShotShift()
            applyAutocapitalization()
        case .tab:
            insert("\t")
        case .returnKey:
            learnCurrentWord()
            insert("\n")
            applyAutocapitalization()
        case .backspace:
            deleteBackward()
            applyAutocapitalization()
        case .shift:
            toggleShift()
        case .capsLock:
            shift = (shift == .capsLock) ? .off : .capsLock
        case .setMode(let newMode):
            mode = newMode
            if newMode != .alphabetic {
                shift = .off
            }
        case .nextKeyboard:
            host?.advanceToNextInputMode()
        case .dismissKeyboard:
            host?.dismissKeyboard()
        case .undo:
            performUndo()
        case .redo:
            performRedo()
        }
        notify()
    }

    public func handleCharacter(_ text: String) {
        handle(.character(text))
    }

    public func predictions() -> [Prediction] {
        guard showsPredictions, mode == .alphabetic else { return [] }
        return PredictionProvider.suggestions(
            prefix: currentWordPrefix(),
            before: document?.documentContextBeforeInput,
            memory: memory
        )
    }

    public func applyPrediction(_ prediction: Prediction) {
        let before = document?.documentContextBeforeInput
        let prefix = currentWordPrefix()
        let previous = PredictionProvider.previousWord(in: before, currentPrefix: prefix)
        memory.record(previous: previous, next: prediction.insertion)
        for _ in prefix {
            deleteBackward()
        }
        insert(prediction.insertion)
        if prediction.insertion.last?.isWhitespace != true {
            insert(" ")
        }
        consumeOneShotShift()
        applyAutocapitalization()
        notify()
    }

    public func layout(for size: CGSize, idiom: UIUserInterfaceIdiom) -> KeyboardLayout {
        let layoutClass = LayoutClassResolver.resolve(size: size, idiom: idiom)
        return LayoutFactory.layout(
            mode: mode,
            shift: shift,
            layoutClass: layoutClass,
            needsInputModeSwitchKey: needsInputModeSwitchKey,
            returnKeyType: traits.returnKeyType
        )
    }

    public func displayedText(for spec: KeySpec) -> String? {
        if shift.isUppercase, let shifted = spec.shiftedDisplay, case .text(let value) = shifted {
            return value
        }
        if case .text(let value) = spec.display {
            return value
        }
        return nil
    }

    private func insert(_ text: String) {
        document?.insertText(text)
        undoStack.append(.insert(text))
        redoStack.removeAll()
    }

    private func deleteBackward() {
        let deleted = document?.documentContextBeforeInput?.last.map(String.init) ?? ""
        document?.deleteBackward()
        if !deleted.isEmpty {
            undoStack.append(.delete(deleted))
            redoStack.removeAll()
        }
    }

    private func consumeOneShotShift() {
        if shift == .shifted {
            shift = .off
        }
    }

    private func toggleShift() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastShiftTap < 0.35 {
            shift = .capsLock
            lastShiftTap = 0
            return
        }
        lastShiftTap = now
        switch shift {
        case .off:
            shift = .shifted
        case .shifted, .capsLock:
            shift = .off
        }
    }

    private func performUndo() {
        guard let record = undoStack.popLast() else { return }
        switch record {
        case .insert(let text):
            for _ in text {
                document?.deleteBackward()
            }
            redoStack.append(record)
        case .delete(let text):
            document?.insertText(text)
            redoStack.append(record)
        }
    }

    private func performRedo() {
        guard let record = redoStack.popLast() else { return }
        switch record {
        case .insert(let text):
            document?.insertText(text)
            undoStack.append(record)
        case .delete:
            document?.deleteBackward()
            undoStack.append(record)
        }
    }

    private func applyAutocapitalization() {
        guard mode == .alphabetic, shift != .capsLock else { return }

        switch traits.autocapitalizationType {
        case .none:
            return
        case .allCharacters:
            shift = .capsLock
        case .words:
            shift = shouldCapitalizeWord(document?.documentContextBeforeInput) ? .shifted : .off
        default:
            shift = shouldCapitalizeSentence(document?.documentContextBeforeInput) ? .shifted : .off
        }
    }

    private func applyKeyboardTypeHint() {
        switch traits.keyboardType {
        case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad:
            if mode == .alphabetic {
                mode = .numeric
            }
        default:
            break
        }
    }

    private func shouldCapitalizeSentence(_ before: String?) -> Bool {
        guard let before, !before.isEmpty else { return true }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if let last = trimmed.last, [".", "!", "?", "\n"].contains(last) {
            return true
        }
        return false
    }

    private func shouldCapitalizeWord(_ before: String?) -> Bool {
        guard let before, !before.isEmpty else { return true }
        if let last = before.last, last == " " || last == "\n" || last == "\t" {
            return true
        }
        return false
    }

    private func currentWordPrefix() -> String {
        PredictionProvider.currentWordPrefix(in: document?.documentContextBeforeInput)
    }

    private func learnCurrentWord() {
        let before = document?.documentContextBeforeInput
        let current = PredictionProvider.currentWordPrefix(in: before)
        guard !current.isEmpty else { return }
        let previous = PredictionProvider.previousWord(in: before, currentPrefix: current)
        memory.record(previous: previous, next: current)
    }

    private func notify() {
        onChange?()
    }
}

private enum UndoRecord {
    case insert(String)
    case delete(String)
}
