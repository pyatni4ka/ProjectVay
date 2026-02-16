import SwiftUI

// MARK: - Color Palette

extension Color {
    // Primary — тёплый шалфейный зелёный
    static let vayPrimary = Color(hue: 0.38, saturation: 0.45, brightness: 0.55)
    // Primary Light — для фонов и subtle fills
    static let vayPrimaryLight = Color(hue: 0.38, saturation: 0.18, brightness: 0.95)
    // Accent — тёплый персиковый коралл
    static let vayAccent = Color(hue: 0.05, saturation: 0.55, brightness: 0.95)
    // Secondary — мягкий лавандовый
    static let vaySecondary = Color(hue: 0.72, saturation: 0.25, brightness: 0.85)
    // Warning — тёплый янтарный
    static let vayWarning = Color(hue: 0.10, saturation: 0.70, brightness: 0.95)
    // Danger — мягкий красный
    static let vayDanger = Color(hue: 0.0, saturation: 0.55, brightness: 0.90)
    // Success — свежий мятный
    static let vaySuccess = Color(hue: 0.42, saturation: 0.50, brightness: 0.80)
    // Info — небесно-голубой
    static let vayInfo = Color(hue: 0.58, saturation: 0.40, brightness: 0.88)

    // Adaptive Backgrounds
    static let vayBackground = Color(.systemGroupedBackground)
    static let vayCardBackground = Color(.secondarySystemGroupedBackground)
    static let vaySurface = Color(.systemBackground)

    // Macro colors (КБЖУ)
    static let vayCalories = Color(hue: 0.08, saturation: 0.65, brightness: 0.95)
    static let vayProtein = Color(hue: 0.58, saturation: 0.50, brightness: 0.85)
    static let vayFat = Color(hue: 0.10, saturation: 0.55, brightness: 0.92)
    static let vayCarbs = Color(hue: 0.42, saturation: 0.45, brightness: 0.80)

    // Location colors
    static let vayFridge = Color(hue: 0.55, saturation: 0.40, brightness: 0.85)
    static let vayFreezer = Color(hue: 0.60, saturation: 0.50, brightness: 0.80)
    static let vayPantry = Color(hue: 0.08, saturation: 0.40, brightness: 0.90)
}

// MARK: - Typography

