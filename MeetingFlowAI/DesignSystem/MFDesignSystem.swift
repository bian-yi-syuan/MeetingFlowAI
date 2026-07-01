import SwiftUI

enum MFColor {
    static let primary = Color(hex: "3274F6")
    static let primaryDark = Color(hex: "225AD4")
    static let accent = Color(hex: "6C63F2")
    static let mint = Color(hex: "39B98A")
    static let background = Color(hex: "F6F7FA")
    static let card = Color.white
    static let text = Color(hex: "171A21")
    static let secondaryText = Color(hex: "687083")
    static let border = Color(hex: "E7E9EF")
    static let warning = Color(hex: "F3A52B")
    static let danger = Color(hex: "E55757")
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

struct MFCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(MFColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MFColor.border.opacity(0.7), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 12, y: 5)
    }
}

extension View {
    func mfCard(padding: CGFloat = 16) -> some View {
        modifier(MFCardModifier(padding: padding))
    }

    func mfScreenBackground() -> some View {
        background(MFColor.background.ignoresSafeArea())
    }
}

struct MFPrimaryButton: View {
    let title: String
    var icon: String?
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(disabled ? MFColor.secondaryText.opacity(0.45) : MFColor.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct MFSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.caption).fontWeight(.medium)
            }
        }
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = MFColor.mint

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(MFColor.primary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(MFColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .mfCard()
    }
}
