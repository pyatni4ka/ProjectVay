import Foundation

enum DynamicChartMetricKind {
    case weightKg
    case bodyFatPercent

    fileprivate var minimumWindow: Double {
        switch self {
        case .weightKg:
            return 4
        case .bodyFatPercent:
            return 3
        }
    }

    fileprivate func roundingStep(for coreSpan: Double) -> Double {
        switch self {
        case .weightKg:
            if coreSpan < 4 {
                return 0.5
            } else if coreSpan < 12 {
                return 1
            } else {
                return 2
            }
        case .bodyFatPercent:
            return coreSpan < 6 ? 0.5 : 1
        }
    }
}

struct DynamicChartScaleDomain: Equatable {
    let lower: Double
    let upper: Double
    let step: Double
    let hasLowerOutliers: Bool
    let hasUpperOutliers: Bool

    var domain: ClosedRange<Double> {
        lower...upper
    }

    func displayValue(for value: Double) -> Double {
        min(max(value, lower), upper)
    }

    func isLowerOutlier(_ value: Double) -> Bool {
        value < lower
    }

    func isUpperOutlier(_ value: Double) -> Bool {
        value > upper
    }

    static func resolve(values: [Double], metric: DynamicChartMetricKind) -> DynamicChartScaleDomain? {
        let sorted = values
            .filter(\.isFinite)
            .sorted()
        guard let minValue = sorted.first, let maxValue = sorted.last else {
            return nil
        }

        let coreMin: Double
        let coreMax: Double
        if sorted.count < 5 {
            coreMin = minValue
            coreMax = maxValue
        } else {
            coreMin = quantile(0.1, sorted: sorted)
            coreMax = quantile(0.9, sorted: sorted)
        }

        let resolvedCoreMin = min(coreMin, coreMax)
        let resolvedCoreMax = max(coreMin, coreMax)
        let coreSpan = max(0, resolvedCoreMax - resolvedCoreMin)
        let step = metric.roundingStep(for: coreSpan)
        let padding = max(step * 1.5, coreSpan * 0.18)

        var lower = floor((resolvedCoreMin - padding) / step) * step
        var upper = ceil((resolvedCoreMax + padding) / step) * step
        lower = max(0, lower)
        if upper <= lower {
            upper = lower + metric.minimumWindow
        }

        if upper - lower < metric.minimumWindow {
            let deficit = metric.minimumWindow - (upper - lower)
            lower -= deficit / 2
            upper += deficit / 2

            if lower < 0 {
                upper -= lower
                lower = 0
            }

            lower = floor(lower / step) * step
            upper = ceil(upper / step) * step
            if upper - lower < metric.minimumWindow {
                upper = ceil((lower + metric.minimumWindow) / step) * step
            }
        }

        return DynamicChartScaleDomain(
            lower: lower == 0 ? 0 : lower,
            upper: upper,
            step: step,
            hasLowerOutliers: minValue < lower,
            hasUpperOutliers: maxValue > upper
        )
    }

    private static func quantile(_ q: Double, sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }

        let clampedQ = min(max(q, 0), 1)
        let position = clampedQ * Double(sorted.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))

        guard lowerIndex != upperIndex else {
            return sorted[lowerIndex]
        }

        let fraction = position - Double(lowerIndex)
        let lowerValue = sorted[lowerIndex]
        let upperValue = sorted[upperIndex]
        return lowerValue + (upperValue - lowerValue) * fraction
    }
}
