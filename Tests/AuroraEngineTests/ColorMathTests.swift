import AuroraEngine
import XCTest

final class ColorMathTests: XCTestCase {
    func testHSVRoundTrip() {
        let rgb = RGBColor(r: 0.2, g: 0.5, b: 0.9)
        let hsv = ColorMath.hsv(from: rgb)
        let back = ColorMath.rgb(from: hsv)
        XCTAssertEqual(back.r, rgb.r, accuracy: 0.02)
        XCTAssertEqual(back.g, rgb.g, accuracy: 0.02)
        XCTAssertEqual(back.b, rgb.b, accuracy: 0.02)
    }

    func testRGBWExtractsWhite() {
        let rgb = RGBColor(r: 0.8, g: 0.6, b: 0.6)
        let rgbw = ColorMath.rgbw(from: rgb)
        XCTAssertEqual(rgbw.w, 0.6, accuracy: 0.001)
        XCTAssertEqual(rgbw.r, 0.2, accuracy: 0.001)
    }
}
