import SwiftUI
import UIKit

/// Makes the board look like part of your app. Pass your own colors (asset-catalog colors resolve
/// for light and dark automatically); the board receives them before it draws, so it never flashes
/// its default theme.
public struct FeatureBoardAppearance: Sendable {
    /// Behind everything. `.clear` lets your own background (a gradient, say) show through.
    public var background: Color
    /// Cards: requests, the form, comments.
    public var surface: Color
    /// Search field, inputs, the sort control and unvoted vote buttons.
    public var field: Color
    public var text: Color
    public var secondaryText: Color
    public var separator: Color
    /// Filled buttons, your votes and focus rings.
    public var accent: Color
    public var onAccent: Color
    /// A darker edge under filled buttons, for raised, 3D-looking buttons. nil draws none.
    public var accentEdge: Color?
    /// A hairline around cards, for example only in dark mode (use a color that is clear in light). nil draws none.
    public var cardOutline: Color?
    public var cornerRadius: CGFloat
    /// The rounded system font (SF Pro Rounded), like `.fontDesign(.rounded)`.
    public var roundedFont: Bool
    /// The board's name above its title. Inside your app it usually repeats what the screen already says.
    public var showsBoardName: Bool

    public init(
        background: Color = Color(uiColor: .systemGroupedBackground),
        surface: Color = Color(uiColor: .secondarySystemGroupedBackground),
        field: Color = Color(uiColor: .tertiarySystemFill),
        text: Color = Color(uiColor: .label),
        secondaryText: Color = Color(uiColor: .secondaryLabel),
        separator: Color = Color(uiColor: .separator),
        accent: Color = .accentColor,
        onAccent: Color = .white,
        accentEdge: Color? = nil,
        cardOutline: Color? = nil,
        cornerRadius: CGFloat = 16,
        roundedFont: Bool = false,
        showsBoardName: Bool = false
    ) {
        self.background = background
        self.surface = surface
        self.field = field
        self.text = text
        self.secondaryText = secondaryText
        self.separator = separator
        self.accent = accent
        self.onAccent = onAccent
        self.accentEdge = accentEdge
        self.cardOutline = cardOutline
        self.cornerRadius = cornerRadius
        self.roundedFont = roundedFont
        self.showsBoardName = showsBoardName
    }

    /// What the page reads as `window.FeatureBoardAppearance`: hex colors only, for both schemes.
    func json() -> String? {
        func palette(_ style: UIUserInterfaceStyle) -> [String: String] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            var colors = [
                "background": hex(background, traits), "surface": hex(surface, traits), "field": hex(field, traits),
                "text": hex(text, traits), "muted": hex(secondaryText, traits), "line": hex(separator, traits),
                "accent": hex(accent, traits), "onAccent": hex(onAccent, traits),
            ]
            if let accentEdge { colors["accentEdge"] = hex(accentEdge, traits) }
            if let cardOutline { colors["outline"] = hex(cardOutline, traits) }
            return colors
        }
        let value: [String: Any] = [
            "light": palette(.light), "dark": palette(.dark),
            "cornerRadius": Double(min(max(cornerRadius, 0), 40)),
            "font": roundedFont ? "rounded" : "system",
            "showBoardName": showsBoardName,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func hex(_ color: Color, _ traits: UITraitCollection) -> String {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "transparent" }
        if alpha <= 0.001 { return "transparent" }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let rgb = String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
        return alpha >= 0.999 ? rgb : rgb + String(format: "%02x", byte(alpha))
    }
}