enum VayFont {
    /// Scales with Dynamic Type via `.largeTitle` text style
    static func hero(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .rounded).leading(.tight)
    }

    /// Scales with Dynamic Type via `.title` text style
    static func title(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold, design: .rounded).leading(.tight)
    }

    /// Scales with Dynamic Type via `.title3` text style
    static func heading(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// Scales with Dynamic Type via `.body` text style
    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    /// Scales with Dynamic Type via `.subheadline` text style
    static func label(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    /// Scales with Dynamic Type via `.caption` text style
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }

    /// Fixed-width; scales with Dynamic Type via `.body` text style
    static func mono(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// Apply to root views to enable Dynamic Type scaling across the app
extension View {
    func vayDynamicType() -> some View {
        self.dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - Spacing

enum VaySpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
}

// MARK: - Corner Radius

enum VayRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let pill: CGFloat = 100
}

enum VayLayout {
    /// Extra bottom space for the custom tab bar + safe-area on iPhone devices.
    static let tabBarOverlayInset: CGFloat = 124
}

// MARK: - Shadows

struct VayShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    static let card = VayShadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    static let cardHover = VayShadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
    static let subtle = VayShadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    static let glow = VayShadow(color: .vayPrimary.opacity(0.3), radius: 16, x: 0, y: 4)
}

extension View {
    func vayShadow(_ shadow: VayShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Animations

enum VayAnimation {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableAnimations") as? Bool ?? true
    }

    private static var instant: Animation {
        .linear(duration: 0)
    }

    static var springBounce: Animation {
        isEnabled ? .spring(response: 0.5, dampingFraction: 0.7) : instant
    }

    static var springSmooth: Animation {
        isEnabled ? .spring(response: 0.4, dampingFraction: 0.85) : instant
    }

    static var springSnappy: Animation {
        isEnabled ? .spring(response: 0.3, dampingFraction: 0.9) : instant
    }

    static var easeOut: Animation {
        isEnabled ? .easeOut(duration: 0.25) : instant
    }

    static var gentleBounce: Animation {
        isEnabled ? .spring(response: 0.6, dampingFraction: 0.75) : instant
    }
}

// MARK: - Gradients

enum VayGradient {
    static let primary = LinearGradient(
        colors: [.vayPrimary, .vayPrimary.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accent = LinearGradient(
        colors: [.vayAccent, .vayAccent.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warm = LinearGradient(
        colors: [
            Color(hue: 0.08, saturation: 0.4, brightness: 1.0),
            Color(hue: 0.05, saturation: 0.5, brightness: 0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cool = LinearGradient(
        colors: [
            Color(hue: 0.55, saturation: 0.3, brightness: 0.95),
            Color(hue: 0.60, saturation: 0.4, brightness: 0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let hero = LinearGradient(
        colors: [
            .vayPrimary.opacity(0.15),
            .vayAccent.opacity(0.08),
            .clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - View Modifiers

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = VayRadius.xl

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }
}

struct VayCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(VaySpacing.lg)
            .background(Color.vayCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))
            .vayShadow(.card)
    }
}

struct VayPillButton: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(VayFont.label())
            .foregroundStyle(.white)
            .padding(.horizontal, VaySpacing.xl)
            .padding(.vertical, VaySpacing.md)
            .background(color)
            .clipShape(Capsule())
            .vayShadow(.subtle)
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = VayRadius.xl) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    func vayCard() -> some View {
        modifier(VayCardStyle())
    }

    func vayPillButton(color: Color = .vayPrimary) -> some View {
        modifier(VayPillButton(color: color))
    }
}

// MARK: - Haptics

enum VayHaptic {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Reduced Motion Support

struct VayMotion {
    let reduceMotion: Bool

    func animation(_ preferred: Animation) -> Animation {
        reduceMotion ? .default : preferred
    }

    var springSnappy: Animation {
        animation(VayAnimation.springSnappy)
    }

    var springSmooth: Animation {
        animation(VayAnimation.springSmooth)
    }

    var springBounce: Animation {
        animation(VayAnimation.springBounce)
    }
}

extension EnvironmentValues {
    var vayMotion: VayMotion {
        VayMotion(reduceMotion: accessibilityReduceMotion)
    }
}

// MARK: - Accessibility Helpers

extension View {
    func vayAccessibilityLabel(_ label: String, hint: String? = nil) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint != nil ? Text(hint!) : Text(""))
    }

    @ViewBuilder
    func dismissKeyboardOnTap() -> some View {
        if #available(iOS 16.0, *) {
            self
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        dismissKeyboard()
                    },
                    including: .gesture
                )
        } else {
            self.simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                },
                including: .gesture
            )
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}

// MARK: - Expiry Helpers

extension Date {
    var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: .now.startOfDay, to: self.startOfDay).day ?? 0
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var expiryColor: Color {
        let days = daysUntilExpiry
        if days < 0 { return .vayDanger }
        if days <= 2 { return .vayWarning }
        if days <= 5 { return .vayAccent }
        return .vaySuccess
    }

    var expiryLabel: String {
        let days = daysUntilExpiry
        if days < 0 { return "Просрочен" }
        if days == 0 { return "Сегодня!" }
        if days == 1 { return "Завтра" }
        if days <= 5 { return "\(days) дн." }
        return "\(days) дн."
    }
}

// MARK: - Location Helpers

extension InventoryLocation {
    var icon: String {
        switch self {
        case .fridge: return "refrigerator"
        case .freezer: return "snowflake"
        case .pantry: return "cabinet"
        }
    }

    var color: Color {
        switch self {
        case .fridge: return .vayFridge
        case .freezer: return .vayFreezer
        case .pantry: return .vayPantry
        }
    }
}

// MARK: - Unit Helpers

extension UnitType {
    var icon: String {
        switch self {
        case .pcs: return "number"
        case .g: return "scalemass"
        case .ml: return "drop"
        }
    }
}
