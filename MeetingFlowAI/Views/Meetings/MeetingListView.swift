import SwiftUI
import SwiftData

private enum MeetingFilter: String, CaseIterable {
    case all = "すべて"
    case summarized = "要約済み"
    case needsReview = "未整理"
}

struct MeetingListView: View {
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var query = ""
    @State private var filter: MeetingFilter = .all

    private var filteredMeetings: [Meeting] {
        meetings.filter { meeting in
            let matchesQuery = query.isEmpty || meeting.title.localizedCaseInsensitiveContains(query) || meeting.participantsText.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .summarized: meeting.hasSummary
            case .needsReview: !meeting.hasSummary
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(MFColor.secondaryText)
                    TextField("キーワードを入力", text: $query)
                        .textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Menu {
                    Picker("表示", selection: $filter) {
                        ForEach(MeetingFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 44, height: 44)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("会議を絞り込む")
            }
            .padding(.horizontal, 18)

            if filteredMeetings.isEmpty {
                Spacer()
                EmptyStateView(icon: "magnifyingglass", title: "会議が見つかりません", message: "検索語やフィルターを変更してください。")
                    .padding(.horizontal, 18)
                Spacer()
            } else {
                List {
                    ForEach(filteredMeetings) { meeting in
                        NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                            MeetingRow(meeting: meeting)
                                .padding(.vertical, 5)
                        }
                        .listRowBackground(Color.white)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.top, 8)
        .navigationTitle("会議一覧")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: AnalyticsView()) { Image(systemName: "chart.line.uptrend.xyaxis") }
                    .accessibilityLabel("分析")
            }
        }
        .mfScreenBackground()
    }
}
