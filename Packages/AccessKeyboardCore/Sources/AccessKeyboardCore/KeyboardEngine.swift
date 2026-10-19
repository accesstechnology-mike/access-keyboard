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
    public var onPredictionsChange: (() -> Void)?
    public var fixClient: (any FixClient)?
    /// False in the keyboard extension until the user turns on Allow Full Access.
    /// The extension also has no general network entitlement without that switch.
    public var networkAllowed: Bool = false
    /// When false, the engine does not read the shared App Group (no Full Access).
    public var sharedPreferencesAvailable: Bool = true
    public private(set) var fixStatus: FixStatus = .idle
    public private(set) var fixNotice: FixNotice = .none
    /// Build-time switch. Tests can override this without editing `FeatureFlags`.
    public var fixConsentRequired: Bool = FeatureFlags.fixConsentRequired
    public var fixConsentIsGranted: () -> Bool = { KeyboardPreferences.fixConsentGranted }
    public var recordFixConsent: (Bool) -> Void = { KeyboardPreferences.fixConsentGranted = $0 }
    /// From `SubscriptionConfig.monetization`. Tests can override the split.
    public var keyboardRequiresSubscription: Bool = SubscriptionConfig.keyboardRequiresSubscription
    public var fixRequiresSubscription: Bool = SubscriptionConfig.fixRequiresSubscription
    /// Reads the App Group record written by the containing app. The extension never purchases.
    public var subscriptionIsActive: () -> Bool = {
        SubscriptionEntitlementStore.readShared().isActive(at: Date())
    }

    /// True when this build locks the keyboard and the extension cannot see an active subscription.
    public var keyboardIsLocked: Bool {
        KeyboardLock.isLocked(
            requiresSubscription: keyboardRequiresSubscription,
            canReadEntitlement: sharedPreferencesAvailable,
            entitled: sharedPreferencesAvailable && subscriptionIsActive()
        )
    }

    private var undoStack: [UndoRecord] = []
    private var redoStack: [UndoRecord] = []
    private var lastShiftTap: TimeInterval = 0
    private var memory: PredictionMemory
    /// True when the character before the cursor is a space this keyboard just
    /// inserted (prediction, space bar, or the space moved after punctuation),
    /// and `automaticSpaceContext` is the document context that space belongs
    /// to. A space that was already in the field is left alone.
    private var trailingSpaceIsAutomatic = false
    private var automaticSpaceContext: String?

    public convenience init() {
        self.init(memory: .shared)
    }

    init(memory: PredictionMemory) {
        self.memory = memory
    }

    public func documentDidChange() {
        reconcileAutomaticTrailingSpace()
        if fixStatus == .failed {
            fixStatus = .idle
        }
        applyAutocapitalization()
        applyKeyboardTypeHint()
        notify()
    }

    public func handle(_ action: KeyAction) {
        if keyboardIsLocked {
            if case .nextKeyboard = action {
                host?.advanceToNextInputMode()
            }
            return
        }
        dismissTransientFixNotice()
        switch action {
        case .character(let text):
            if text.contains(where: { $0.isPunctuation || $0.isNewline }) {
                learnCurrentWord()
            }
            insertCharacter(text)
            consumeOneShotShift()
            applyAutocapitalization()
        case .space:
            learnCurrentWord()
            insertSpaceOrPeriod()
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
            clearAutomaticTrailingSpace()
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

    public func continueBackspace(byWord: Bool) {
        guard !keyboardIsLocked else { return }
        if byWord {
            deleteBackwardWord()
        } else {
            deleteBackward()
        }
        clearAutomaticTrailingSpace()
        applyAutocapitalization()
        notify()
    }

    public func moveCursor(horizontal: Int, vertical: Int) {
        guard !keyboardIsLocked else { return }
        let before = document?.documentContextBeforeInput ?? ""
        let after = document?.documentContextAfterInput ?? ""
        let offset = EditingShortcuts.cursorOffset(
            before: before,
            after: after,
            horizontal: horizontal,
            vertical: vertical
        )
        guard offset != 0 else { return }
        document?.adjustTextPosition(byCharacterOffset: offset)
        clearAutomaticTrailingSpace()
        let previousShift = shift
        applyAutocapitalization()
        if previousShift != shift {
            notify()
        } else {
            onPredictionsChange?()
        }
    }

    public func predictions() -> [Prediction] {
        guard showsPredictions, mode == .alphabetic else { return [] }
        return PredictionProvider.suggestions(
            prefix: currentWordPrefix(),
            before: document?.documentContextBeforeInput,
            memory: memory
        )
    }

    public func requestFix() {
        guard fixStatus != .running else { return }
        guard !traits.isSecureTextEntry else {
            presentFixNotice(.secureField)
            return
        }
        // Only the paragraph around the cursor is sent and replaced, so Fix
        // never deletes back across a line break (Notes title / heading style).
        let original = fixTarget()
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        // Entitlement before consent. Without the App Group the extension cannot
        // see the record the app wrote, and Fix cannot use the network either.
        if fixRequiresSubscription {
            guard sharedPreferencesAvailable else {
                presentFixNotice(.fullAccess)
                return
            }
            guard subscriptionIsActive() else {
                presentFixNotice(.subscribe)
                return
            }
        }
        // Full Access is what lets the extension open a network connection.
        // Without it, Fix must not pretend to run and must not block typing.
        guard networkAllowed else {
            presentFixNotice(.fullAccess)
            return
        }
        guard let client = fixClient else {
            presentFixNotice(.unavailable)
            return
        }
        if fixConsentRequired && !fixConsentIsGranted() {
            presentFixNotice(.consent)
            return
        }

        fixNotice = .none
        fixStatus = .running
        notify()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fixed = try await client.fix(original)
                self.applyFixedText(original: original, fixed: fixed)
            } catch {
                self.failFix()
            }
        }
    }

    public func allowFixConsentAndSend() {
        recordFixConsent(true)
        fixNotice = .none
        requestFix()
    }

    public func declineFixConsent() {
        fixNotice = .none
        notify()
    }

    func usePredictionStore(sharedWithApp: Bool) {
        memory = PredictionMemory.store(sharedWithApp: sharedWithApp)
    }

    public func applyPrediction(_ prediction: Prediction) {
        guard !keyboardIsLocked else { return }
        dismissTransientFixNotice()
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
            noteAutomaticTrailingSpace()
        } else {
            clearAutomaticTrailingSpace()
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
            returnKeyType: traits.returnKeyType,
            letterLayout: sharedPreferencesAvailable ? KeyboardPreferences.letterLayout : .qwerty
        )
    }

    public func displayedText(for spec: KeySpec) -> String? {
        if shift.affectsSymbolKeys, let shifted = spec.shiftedDisplay, case .text(let value) = shifted {
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

    private func insertCharacter(_ text: String) {
        let before = document?.documentContextBeforeInput ?? ""
        if let replacement = EditingShortcuts.replacementByMovingAutomaticSpace(
            punctuation: text,
            before: before,
            spaceIsAutomatic: trailingSpaceIsAutomatic
        ) {
            document?.deleteBackward()
            if case .insert(" ") = undoStack.last {
                undoStack.removeLast()
            }
            insert(replacement)
            noteAutomaticTrailingSpace()
        } else {
            insert(text)
            clearAutomaticTrailingSpace()
        }
        if mode != .alphabetic, EditingShortcuts.returnsToAlphabetic(text) {
            mode = .alphabetic
        }
    }

    private func insertSpaceOrPeriod() {
        let before = document?.documentContextBeforeInput ?? ""
        guard EditingShortcuts.shouldConvertDoubleSpace(before) else {
            insert(" ")
            noteAutomaticTrailingSpace()
            return
        }
        document?.deleteBackward()
        if case .insert(" ") = undoStack.last {
            undoStack.removeLast()
        }
        insert(". ")
        noteAutomaticTrailingSpace()
    }

    private func noteAutomaticTrailingSpace() {
        let before = document?.documentContextBeforeInput ?? ""
        guard before.hasSuffix(" ") else {
            clearAutomaticTrailingSpace()
            return
        }
        trailingSpaceIsAutomatic = true
        automaticSpaceContext = before
    }

    private func clearAutomaticTrailingSpace() {
        trailingSpaceIsAutomatic = false
        automaticSpaceContext = nil
    }

    /// Drops the automatic-space flag when the field changed out from under the
    /// space we inserted (cursor moved elsewhere, or another edit landed).
    private func reconcileAutomaticTrailingSpace() {
        guard trailingSpaceIsAutomatic else { return }
        let before = document?.documentContextBeforeInput ?? ""
        if before != automaticSpaceContext {
            clearAutomaticTrailingSpace()
        }
    }

    private func deleteBackward() {
        let deleted = document?.documentContextBeforeInput?.last.map(String.init) ?? ""
        document?.deleteBackward()
        if !deleted.isEmpty {
            undoStack.append(.delete(deleted))
            redoStack.removeAll()
        }
    }

    private func deleteBackwardWord() {
        let before = document?.documentContextBeforeInput ?? ""
        let count = EditingShortcuts.wordDeleteLength(in: before)
        guard count > 0 else { return }
        let deleted = String(before.suffix(count))
        for _ in deleted {
            document?.deleteBackward()
        }
        undoStack.append(.delete(deleted))
        redoStack.removeAll()
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
        case .shifted, .autoShifted, .capsLock:
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
        case .replace(let deleted, let inserted):
            replaceDocument(from: inserted, to: deleted)
            redoStack.append(record)
        }
        clearAutomaticTrailingSpace()
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
        case .replace(let deleted, let inserted):
            replaceDocument(from: deleted, to: inserted)
            undoStack.append(record)
        }
        clearAutomaticTrailingSpace()
    }

    private func applyFixedText(original: String, fixed rawFixed: String) {
        clearAutomaticTrailingSpace()
        // The proxy trims the model's reply, so put back the original's
        // leading and trailing whitespace (newlines, an automatic space).
        let fixed = Self.preservingOuterWhitespace(of: original, in: rawFixed)
        if original != fixed {
            if document?.entireText == nil, fixTarget() != original {
                // The paragraph changed while Fix was running. Deleting
                // `original.count` characters now would eat the wrong text.
                failFix()
                return
            }
            if document?.replaceEntireText(fixed) == true {
                undoStack.append(.replace(deleted: original, inserted: fixed))
                redoStack.removeAll()
            } else {
                replaceHarvested(original, with: fixed)
            }
            applyAutocapitalization()
        }
        fixStatus = .idle
        notify()
        if original != fixed {
            UIAccessibility.post(notification: .announcement, argument: "Text fixed")
        }
    }

    private func replaceHarvested(_ original: String, with fixed: String) {
        // Move only to the end of the current paragraph, never past a newline,
        // then delete exactly the paragraph text Fix harvested.
        let afterInParagraph = Self.paragraphTail(of: document?.documentContextAfterInput)
        document?.adjustTextPosition(byCharacterOffset: (afterInParagraph as NSString).length)
        for _ in original {
            document?.deleteBackward()
        }
        document?.insertText(fixed)
        undoStack.append(.replace(deleted: original, inserted: fixed))
        redoStack.removeAll()
    }

    private func replaceDocument(from current: String, to next: String) {
        if document?.replaceEntireText(next) == true {
            return
        }
        for _ in current {
            document?.deleteBackward()
        }
        document?.insertText(next)
    }

    /// The text Fix sends and replaces. In the keyboard extension
    /// (`UITextDocumentProxy`) that is only the paragraph the cursor is in:
    /// the proxy can only delete backwards and insert, so harvesting across
    /// newlines meant Fix deleted earlier lines (in Notes, back into the
    /// title line) and re-inserted everything there, where it picked up the
    /// title style. The in-app test field can replace its whole text, so it
    /// keeps whole-field Fix.
    private func fixTarget() -> String {
        if let entire = document?.entireText {
            return entire
        }
        let selected = document?.selectedText ?? ""
        guard !selected.contains(where: \.isNewline) else {
            // A multi-paragraph selection cannot be replaced safely with
            // deleteBackward; fix nothing rather than merge paragraphs.
            return ""
        }
        return Self.paragraphHead(of: document?.documentContextBeforeInput)
            + selected
            + Self.paragraphTail(of: document?.documentContextAfterInput)
    }

    /// Text before the cursor back to (not including) the previous newline.
    static func paragraphHead(of before: String?) -> String {
        guard let before else { return "" }
        if let newline = before.lastIndex(where: \.isNewline) {
            return String(before[before.index(after: newline)...])
        }
        return before
    }

    /// Text after the cursor up to (not including) the next newline.
    static func paragraphTail(of after: String?) -> String {
        guard let after else { return "" }
        if let newline = after.firstIndex(where: \.isNewline) {
            return String(after[..<newline])
        }
        return after
    }

    static func preservingOuterWhitespace(of original: String, in fixed: String) -> String {
        let core = fixed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return fixed }
        let leading = original.prefix(while: \.isWhitespace)
        let trailing = String(original.reversed().prefix(while: \.isWhitespace).reversed())
        return String(leading) + core + trailing
    }

    private func presentFixNotice(_ notice: FixNotice) {
        fixNotice = notice
        fixStatus = .idle
        notify()
        if !notice.message.isEmpty {
            UIAccessibility.post(notification: .announcement, argument: notice.message)
        }
    }

    private func dismissTransientFixNotice() {
        guard fixNotice.isTransient else { return }
        fixNotice = .none
    }

    private func failFix() {
        fixStatus = .failed
        fixNotice = .offline
        notify()
        UIAccessibility.post(notification: .announcement, argument: FixNotice.offline.message)
    }

    private func applyAutocapitalization() {
        guard mode == .alphabetic, shift != .capsLock else { return }

        // URL / email / web-search / credential fields must never be
        // autocapitalized, so a typed address stays `x.com` rather than
        // `X.Com`. This also suppresses the capital after a `.` inside a URL.
        // Only clear an auto-shift; a manual shift the user just tapped is left
        // intact so they can still type an occasional capital.
        if traits.isURLLikeField {
            if shift == .autoShifted { shift = .off }
            return
        }

        switch traits.autocapitalizationType {
        case .none:
            return
        case .allCharacters:
            shift = .capsLock
        case .words:
            shift = shouldCapitalizeWord(document?.documentContextBeforeInput) ? .autoShifted : .off
        default:
            shift = shouldCapitalizeSentence(document?.documentContextBeforeInput) ? .autoShifted : .off
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
    case replace(deleted: String, inserted: String)
}
