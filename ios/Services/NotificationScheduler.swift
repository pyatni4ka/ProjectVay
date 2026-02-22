import Foundation
import UserNotifications

struct ReminderCandidate: Equatable {
    let daysBefore: Int
    let fireDate: Date
}

protocol NotificationScheduling: Sendable {
    func scheduleExpiryNotifications(for batch: Batch, product: Product, settings: AppSettings) async throws
    func cancelExpiryNotifications(batchId: UUID) async throws
    func cancelAllExpiryNotifications() async throws
    func rescheduleExpiryNotifications(for batch: Batch, product: Product, settings: AppSettings) async throws
}

final class NotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter?
    private let calendar: Calendar

    init(center: UNUserNotificationCenter? = nil, calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    func scheduleExpiryNotifications(for batch: Batch, product: Product, settings: AppSettings) async throws {
        try await cancelExpiryNotifications(batchId: batch.id)

        guard center != nil else { return }
        guard let expiryDate = batch.expiryDate else { return }
        let reminders = reminderDates(
            expiryDate: expiryDate,
            alertDays: settings.expiryAlertsDays,
            quietStartMinute: settings.quietStartMinute,
            quietEndMinute: settings.quietEndMinute
        )

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = "Проверь срок годности"
            content.body = "\(product.name): срок истекает через \(reminder.daysBefore) дн."
            content.sound = .default
            // Группировка уведомлений
            content.threadIdentifier = "expiry-alerts"
            // Actionable notification с кнопками
            content.categoryIdentifier = "EXPIRY_ALERT"
            content.userInfo = [
                "batchId": batch.id.uuidString,
                "productId": batch.productId.uuidString,
                "productName": product.name
            ]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(batchId: batch.id, daysBefore: reminder.daysBefore),
                content: content,
                trigger: trigger
            )

            try await add(request)
        }
    }

    func cancelExpiryNotifications(batchId: UUID) async throws {
        guard let center else { return }
        let prefix = "expiry.\(batchId.uuidString)."
        let identifiers = await pendingRequestIdentifiers()
            .filter { $0.hasPrefix(prefix) }

        guard !identifiers.isEmpty else { return }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAllExpiryNotifications() async throws {
        guard let center else { return }
        let identifiers = await pendingRequestIdentifiers()
            .filter { $0.hasPrefix("expiry.") }

        guard !identifiers.isEmpty else { return }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func rescheduleExpiryNotifications(for batch: Batch, product: Product, settings: AppSettings) async throws {
        try await cancelExpiryNotifications(batchId: batch.id)
        try await scheduleExpiryNotifications(for: batch, product: product, settings: settings)
    }

    func reminderDates(
        expiryDate: Date,
        alertDays: [Int],
        quietStartMinute: Int,
        quietEndMinute: Int,
        now: Date = Date()
    ) -> [ReminderCandidate] {
        let normalizedDays = Array(Set(alertDays.map { min(max($0, 1), 30) })).sorted(by: >)
        let expiryStart = calendar.startOfDay(for: expiryDate)

        return normalizedDays.compactMap { daysBefore in
            guard let reminderDay = calendar.date(byAdding: .day, value: -daysBefore, to: expiryStart) else {
                return nil
            }

            var candidate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: reminderDay) ?? reminderDay
            candidate = adjustedForQuietHours(candidate, quietStartMinute: quietStartMinute, quietEndMinute: quietEndMinute)

            if candidate < now {
                if calendar.isDate(expiryDate, inSameDayAs: now) {
                    let todayCandidate = adjustedForQuietHours(now, quietStartMinute: quietStartMinute, quietEndMinute: quietEndMinute)
                    if calendar.isDate(todayCandidate, inSameDayAs: now), todayCandidate >= now {
                        candidate = todayCandidate
                    } else {
                        candidate = now.addingTimeInterval(60)
                    }
                } else {
                    return nil
                }
            }

            if candidate < now {
                return nil
            }

            return ReminderCandidate(daysBefore: daysBefore, fireDate: candidate)
        }
    }

    func adjustedForQuietHours(
        _ date: Date,
        quietStartMinute: Int,
        quietEndMinute: Int
    ) -> Date {
        let start = AppSettings.clampMinute(quietStartMinute)
        let end = AppSettings.clampMinute(quietEndMinute)

        guard start != end else {
            return date
        }

        let minute = minuteOfDay(for: date)
        let inQuiet = isWithinQuietHour(minute: minute, start: start, end: end)

        guard inQuiet else {
            return date
        }

        var startOfDay = calendar.startOfDay(for: date)
        let targetMinute = end

        if start > end, minute >= start {
            startOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        }

        let adjusted = calendar.date(byAdding: .minute, value: targetMinute, to: startOfDay) ?? date
        if adjusted <= date {
            return calendar.date(byAdding: .day, value: 1, to: adjusted) ?? adjusted
        }

        return adjusted
    }

    private func notificationIdentifier(batchId: UUID, daysBefore: Int) -> String {
        "expiry.\(batchId.uuidString).\(daysBefore)"
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }

    private func isWithinQuietHour(minute: Int, start: Int, end: Int) -> Bool {
        if start < end {
            return minute >= start && minute < end
        }

        return minute >= start || minute < end
    }

    private func add(_ request: UNNotificationRequest) async throws {
        guard let center else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func pendingRequestIdentifiers() async -> [String] {
        guard let center else { return [] }
        return await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }
}
