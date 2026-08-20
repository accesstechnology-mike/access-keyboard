import XCTest
@testable import AccessKeyboardCore

final class LayoutClassResolverTests: XCTestCase {
    func testReferenceSizeUsesBoundsWhenAvailable() {
        let size = LayoutClassResolver.referenceSize(
            bounds: CGSize(width: 834, height: 280),
            fallback: CGSize(width: 1366, height: 300)
        )
        XCTAssertEqual(size.width, 834)
        XCTAssertEqual(
            LayoutClassResolver.resolve(size: size, idiom: .pad),
            .iPad
        )
    }

    func testReferenceSizeDoesNotUseProWidthFallback() {
        let size = LayoutClassResolver.referenceSize(
            bounds: .zero,
            fallback: CGSize(width: 834, height: 1194)
        )
        XCTAssertEqual(size.width, 834)
        XCTAssertEqual(
            LayoutClassResolver.resolve(size: size, idiom: .pad),
            .iPad
        )
    }

    func testWideLandscapeIsPro() {
        XCTAssertEqual(
            LayoutClassResolver.resolve(size: CGSize(width: 1180, height: 300), idiom: .pad),
            .iPadPro
        )
    }
}
