import XCTest
import UIKit
@testable import AccessKeyboardCore

final class PredictionColumnTests: XCTestCase {
    func testShortPredictionsFillTheLeftColumnAndKeepFixAtTheBottom() {
        let board = qwertyPad()
        let metrics = padMetrics(width: 834, height: 1194)
        let texts = ["the", "to", "and", "of", "a", "in"]
        let plan = PredictionColumnGeometry.arrangement(
            texts: texts,
            keyboardSize: CGSize(width: 390, height: metrics.preferredHeight),
            metrics: metrics,
            layout: board,
            showsPredictions: true
        )

        XCTAssertEqual(plan.visibleTexts, texts, "six short predictions should all stay visible")
        XCTAssertEqual(plan.columnFrame.minX, metrics.sideInset, accuracy: 0.5)
        XCTAssertGreaterThan(plan.fixFrame.minY, plan.predictionFrames.last?.maxY ?? 0)
        XCTAssertEqual(plan.fixFrame.maxX, plan.columnFrame.maxX, accuracy: 0.5)
        XCTAssertEqual(plan.fixFrame.minX, plan.columnFrame.minX, accuracy: 0.5)
        XCTAssertEqual(plan.fixFrame.height, metrics.keyHeight, accuracy: 0.5, "Fix lines up with the bottom key row")
        assertTextsFit(plan, metrics: metrics, minimumFont: plan.minimumReadableFontSize)
    }

    func testLongWordsStayOnOneLineByShrinking() {
        let board = qwertyPad()
        let metrics = padMetrics(width: 1180, height: 820)
        let words = ["Communications", "Responsibilities", "Internationally"]
        for word in words {
            let plan = PredictionColumnGeometry.arrangement(
                texts: [word, "the", "to", "and", "a", "of"],
                keyboardSize: CGSize(width: 1180, height: metrics.preferredHeight),
                metrics: metrics,
                layout: board,
                showsPredictions: true
            )

            XCTAssertEqual(plan.visibleTexts.first, word)
            XCTAssertFalse(plan.visibleTexts.contains { $0.contains("…") || $0.hasSuffix("...") })
            let inner = plan.predictionFrames[0].width - plan.textInsets.left - plan.textInsets.right
            let width = PredictionColumnGeometry.singleLineWidth(word, fontSize: plan.predictionFontSizes[0])
            XCTAssertLessThanOrEqual(width, inner + 1, "\(word) should fit on one line without an ellipsis")
            XCTAssertLessThanOrEqual(
                plan.predictionFontSizes[0],
                plan.predictionFontSizes[1] + 0.01,
                "\(word) should not be larger than a short neighbour"
            )
            XCTAssertLessThanOrEqual(
                plan.predictionFrames[0].height,
                plan.predictionFrames[1].height + 1,
                "\(word) should not take a taller wrapped row"
            )
            assertTextsFit(plan, metrics: metrics, minimumFont: plan.minimumReadableFontSize)

            let reserved = PredictionColumnGeometry.reservedLeading(for: plan, metrics: metrics)
            let rows = KeyboardGeometry.frames(
                for: board,
                metrics: metrics,
                boundsWidth: 1180,
                reservedLeading: reserved
            )
            let leftmost = rows.flatMap { $0 }.map(\.minX).min() ?? 0
            XCTAssertGreaterThanOrEqual(leftmost, plan.columnFrame.maxX + metrics.keySpacing - 0.5)
        }
    }

    func testExtremeWordStaysOneLineAndStopsAtTheReadableFloor() {
        let board = qwertyPad()
        let metrics = padMetrics(width: 1180, height: 820)
        let word = "supercalifragilisticexpialidocious"
        let plan = PredictionColumnGeometry.arrangement(
            texts: [word, "the", "to", "and", "a", "of"],
            keyboardSize: CGSize(width: 1180, height: metrics.preferredHeight),
            metrics: metrics,
            layout: board,
            showsPredictions: true
        )

        XCTAssertEqual(plan.visibleTexts.first, word, "the label ellipsizes; the word itself is kept")
        XCTAssertEqual(plan.predictionFontSizes[0], plan.minimumReadableFontSize, accuracy: 0.6)
        let inner = plan.predictionFrames[0].width - plan.textInsets.left - plan.textInsets.right
        let width = PredictionColumnGeometry.singleLineWidth(word, fontSize: plan.predictionFontSizes[0])
        XCTAssertGreaterThan(width, inner, "this word is the ellipsis case, not a wrap")
        XCTAssertLessThanOrEqual(
            plan.predictionFrames[0].height,
            plan.predictionFrames[1].height + 1
        )
        assertTextsFit(plan, metrics: metrics, minimumFont: plan.minimumReadableFontSize)
    }

    func testHiddenPredictionsLeaveTheFullWidthForKeys() {
        let board = qwertyPad()
        let metrics = padMetrics(width: 834, height: 1194)
        let plan = PredictionColumnGeometry.arrangement(
            texts: ["the"],
            keyboardSize: CGSize(width: 390, height: metrics.preferredHeight),
            metrics: metrics,
            layout: board,
            showsPredictions: false
        )
        XCTAssertTrue(plan.isHidden)
        XCTAssertEqual(PredictionColumnGeometry.reservedLeading(for: plan, metrics: metrics), 0)
        XCTAssertTrue(plan.fixFrame.isEmpty)
    }

