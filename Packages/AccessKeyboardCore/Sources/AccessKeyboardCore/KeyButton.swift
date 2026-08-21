import UIKit

final class KeyButton: UIControl {
    var spec: KeySpec
    var appearance: KeyboardAppearance
    var metrics: LayoutMetrics
    var shift: ShiftState
    var isModifierHighlighted: Bool

    var onPress: ((KeySpec) -> Void)?
    var onRelease: ((KeySpec) -> Void)?
    var onLongPress: ((KeySpec) -> Void)?
    var onRepeat: ((KeySpec) -> Void)?
    var onDrag: ((KeySpec, CGPoint) -> Void)?
    var onFinishLongPress: ((KeySpec) -> Void)?

    private let label = UILabel()
    private let secondaryLabel = UILabel()
    private let symbolView = UIImageView()
    private var longPressTimer: Timer?
    private var repeatTimer: Timer?
    private var didLongPress = false

    init(
        spec: KeySpec,
        appearance: KeyboardAppearance,
        metrics: LayoutMetrics,
        shift: ShiftState,
        isModifierHighlighted: Bool
    ) {
        self.spec = spec
        self.appearance = appearance
        self.metrics = metrics
        self.shift = shift
        self.isModifierHighlighted = isModifierHighlighted
        super.init(frame: .zero)
        isExclusiveTouch = true
        layer.cornerRadius = metrics.cornerRadius
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 1
        clipsToBounds = false

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.isUserInteractionEnabled = false

        secondaryLabel.textAlignment = .right
        secondaryLabel.isUserInteractionEnabled = false

        symbolView.contentMode = .scaleAspectFit
        symbolView.isUserInteractionEnabled = false
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: metrics.symbolPointSize,
            weight: .medium
        )

        addSubview(label)
        addSubview(secondaryLabel)
        addSubview(symbolView)
        applyChrome()
        applyContent()
        configureAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        longPressTimer?.invalidate()
        repeatTimer?.invalidate()
    }

    override var isHighlighted: Bool {
        didSet { applyChrome() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 2
        if spec.secondary != nil {
            secondaryLabel.frame = CGRect(x: inset, y: 3, width: bounds.width - inset * 2, height: 12)
            label.frame = CGRect(x: inset, y: 10, width: bounds.width - inset * 2, height: bounds.height - 12)
        } else {
            secondaryLabel.frame = .zero
            label.frame = bounds.insetBy(dx: 4, dy: 2)
        }
        symbolView.frame = bounds.insetBy(dx: 8, dy: 8)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: metrics.cornerRadius).cgPath
        layer.shadowColor = appearance.shadowColor.cgColor
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isHighlighted = true
        didLongPress = false
        onPress?(spec)
        scheduleLongPress()
        if spec.action == .backspace {
            scheduleRepeat()
        }
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let locationInSelf = touch.location(in: self)
        let inside = bounds.insetBy(dx: -20, dy: -20).contains(locationInSelf)
        isHighlighted = inside && !didLongPress
        if didLongPress, let parent = superview {
            onDrag?(spec, touch.location(in: parent))
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        cancelTimers()
        let inside = bounds.insetBy(dx: -20, dy: -20).contains(touch?.location(in: self) ?? .zero)
        isHighlighted = false
        if didLongPress {
            onFinishLongPress?(spec)
        } else if inside {
            onRelease?(spec)
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        cancelTimers()
        isHighlighted = false
    }

    private func scheduleLongPress() {
        longPressTimer = Timer.scheduledTimer(withTimeInterval: spec.action == .capsLock ? 0.35 : 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.didLongPress = true
                self.onLongPress?(self.spec)
            }
        }
    }

    private func scheduleRepeat() {
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.onRepeat?(self.spec)
                    }
                }
            }
        }
    }

    private func cancelTimers() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func applyChrome() {
        backgroundColor = appearance.fill(
            for: spec.style,
            character: letterCharacter,
            pressed: isHighlighted,
            highlightedModifier: isModifierHighlighted
        )
        let color = spec.style == .primary && !isHighlighted
            ? appearance.primaryTextColor
            : appearance.foreground(
                for: spec.style == .primary && isHighlighted ? .letter : spec.style,
                character: letterCharacter
            )
        label.textColor = color
        symbolView.tintColor = color
        secondaryLabel.textColor = appearance.secondaryTextColor
        layer.cornerRadius = metrics.cornerRadius
    }

    private func applyContent() {
        secondaryLabel.font = .systemFont(ofSize: 10, weight: .regular)
        secondaryLabel.text = spec.secondary

        switch display {
        case .text(let value):
            label.isHidden = false
            symbolView.isHidden = true
            label.text = displayedLabel(for: value)
            let isModifier = spec.style != .letter
            if spec.style == .letter,
               appearance.usesLiteracyFont,
               let literacy = LiteracyFont.uiFont(ofSize: metrics.letterFontSize) {
                label.font = literacy
            } else {
                label.font = .systemFont(
                    ofSize: isModifier ? metrics.modifierFontSize : metrics.letterFontSize,
                    weight: .regular
                )
                if spec.style == .letter, value.count == 1 {
                    label.font = .systemFont(ofSize: metrics.letterFontSize, weight: .light)
                }
            }
        case .symbol(let name):
            label.isHidden = true
            symbolView.isHidden = false
            symbolView.image = UIImage(systemName: name)
        case .blank:
            label.isHidden = true
            symbolView.isHidden = true
        }
    }

    private var display: KeyDisplay {
        if shift.isUppercase, let shifted = spec.shiftedDisplay {
            return shifted
        }
        return spec.display
    }

    private var letterCharacter: String? {
        if case .character(let text) = spec.action {
            return text
        }
        return nil
    }

    private func displayedLabel(for value: String) -> String {
        guard appearance.keepsLetterKeycapsLowercase,
              spec.style == .letter,
              value.count == 1,
              value.first?.isLetter == true else {
            return value
        }
        return value.lowercased()
    }

    private func configureAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityLabel = accessibilityTitle
    }

    private var accessibilityTitle: String {
        switch spec.action {
        case .character(let text):
            if shift.isUppercase, let shifted = spec.shiftedDisplay, case .text(let value) = shifted {
                return value
            }
            return text
        case .shift:
            switch shift {
            case .off: return "Shift"
            case .shifted: return "Shifted"
            case .capsLock: return "Caps Lock"
            }
        case .capsLock: return "Caps Lock"
        case .backspace: return "Delete"
        case .space: return "Space"
        case .returnKey: return "Return"
        case .tab: return "Tab"
        case .setMode(let mode):
            switch mode {
            case .alphabetic: return "Letters"
            case .numeric: return "Numbers"
            case .symbols: return "Symbols"
            }
        case .nextKeyboard: return "Next Keyboard"
        case .dismissKeyboard: return "Hide Keyboard"
        case .undo: return "Undo"
        case .redo: return "Redo"
        }
    }
}
