import Foundation

struct BodyMetricsTimeRange: Equatable {
    let mode: AppSettings.BodyMetricsRangeMode
    let months: Int
    let year: Int

    init(
        mode: AppSettings.BodyMetricsRangeMode,
        months: Int,
        year: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let currentYear = calendar.component(.year, from: now)
        self.mode = mode
        self.months = min(max(months, 1), 60)
        self.year = min(max(year, 1970), currentYear)
    }

    init(settings: AppSettings, now: Date = Date(), calendar: Calendar = .current) {
        self.init(
            mode: settings.bodyMetricsRangeMode,
            months: settings.bodyMetricsRangeMonths,
            year: settings.bodyMetricsRangeYear,
            now: now,
            calendar: calendar
        )
    }

    var fullLabel: String {
        switch mode {
        case .lastMonths:
            return "Последние \(months) мес."
        case .year:
            return "За \(year) год"
        case .sinceYear:
            return "С \(year) года"
        }
    }

    var compactDeltaLabel: String {
        switch mode {
        case .lastMonths:
            return "за \(months) мес"
        case .year:
            return "за \(year) год"
        case .sinceYear:
            return "с \(year)"
        }
    }

    func dateInterval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let currentYear = calendar.component(.year, from: now)

        switch mode {
        case .lastMonths:
            let start = calendar.date(byAdding: .month, value: -months, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .year:
            let resolvedYear = min(max(year, 1970), currentYear)
            let start = calendar.date(from: DateComponents(year: resolvedYear, month: 1, day: 1)) ?? now
            if resolvedYear == currentYear {
                return DateInterval(start: start, end: now)
            }
            let end = calendar.date(from: DateComponents(year: resolvedYear + 1, month: 1, day: 1)) ?? now
            return DateInterval(start: start, end: end)
        case .sinceYear:
            let resolvedYear = min(max(year, 1970), currentYear)
            let start = calendar.date(from: DateComponents(year: resolvedYear, month: 1, day: 1)) ?? now
            return DateInterval(start: start, end: now)
        }
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let interval = dateInterval(now: now, calendar: calendar)
        if date == interval.end {
            switch mode {
            case .lastMonths, .sinceYear:
                return true
            case .year:
                let currentYear = calendar.component(.year, from: now)
                return year >= currentYear
            }
        }
        return interval.contains(date)
    }

    func filter(
        points: [HealthKitService.SamplePoint],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HealthKitService.SamplePoint] {
        points.filter { contains($0.date, now: now, calendar: calendar) }
    }

    static func availableYears(
        from collections: [[HealthKitService.SamplePoint]],
        selectedYear: Int? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        var years = Set<Int>()
        years.insert(calendar.component(.year, from: now))
        if let selectedYear {
            years.insert(selectedYear)
        }

        for point in collections.flatMap({ $0 }) {
            years.insert(calendar.component(.year, from: point.date))
        }

        return years.sorted(by: >)
    }
}
