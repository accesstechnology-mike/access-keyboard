import XCTest
import UIKit
@testable import AccessKeyboardCore

final class PredictionColumnTests: XCTestCase {
    func testShortPredictionsFillTheLeftColumnAndKeepFixAtTheBottom() {
        let board = qwertyCompact()
        let metrics = compactMetrics(width: 390)
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

    func testLongWordIsShownInFullAndGetsATallerRow() {
        let board = qwertyCompact()
        let metrics = compactMetrics(width: 390)
        let word = "internationalization"
        let texts = [word, "the", "to", "and", "a", "of"]
        let plan = PredictionColumnGeometry.arrangement(
            texts: texts,
            keyboardSize: CGSize(width: 390, height: metrics.preferredHeight),
            metrics: metrics,
            layout: board,
            showsPredictions: true
        )

        XCTAssertEqual(plan.visibleTexts.first, word)
        XCTAssertFalse(plan.visibleTexts.contains { $0.contains("…") || $0.hasSuffix("...") })
        let preferred = PredictionColumnGeometry.preferredFontSize(metrics)
        let singleLine = PredictionColumnGeometry.boundingSize(
            of: word,
            font: PredictionColumnGeometry.measurementFont(ofSize: preferred),
            width: 10_000
        ).width
        let inner = plan.predictionFrames[0].width - plan.textInsets.left - plan.textInsets.right
        if singleLine > inner + 1 {
            let shorterType = plan.predictionFontSizes[0] + 0.1 < plan.predictionFontSizes[1]
            let tallerRow = plan.predictionFrames[0].height > plan.predictionFrames[1].height + 0.5
            XCTAssertTrue(
                shorterType || tallerRow,
                "a word that does not fit on one line should use a smaller size or a taller row"
            )
        }
        assertTextsFit(plan, metrics: metrics, minimumFont: plan.minimumReadableFontSize)

        let reserved = PredictionColumnGeometry.reservedLeading(for: plan, metrics: metrics)
        let rows = KeyboardGeometry.frames(
            for: board,
            metrics: metrics,
            boundsWidth: 390,
            reservedLeading: reserved
        )
        let leftmost = rows.flatMap { $0 }.map(\.minX).min() ?? 0
        XCTAssertGreaterThanOrEqual(leftmost, plan.columnFrame.maxX + metrics.keySpacing - 0.5)
    }

    func testVeryLongWordsDropRowsInsteadOfTruncating() {
        let board = qwertyCompact()
        let metrics = compactMetrics(width: 320)
        let word = "supercalifragilisticexpialidocious"
        let texts = Array(repeating: word, count: 6)
        // Short on purpose: six wrapped copies cannot fit, so the column must
        // show fewer complete words rather than clip them.
        let plan = PredictionColumnGeometry.arrangement(
            texts: texts,
            keyboardSize: CGSize(width: 320, height: 150),
            metrics: metrics,
            layout: board,
            showsPredictions: true
        )

        XCTAssertFalse(plan.visibleTexts.isEmpty)
        XCTAssertLessThan(plan.visibleTexts.count, texts.count)
        XCTAssertTrue(plan.visibleTexts.allSatisfy { $0 == word })
        assertTextsFit(plan, metrics: metrics, minimumFont: 9)
    }

    func testHiddenPredictionsLeaveTheFullWidthForKeys() {
        let board = qwertyCompact()
        let metrics = compactMetrics(width: 390)
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

    func testColumnIsOnTheLeftForPadLayoutsToo() {
        for layoutClass in [LayoutClass.iPad, .iPadPro] {
            let bounds = layoutClass == .iPad
                ? CGSize(width: 834, height: 1194)
                : CGSize(width: 1024, height: 1366)
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
            let font = PredictionColumnGeometry.measurementFont(ofSize: fontSize)
            let innerWidth = frame.width - plan.textInsets.left - plan.textInsets.right
            let innerHeight = frame.height - plan.textInsets.top - plan.textInsets.bottom
            let needed = PredictionColumnGeometry.boundingSize(of: text, font: font, width: innerWidth)
            XCTAssertLessThanOrEqual(needed.width, innerWidth + 1, "\(text) is wider than its row")
            XCTAssertLessThanOrEqual(needed.height, innerHeight + 1, "\(text) is taller than its row")
        }
    }

    private func qwertyCompact() -> KeyboardLayout {
        LayoutFactory.layout(
            mode: .alphabetic,
            shift: .off,
            layoutClass: .compact,
            needsInputModeSwitchKey: true,
            returnKeyType: .default,
            letterLayout: .qwerty
        )
    }

    private func compactMetrics(width: CGFloat) -> LayoutMetrics {
        LayoutMetrics.metrics(
            for: .compact,
            bounds: CGSize(width: width, height: 320),
            safeBottom: 0,
            rowCount: 4
        )
    }
}
