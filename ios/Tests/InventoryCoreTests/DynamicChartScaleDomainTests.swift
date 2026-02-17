import XCTest
@testable import InventoryCore

final class DynamicChartScaleDomainTests: XCTestCase {
    func testSmallSeriesWithoutOutliersKeepsAllPointsInDomain() {
        let values: [Double] = [70, 71, 71.5, 72]

        let scale = DynamicChartScaleDomain.resolve(values: values, metric: .weightKg)

        XCTAssertNotNil(scale)
        XCTAssertEqual(scale?.step, 0.5)
        XCTAssertFalse(scale?.hasLowerOutliers ?? true)
        XCTAssertFalse(scale?.hasUpperOutliers ?? true)
        XCTAssertTrue(scale?.domain.contains(70) ?? false)
        XCTAssertTrue(scale?.domain.contains(72) ?? false)
    }

    func testSingleHighOutlierDoesNotStretchRobustDomain() {
        let values: [Double] = [69.8, 70, 70.1, 70.2, 70.4, 70.5, 70.7, 70.8, 71, 71.2, 110]

        let scale = DynamicChartScaleDomain.resolve(values: values, metric: .weightKg)

        XCTAssertNotNil(scale)
        XCTAssertTrue(scale?.hasUpperOutliers ?? false)
        XCTAssertLessThan(scale?.upper ?? .infinity, 110)
        XCTAssertEqual(scale?.displayValue(for: 110), scale?.upper)
    }

    func testConstantSeriesGetsNonZeroMinimumWindow() {
        let values = Array(repeating: 75.0, count: 6)

        let scale = DynamicChartScaleDomain.resolve(values: values, metric: .weightKg)

        XCTAssertNotNil(scale)
        XCTAssertGreaterThanOrEqual((scale?.upper ?? 0) - (scale?.lower ?? 0), 4)
        XCTAssertGreaterThanOrEqual(scale?.lower ?? -1, 0)
    }

    func testBoundaryBetweenFourAndFivePointsSwitchesToPercentileMode() {
        let firstFour: [Double] = [70, 70.5, 71, 71.5]
        let fiveWithOutlier = firstFour + [105]

        let scaleFour = DynamicChartScaleDomain.resolve(values: firstFour, metric: .weightKg)
        let scaleFive = DynamicChartScaleDomain.resolve(values: fiveWithOutlier, metric: .weightKg)

        XCTAssertNotNil(scaleFour)
        XCTAssertNotNil(scaleFive)
        XCTAssertFalse(scaleFour?.hasUpperOutliers ?? true)
        XCTAssertTrue(scaleFive?.hasUpperOutliers ?? false)
        XCTAssertLessThan(scaleFive?.upper ?? .infinity, 105)
    }
}
