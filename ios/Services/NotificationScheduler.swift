import Foundation

final class NotificationScheduler {
    func reminderDates(
        expiryDate: Date,
        alertDays: [Int],
        quietStart: DateComponents,
        quietEnd: DateComponents
    ) -> [Date] {
        let calendar = Calendar.current

        return alertDays.compactMap { days in
            guard let rawDate = calendar.date(byAdding: .day, value: -days, to: expiryDate) else { return nil }
            return adjustedForQuietHours(rawDate, quietStart: quietStart, quietEnd: quietEnd, calendar: calendar)
        }
    }

    func adjustedForQuietHours(
        _ date: Date,
        quietStart: DateComponents,
        quietEnd: DateComponents,
        calendar: Calendar = .current
    ) -> Date {
        let startHour = quietStart.hour ?? 1
        let endHour = quietEnd.hour ?? 6
        let hour = calendar.component(.hour, from: date)

        let isWithinQuiet: Bool
        if startHour <= endHour {
            isWithinQuiet = (hour >= startHour && hour < endHour)
        } else {
            isWithinQuiet = (hour >= startHour || hour < endHour)
        }

        guard isWithinQuiet else { return date }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = endHour
        components.minute = 0
        return calendar.date(from: components) ?? date
    }
}
