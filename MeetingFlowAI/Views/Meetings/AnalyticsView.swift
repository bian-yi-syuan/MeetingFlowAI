import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query private var meetings: [Meeting]
    @Query private var todos: [TodoItem]

    private var totalDuration: TimeInterval { meetings.reduce(0) { $0 + $1.duration } }
    private var completion: Double { todos.isEmpty ? 0 : Double(todos.filter(\.isCompleted).count) / Double(todos.count) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    AnalyticsMetric(title: "会議時間", value: durationText, change: "端末内集計", color: MFColor.primary)
                    AnalyticsMetric(title: "会議数", value: "\(meetings.count)件", change: "保存済み", color: MFColor.mint)
                    AnalyticsMetric(title: "ToDo完了率", value: "\(Int(completion * 100))%", change: "\(todos.filter(\.isCompleted).count)/\(todos.count)", color: MFColor.accent)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("会議時間の推移").font(.headline)
                    DurationChart(values: chartValues)
                        .frame(height: 180)
                    HStack {
                        ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { day in
                            Text(day).font(.caption2).foregroundStyle(MFColor.secondaryText).frame(maxWidth: .infinity)
                        }
                    }
                }
                .mfCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("プライバシーに配慮した分析").font(.headline)
                    Label("この分析はSwiftDataに保存された端末内データだけで計算しています。", systemImage: "lock.shield.fill")
                        .font(.subheadline).foregroundStyle(MFColor.secondaryText)
                }
                .mfCard()
            }
            .padding(18)
        }
        .navigationTitle("分析")
        .navigationBarTitleDisplayMode(.inline)
        .mfScreenBackground()
    }

    private var durationText: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) / 60) % 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
    }

    private var chartValues: [Double] {
        var result = Array(repeating: 0.0, count: 7)
        for meeting in meetings {
            let weekday = Calendar.current.component(.weekday, from: meeting.startedAt)
            let mondayIndex = (weekday + 5) % 7
            result[mondayIndex] += meeting.duration / 60
        }
        return result
    }
}

private struct AnalyticsMetric: View {
    let title: String
    let value: String
    let change: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(MFColor.secondaryText).lineLimit(1)
            Text(value).font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(change).font(.system(size: 9, weight: .medium)).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mfCard(padding: 11)
    }
}

private struct DurationChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(values.max() ?? 1, 1)
            ZStack {
                VStack { ForEach(0..<4, id: \.self) { _ in Spacer(); Divider() } }
                if values.allSatisfy({ $0 == 0 }) {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.flattrend.xyaxis")
                            .font(.title2)
                            .foregroundStyle(MFColor.secondaryText.opacity(0.7))
                        Text("会議を録音すると推移が表示されます")
                            .font(.caption)
                            .foregroundStyle(MFColor.secondaryText)
                    }
                } else {
                    Path { path in
                        for index in values.indices {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                            let y = geometry.size.height * (1 - CGFloat(values[index] / maxValue) * 0.85)
                            if index == values.startIndex { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(MFColor.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
