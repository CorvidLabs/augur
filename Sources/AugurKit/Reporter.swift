@preconcurrency import Foundation

/// Renders an `Assessment` as human-readable terminal text.
public enum Reporter {
    public static func render(_ assessment: Assessment, verbose: Bool) -> String {
        var lines: [String] = []
        let v = assessment.verdict
        lines.append("augur · \(assessment.scope)")
        lines.append("")
        lines.append("  verdict     \(badge(v)) \(v.rawValue.uppercased())")
        lines.append("  risk        \(bar(assessment.riskScore))  \(fmt(assessment.riskScore))/100")
        lines.append("  confidence  \(fmt(assessment.confidence))/100")
        lines.append("  calibration \(assessment.calibration.band) (\(assessment.calibration.incidentCommits) incidents / \(assessment.calibration.totalCommits) commits)")
        lines.append("")
        lines.append("  files (\(assessment.files.count)), riskiest first:")
        for file in assessment.files {
            let marker = dot(file.verdict)
            let score = fmt(file.riskScore).leftPadded(to: 5)
            lines.append("    " + marker + " " + score + "  " + file.path)
            if verbose {
                for signal in file.signals where signal.risk > 0 {
                    lines.append("          · \(signal.name): \(signal.detail)")
                }
            } else {
                let top = file.signals.filter { $0.risk > 0 }.max(by: { $0.risk * $0.weight < $1.risk * $1.weight })
                if let top {
                    lines.append("          · \(top.name): \(top.detail)")
                }
            }
        }
        if v != .proceed {
            lines.append("")
            lines.append("  → \(advice(v))")
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

    private static func bar(_ score: Double) -> String {
        let filled = Int((score / 100 * 20).rounded())
        return "[" + String(repeating: "#", count: filled) + String(repeating: " ", count: 20 - filled) + "]"
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
