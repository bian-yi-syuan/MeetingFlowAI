import SwiftUI

struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(monthText)
                    .font(.system(size: 8, weight: .bold))
                Text(dayText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(iconColor)
            .frame(width: 42, height: 42)
            .background(iconColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(meeting.startedAt.formatted(date: .abbreviated, time: .omitted))
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MFColor.text)
                    .lineLimit(1)
                Label(meeting.participants.isEmpty ? "参加者未設定" : meeting.participants.joined(separator: "、"), systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(MFColor.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            StatusPill(text: meeting.status.title, color: meeting.status == .completed ? MFColor.mint : MFColor.warning)
        }
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        let colors = [MFColor.mint, MFColor.danger, MFColor.primary, MFColor.accent]
        return colors[abs(meeting.title.hashValue) % colors.count]
    }

    private var monthText: String {
        String(format: "%02d月", Calendar.current.component(.month, from: meeting.startedAt))
    }

    private var dayText: String {
        String(format: "%02d日", Calendar.current.component(.day, from: meeting.startedAt))
    }
}
