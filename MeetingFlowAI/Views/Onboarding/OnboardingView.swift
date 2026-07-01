import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let message: String
    let buttonTitle: String
    let color: Color
    let symbol: String
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var pageIndex = 0

    private let pages = [
        OnboardingPage(
            id: 0,
            title: "AIで会議ワークフローを効率化",
            message: "録音、文字起こし、会議内容の要約、ToDo作成、カレンダー登録、メール共有まで。\n会議後の面倒な作業を、AIがスムーズにサポートします。",
            buttonTitle: "次へ",
            color: MFColor.primary,
            symbol: "wand.and.stars"
        ),
        OnboardingPage(
            id: 1,
            title: "30秒で会議記録を作成",
            message: "録音した会議内容から、AIが短時間で会議記録を自動生成。\n重要な発言にはタグを付けて、あとから簡単に確認できます。",
            buttonTitle: "次へ",
            color: MFColor.accent,
            symbol: "waveform.badge.mic"
        ),
        OnboardingPage(
            id: 2,
            title: "ToDoとカレンダーを連携",
            message: "会議で決まったタスクをToDoに登録し、カレンダーにも予定として追加できます。\nスマートフォンの通知と連携して、対応漏れを防ぎます。",
            buttonTitle: "次へ",
            color: MFColor.mint,
            symbol: "calendar.badge.checkmark"
        ),
        OnboardingPage(
            id: 3,
            title: "会議後の共有もスムーズに",
            message: "会議終了後、AIが内容を整理し、出席者に共有するメール文を作成します。\n決定事項や次回アクションを、すぐにチームへ共有できます。",
            buttonTitle: "次へ",
            color: MFColor.primary,
            symbol: "envelope.badge"
        ),
        OnboardingPage(
            id: 4,
            title: "無料版を今すぐお試しください",
            message: "MeetingFlow AIの無料版をご利用いただけます。\n試用後のご感想や改善点がございましたら、開発者 Bian Yi Syuan までぜひお聞かせください。\n\n本試用プログラムへのご参加、誠にありがとうございます。",
            buttonTitle: "無料で始める",
            color: MFColor.accent,
            symbol: "heart.text.square.fill"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("MimiFlowLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("MeetingFlow AI")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MFColor.primaryDark)
                Spacer()
                Text("\(pageIndex + 1) / \(pages.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(MFColor.secondaryText)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            TabView(selection: $pageIndex) {
                ForEach(pages) { page in
                    pageView(page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageIndicator
                .padding(.bottom, 18)

            MFPrimaryButton(
                title: pages[pageIndex].buttonTitle,
                icon: pageIndex == pages.count - 1 ? "arrow.right.circle.fill" : "chevron.right"
            ) {
                if pageIndex == pages.count - 1 {
                    onComplete()
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) { pageIndex += 1 }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .background(MFColor.background.ignoresSafeArea())
        .tint(pages[pageIndex].color)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(page.color)
                        .frame(width: 42, height: 42)
                    Text("\(page.id + 1)")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }

                Text(page.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MFColor.text)
                    .frame(maxWidth: 340)

                OnboardingIllustration(page: page)
                    .frame(maxWidth: 360)

                Text(page.message)
                    .font(.subheadline)
                    .foregroundStyle(MFColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .frame(maxWidth: 350)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 18)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == pageIndex ? pages[pageIndex].color : MFColor.border)
                    .frame(width: index == pageIndex ? 24 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: pageIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("全5ページ中\(pageIndex + 1)ページ目")
    }
}

private struct OnboardingIllustration: View {
    let page: OnboardingPage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [page.color.opacity(0.08), page.color.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 245)

            switch page.id {
            case 0: workflowGraphic
            case 1: recordGraphic
            case 2: todoCalendarGraphic
            case 3: sharingGraphic
            default: trialGraphic
            }
        }
    }

    private var workflowGraphic: some View {
        ZStack {
            Circle().fill(.white).frame(width: 90, height: 90).shadow(color: page.color.opacity(0.15), radius: 14, y: 6)
            Image(systemName: "sparkles").font(.system(size: 38, weight: .semibold)).foregroundStyle(page.color)
            ForEach(Array(["mic.fill", "text.quote", "checklist", "envelope.fill"].enumerated()), id: \.offset) { index, symbol in
                let angle = Double(index) * .pi / 2 - .pi / 2
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(page.color)
                    .frame(width: 48, height: 48)
                    .background(.white)
                    .clipShape(Circle())
                    .offset(x: cos(angle) * 105, y: sin(angle) * 72)
            }
        }
    }

    private var recordGraphic: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(page.color.opacity(0.18), lineWidth: 14).frame(width: 118, height: 118)
                Circle().trim(from: 0, to: 0.78).stroke(page.color, style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 118, height: 118)
                VStack(spacing: 0) {
                    Text("30").font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(page.color)
                    Text("秒").font(.caption.weight(.bold)).foregroundStyle(MFColor.secondaryText)
                }
            }
            Label("重要な発言を自動整理", systemImage: "bookmark.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.white).clipShape(Capsule())
        }
    }

    private var todoCalendarGraphic: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Label("資料を作成", systemImage: "checkmark.circle.fill")
                Label("デザイン確認", systemImage: "checkmark.circle.fill")
                Label("顧客へ連絡", systemImage: "circle")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(MFColor.text)
            .padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 18))

            Image(systemName: "arrow.right").foregroundStyle(page.color)

            VStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 54)).foregroundStyle(page.color)
                Text("予定と通知").font(.caption.weight(.bold))
            }
            .padding(18).background(.white).clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var sharingGraphic: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 58))
                .foregroundStyle(page.color)
                .frame(width: 105, height: 105)
                .background(.white)
                .clipShape(Circle())
                .shadow(color: page.color.opacity(0.18), radius: 14, y: 6)
            HStack(spacing: -8) {
                ForEach(0..<3, id: \.self) { _ in
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 38)).foregroundStyle(page.color.opacity(0.85)).background(.white).clipShape(Circle())
                }
            }
            Text("決定事項・次回アクション・ToDo")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 15).padding(.vertical, 8)
                .background(.white).clipShape(Capsule())
        }
    }

    private var trialGraphic: some View {
        HStack(spacing: 20) {
            Image("MimiFlowLogo")
                .resizable().scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: page.color.opacity(0.18), radius: 18, y: 8)
            VStack(alignment: .leading, spacing: 10) {
                feature("録音・文字起こし")
                feature("AI要約")
                feature("ToDo・カレンダー")
                feature("メール共有")
            }
        }
    }

    private func feature(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(MFColor.text)
    }
}
