import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Centralized typography tokens for module search results.
enum BrandSearchResultTypography {
    /// Global scale factor for search results text.
    static let multiplier: CGFloat = 1.22

    static func headline(weight: Font.Weight = .semibold) -> Font {
        scaledFont(token: .headline, weight: weight)
    }

    static func subheadline(weight: Font.Weight = .regular) -> Font {
        scaledFont(token: .subheadline, weight: weight)
    }

    static func caption(weight: Font.Weight = .regular) -> Font {
        scaledFont(token: .caption, weight: weight)
    }

    static func caption2(weight: Font.Weight = .regular) -> Font {
        scaledFont(token: .caption2, weight: weight)
    }

    static func title3(weight: Font.Weight = .regular) -> Font {
        scaledFont(token: .title3, weight: weight)
    }

    private enum Token {
        case headline
        case subheadline
        case caption
        case caption2
        case title3
    }

    private static func scaledFont(token: Token, weight: Font.Weight) -> Font {
        let baseSize = basePointSize(for: token)
        return .system(size: baseSize * multiplier, weight: weight, design: .rounded)
    }

    private static func basePointSize(for token: Token) -> CGFloat {
#if canImport(UIKit)
        switch token {
        case .headline:
            UIFont.preferredFont(forTextStyle: .headline).pointSize
        case .subheadline:
            UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        case .caption:
            UIFont.preferredFont(forTextStyle: .caption1).pointSize
        case .caption2:
            UIFont.preferredFont(forTextStyle: .caption2).pointSize
        case .title3:
            UIFont.preferredFont(forTextStyle: .title3).pointSize
        }
#else
        switch token {
        case .headline:
            17
        case .subheadline:
            15
        case .caption:
            12
        case .caption2:
            11
        case .title3:
            20
        }
#endif
    }
}

//endofline
