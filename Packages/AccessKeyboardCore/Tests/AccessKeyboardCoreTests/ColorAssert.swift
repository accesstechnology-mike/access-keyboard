import XCTest
import UIKit

func XCTAssertEqual(_ lhs: UIColor, _ rhs: UIColor, file: StaticString = #filePath, line: UInt = #line) {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    lhs.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    rhs.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    XCTAssertEqual(r1, r2, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(g1, g2, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(b1, b2, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(a1, a2, accuracy: 0.001, file: file, line: line)
}
