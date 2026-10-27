import SwiftUI
import Charts

/// Small trend line used in the signal detail sheet and Trends: recent days,
/// optional baseline reference rule, latest point highlighted.
struct Sparkline: View {
    let points: [TrendPoint]
    var baseline: Double? = nil
    var color: Color = Theme.textPrimary
    var height: CGFloat = 72

    var body: some View {
        Chart {
            if let baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(Theme.laneLine)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(points) { point in
                LineMark(x: .value("Day", point.date), y: .value("Value", point.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.date), y: .value("Value", last.value))
                    .foregroundStyle(color)
                    .symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .frame(height: height)
    }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.value)
        if let baseline { values.append(baseline) }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.2, 0.5)
        return (lo - pad)...(hi + pad)
    }
}
