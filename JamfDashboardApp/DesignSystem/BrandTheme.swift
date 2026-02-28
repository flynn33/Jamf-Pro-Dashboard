import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// BrandTheme declaration.
enum BrandTheme {
    /// Radius declaration.
    enum Radius {
        static let card: CGFloat = 18
        static let button: CGFloat = 12
    }

    /// Spacing declaration.
    enum Spacing {
        static let section: CGFloat = 20
        static let item: CGFloat = 12
        static let compact: CGFloat = 8
    }

    static let accent = BrandColors.bluePrimary
    static var surface: Color {
#if canImport(UIKit)
        Color(uiColor: .systemBackground)
#elseif canImport(AppKit)
        Color(nsColor: .textBackgroundColor)
#else
        Color.white
#endif
    }
    static var groupedSurface: Color {
#if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
#elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
#else
        Color.gray.opacity(0.16)
#endif
    }
    static let border = BrandColors.blueSecondary.opacity(0.30)
    static let strongBorder = BrandColors.blueSecondary.opacity(0.48)
    static let shadowColor = Color.black.opacity(0.10)
    static let shadowColorStrong = Color.black.opacity(0.16)
    static let buttonTextOnPrimary = Color.white

    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                BrandColors.bluePrimary.opacity(0.95),
                BrandColors.bluePrimary,
                BrandColors.blueSecondary.opacity(0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var appBackdropGradient: LinearGradient {
        LinearGradient(
            colors: [
                BrandColors.blueSecondary.opacity(0.18),
                BrandColors.greenPrimary.opacity(0.08),
                groupedSurface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    static func appBackground() -> some View {
        ZStack {
            groupedSurface
            appBackdropGradient
        }
    }
}

//endofline
