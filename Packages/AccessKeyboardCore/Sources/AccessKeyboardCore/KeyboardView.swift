import UIKit

public final class KeyboardView: UIView {
    public let engine: KeyboardEngine

    public var idiom: UIUserInterfaceIdiom
    public var extraBottomInset: CGFloat = 0

    private var keyButtons: [KeyButton] = []
    private var currentLayout: KeyboardLayout?
    private var currentMetrics: LayoutMetrics?
    private var contentDirty = false
    private var appearance = KeyboardAppearance.system(for: .light)
    private var callout: AccentCalloutView?
    private var preferenceObservation: KeyboardPreferenceObservation?
    private let predictionBar = PredictionBarView()
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var cursorTrackpad: UIPanGestureRecognizer?
    private var trackpadRemainder = CGPoint.zero

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
        isMultipleTouchEnabled = true
        engine.onChange = { [weak self] in
            self?.reloadKeys()
        }
        engine.onPredictionsChange = { [weak self] in
            self?.refreshPredictions()
        }
        // Two-finger pan scrubs the text cursor across the whole keyboard
        // surface, like the stock iOS/iPadOS keyboard. Requiring two touches
        // keeps single-finger typing untouched: a lone touch never starts the
        // pan, so it flows straight through to the key buttons.
        let trackpad = UIPanGestureRecognizer(target: self, action: #selector(handleCursorTrackpad(_:)))
        trackpad.minimumNumberOfTouches = 2
        trackpad.maximumNumberOfTouches = 2
        trackpad.cancelsTouchesInView = true
        trackpad.delegate = self
        addGestureRecognizer(trackpad)
        cursorTrackpad = trackpad
        predictionBar.onSelect = { [weak self] prediction in
            UIDevice.current.playInputClick()
            self?.haptics.impactOccurred(intensity: 0.55)
            self?.engine.applyPrediction(prediction)
        }
        predictionBar.onFix = { [weak self] in
            UIDevice.current.playInputClick()
            self?.haptics.impactOccurred(intensity: 0.55)
            self?.engine.requestFix()
        }
        addSubview(predictionBar)
        updateAppearance()
        preferenceObservation = KeyboardPreferences.observe { [weak self] in
            self?.applyCurrentPreferences()
        }
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
            safeBottom: extraBottomInset,
            rowCount: layout.rows.count
        )
        // Rebuild the view hierarchy only when the board's shape changes (mode,
        // rotation, size class). For ordinary keystrokes the structure is
        // identical, so reuse the existing buttons and just refresh their
        // content — this avoids destroying and recreating ~30-40 views on every
        // press, which caused allocation churn and mid-touch teardown in the
        // memory-limited keyboard extension.
        if keyButtons.isEmpty || metrics != currentMetrics || !layout.hasSameStructure(as: currentLayout) {
            rebuildKeys(layout: layout, metrics: metrics)
        } else if layout != currentLayout || contentDirty {
            updateKeys(layout: layout, metrics: metrics)
        }
        currentLayout = layout
        currentMetrics = metrics
        contentDirty = false
        layoutPredictionBar(metrics: metrics)
        layoutKeys(layout: layout, metrics: metrics)
    }

    public var preferredHeight: CGFloat {
        let size = bounds.size.width > 0 ? bounds.size : CGSize(width: 1024, height: 300)
        let layout = engine.layout(for: size, idiom: idiom)
        let metrics = LayoutMetrics.metrics(
            for: layout.layoutClass,
            bounds: size,
            safeBottom: extraBottomInset,
            rowCount: layout.rows.count
        )
        if engine.showsPredictions {
            return metrics.preferredHeight
        }
        return metrics.preferredHeight - metrics.predictionBarHeight
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    public func applyCurrentPreferences() {
        updateAppearance()
        reloadKeys()
    }

    /// Drops transient UI (the accent callout) so the keyboard extension can
    /// shed memory when the system issues a memory warning. Keyboard extensions
    /// run under a tight memory limit, so releasing anything non-essential
    /// reduces the chance of a jetsam kill during long sessions.
    public func releaseTransientResources() {
        callout?.removeFromSuperview()
        callout = nil
    }

    private func updateAppearance() {
        LiteracyFont.registerIfNeeded()
        KeyboardPreferences.persistMigratedColourOptionIfNeeded()
        appearance = KeyboardAppearance.resolved(
            colour: KeyboardPreferences.colourOption,
            style: traitCollection.userInterfaceStyle
        )
        backgroundColor = appearance.backgroundColor
    }

    private func reloadKeys() {
        contentDirty = true
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private func refreshPredictions() {
        guard let metrics = currentMetrics else {
            reloadKeys()
            return
        }
        layoutPredictionBar(metrics: metrics)
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
                button.onRepeat = { [weak self] spec, phase in
                    self?.handleRepeat(spec, phase: phase)
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

    private func updateKeys(layout: KeyboardLayout, metrics: LayoutMetrics) {
        let specs = layout.rows.flatMap { $0.keys }
        guard specs.count == keyButtons.count else {
            rebuildKeys(layout: layout, metrics: metrics)
            return
        }
        for (index, spec) in specs.enumerated() {
            let button = keyButtons[index]
            button.update(
                spec: spec,
                appearance: appearance,
                metrics: metrics,
                shift: engine.shift,
                isModifierHighlighted: isHighlightedModifier(spec)
            )
        }
    }

    private func layoutPredictionBar(metrics: LayoutMetrics) {
        predictionBar.isHidden = !engine.showsPredictions
        guard engine.showsPredictions else { return }
        predictionBar.update(
            predictions: engine.predictions(),
            fixStatus: engine.fixStatus,
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
        // The width math lives in KeyboardGeometry so it can be unit tested
        // (a compact iPhone board must never overflow); the view just positions
        // its buttons from the frames it returns.
        let rows = KeyboardGeometry.frames(
            for: layout,
            metrics: metrics,
            boundsWidth: bounds.width,
            showsPredictions: engine.showsPredictions
        )
        var buttonIndex = 0
        for frames in rows {
            for frame in frames {
                if buttonIndex < keyButtons.count {
                    keyButtons[buttonIndex].frame = frame
                    buttonIndex += 1
                }
            }
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

    private func handleRepeat(_ spec: KeySpec, phase: KeyRepeatPhase) {
        if spec.action == .backspace {
            engine.continueBackspace(byWord: phase == .word)
        }
    }

    @objc private func handleCursorTrackpad(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            trackpadRemainder = .zero
        case .changed:
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            trackpadRemainder.x += translation.x
            trackpadRemainder.y += translation.y
            guard let keyHeight = currentMetrics?.keyHeight else { return }
            let characterStep = max(1, (keyHeight / 8).rounded())
            let lineStep = max(1, (keyHeight / 4).rounded())
            let horizontal = Int((trackpadRemainder.x / characterStep).rounded(.towardZero))
            let vertical = Int((trackpadRemainder.y / lineStep).rounded(.towardZero))
            if horizontal != 0 {
                trackpadRemainder.x -= CGFloat(horizontal) * characterStep
            }
            if vertical != 0 {
                trackpadRemainder.y -= CGFloat(vertical) * lineStep
            }
            if horizontal != 0 || vertical != 0 {
                engine.moveCursor(horizontal: horizontal, vertical: vertical)
            }
        default:
            trackpadRemainder = .zero
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
        if engine.shift.affectsSymbolKeys, let shifted = spec.shiftedDisplay, case .text(let value) = shifted {
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
        let letterFill = appearance.usesBethLetterColors ? BethColorMap.fill(for: options[0]) : nil
        view.show(options: options, from: keyFrame, in: self, appearance: appearance, letterFill: letterFill)
        callout = view
    }
}

extension KeyboardView: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}

extension KeyboardView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === cursorTrackpad else { return true }
        // Accept touches anywhere on the keyboard, even when they land on a key
        // button, so a two-finger pan scrubs the cursor over the whole surface,
        // not just the space bar. The two-touch requirement means this never
        // steals a single-finger tap from a key or a prediction.
        return true
    }

    // Note: `gestureRecognizerShouldBegin(_:)` is intentionally NOT implemented
    // here. It is a `UIView` method (not just a delegate method), so declaring
    // it in this extension would require `override`, which extensions cannot do.
    // The default returns true, which is exactly what the scrub needs: the pan
    // only begins once two touches are in motion, so it never fights typing.

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Never let another recognizer block the cursor scrub, or require it to
        // fail first, when fingers start on a key.
        gestureRecognizer === cursorTrackpad || other === cursorTrackpad
    }
}
