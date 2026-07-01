import SwiftUI

struct WaveformView: View {
    var level: Float
    var isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !isActive)) { timeline in
            GeometryReader { geometry in
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<46, id: \.self) { index in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let wave = abs(sin(Double(index) * 0.71 + time * 5.2))
                        let activity = isActive ? max(Double(level), 0.15) : 0.12
                        Capsule()
                            .fill(index == 23 ? MFColor.primaryDark : MFColor.primary.opacity(0.75))
                            .frame(
                                width: max(2, (geometry.size.width - 135) / 46),
                                height: max(5, 12 + 62 * wave * activity)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 112)
        .accessibilityLabel("録音波形")
    }
}
