//
//  CrashReporter.swift
//  MeasureGo
//
//  Crash capture without a third-party SDK.
//
//  Three complementary sources, because no single one catches everything:
//   1. MetricKit — Apple's own symbolicated crash diagnostics, delivered on a
//      later launch. The highest-quality signal, and it costs us nothing.
//   2. Uncaught Objective-C exceptions — caught in-process and written
//      immediately, so a crash is recorded even before MetricKit reports it.
//   3. Unclean-shutdown detection — a flag that survives the crash, so the
//      next launch knows the last session ended abnormally even when neither
//      of the above produced a report (Swift traps, out-of-memory kills).
//
//  Reports stay on the device. They only ever leave it if the user attaches
//  them to a feedback email themselves, so this adds no automatic data
//  collection and needs no privacy-manifest change.
//

import Foundation
import MetricKit

final class CrashReporter: NSObject, MXMetricManagerSubscriber {

    static let shared = CrashReporter()

    private let uncleanShutdownKey = "measurego_session_running"
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    /// True when the previous session ended without a clean shutdown.
    private(set) var previousSessionCrashed = false

    private var crashesFolder: URL { AppLog.logsFolder }

    // MARK: - Lifecycle

    func start() {
        MXMetricManager.shared.add(self)
        installExceptionHandler()
        detectUncleanShutdown()
        // Mark the session as running; cleared when we background or terminate.
        UserDefaults.standard.set(true, forKey: uncleanShutdownKey)
    }

    /// Call when the app backgrounds or terminates normally.
    func markCleanShutdown() {
        UserDefaults.standard.set(false, forKey: uncleanShutdownKey)
    }

    /// Call when the app becomes active again.
    func markSessionRunning() {
        UserDefaults.standard.set(true, forKey: uncleanShutdownKey)
    }

    private func detectUncleanShutdown() {
        // Only meaningful after a first run has recorded the key.
        guard UserDefaults.standard.object(forKey: uncleanShutdownKey) != nil else { return }
        previousSessionCrashed = UserDefaults.standard.bool(forKey: uncleanShutdownKey)
        if previousSessionCrashed {
            AppLog.log("Previous session ended unexpectedly (crash, or terminated while in use)")
        }
    }

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let text = """
            Uncaught exception
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            App: \(AppLog.appVersion)
            Device: \(AppLog.deviceIdentifier)

            Call stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            CrashReporter.shared.write(report: text, prefix: "exception")
        }
    }

    // MARK: - MetricKit

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Performance metrics — not used, but the protocol requires this.
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let crashes = payload.crashDiagnostics, !crashes.isEmpty else { continue }
            for crash in crashes {
                let meta = crash.metaData
                let text = """
                MetricKit crash diagnostic
                App version: \(meta.applicationBuildVersion)
                OS: \(meta.osVersion)
                Device: \(meta.deviceType)
                Exception type: \(crash.exceptionType?.stringValue ?? "n/a")
                Exception code: \(crash.exceptionCode?.stringValue ?? "n/a")
                Signal: \(crash.signal?.stringValue ?? "n/a")
                Termination reason: \(crash.terminationReason ?? "n/a")

                Call stack:
                \(String(data: crash.callStackTree.jsonRepresentation(), encoding: .utf8) ?? "unavailable")
                """
                write(report: text, prefix: "crash")
            }
            AppLog.log("Received \(crashes.count) crash diagnostic(s) from MetricKit")
        }
    }

    // MARK: - Storage

    private func write(report: String, prefix: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: crashesFolder, withIntermediateDirectories: true)
        let url = crashesFolder
            .appendingPathComponent("\(prefix)-\(dateFormatter.string(from: Date())).crash")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    private var reportURLs: [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: crashesFolder, includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "crash" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return l > r
            }
    }

    var pendingReportCount: Int { reportURLs.count }

    /// Newest reports, for attaching to a feedback email.
    func pendingReportsText(limit: Int = 3) -> String {
        reportURLs
            .prefix(limit)
            .compactMap { url -> String? in
                guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return "----- \(url.lastPathComponent) -----\n\(body)"
            }
            .joined(separator: "\n\n")
    }

    /// Called once the user has sent (or dismissed) the reports.
    func clearReports() {
        for url in reportURLs {
            try? FileManager.default.removeItem(at: url)
        }
        previousSessionCrashed = false
    }
}
