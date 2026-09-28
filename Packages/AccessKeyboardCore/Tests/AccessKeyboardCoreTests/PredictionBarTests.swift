import XCTest
import UIKit
@testable import AccessKeyboardCore

final class PredictionBarTests: XCTestCase {
    func testShortWordsStayVisibleAndFixStaysOnTheLeft() {
        let metrics = compactMetrics()
        let texts = ["the", "to", "and", "of", "a", "in"]
        let plan = bar(texts: texts, metrics: metrics, width: 390)

        XCTAssertEqual(plan.visibleTexts, texts)
        XCTAssertEqual(plan.fixFrame.minX, 0, accuracy: 0.5)
        XCTAssertLessThan(plan.fixFrame.maxX, plan.cellFrames[0].minX + 0.5)
        XCTAssertEqual(plan.cellFrames.count, texts.count)
        assertCellsFit(plan)
    }

    func testLongWordGetsAWiderCellAndIsNotTruncated() {
        let metrics = compactMetrics()
        let long = "extraordinary"
        let texts = [long, "the", "to", "and", "a", "of"]
        let plan = bar(texts: texts, metrics: metrics, width: 390)

        XCTAssertEqual(plan.visibleTexts.first, long)
        XCTAssertFalse(plan.visibleTexts.contains { $0.contains("…") })
        assertCellsFit(plan)
        XCTAssertGreaterThan(plan.cellFrames[0].width, plan.cellFrames[1].width + 4)
        let sizes = Set(plan.visibleTexts.map { _ in plan.fontSize })
        XCTAssertEqual(sizes.count, 1, "every visible word uses the same type size")
    }

    func testExtremeWordsDropLaterSuggestionsInsteadOfTruncating() {
        let metrics = compactMetrics()
        let word = "supercalifragilisticexpialidocious"
        let texts = Array(repeating: word, count: 6)
        let plan = bar(texts: texts, metrics: metrics, width: 320)

        XCTAssertFalse(plan.visibleTexts.isEmpty)
        XCTAssertLessThan(plan.visibleTexts.count, texts.count)
        XCTAssertTrue(plan.visibleTexts.allSatisfy { $0 == word })
        assertCellsFit(plan)
    }

    private func assertCellsFit(_ plan: PredictionBarArrangement) {
        var cursor = plan.fixFrame.maxX
        for (index, text) in plan.visibleTexts.enumerated() {
            let frame = plan.cellFrames[index]
            XCTAssertEqual(frame.minX, cursor, accuracy: 0.5, text)
            XCTAssertGreaterThan(frame.width, 0)
            let needed = PredictionBarGeometry.textWidth(text, fontSize: plan.fontSize)
                + PredictionBarGeometry.horizontalInset * 2
            XCTAssertLessThanOrEqual(needed, frame.width + 1, "\(text) does not fit its cell")
            cursor = frame.maxX
        }
    }

    private func bar(texts: [String], metrics: LayoutMetrics, width: CGFloat) -> PredictionBarArrangement {
        let barWidth = width - metrics.sideInset * 2
        return PredictionBarGeometry.arrangement(
            texts: texts,
            barWidth: barWidth,
            barHeight: metrics.predictionBarHeight - 8,
            preferredFontSize: metrics.modifierFontSize + 2,
            minimumReadableFontSize: PredictionColumnGeometry.minimumReadableFontSize(metrics)
        )
    }

    private func compactMetrics() -> LayoutMetrics {
        LayoutMetrics.metrics(
            for: .compact,
            bounds: CGSize(width: 390, height: 320),
            safeBottom: 0,
            rowCount: 4
        )
    }
}
