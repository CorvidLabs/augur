@preconcurrency import Foundation
import XCTest

// MARK: - Snapshot Harness

/// A tiny, dependency-free golden-file snapshot harness.
///
/// Golden files live in `__snapshots__/<name>.snap` resolved *relative to this
/// test source file* (via `#filePath`), so they are found regardless of the
/// process working directory. The harness has two modes:
///
/// - **Record**: when the golden file is missing, or when the `RECORD_SNAPSHOTS`
///   environment variable is set, the `actual` string is written to disk and the
///   test fails with `recorded snapshot <name>` — a record run is never a silent
///   pass, so a forgotten golden surfaces immediately in CI.
/// - **Assert**: otherwise the golden is read and compared byte-for-byte against
///   `actual`, with a diff-friendly failure message on mismatch.
///
/// This intentionally avoids any third-party package (e.g. swift-snapshot-testing)
/// to keep the test target dependency-free.
enum Snapshot {
    /// The directory holding the golden `.snap` files, resolved relative to this
    /// source file so it is independent of the working directory.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__snapshots__", isDirectory: true)
    }

    /// Whether the harness is in record mode for every snapshot.
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil
    }
}

/// Asserts that `actual` matches the golden snapshot named `name`.
///
/// Records the golden (and fails) when it is missing or when `RECORD_SNAPSHOTS`
/// is set; otherwise compares `actual` against the stored golden.
/// - Parameters:
///   - actual: The freshly rendered string to lock or compare.
///   - name: The snapshot name; the golden lives at `__snapshots__/<name>.snap`.
///   - file: The call-site file, for failure attribution.
///   - line: The call-site line, for failure attribution.
func assertSnapshot(
    _ actual: String,
    _ name: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let url = Snapshot.directory.appendingPathComponent("\(name).snap")
    let exists = FileManager.default.fileExists(atPath: url.path)

    if Snapshot.isRecording || !exists {
        do {
            try FileManager.default.createDirectory(
                at: Snapshot.directory,
                withIntermediateDirectories: true
            )
            try actual.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("failed to record snapshot \(name): \(error)", file: file, line: line)
            return
        }
        XCTFail(
            "recorded snapshot \(name) — re-run without RECORD_SNAPSHOTS to assert it",
            file: file,
            line: line
        )
        return
    }

    let expected: String
    do {
        expected = try String(contentsOf: url, encoding: .utf8)
    } catch {
        XCTFail("failed to read snapshot \(name): \(error)", file: file, line: line)
        return
    }

    XCTAssertEqual(
        actual,
        expected,
        """
        snapshot \(name) did not match the golden at \(url.path).
        If this change is intentional, re-record with RECORD_SNAPSHOTS=1 swift test.
        """,
        file: file,
        line: line
    )
}
