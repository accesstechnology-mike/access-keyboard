import UIKit

/// Horizontal prediction bar across the top of the iPhone keyboard.
///
/// Fix stays on the left, as it did before the column experiment. Suggestion
/// cells are not equal width: each one is as wide as its word, so a long
/// suggestion is shown in full.
final class PredictionBarView: UIView {
    var onSelect: ((Prediction) -> Void)?
    var onFix: (() -> Void)?
    var onAllowConsent: (() -> Void)?
    var onDeclineConsent: (() -> Void)?

    private static let slotCount = PredictionProvider.maxSuggestions

    private var predictions: [Prediction] = []
    private var arrangement = PredictionBarArrangement(
        fixFrame: .zero,
        cellFrames: [],
        visibleTexts: [],
        fontSize: 17
    )
    private let fixButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let buttons = (0..<PredictionBarView.slotCount).map { _ in UIButton(type: .system) }
    private let separators = (0..<PredictionBarView.slotCount).map { _ in UIView() }
    private let noticeLabel = UILabel()
    private let allowButton = UIButton(type: .system)
    private let declineButton = UIButton(type: .system)
    private var notice: FixNotice = .none

    override init(frame: CGRect) {
        super.init(frame: frame)
        fixButton.addTarget(self, action: #selector(tapFix), for: .touchUpInside)
        fixButton.isAccessibilityElement = true
        fixButton.clipsToBounds = true
        addSubview(fixButton)
        spinner.hidesWhenStopped = true
        spinner.isUserInteractionEnabled = false
        addSubview(spinner)
        buttons.enumerated().forEach { index, button in
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.7
            button.titleLabel?.allowsDefaultTighteningForTruncation = true
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.baselineAdjustment = .alignCenters
            button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            button.tag = index
            button.isAccessibilityElement = true
            addSubview(button)
        }
        separators.forEach { addSubview($0) }
        noticeLabel.numberOfLines = 3
        noticeLabel.adjustsFontSizeToFitWidth = true
        noticeLabel.minimumScaleFactor = 0.75
        noticeLabel.isHidden = true
        noticeLabel.isAccessibilityElement = true
        addSubview(noticeLabel)
        configureChoice(allowButton, title: "Allow", action: #selector(tapAllow))
        configureChoice(declineButton, title: "Not now", action: #selector(tapDecline))
        allowButton.accessibilityLabel = "Allow Fix to send this field to OpenAI"
        declineButton.accessibilityLabel = "Not now"
    }

    private func configureChoice(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
        button.isHidden = true
        button.addTarget(self, action: action, for: .touchUpInside)
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        predictions: [Prediction],
        arrangement: PredictionBarArrangement,
        fixStatus: FixStatus,
        notice: FixNotice = .none,
        appearance: KeyboardAppearance
    ) {
        self.predictions = predictions
        self.arrangement = arrangement
        self.notice = notice
        let running = fixStatus == .running
        let showingNotice = notice != .none
        fixButton.setTitle(running ? "" : "Fix", for: .normal)
        fixButton.isEnabled = !running
        fixButton.backgroundColor = appearance.primaryFill
        fixButton.setTitleColor(appearance.primaryTextColor, for: .normal)
        fixButton.titleLabel?.font = .systemFont(ofSize: arrangement.fontSize, weight: .semibold)
        if showingNotice && notice != .consent {
            fixButton.accessibilityLabel = notice.message
        } else if running {
            fixButton.accessibilityLabel = "Fix in progress"
        } else if fixStatus == .failed {
            fixButton.accessibilityLabel = "Fix failed, try again"
        } else {
            fixButton.accessibilityLabel = "Fix typing errors"
        }
        fixButton.accessibilityTraits = .button
        if running {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        spinner.color = appearance.primaryTextColor

        noticeLabel.isHidden = !showingNotice
        noticeLabel.text = notice.message
        noticeLabel.textColor = appearance.textColor
        noticeLabel.font = .systemFont(ofSize: min(arrangement.fontSize, 15))
        noticeLabel.accessibilityLabel = showingNotice ? notice.message : nil
        let choosing = notice == .consent
        allowButton.isHidden = !choosing
        declineButton.isHidden = !choosing
        allowButton.backgroundColor = appearance.primaryFill
        allowButton.setTitleColor(appearance.primaryTextColor, for: .normal)
        declineButton.backgroundColor = appearance.modifierFill
        declineButton.setTitleColor(appearance.modifierTextColor, for: .normal)

        // While a Fix hint or the consent step shows, it replaces the words.
        let visible = showingNotice ? [] : Array(predictions.prefix(arrangement.visibleTexts.count))
        for (index, button) in buttons.enumerated() {
            if visible.indices.contains(index) {
                let item = visible[index]
                button.isHidden = false
                button.setTitle(item.displayText, for: .normal)
                button.isEnabled = !running
                button.accessibilityLabel = item.isVerbatim
                    ? "Use as typed, \(item.insertion)"
                    : "Predicted word, \(item.insertion)"
                button.accessibilityTraits = .button
                button.titleLabel?.font = PredictionColumnGeometry.measurementFont(ofSize: arrangement.fontSize)
                button.setTitleColor(appearance.textColor, for: .normal)
                button.alpha = running ? 0.45 : 1
            } else {
                button.isHidden = true
                button.setTitle(nil, for: .normal)
                button.isEnabled = false
                button.accessibilityLabel = nil
            }
        }
        let line = appearance.secondaryTextColor.withAlphaComponent(0.45)
        for separator in separators {
            separator.backgroundColor = line
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        if notice != .none {
            layoutNotice(height: height)
            return
        }
        fixButton.frame = arrangement.fixFrame
        fixButton.layer.cornerRadius = min(8, max(0, arrangement.fixFrame.height) / 4)
        spinner.center = fixButton.center

        let separatorWidth: CGFloat = 1 / max(traitCollection.displayScale, 1)
        for (index, button) in buttons.enumerated() {
            if arrangement.cellFrames.indices.contains(index) {
                button.frame = arrangement.cellFrames[index]
            }
        }
        let count = arrangement.cellFrames.count
        for (index, separator) in separators.enumerated() {
            separator.isHidden = count <= index
            guard count > index else { continue }
            let x = index == 0
                ? arrangement.fixFrame.maxX
                : arrangement.cellFrames[index - 1].maxX
            separator.frame = CGRect(x: x, y: height * 0.22, width: separatorWidth, height: height * 0.56)
        }
    }

    /// Fix keeps its width and stays at most 44pt tall, centred; the hint or
    /// the consent text and its Allow / Not now buttons take the rest.
    private func layoutNotice(height: CGFloat) {
        separators.forEach { $0.isHidden = true }
        let fixWidth = arrangement.fixFrame.width > 0 ? arrangement.fixFrame.width : min(92, max(72, bounds.width * 0.14))
        let fixHeight = max(0, min(44, height - 4))
        fixButton.frame = CGRect(x: arrangement.fixFrame.minX, y: (height - fixHeight) / 2, width: fixWidth, height: fixHeight)
        fixButton.layer.cornerRadius = min(8, fixHeight / 4)
        spinner.center = fixButton.center

        let restMinX = fixButton.frame.maxX + 8
        let restWidth = max(0, bounds.width - restMinX)
        if notice == .consent {
            let buttonHeight: CGFloat = 44
            let buttonGap: CGFloat = 8
            let buttonsY = height - buttonHeight - 4
            let buttonWidth = min(128, max(76, (restWidth - buttonGap) / 2))
            allowButton.frame = CGRect(x: restMinX, y: buttonsY, width: buttonWidth, height: buttonHeight)
            declineButton.frame = CGRect(
                x: restMinX + buttonWidth + buttonGap,
                y: buttonsY,
                width: buttonWidth,
                height: buttonHeight
            )
            noticeLabel.frame = CGRect(x: restMinX, y: 4, width: restWidth, height: max(0, buttonsY - 6))
        } else {
            noticeLabel.frame = CGRect(x: restMinX, y: 4, width: restWidth, height: max(0, height - 8))
        }
    }

    @objc private func tap(_ sender: UIButton) {
        guard notice == .none else { return }
        let visible = Array(predictions.prefix(arrangement.visibleTexts.count))
        guard visible.indices.contains(sender.tag) else { return }
        onSelect?(visible[sender.tag])
    }

    @objc private func tapFix() {
        onFix?()
    }

    @objc private func tapAllow() {
        onAllowConsent?()
    }

    @objc private func tapDecline() {
        onDeclineConsent?()
    }
}
