import UIKit

public final class KeyboardView: UIView {
    public let engine: KeyboardEngine

    public var idiom: UIUserInterfaceIdiom
    public var extraBottomInset: CGFloat = 0

    private var keyButtons: [KeyButton] = []
    private var currentLayout: KeyboardLayout?
    private var currentMetrics: LayoutMetrics?
    private var appearance = KeyboardAppearance.system(for: .light)
    private var callout: AccentCalloutView?
    private let predictionBar = PredictionBarView()
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    public convenience init() {
        self.init(engine: KeyboardEngine())
    }

    public init(engine: KeyboardEngine) {
        self.engine = engine
        self.idiom = UIDevice.current.userInterfaceIdiom
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        isMultipleTouchEnabled = false
        engine.onChange = { [weak self] in
            self?.reloadKeys()
        }
        predictionBar.onSelect = { [weak self] prediction in
            UIDevice.current.playInputClick()
            self?.haptics.impactOccurred(intensity: 0.55)
            self?.engine.applyPrediction(prediction)
        }
        addSubview(predictionBar)
        updateAppearance()
        haptics.prepare()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateAppearance()
            reloadKeys()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let layout = engine.layout(for: bounds.size, idiom: idiom)
        let metrics = LayoutMetrics.metrics(
            for: layout.layoutClass,
            bounds: bounds.size,
            safeBottom: extraBottomInset
        )
        if layout != currentLayout || metrics != currentMetrics {
            currentLayout = layout
            currentMetrics = metrics
            rebuildKeys(layout: layout, metrics: metrics)
        }
        layoutPredictionBar(metrics: metrics)
        layoutKeys(layout: layout, metrics: metrics)
    }

