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
    private let predictionColumn = PredictionColumnView()
    private let predictionBar = PredictionBarView()
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var cursorTrackpad: UIPanGestureRecognizer?
    private var trackpadRemainder = CGPoint.zero
    private var sharesPredictionMemory: Bool
    /// The host updates its height constraint when Fix shows a hint or the consent step.
    public var onPreferredHeightChange: (() -> Void)?
    private var predictionPlacement = KeyboardPreferences.predictionPlacement

    /// `sharesPredictionMemory` is false in the keyboard extension until Allow Full
    /// Access is on. That path keeps learned words in the extension's own defaults
    /// and does not open the App Group.
    public convenience init(sharesPredictionMemory: Bool = true) {
        let engine = KeyboardEngine(memory: PredictionMemory.store(sharedWithApp: sharesPredictionMemory))
        engine.sharedPreferencesAvailable = sharesPredictionMemory
        engine.networkAllowed = sharesPredictionMemory
        self.init(engine: engine, sharesPredictionMemory: sharesPredictionMemory)
    }

    public init(engine: KeyboardEngine, sharesPredictionMemory: Bool = true) {
        self.engine = engine
        self.sharesPredictionMemory = sharesPredictionMemory
        self.idiom = UIDevice.current.userInterfaceIdiom
        super.init(frame: .zero)
        commonInit()
    }

    public func setSharesPredictionMemory(_ shares: Bool) {
        guard sharesPredictionMemory != shares else { return }
        sharesPredictionMemory = shares
        engine.usePredictionStore(sharedWithApp: shares)
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
        let selectPrediction: (Prediction) -> Void = { [weak self] prediction in
            UIDevice.current.playInputClick()
            self?.haptics.impactOccurred(intensity: 0.55)
            self?.engine.applyPrediction(prediction)
        }
        let requestFix: () -> Void = { [weak self] in
            UIDevice.current.playInputClick()
            self?.haptics.impactOccurred(intensity: 0.55)
            self?.engine.requestFix()
        }
        predictionBar.onAllowConsent = { [weak self] in
            self?.engine.allowFixConsentAndSend()
        }
        predictionBar.onDeclineConsent = { [weak self] in
            self?.engine.declineFixConsent()
        }
        predictionColumn.onSelect = selectPrediction
        predictionColumn.onFix = requestFix
        predictionBar.onSelect = selectPrediction
        predictionBar.onFix = requestFix
        addSubview(predictionColumn)
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
        let current = board(for: bounds.size)
        let layout = current.layout
        let metrics = current.metrics
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
        let arrangement = predictionArrangement(layout: layout, metrics: metrics, usesColumn: current.usesColumn)
        layoutPredictionColumn(arrangement: arrangement, metrics: metrics)
        layoutPredictionBar(layout: layout, metrics: metrics, usesColumn: current.usesColumn)
        layoutKeys(layout: layout, metrics: metrics, arrangement: arrangement, usesColumn: current.usesColumn)
    }

    private struct Board {
        var layout: KeyboardLayout
        var metrics: LayoutMetrics
        /// Predictions in the left column (true) or a bar above the keys.
        var usesColumn: Bool
    }

    /// Layout, metrics and prediction placement for a keyboard of `size`.
    /// iPad boards normally use the side column and have no bar height. When
    /// the user prefers top and the iPad is in landscape, the board gets a
    /// bar one key tall above the keys instead; the keys keep their size.
    private func board(for size: CGSize) -> Board {
        let layout = engine.layout(for: size, idiom: idiom)
        var metrics = LayoutMetrics.metrics(
            for: layout.layoutClass,
            bounds: size,
            safeBottom: extraBottomInset,
            rowCount: layout.rows.count
        )
        let usesColumn = PredictionColumnGeometry.usesVerticalColumn(
            layout.layoutClass,
            placement: predictionPlacement,
            isLandscape: isLandscapeScreen,
            fixNotice: engine.fixNotice
        )
        if PredictionColumnGeometry.usesVerticalColumn(layout.layoutClass), !usesColumn {
            metrics.predictionBarHeight = PredictionColumnGeometry.topBarHeight(for: metrics)
        }
        metrics = metricsForCurrentNotice(metrics)
        return Board(layout: layout, metrics: metrics, usesColumn: usesColumn)
    }

    /// Interface orientation of the screen the keyboard is on. The keyboard's
    /// own bounds are always wider than tall, so they cannot tell portrait
    /// from landscape. Screen bounds follow the interface orientation.
    private var isLandscapeScreen: Bool {
        let size = window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        return size.width > size.height
    }

    public var preferredHeight: CGFloat {
        let size = bounds.size.width > 0 ? bounds.size : CGSize(width: 1024, height: 300)
        let metrics = board(for: size).metrics
        if engine.showsPredictions {
            return metrics.preferredHeight
        }
        return metrics.preferredHeight - metrics.predictionBarHeight
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    public func applyCurrentPreferences() {
        predictionPlacement = KeyboardPreferences.predictionPlacement
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
        let colour: ColourOption
        if engine.sharedPreferencesAvailable {
            KeyboardPreferences.persistMigratedColourOptionIfNeeded()
            colour = KeyboardPreferences.colourOption
        } else {
            colour = .system
        }
        appearance = KeyboardAppearance.resolved(
            colour: colour,
            style: traitCollection.userInterfaceStyle
        )
        backgroundColor = appearance.backgroundColor
    }

    private func reloadKeys() {
        contentDirty = true
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        onPreferredHeightChange?()
    }

    /// The consent step and the short Fix hints need a taller suggestion bar.
    /// Keys move down with that bar; they are not covered.
    private func metricsForCurrentNotice(_ metrics: LayoutMetrics) -> LayoutMetrics {
        var metrics = metrics
        switch engine.fixNotice {
        case .consent:
            metrics.predictionBarHeight = max(metrics.predictionBarHeight, 112)
        case .fullAccess, .offline, .secureField, .unavailable:
            metrics.predictionBarHeight = max(metrics.predictionBarHeight, 72)
        case .none:
            break
        }
        return metrics
    }

    private func refreshPredictions() {
        // On iPad a long word can widen the column and move the keys. On
        // iPhone only the bar's cells change width. Either way, lay out again.
        setNeedsLayout()
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

    private func predictionArrangement(
        layout: KeyboardLayout,
        metrics: LayoutMetrics,
        usesColumn: Bool
    ) -> PredictionColumnArrangement {
        let showsColumn = engine.showsPredictions && usesColumn
        let texts = showsColumn ? engine.predictions().map(\.displayText) : []
        return PredictionColumnGeometry.arrangement(
            texts: texts,
            keyboardSize: bounds.size,
            metrics: metrics,
            layout: layout,
            showsPredictions: showsColumn
        )
    }

    private func layoutPredictionBar(layout: KeyboardLayout, metrics: LayoutMetrics, usesColumn: Bool) {
        let showsBar = engine.showsPredictions && !usesColumn
        predictionBar.isHidden = !showsBar
        guard showsBar else { return }
        let frame = CGRect(
            x: metrics.sideInset,
            y: 4,
            width: max(0, bounds.width - metrics.sideInset * 2),
            height: max(0, metrics.predictionBarHeight - 8)
        )
        // An iPad board on top keeps its side-column Fix size and type size.
        // iPhone and the compact fallback board keep the original bar.
        let isPadTopBar = PredictionColumnGeometry.usesVerticalColumn(layout.layoutClass)
        let arrangement = PredictionBarGeometry.arrangement(
            texts: engine.predictions().map(\.displayText),
            barWidth: frame.width,
            barHeight: frame.height,
            preferredFontSize: isPadTopBar
                ? PredictionColumnGeometry.preferredFontSize(metrics)
                : metrics.modifierFontSize + 2,
            minimumReadableFontSize: PredictionColumnGeometry.minimumReadableFontSize(metrics),
            fixWidth: isPadTopBar
                ? PredictionColumnGeometry.topBarFixWidth(boundsWidth: bounds.width, metrics: metrics, layout: layout)
                : nil
        )
        predictionBar.update(
            predictions: engine.predictions(),
            arrangement: arrangement,
            fixStatus: engine.fixStatus,
            notice: engine.fixNotice,
            appearance: appearance
        )
        predictionBar.frame = frame
        bringSubviewToFront(predictionBar)
    }

    private func layoutPredictionColumn(arrangement: PredictionColumnArrangement, metrics: LayoutMetrics) {
        predictionColumn.isHidden = arrangement.isHidden
        guard !arrangement.isHidden else { return }
        predictionColumn.update(
            predictions: engine.predictions(),
            arrangement: arrangement,
            fixStatus: engine.fixStatus,
            appearance: appearance,
            metrics: metrics
        )
        predictionColumn.frame = arrangement.columnFrame
        bringSubviewToFront(predictionColumn)
    }

    private func layoutKeys(
        layout: KeyboardLayout,
        metrics: LayoutMetrics,
        arrangement: PredictionColumnArrangement,
        usesColumn: Bool
    ) {
        // The width math lives in KeyboardGeometry so it can be unit tested
        // (a compact iPhone board must never overflow); the view just positions
        // its buttons from the frames it returns.
        let showsBar = engine.showsPredictions && !usesColumn
        let rows = KeyboardGeometry.frames(
            for: layout,
            metrics: metrics,
            boundsWidth: bounds.width,
            reservedLeading: PredictionColumnGeometry.reservedLeading(for: arrangement, metrics: metrics),
            reservedTop: showsBar ? metrics.predictionBarHeight : 0
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
