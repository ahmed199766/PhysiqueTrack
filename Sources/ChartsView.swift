import SwiftUI
import Charts

struct ChartsView: View {
    @EnvironmentObject private var store: DataStore

    private var chronological: [ProgressEntry] {
        store.sortedChronological
    }

    private var bodyFatEntries: [ProgressEntry] {
        chronological.filter { $0.bodyFatPercent != nil }
    }

    private var weightBounds: ClosedRange<Double> {
        let weights = chronological.map { $0.weightKg }
        let minW = (weights.min() ?? 70) - 2.0
        let maxW = (weights.max() ?? 80) + 2.0
        return max(0, minW)...maxW
    }

    private var bodyFatBounds: ClosedRange<Double> {
        let vals = bodyFatEntries.compactMap { $0.bodyFatPercent }
        let minV = (vals.min() ?? 10) - 1.5
        let maxV = (vals.max() ?? 20) + 1.5
        return max(0, minV)...maxV
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if chronological.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("لا توجد بيانات كافية للرسم البياني بعد")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 70)
                    } else {
                        weightChartCard
                        statsGrid
                        if bodyFatEntries.count >= 2 {
                            bodyFatChartCard
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("الرسم البياني")
        }
    }

    private var weightChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("تغيّر الوزن (كغم)")
                .font(.headline)

            Chart(chronological) { entry in
                AreaMark(
                    x: .value("التاريخ", entry.date),
                    yStart: .value("بداية", weightBounds.lowerBound),
                    yEnd: .value("الوزن", entry.weightKg)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("التاريخ", entry.date),
                    y: .value("الوزن", entry.weightKg)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("التاريخ", entry.date),
                    y: .value("الوزن", entry.weightKg)
                )
                .foregroundStyle(Color.white)
                .symbolSize(36)
            }
            .chartYScale(domain: weightBounds)
            .frame(height: 230)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var bodyFatChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("تغيّر نسبة الدهون (%)")
                .font(.headline)

            Chart(bodyFatEntries) { entry in
                if let bf = entry.bodyFatPercent {
                    LineMark(
                        x: .value("التاريخ", entry.date),
                        y: .value("الدهون", bf)
                    )
                    .foregroundStyle(Color.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("التاريخ", entry.date),
                        y: .value("الدهون", bf)
                    )
                    .foregroundStyle(Color.cyan)
                    .symbolSize(36)
                }
            }
            .chartYScale(domain: bodyFatBounds)
            .frame(height: 200)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statsGrid: some View {
        let weights = chronological.map { $0.weightKg }
        let minW = weights.min() ?? 0
        let maxW = weights.max() ?? 0
        let avgW = weights.reduce(0, +) / Double(max(1, weights.count))

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            miniStat(title: "أقل وزن", value: "\(NumberParser.formatWeight(minW)) كغم", color: .green)
            miniStat(title: "أعلى وزن", value: "\(NumberParser.formatWeight(maxW)) كغم", color: .orange)
            miniStat(title: "المتوسط", value: "\(NumberParser.formatWeight(avgW)) كغم", color: .accentColor)
            miniStat(title: "عدد التسجيلات", value: "\(chronological.count)", color: .cyan)
        }
    }

    private func miniStat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
