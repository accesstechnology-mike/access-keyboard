import UIKit

/// Vertical prediction list on the left of the iPad keyboard, with Fix anchored
/// at the bottom of the same column. iPhone uses `PredictionBarView` instead.
final class PredictionColumnView: UIView {
    var onSelect: ((Prediction) -> Void)?
    var onFix: (() -> Void)?

    private var predictions: [Prediction] = []
    private var arrangement = PredictionColumnArrangement(
        columnFrame: .zero,
        predictionFrames: [],
        predictionFontSizes: [],
        visibleTexts: [],
        fixFrame: .zero,
        textInsets: PredictionColumnGeometry.textInsets,
        minimumReadableFontSize: 13
    )
    private let fixButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var cells: [PredictionCell] = []
    private var separators: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isExclusiveTouch = false
        fixButton.addTarget(self, action: #selector(tapFix), for: .touchUpInside)
        fixButton.isAccessibilityElement = true
        fixButton.isExclusiveTouch = false
        fixButton.clipsToBounds = true
        addSubview(fixButton)
        spinner.hidesWhenStopped = true
        spinner.isUserInteractionEnabled = false
        addSubview(spinner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        predictions: [Prediction],
        arrangement: PredictionColumnArrangement,
        fixStatus: FixStatus,
        appearance: KeyboardAppearance,
        metrics: LayoutMetrics
    ) {
        self.predictions = predictions
        self.arrangement = arrangement
        let running = fixStatus == .running
        fixButton.setTitle(running ? "" : "Fix", for: .normal)
        fixButton.isEnabled = !running
        fixButton.backgroundColor = appearance.primaryFill
        fixButton.setTitleColor(appearance.primaryTextColor, for: .normal)
        fixButton.titleLabel?.font = .systemFont(ofSize: metrics.modifierFontSize, weight: .semibold)
        fixButton.accessibilityLabel = running
            ? "Fix in progress"
            : (fixStatus == .failed ? "Fix failed, try again" : "Fix typing errors")
        fixButton.accessibilityTraits = .button
        fixButton.layer.cornerRadius = metrics.cornerRadius
        if running {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        spinner.color = appearance.primaryTextColor

        let visible = Array(predictions.prefix(arrangement.visibleTexts.count))
        ensureCells(count: visible.count)
        for (index, cell) in cells.enumerated() {
            if visible.indices.contains(index) {
                let item = visible[index]
                let fontSize = arrangement.predictionFontSizes.indices.contains(index)
                    ? arrangement.predictionFontSizes[index]
                    : arrangement.minimumReadableFontSize
                cell.isHidden = false
                cell.prediction = item
                cell.apply(
                    text: item.displayText,
                    fontSize: fontSize,
                    minimumFontSize: arrangement.minimumReadableFontSize,
                    insets: arrangement.textInsets,
                    color: appearance.textColor,
                    enabled: !running
                )
                cell.accessibilityLabel = item.isVerbatim
                    ? "Use as typed, \(item.insertion)"
                    : "Predicted word, \(item.insertion)"
            } else {
                cell.isHidden = true
                cell.prediction = nil
                cell.accessibilityLabel = nil
            }
        }
        ensureSeparators(count: max(0, visible.count))
        let line = appearance.secondaryTextColor.withAlphaComponent(0.35)
        for separator in separators {
            separator.backgroundColor = line
            separator.isHidden = visible.isEmpty
        }
        isHidden = arrangement.isHidden
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let origin = arrangement.columnFrame.origin
        for (index, cell) in cells.enumerated() where arrangement.predictionFrames.indices.contains(index) {
            cell.frame = arrangement.predictionFrames[index].offsetBy(dx: -origin.x, dy: -origin.y)
        }
        fixButton.frame = arrangement.fixFrame.offsetBy(dx: -origin.x, dy: -origin.y)
        spinner.center = fixButton.center
        let scale = max(traitCollection.displayScale, 1)
        let thickness = 1 / scale
        for (index, separator) in separators.enumerated() where cells.indices.contains(index) {
            let cell = cells[index]
            separator.frame = CGRect(
                x: arrangement.textInsets.left,
                y: cell.frame.maxY - thickness,
                width: max(0, bounds.width - arrangement.textInsets.left - arrangement.textInsets.right),
                height: thickness
            )
            separator.isHidden = cell.isHidden || index == arrangement.visibleTexts.count - 1
        }
    }

    private func ensureCells(count: Int) {
        while cells.count < count {
            let cell = PredictionCell()
            cell.addTarget(self, action: #selector(tapCell(_:)), for: .touchUpInside)
            addSubview(cell)
            cells.append(cell)
        }
    }

    private func ensureSeparators(count: Int) {
        while separators.count < count {
            let separator = UIView()
            separator.isUserInteractionEnabled = false
            addSubview(separator)
            separators.append(separator)
        }
    }

    @objc private func tapCell(_ sender: PredictionCell) {
        guard let prediction = sender.prediction else { return }
        onSelect?(prediction)
    }

    @objc private func tapFix() {
        onFix?()
    }
}

private final class PredictionCell: UIControl {
    var prediction: Prediction?
    private let label = UILabel()
    private var insets = PredictionColumnGeometry.textInsets

    override init(frame: CGRect) {
        super.init(frame: frame)
        isExclusiveTouch = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.allowsDefaultTighteningForTruncation = true
        label.baselineAdjustment = .alignCenters
        label.textAlignment = .left
        label.isUserInteractionEnabled = false
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        text: String,
        fontSize: CGFloat,
        minimumFontSize: CGFloat,
        insets: UIEdgeInsets,
        color: UIColor,
        enabled: Bool
    ) {
        self.insets = insets
        label.text = text
        label.textColor = color
        label.font = PredictionColumnGeometry.measurementFont(ofSize: fontSize)
        // The geometry already picks a size that fits on one line when it can.
        // This only absorbs measurement slack, and stops at the readable floor
        // so a word that still overflows is ellipsized rather than wrapped.
        label.minimumScaleFactor = fontSize > 0 ? min(1, max(minimumFontSize, 1) / fontSize) : 1
        isEnabled = enabled
        alpha = enabled ? 1 : 0.45
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.inset(by: insets)
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.45 : (isEnabled ? 1 : 0.45) }
    }
}
