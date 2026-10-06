import UIKit

/// Horizontal prediction bar across the top of the iPhone keyboard.
///
/// Fix stays on the left, as it did before the column experiment. Suggestion
/// cells are not equal width: each one is as wide as its word, so a long
/// suggestion is shown in full.
final class PredictionBarView: UIView {
    var onSelect: ((Prediction) -> Void)?
    var onFix: (() -> Void)?

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        predictions: [Prediction],
        arrangement: PredictionBarArrangement,
        fixStatus: FixStatus,
        appearance: KeyboardAppearance
    ) {
        self.predictions = predictions
        self.arrangement = arrangement
        let running = fixStatus == .running
        fixButton.setTitle(running ? "" : "Fix", for: .normal)
        fixButton.isEnabled = !running
        fixButton.backgroundColor = appearance.primaryFill
        fixButton.setTitleColor(appearance.primaryTextColor, for: .normal)
        fixButton.titleLabel?.font = .systemFont(ofSize: arrangement.fontSize, weight: .semibold)
        fixButton.accessibilityLabel = running
            ? "Fix in progress"
            : (fixStatus == .failed ? "Fix failed, try again" : "Fix typing errors")
        fixButton.accessibilityTraits = .button
        if running {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        spinner.color = appearance.primaryTextColor

        let visible = Array(predictions.prefix(arrangement.visibleTexts.count))
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
        fixButton.frame = arrangement.fixFrame
        fixButton.layer.cornerRadius = min(8, max(0, arrangement.fixFrame.height) / 4)
        spinner.center = fixButton.center

        let height = bounds.height
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

    @objc private func tap(_ sender: UIButton) {
        let visible = Array(predictions.prefix(arrangement.visibleTexts.count))
        guard visible.indices.contains(sender.tag) else { return }
        onSelect?(visible[sender.tag])
    }

    @objc private func tapFix() {
        onFix?()
    }
}
