@preconcurrency import Foundation

// MARK: - ANSI

/// ANSI SGR (Select Graphic Rendition) escape codes for terminal styling.
///
/// Pure-Foundation, zero-dependency color helpers: a `Style` carries the raw
/// escape sequences, and `Colorizer` applies them only when enabled (so
/// non-TTY / `NO_COLOR` output stays plain). Codes are emitted as escape
/// strings — nothing here touches a terminal directly.
enum ANSI {
    /// The control sequence introducer ending an SGR reset.
    static let reset = "\u{001B}[0m"

    /// A single SGR styling attribute (a foreground color or a text effect).
    ///
    /// Cases map to standard SGR parameter codes; `code` yields the full escape
    /// prefix so a `Style` can concatenate several attributes into one sequence.
    enum Attribute: Sendable {
        case red
        case green
        case yellow
        case cyan
        case magenta
        case blue
        case white
        case bold
        case dim

        /// The numeric SGR parameter for this attribute.
        var parameter: Int {
            switch self {
            case .bold: return 1
            case .dim: return 2
            case .red: return 31
            case .green: return 32
            case .yellow: return 33
            case .blue: return 34
            case .magenta: return 35
            case .cyan: return 36
            case .white: return 37
            }
        }
    }

    /// A composed set of `Attribute`s rendered as a single SGR escape sequence.
    ///
    /// Combine attributes (for example bold + red) and apply them to text. A
    /// `Style` only produces escape codes; the decision to use them lives in
    /// `Colorizer`.
    struct Style: Sendable {
        private let attributes: [Attribute]

        /// Creates a style from an ordered list of attributes.
        /// - Parameter attributes: The SGR attributes to combine.
        init(_ attributes: [Attribute]) {
            self.attributes = attributes
        }

        /// Creates a style from a variadic list of attributes.
        /// - Parameter attributes: The SGR attributes to combine.
        init(_ attributes: Attribute...) {
            self.attributes = attributes
        }

        /// The opening escape sequence for this style, or `""` when empty.
        var open: String {
            guard !attributes.isEmpty else { return "" }
            let parameters = attributes.map { String($0.parameter) }.joined(separator: ";")
            return "\u{001B}[\(parameters)m"
        }

        /// Wraps `text` in this style's open sequence and a reset.
        /// - Parameter text: The text to style.
        /// - Returns: The styled string with a trailing reset.
        func apply(to text: String) -> String {
            guard !attributes.isEmpty else { return text }
            return open + text + ANSI.reset
        }
    }
}

// MARK: - Palette

/// The semantic color scheme for augur's report — names map intent (a verdict,
/// a risk level, a label) to a concrete `ANSI.Style`, so call sites stay
/// readable and the look is centralized.
enum Palette {
    /// Style for the `proceed` verdict and low-risk elements.
    static let proceed = ANSI.Style(.green)
    /// Style for the `review` verdict and moderate-risk elements.
    static let review = ANSI.Style(.yellow)
    /// Style for the `block` verdict and high-risk elements (bold for weight).
    static let block = ANSI.Style(.bold, .red)
    /// Style for primary headers and emphasized labels.
    static let header = ANSI.Style(.bold)
    /// Style for secondary / detail text (signal details, counts).
    static let secondary = ANSI.Style(.dim)
    /// Style for file paths.
    static let path = ANSI.Style(.cyan)
    /// Style for confidence / calibration figures.
    static let confidence = ANSI.Style(.cyan)

    /// The style for a verdict.
    /// - Parameter verdict: The verdict to color.
    /// - Returns: The matching style.
    static func style(for verdict: Verdict) -> ANSI.Style {
        switch verdict {
        case .proceed: return proceed
        case .review: return review
        case .block: return block
        }
    }
}

// MARK: - Colorizer

/// Applies styles to text only when enabled.
///
/// Construct with `enabled: false` for non-TTY / `NO_COLOR` contexts and every
/// `apply` is an identity no-op, guaranteeing byte-identical plain output.
struct Colorizer: Sendable {
    /// Whether styling is active. When `false`, all styling is a no-op.
    let enabled: Bool

    /// Creates a colorizer.
    /// - Parameter enabled: Whether to emit ANSI codes.
    init(enabled: Bool) {
        self.enabled = enabled
    }

    /// Styles `text` with `style` when enabled, otherwise returns it unchanged.
    /// - Parameters:
    ///   - text: The text to style.
    ///   - style: The style to apply.
    /// - Returns: The styled or plain string.
    func apply(_ text: String, _ style: ANSI.Style) -> String {
        enabled ? style.apply(to: text) : text
    }
}