    public var preferredHeight: CGFloat {
        let layoutClass = LayoutClassResolver.resolve(size: bounds.size.width > 0 ? bounds.size : CGSize(width: 1024, height: 300), idiom: idiom)
        let metrics = LayoutMetrics.metrics(for: layoutClass, bounds: bounds.size, safeBottom: extraBottomInset)
        if engine.showsPredictions {
            return metrics.preferredHeight
        }
        return metrics.preferredHeight - metrics.predictionBarHeight
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    private func updateAppearance() {
        appearance = KeyboardAppearance.system(for: traitCollection.userInterfaceStyle)
        backgroundColor = appearance.backgroundColor
    }

    private func reloadKeys() {
        currentLayout = nil
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private func rebuildKeys(layout: KeyboardLayout, metrics: LayoutMetrics) {
        keyButtons.forEach { $0.removeFromSuperview() }
        keyButtons = layout.rows.flatMap { row in
            row.keys.map { spec in
                let button = KeyButton(
                    spec: spec,
                    appearance: appearance,
                    metrics: metrics,
                    shift: engine.shift,
                    isModifierHighlighted: isHighlightedModifier(spec)
                )
                button.onPress = { [weak self] spec in
                    self?.handlePress(spec)
                }
                button.onRelease = { [weak self] spec in
                    self?.handleRelease(spec)
                }
                button.onLongPress = { [weak self] spec in
                    self?.handleLongPress(spec, from: button)
                }
                button.onRepeat = { [weak self] spec in
                    self?.handleRepeat(spec)
                }
                button.onDrag = { [weak self] _, point in
                    self?.callout?.updateSelection(at: point)
                }
                button.onFinishLongPress = { [weak self] spec in
                    self?.finishLongPress(spec)
                }
                addSubview(button)
                return button
            }
        }
    }

    private func layoutPredictionBar(metrics: LayoutMetrics) {
        predictionBar.isHidden = !engine.showsPredictions
        guard engine.showsPredictions else { return }
        predictionBar.update(
            predictions: engine.predictions(),
            appearance: appearance,
            fontSize: metrics.modifierFontSize + 2
        )
        predictionBar.frame = CGRect(
            x: metrics.sideInset,
            y: 4,
            width: bounds.width - metrics.sideInset * 2,
            height: metrics.predictionBarHeight - 8
        )
        bringSubviewToFront(predictionBar)
    }

    private func layoutKeys(layout: KeyboardLayout, metrics: LayoutMetrics) {
        let usableWidth = bounds.width - metrics.sideInset * 2
        let unit = unitWidth(in: layout, usableWidth: usableWidth, metrics: metrics)
        var y = metrics.topInset + (engine.showsPredictions ? metrics.predictionBarHeight : 0)
        var buttonIndex = 0
        for row in layout.rows {
            let frames = framesForRow(row, y: y, usableWidth: usableWidth, unit: unit, metrics: metrics)
            for frame in frames {
                if buttonIndex < keyButtons.count {
                    keyButtons[buttonIndex].frame = frame
                    buttonIndex += 1
                }
            }
            y += metrics.keyHeight + metrics.rowSpacing
        }
    }

    private func unitWidth(in layout: KeyboardLayout, usableWidth: CGFloat, metrics: LayoutMetrics) -> CGFloat {
        let reference = layout.rows.max { lhs, rhs in
            fixedWeight(of: lhs) < fixedWeight(of: rhs)
        } ?? layout.rows[0]
        let gaps = CGFloat(max(reference.keys.count - 1, 0)) * metrics.keySpacing
        let weight = max(fixedWeight(of: reference), 1)
        return (usableWidth - gaps) / weight
    }

    private func framesForRow(
        _ row: KeyboardRow,
        y: CGFloat,
        usableWidth: CGFloat,
        unit: CGFloat,
        metrics: LayoutMetrics
    ) -> [CGRect] {
        let gap = metrics.keySpacing
        let gaps = CGFloat(max(row.keys.count - 1, 0)) * gap
        let flexibleCount = row.keys.filter { $0.width == .flexible }.count
        let fixed = row.keys.reduce(CGFloat(0)) { sum, spec in
            if spec.width == .flexible { return sum }
            return sum + weight(of: spec.width)
        }

        let leftover = usableWidth - fixed * unit - gaps
        let flexWidth: CGFloat
        let leading: CGFloat
        if flexibleCount > 0 {
            flexWidth = max(unit, leftover / CGFloat(flexibleCount))
            leading = metrics.sideInset
        } else {
            flexWidth = 0
            let rowWidth = fixed * unit + gaps
            leading = metrics.sideInset + max(0, (usableWidth - rowWidth) / 2) + row.leadingInsetUnits * unit
        }

        var cursor = leading
        var frames: [CGRect] = []
        for spec in row.keys {
            let keyWidth: CGFloat
            if spec.width == .flexible {
                keyWidth = flexWidth
            } else {
                keyWidth = unit * weight(of: spec.width)
            }
            frames.append(CGRect(x: cursor, y: y, width: keyWidth, height: metrics.keyHeight))
            cursor += keyWidth + gap
        }
        return frames
    }

    private func fixedWeight(of row: KeyboardRow) -> CGFloat {
        row.keys.reduce(0) { $0 + weight(of: $1.width) }
    }

    private func weight(of width: KeyWidth) -> CGFloat {
        switch width {
        case .unit(let value):
            return value
        case .flexible:
            return 4.5
        }
    }

    private func isHighlightedModifier(_ spec: KeySpec) -> Bool {
        switch spec.action {
        case .shift:
            return engine.shift != .off
        case .capsLock:
            return engine.shift == .capsLock
        default:
            return false
        }
    }

    private func handlePress(_ spec: KeySpec) {
        UIDevice.current.playInputClick()
        haptics.impactOccurred(intensity: 0.55)
        haptics.prepare()
        if spec.action == .backspace {
            engine.handle(.backspace)
        }
    }

    private func handleRelease(_ spec: KeySpec) {
        if spec.action == .backspace {
            return
        }
        perform(spec)
    }

    private func handleLongPress(_ spec: KeySpec, from button: KeyButton) {
        switch spec.action {
        case .capsLock:
            engine.handle(.capsLock)
        case .character(let text):
            let base = displayedCharacter(for: spec) ?? text
            let options = AccentMap.displaying(
                AccentMap.accents(for: base),
                uppercase: engine.shift.isUppercase
            )
            guard !options.isEmpty else { return }
            showCallout(options: [base] + options, from: button.frame)
        default:
            break
        }
    }

    private func handleRepeat(_ spec: KeySpec) {
        if spec.action == .backspace {
            engine.handle(.backspace)
        }
    }

    private func finishLongPress(_ spec: KeySpec) {
        if callout != nil {
            callout?.commit()
            callout = nil
            return
        }
        switch spec.action {
        case .capsLock, .backspace:
            break
        default:
            perform(spec)
        }
    }

    private func perform(_ spec: KeySpec) {
        if case .character = spec.action, let text = displayedCharacter(for: spec) {
            engine.handleCharacter(text)
            return
        }
        engine.handle(spec.action)
    }

    private func displayedCharacter(for spec: KeySpec) -> String? {
        if engine.shift.isUppercase, let shifted = spec.shiftedDisplay, case .text(let value) = shifted {
            return value
        }
        if case .text(let value) = spec.display {
            return value
        }
        if case .character(let value) = spec.action {
            return value
        }
        return nil
    }

    private func showCallout(options: [String], from keyFrame: CGRect) {
        callout?.removeFromSuperview()
        let view = AccentCalloutView(appearance: appearance)
        view.onSelect = { [weak self] value in
            self?.engine.handleCharacter(value)
            self?.callout = nil
        }
        view.show(options: options, from: keyFrame, in: self, appearance: appearance)
        callout = view
    }
}

extension KeyboardView: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}
