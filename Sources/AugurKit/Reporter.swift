@preconcurrency import Foundation

/// Renders an `Assessment` as human-readable terminal text.
public enum Reporter {
    /// Renders the assessment as plain (uncolored) terminal text.
    /// - Parameters:
    ///   - assessment: The assessment to render.
    ///   - verbose: When `true`, list every contributing signal per file.
    /// - Returns: The rendered report.
    public static func render(_ assessment: Assessment, verbose: Bool) -> String {
        render(assessment, verbose: verbose, color: false)
    }

    /// Renders the assessment, optionally applying semantic ANSI colors.
    ///
    /// With `color: false` the output is byte-identical to plain rendering, so
    /// piped / non-TTY contexts stay clean. With `color: true` verdicts, the
    /// risk meter, headers, file paths, and calibration are tinted by meaning.
    /// - Parameters:
    ///   - assessment: The assessment to render.
    ///   - verbose: When `true`, list every contributing signal per file.
    ///   - color: When `true`, emit ANSI color escape codes.
    /// - Returns: The rendered report.
    public static func render(_ assessment: Assessment, verbose: Bool, color: Bool) -> String {
        let c = Colorizer(enabled: color)
        var lines: [String] = []
        let v = assessment.verdict
        let verdictStyle = Palette.style(for: v)
        lines.append(c.apply("augur", Palette.header) + " · " + c.apply(assessment.scope, Palette.secondary))
        lines.append("")
        lines.append(
            "  " + c.apply("verdict", Palette.header) + "     "
                + c.apply(badge(v), verdictStyle) + " "
                + c.apply(v.rawValue.uppercased(), verdictStyle)
        )
        lines.append(
            "  " + c.apply("risk", Palette.header) + "        "
                + bar(assessment.riskScore, colorizer: c) + "  "
                + fmt(assessment.riskScore) + "/100"
        )
        lines.append(
            "  " + c.apply("confidence", Palette.header) + "  "
                + c.apply(fmt(assessment.confidence), Palette.confidence) + "/100"
        )
        lines.append(
            "  " + c.apply("calibration", Palette.header) + " "
                + c.apply(assessment.calibration.band, Palette.confidence)
                + c.apply(
                    " (\(assessment.calibration.incidentCommits) incidents / \(assessment.calibration.totalCommits) commits)",
                    Palette.secondary
                )
        )
        lines.append("")
        lines.append("  " + c.apply("files (\(assessment.files.count)), riskiest first:", Palette.header))
        for file in assessment.files {
            let fileVerdict = file.verdict(thresholds: assessment.thresholds)
            let fileStyle = Palette.style(for: fileVerdict)
            let marker = c.apply(dot(fileVerdict), fileStyle)
            let score = c.apply(fmt(file.riskScore).leftPadded(to: 5), fileStyle)
            lines.append("    " + marker + " " + score + "  " + c.apply(file.path, Palette.path))
            if verbose {
                for signal in file.signals where signal.risk > 0 {
                    lines.append(c.apply("          · \(signal.name): \(signal.detail)", Palette.secondary))
                }
            } else {
                let top = file.signals.filter { $0.risk > 0 }.max(by: { $0.risk * $0.weight < $1.risk * $1.weight })
                if let top {
                    lines.append(c.apply("          · \(top.name): \(top.detail)", Palette.secondary))
                }
            }
        }
        if !assessment.excludedPaths.isEmpty {
            lines.append("")
            lines.append(
                "  " + c.apply(
                    "excluded: \(assessment.excludedPaths.count) file\(assessment.excludedPaths.count == 1 ? "" : "s")",
                    Palette.secondary
                )
            )
        }
        if v != .proceed {
            lines.append("")
            lines.append("  " + c.apply("→ \(advice(v))", verdictStyle))
        }
        return lines.joined(separator: "\n")
    }

    private static func advice(_ verdict: Verdict) -> String {
        switch verdict {
        case .proceed: return "safe to proceed"
        case .review: return "an agent should request human review before merging"
        case .block: return "do not merge without deliberate human sign-off"
        }
    }

    private static func badge(_ verdict: Verdict) -> String {
        switch verdict {
        case .proceed: return "[ok]"
        case .review: return "[!]"
        case .block: return "[x]"
        }
    }

    private static func dot(_ verdict: Verdict) -> String {
        switch verdict {
        case .proceed: return "·"
        case .review: return "!"
        case .block: return "x"
        }
    }

    private static func bar(_ score: Double, colorizer: Colorizer) -> String {
        let width = 20
        let filled = Int((score / 100 * Double(width)).rounded())
        guard colorizer.enabled else {
            return "[" + String(repeating: "#", count: filled) + String(repeating: " ", count: width - filled) + "]"
        }
        let style = Palette.style(for: Verdict.from(riskScore: score))
        let meter = colorizer.apply(String(repeating: "█", count: filled), style)
            + colorizer.apply(String(repeating: "░", count: width - filled), Palette.secondary)
        return "[" + meter + "]"
    }

    private static func fmt(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
