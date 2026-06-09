@preconcurrency import Foundation

/// Renders an `Assessment` as GitHub-flavored markdown for PR-level visibility.
///
/// The output is designed to be dropped into a GitHub Actions job summary or a
/// sticky pull-request comment: a verdict heading, a confidence/calibration
/// line, a per-file risk table (riskiest first), and a trailing hidden marker
/// comment (`<!-- augur-report -->`) a CI job can grep for to update a sticky
/// comment in place. Output is deterministic: no `Date()` or randomness feeds it,
/// so identical assessments render byte-identical markdown.
public enum MarkdownReporter: Sendable {
    /// The hidden HTML comment marker a CI job greps for to find and update the
    /// sticky pull-request comment in place.
    public static let marker = "<!-- augur-report -->"

    /// The maximum number of file rows rendered in the table before collapsing
    /// the remainder into a single "and N more" line.
    public static let maxRows = 25

    /// Renders the assessment as GitHub-flavored markdown.
    ///
    /// The result contains a verdict heading, a confidence/calibration line, a
    /// risk table (riskiest first, capped at ``maxRows`` rows with an overflow
    /// note), and a trailing ``marker`` line.
    /// - Parameter assessment: The assessment to render.
    /// - Returns: The markdown report.
    public static func render(_ assessment: Assessment) -> String {
        var lines: [String] = []
        let verdict = assessment.verdict
        let risk = fmt(assessment.riskScore)
        lines.append(
            "### augur: \(emoji(verdict)) \(verdict.rawValue.uppercased()) - risk \(risk)/100"
        )
        lines.append("")
        let confidence = fmt(assessment.confidence)
        let calibration = assessment.calibration
        lines.append(
            "Confidence \(confidence)/100 - calibration \(calibration.band) "
                + "(\(calibration.incidentCommits) incidents / \(calibration.totalCommits) commits)."
        )
        lines.append("")

        let ranked = assessment.files.sorted { lhs, rhs in
            if lhs.riskScore != rhs.riskScore { return lhs.riskScore > rhs.riskScore }
            return lhs.path < rhs.path
        }
        lines.append("| File | Risk | Verdict | Top signal |")
        lines.append("| --- | ---: | --- | --- |")
        for file in ranked.prefix(maxRows) {
            let fileVerdict = file.verdict(thresholds: assessment.thresholds)
            lines.append(
                "| `\(escapeCell(file.path))` | \(fmt(file.riskScore)) "
                    + "| \(emoji(fileVerdict)) \(fileVerdict.rawValue) "
                    + "| \(escapeCell(topSignal(file))) |"
            )
        }
        if ranked.count > maxRows {
            let remaining = ranked.count - maxRows
            lines.append("")
            lines.append("and \(remaining) more file\(remaining == 1 ? "" : "s").")
        }
        lines.append("")
        lines.append(marker)
        return lines.joined(separator: "\n")
    }

    // MARK: - Private Methods

    /// The highest-weighted contributing signal's detail for a file, or a dash
    /// when no signal contributes risk.
    private static func topSignal(_ file: FileAssessment) -> String {
        let top = file.signals
            .filter { $0.risk > 0 }
            .max(by: { $0.risk * $0.weight < $1.risk * $1.weight })
        guard let top else { return "-" }
        return "\(top.name): \(top.detail)"
    }

    /// A small emoji badge per verdict (no em-dashes anywhere in output).
    private static func emoji(_ verdict: Verdict) -> String {
        switch verdict {
        case .proceed: return "✅"
        case .review: return "⚠️"
        case .block: return "⛔"
        }
    }

    /// Escapes characters that would break a markdown table cell.
    private static func escapeCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Rounds a 0...100 score to a whole-number string.
    private static func fmt(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
