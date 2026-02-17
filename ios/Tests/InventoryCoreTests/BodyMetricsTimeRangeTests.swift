import XCTest
@testable import InventoryCore

final class BodyMetricsTimeRangeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 2, day: 17, hour: 12)) ?? Date()
    }

    func testLastMonthsFiltersByRollingWindow() {
        let range = BodyMetricsTimeRange(mode: .lastMonths, months: 12, year: 2026, now: now, calendar: calendar)
        let points = [
            sample(year: 2025, month: 2, day: 16, value: 70),
            sample(year: 2025, month: 2, day: 17, value: 71),
            sample(year: 2026, month: 2, day: 17, value: 72)
        ]

        let filtered = range.filter(points: points, now: now, calendar: calendar)

        XCTAssertEqual(filtered.map(\.value), [71, 72])
    }

    func testYearFiltersSingleCalendarYear() {
        let range = BodyMetricsTimeRange(mode: .year, months: 12, year: 2025, now: now, calendar: calendar)
        let points = [
            sample(year: 2024, month: 12, day: 31, value: 68),
            sample(year: 2025, month: 6, day: 10, value: 69),
            sample(year: 2026, month: 1, day: 1, value: 70)
        ]

        let filtered = range.filter(points: points, now: now, calendar: calendar)

        XCTAssertEqual(filtered.map(\.value), [69])
    }

    func testSinceYearFiltersFromYearStartToNow() {
        let range = BodyMetricsTimeRange(mode: .sinceYear, months: 12, year: 2025, now: now, calendar: calendar)
        let points = [
            sample(year: 2024, month: 12, day: 31, value: 66),
            sample(year: 2025, month: 1, day: 1, value: 67),
            sample(year: 2026, month: 2, day: 17, value: 68)
        ]

        let filtered = range.filter(points: points, now: now, calendar: calendar)

        XCTAssertEqual(filtered.map(\.value), [67, 68])
    }

    func testLabelsForHomeAndBodyAreReadable() {
        let rangeLastMonths = BodyMetricsTimeRange(mode: .lastMonths, months: 9, year: 2026, now: now, calendar: calendar)
        let rangeYear = BodyMetricsTimeRange(mode: .year, months: 12, year: 2025, now: now, calendar: calendar)
        let rangeSinceYear = BodyMetricsTimeRange(mode: .sinceYear, months: 12, year: 2025, now: now, calendar: calendar)

        XCTAssertEqual(rangeLastMonths.fullLabel, "Последние 9 мес.")
        XCTAssertEqual(rangeLastMonths.compactDeltaLabel, "за 9 мес")
        XCTAssertEqual(rangeYear.fullLabel, "За 2025 год")
        XCTAssertEqual(rangeYear.compactDeltaLabel, "за 2025 год")
        XCTAssertEqual(rangeSinceYear.fullLabel, "С 2025 года")
        XCTAssertEqual(rangeSinceYear.compactDeltaLabel, "с 2025")
    }

    func testAvailableYearsIncludesCurrentSelectedAndDataYears() {
        let values = [
            [sample(year: 2024, month: 4, day: 1, value: 70)],
            [sample(year: 2022, month: 8, day: 1, value: 20)]
        ]

        let years = BodyMetricsTimeRange.availableYears(
            from: values,
            selectedYear: 2023,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(years, [2026, 2024, 2023, 2022])
    }

    private func sample(year: Int, month: Int, day: Int, value: Double) -> HealthKitService.SamplePoint {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? now
        return .init(date: date, value: value)
    }
}
