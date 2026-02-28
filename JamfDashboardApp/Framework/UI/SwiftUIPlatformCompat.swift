import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared SwiftUI compatibility helpers for iOS and macOS.
extension View {
    /// Applies a rounded native typography treatment where available.
    @ViewBuilder
    func appRoundedTypography() -> some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
            fontDesign(.rounded)
        } else {
            self
        }
#elseif os(macOS)
        if #available(macOS 13.0, *) {
            fontDesign(.rounded)
        } else {
            self
        }
#else
        self
#endif
    }

    /// Applies app-wide backdrop treatment.
    @ViewBuilder
    func appBackground() -> some View {
        background {
            BrandTheme.appBackground()
                .ignoresSafeArea()
        }
    }

    /// Applies a shared elevated card style.
    func appCardSurface(fill: Color = BrandTheme.surface) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrandTheme.Radius.card, style: .continuous)
        return self
            .background(shape.fill(fill))
            .overlay(shape.stroke(BrandTheme.border, lineWidth: 1))
            .shadow(color: BrandTheme.shadowColor, radius: 10, x: 0, y: 5)
    }

    /// Applies a shared bottom bar style used by action insets.
    func appBottomBarSurface() -> some View {
        self
            .background(BrandTheme.groupedSurface)
            .overlay(alignment: .top) {
                Divider()
                    .overlay(BrandTheme.border)
            }
            .shadow(color: BrandTheme.shadowColorStrong.opacity(0.55), radius: 9, x: 0, y: -2)
    }

    /// Uses inline navigation title mode on iOS and no-op on macOS.
    @ViewBuilder
    func appInlineNavigationTitle() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    /// Adds a leading back button that dismisses the current view.
    func appBackButtonToolbar(label: String = "Back") -> some View {
        modifier(BrandBackButtonToolbarModifier(label: label))
    }

    /// Applies grouped list style on iOS and inset list style on macOS.
    @ViewBuilder
    func appInsetGroupedListStyle() -> some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
            listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .appBackground()
        } else {
            listStyle(.insetGrouped)
        }
#else
        if #available(macOS 13.0, *) {
            listStyle(.inset)
                .scrollContentBackground(.hidden)
                .appBackground()
        } else {
            listStyle(.inset)
        }
#endif
    }

    /// Disables auto-correction and capitalization on iOS and no-op on macOS.
    @ViewBuilder
    func appNoAutoCorrectionTextInput() -> some View {
#if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
#else
        self
#endif
    }

    /// Uses URL keyboard on iOS and no-op on macOS.
    @ViewBuilder
    func appURLKeyboard() -> some View {
#if os(iOS)
        keyboardType(.URL)
#else
        self
#endif
    }
}

private struct BrandBackButtonToolbarModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let label: String

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .appTopBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label(label, systemImage: "chevron.left")
                }
            }
        }
    }
}

extension ToolbarItemPlacement {
    /// Resolves leading top bar placement for each platform.
    static var appTopBarLeading: ToolbarItemPlacement {
#if os(iOS)
        .topBarLeading
#else
        .navigation
#endif
    }

    /// Resolves trailing top bar placement for each platform.
    static var appTopBarTrailing: ToolbarItemPlacement {
#if os(iOS)
        .topBarTrailing
#else
        .primaryAction
#endif
    }
}

/// Cross-platform clipboard helper.
enum BrandClipboard {
    /// Copies a string to the current platform pasteboard.
    static func copy(_ value: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = value
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
#endif
    }
}

//endofline
