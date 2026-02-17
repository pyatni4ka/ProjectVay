import XCTest
@testable import InventoryCore

final class BodyMetricsTimeRangeTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testLastMonthsFiltersPointsWithinInterval() {
        let now = makeDate(year: 2026, month: 2, day: 15)
        let range = BodyMetricsTimeRange(mode: .lastMonths, months: 2, year: 2026, now: now, calendar: calendar)

        let points = [
            HealthKitService.SamplePoint(date: makeDate(year: 2025, month: 11, day: 20), value: 75),
            HealthKitService.SamplePoint(date: makeDate(year: 2025, month: 12, day: 15), value: 74.5),
            HealthKitService.SamplePoint(date: makeDate(year: 2026, month: 1, day: 10), value: 74.2),
            HealthKitService.SamplePoint(date: makeDate(year: 2026, month: 2, day: 14), value: 74)
        ]

        let filtered = range.filter(points: points, now: now, calendar: calendar)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.map(\.value), [74.2, 74])
    }

    func testYearModeUsesCalendarYearBounds() {
        let now = makeDate(year: 2026, month: 8, day: 1)
        let range = BodyMetricsTimeRange(mode: .year, months: 12, year: 2025, now: now, calendar: calendar)

        let points = [
            HealthKitService.SamplePoint(date: makeDate(year: 2024, month: 12, day: 31), value: 80),
            HealthKitService.SamplePoint(date: makeDate(year: 2025, month: 1, day: 1), value: 79.8),
            HealthKitService.SamplePoint(date: makeDate(year: 2025, month: 12, day: 31), value: 78.5),
            HealthKitService.SamplePoint(date: makeDate(year: 2026, month: 1, day: 1), value: 78.3)
        ]

        let filtered = range.filter(points: points, now: now, calendar: calendar)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.map(\.value), [79.8, 78.5])
    }

    func testSinceYearStartsFromJanuaryFirst() {
        let now = makeDate(year: 2026, month: 2, day: 15)
        let range = BodyMetricsTimeRange(mode: .sinceYear, months: 12, year: 2025, now: now, calendar: calendar)

        let points = [
            HealthKitService.SamplePoint(date: makeDate(year: 2024, month: 6, day: 1), value: 82),
            HealthKitService.SamplePoint(date: makeDate(year: 2025, month: 1, day: 1), value: 80),
            HealthKitService.SamplePoint(date: makeDate(year: 2025, month: 9, day: 1), value: 78),
            HealthKitService.SamplePoint(date: makeDate(year: 2026, month: 2, day: 1), value: 77)
        ]

        let filtered = range.filter(points: points, now: now, calendar: calendar)

        XCTAssertEqual(filtered.count, 3)
        XCTAssertEqual(filtered.map(\.value), [80, 78, 77])
    }

    func testLabels() {
        XCTAssertEqual(
            BodyMetricsTimeRange(mode: .lastMonths, months: 12, year: 2026).compactDeltaLabel,
            "за 12 мес"
        )
        XCTAssertEqual(
            BodyMetricsTimeRange(mode: .year, months: 12, year: 2026).compactDeltaLabel,
            "за 2026 год"
        )
        XCTAssertEqual(
            BodyMetricsTimeRange(mode: .sinceYear, months: 12, year: 2025).compactDeltaLabel,
            "с 2025"
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
