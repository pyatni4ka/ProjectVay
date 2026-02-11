import XCTest
@testable import InventoryCore

final class NotificationSchedulerTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testAdjustedForQuietHoursWithinSameDayWindow() {
        let scheduler = NotificationScheduler(calendar: calendar)
        let date = makeDate(year: 2026, month: 1, day: 10, hour: 2, minute: 15)

        let adjusted = scheduler.adjustedForQuietHours(date, quietStartMinute: 60, quietEndMinute: 360)

        XCTAssertEqual(adjusted, makeDate(year: 2026, month: 1, day: 10, hour: 6, minute: 0))
    }

    func testAdjustedForQuietHoursAcrossMidnightWindow() {
        let scheduler = NotificationScheduler(calendar: calendar)
        let date = makeDate(year: 2026, month: 1, day: 10, hour: 23, minute: 20)

        let adjusted = scheduler.adjustedForQuietHours(date, quietStartMinute: 23 * 60, quietEndMinute: 7 * 60)

        XCTAssertEqual(adjusted, makeDate(year: 2026, month: 1, day: 11, hour: 7, minute: 0))
    }

    func testReminderDatesSkipPast() {
        let scheduler = NotificationScheduler(calendar: calendar)
        let now = makeDate(year: 2026, month: 1, day: 10, hour: 12, minute: 0)
        let expiry = makeDate(year: 2026, month: 1, day: 12, hour: 18, minute: 0)

        let reminders = scheduler.reminderDates(
            expiryDate: expiry,
            alertDays: [5, 1],
            quietStartMinute: 60,
            quietEndMinute: 360,
            now: now
        )

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.daysBefore, 1)
    }

    func testExpiryTodaySchedulesAtNearestAllowedTime() {
        let scheduler = NotificationScheduler(calendar: calendar)
        let now = makeDate(year: 2026, month: 1, day: 10, hour: 2, minute: 10)
        let expiry = makeDate(year: 2026, month: 1, day: 10, hour: 20, minute: 0)

        let reminders = scheduler.reminderDates(
            expiryDate: expiry,
            alertDays: [1],
            quietStartMinute: 60,
            quietEndMinute: 360,
            now: now
        )

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.fireDate, makeDate(year: 2026, month: 1, day: 10, hour: 6, minute: 0))
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.calendar = calendar
        return components.date!
    }
}
