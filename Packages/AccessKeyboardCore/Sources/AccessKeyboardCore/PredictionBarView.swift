import UIKit

final class PredictionBarView: UIView {
    var onSelect: ((Prediction) -> Void)?
    var onFix: (() -> Void)?
    var onAllowConsent: (() -> Void)?
    var onDeclineConsent: (() -> Void)?

    /// Number of prediction slots. Matches `PredictionProvider.maxSuggestions`
    /// so every returned suggestion has a slot to land in.
    private static let slotCount = PredictionProvider.maxSuggestions

    private var predictions: [Prediction] = []
    private let fixButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    // One button per prediction slot, plus one separator per slot: separators[0]
    // divides Fix from the first slot and the rest sit between adjacent slots.
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
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            button.tag = index
            button.isAccessibilityElement = true
            addSubview(button)
        }
        separators.forEach { separator in
            addSubview(separator)
        }
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
        fixStatus: FixStatus,
        notice: FixNotice,
        appearance: KeyboardAppearance,
        fontSize: CGFloat
    ) {
        self.predictions = predictions
        self.notice = notice
        let running = fixStatus == .running
        let showingNotice = notice != .none
        fixButton.setTitle(running ? "" : "Fix", for: .normal)
        fixButton.isEnabled = !running
        fixButton.backgroundColor = appearance.primaryFill
        fixButton.setTitleColor(appearance.primaryTextColor, for: .normal)
        fixButton.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .semibold)
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
        noticeLabel.font = .systemFont(ofSize: min(fontSize, 15))
        noticeLabel.accessibilityLabel = showingNotice ? notice.message : nil
        let choosing = notice == .consent
        allowButton.isHidden = !choosing
        declineButton.isHidden = !choosing
        allowButton.backgroundColor = appearance.primaryFill
        allowButton.setTitleColor(appearance.primaryTextColor, for: .normal)
        declineButton.backgroundColor = appearance.modifierFill
        declineButton.setTitleColor(appearance.modifierTextColor, for: .normal)

        for (index, button) in buttons.enumerated() {
            if showingNotice {
                button.isHidden = true
                button.isEnabled = false
                button.accessibilityLabel = nil
                continue
            }
            if predictions.indices.contains(index) {
                let item = predictions[index]
                button.isHidden = false
                button.setTitle(item.displayText, for: .normal)
                button.isEnabled = !running
                button.accessibilityLabel = item.isVerbatim
                    ? "Use as typed, \(item.insertion)"
                    : "Predicted word, \(item.insertion)"
                button.accessibilityTraits = .button
                button.titleLabel?.font = LiteracyFont.uiFont(ofSize: fontSize)
                    ?? .systemFont(ofSize: fontSize, weight: item.isVerbatim ? .regular : .medium)
                button.setTitleColor(appearance.textColor, for: .normal)
                button.alpha = running ? 0.45 : 1
            } else {
                // No suggestion for this slot (e.g. numeric/symbol modes): hide it
                // entirely rather than showing an empty, divided, tappable slot.
                button.isHidden = true
                button.setTitle("", for: .normal)
                button.isEnabled = false
                button.accessibilityLabel = nil
            }
        }
        let count = showingNotice ? 0 : min(predictions.count, buttons.count)
        let line = appearance.secondaryTextColor.withAlphaComponent(0.45)
        for (index, separator) in separators.enumerated() {
            // separators[0] divides Fix from the first slot; the rest sit between
            // adjacent slots. Show a divider only where a filled slot follows.
            separator.backgroundColor = line
            separator.isHidden = count <= index
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fixWidth = min(92, max(72, bounds.width * 0.14))
        let height = bounds.height
        let fixHeight = min(44, height - 4)
        fixButton.frame = CGRect(x: 0, y: (height - fixHeight) / 2, width: fixWidth, height: fixHeight)
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
            return
        }
        if notice != .none {
            noticeLabel.frame = CGRect(x: restMinX, y: 4, width: restWidth, height: height - 8)
            return
        }

        let slotsMinX = fixButton.frame.maxX
        let slotWidth = max(0, bounds.width - slotsMinX) / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: slotsMinX + CGFloat(index) * slotWidth, y: 0, width: slotWidth, height: height)
        }
        let separatorWidth: CGFloat = 1 / max(traitCollection.displayScale, 1)
        separators[0].frame = CGRect(
            x: slotsMinX,
            y: height * 0.22,
            width: separatorWidth,
            height: height * 0.56
        )
        for index in 0..<(buttons.count - 1) {
            let x = slotsMinX + slotWidth * CGFloat(index + 1)
            separators[index + 1].frame = CGRect(x: x, y: height * 0.22, width: separatorWidth, height: height * 0.56)
        }
    }

    @objc private func tap(_ sender: UIButton) {
        guard predictions.indices.contains(sender.tag) else { return }
        onSelect?(predictions[sender.tag])
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
