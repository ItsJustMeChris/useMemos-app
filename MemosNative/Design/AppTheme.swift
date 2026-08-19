import SwiftUI

enum AppTheme {
    static let tint = Color(red: 0.105, green: 0.61, blue: 0.31)
    static let softTint = tint.opacity(0.12)
    static let warmBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.065, blue: 0.06, alpha: 1)
            : UIColor(red: 0.965, green: 0.972, blue: 0.955, alpha: 1)
    })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedCard = Color(uiColor: .systemBackground)
    static let hairline = Color.primary.opacity(0.08)
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct RoundedCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 0.75)
            }
    }
}

extension View {
    func roundedCard(padding: CGFloat = 16) -> some View {
        modifier(RoundedCardModifier(padding: padding))
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
    }
}

struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
        .frame(width: size, height: size)
        .shadow(color: AppTheme.tint.opacity(0.25), radius: size * 0.18, y: size * 0.1)
        .accessibilityHidden(true)
    }
}