    func testLandscapeColumnIsModestlyNarrowerThanTheFirstVerticalLayout() {
        // Point widths of iPad portrait and landscape boards, including
        // iPad Air 11-inch landscape (1180).
        let widths: [CGFloat] = [744, 820, 1024, 1133, 1180, 1366]
        for width in widths {
            let metrics = padMetrics(width: width, height: 820)
            let maximum = PredictionColumnGeometry.maximumColumnWidth(
                boundsWidth: width,
                metrics: metrics,
                layout: qwertyPad()
            )
            let standard = PredictionColumnGeometry.standardColumnWidth(
                boundsWidth: width,
                maximum: maximum
            )
            let previous = (width * 0.19).rounded()
            let reduction = (previous - standard) / previous
            XCTAssertEqual(
                standard,
                (width * PredictionColumnGeometry.standardWidthFraction).rounded(),
                "width \(width) should follow the resting fraction"
            )
            XCTAssertGreaterThan(reduction, 0.15, "width \(width) reduced by \(reduction)")
            XCTAssertLessThan(reduction, 0.25, "width \(width) reduced by \(reduction)")
        }
    }

    func testColumnIsIPadOnly() {
        XCTAssertFalse(PredictionColumnGeometry.usesVerticalColumn(.compact))
        XCTAssertTrue(PredictionColumnGeometry.usesVerticalColumn(.iPad))
        XCTAssertTrue(PredictionColumnGeometry.usesVerticalColumn(.iPadPro))
    }

    func testColumnIsOnTheLeftForPadLayoutsToo() {
        let cases: [(LayoutClass, CGSize)] = [
            (.iPad, CGSize(width: 820, height: 1180)),
            (.iPad, CGSize(width: 1180, height: 820)),
            (.iPadPro, CGSize(width: 1024, height: 1366)),
            (.iPadPro, CGSize(width: 1366, height: 1024))
        ]
        for (layoutClass, bounds) in cases {
            let board = LayoutFactory.layout(
                mode: .alphabetic,
                shift: .off,
                layoutClass: layoutClass,
                needsInputModeSwitchKey: true,
                returnKeyType: .default,
                letterLayout: .qwerty
            )
            let metrics = LayoutMetrics.metrics(
                for: layoutClass,
                bounds: bounds,
                safeBottom: 20,
                rowCount: board.rows.count
            )
            let plan = PredictionColumnGeometry.arrangement(
                texts: ["communication", "the", "and", "to", "of", "a"],
                keyboardSize: CGSize(width: bounds.width, height: metrics.preferredHeight),
                metrics: metrics,
                layout: board,
                showsPredictions: true
            )
            XCTAssertEqual(plan.columnFrame.minX, metrics.sideInset, accuracy: 0.5, "\(layoutClass)")
            XCTAssertGreaterThan(plan.fixFrame.minY, plan.columnFrame.minY, "\(layoutClass)")
            XCTAssertEqual(plan.visibleTexts.first, "communication", "\(layoutClass)")
            assertTextsFit(plan, metrics: metrics, minimumFont: plan.minimumReadableFontSize)
        }
    }

    private func assertTextsFit(
        _ plan: PredictionColumnArrangement,
        metrics: LayoutMetrics,
        minimumFont: CGFloat
    ) {
        XCTAssertEqual(plan.visibleTexts.count, plan.predictionFrames.count)
        for (index, text) in plan.visibleTexts.enumerated() {
            let frame = plan.predictionFrames[index]
            let fontSize = plan.predictionFontSizes[index]
            XCTAssertGreaterThanOrEqual(fontSize, minimumFont - 0.01, text)
            let innerWidth = frame.width - plan.textInsets.left - plan.textInsets.right
            let innerHeight = frame.height - plan.textInsets.top - plan.textInsets.bottom
            let lineWidth = PredictionColumnGeometry.singleLineWidth(text, fontSize: fontSize)
            let font = PredictionColumnGeometry.measurementFont(ofSize: fontSize)
            let measuredHeight = PredictionColumnGeometry.boundingSize(
                of: text,
                font: font,
                width: 10_000
            ).height
            XCTAssertLessThanOrEqual(measuredHeight, innerHeight + 1, "\(text) is taller than its row")
            if lineWidth > innerWidth + 1 {
                XCTAssertLessThanOrEqual(
                    fontSize,
                    minimumFont + 0.6,
                    "\(text) should be at the readable floor before an ellipsis"
                )
            }
        }
    }

    private func qwertyPad() -> KeyboardLayout {
        LayoutFactory.layout(
            mode: .alphabetic,
            shift: .off,
            layoutClass: .iPad,
            needsInputModeSwitchKey: true,
            returnKeyType: .default,
            letterLayout: .qwerty
        )
    }

    private func padMetrics(width: CGFloat, height: CGFloat) -> LayoutMetrics {
        LayoutMetrics.metrics(
            for: .iPad,
            bounds: CGSize(width: width, height: height),
            safeBottom: 0,
            rowCount: 4
        )
    }
}
