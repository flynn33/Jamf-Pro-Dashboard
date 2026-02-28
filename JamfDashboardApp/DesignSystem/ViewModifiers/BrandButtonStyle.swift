import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// BrandPrimaryButtonStyle declaration.
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// Handles makeBody.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrandTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(BrandTheme.buttonTextOnPrimary)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background {
                if isEnabled {
                    shape.fill(BrandTheme.primaryButtonGradient)
                } else {
                    shape.fill(BrandPlatformColors.disabledPrimaryBackground)
                }
            }
            .overlay(
                shape
                    .stroke(BrandTheme.strongBorder.opacity(isEnabled ? 0.65 : 0.25), lineWidth: 1)
            )
            .shadow(
                color: isEnabled ? BrandTheme.shadowColor : .clear,
                radius: configuration.isPressed ? 2 : 7,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// BrandSecondaryButtonStyle declaration.
struct BrandSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// Handles makeBody.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrandTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(isEnabled ? BrandColors.bluePrimary : Color.secondary)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(
                shape
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                shape
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: isEnabled ? BrandTheme.shadowColor.opacity(0.65) : .clear,
                radius: configuration.isPressed ? 1 : 4,
                x: 0,
                y: configuration.isPressed ? 0 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var borderColor: Color {
        isEnabled ? BrandColors.bluePrimary.opacity(0.35) : BrandPlatformColors.separator
    }

    /// Handles backgroundColor.
    private func backgroundColor(isPressed: Bool) -> Color {
        if isEnabled == false {
            return BrandPlatformColors.tertiaryFill
        }

        return isPressed ? BrandColors.blueSecondary.opacity(0.22) : BrandTheme.surface
    }
}

/// BrandDangerButtonStyle declaration.
struct BrandDangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// Handles makeBody.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrandTheme.Radius.button, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(isEnabled ? Color.red : Color.secondary)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(
                shape
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                shape
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: isEnabled ? BrandTheme.shadowColor.opacity(0.60) : .clear,
                radius: configuration.isPressed ? 1 : 4,
                x: 0,
                y: configuration.isPressed ? 0 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var borderColor: Color {
        isEnabled ? Color.red.opacity(0.35) : BrandPlatformColors.separator
    }

    /// Handles backgroundColor.
    private func backgroundColor(isPressed: Bool) -> Color {
        if isEnabled == false {
            return BrandPlatformColors.tertiaryFill
        }

        return isPressed ? Color.red.opacity(0.16) : BrandTheme.surface
    }
}

/// Centralized platform-dependent semantic colors used by button styles.
private enum BrandPlatformColors {
    static var disabledPrimaryBackground: Color {
#if canImport(UIKit)
        Color(uiColor: .systemGray3)
#elseif canImport(AppKit)
        Color(nsColor: .systemGray)
#else
        Color.gray.opacity(0.35)
#endif
    }

    static var separator: Color {
#if canImport(UIKit)
        Color(uiColor: .separator)
#elseif canImport(AppKit)
        Color(nsColor: .separatorColor)
#else
        Color.gray.opacity(0.3)
#endif
    }

    static var tertiaryFill: Color {
#if canImport(UIKit)
        Color(uiColor: .tertiarySystemFill)
#elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
#else
        Color.gray.opacity(0.2)
#endif
    }

}

extension ButtonStyle where Self == BrandPrimaryButtonStyle {
    static var appPrimary: BrandPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == BrandSecondaryButtonStyle {
    static var appSecondary: BrandSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == BrandDangerButtonStyle {
    static var appDanger: BrandDangerButtonStyle { .init() }
}

//endofline
