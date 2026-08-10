//
//  AppLog.swift
//  MeasureGo
//
//  Lightweight session logging for bug reports — port of Unity's
//  LogCapture.cs: a per-session file in Documents/Logs with a device header,
//  an in-memory buffer, and cleanup of old files.
//

import Foundation
import UIKit

enum AppLog {

    private static let maxLogFiles = 10
    private static let maxBufferedLines = 500

    private static let queue = DispatchQueue(label: "com.latham.MeasureGo.applog")
    private static var buffer: [String] = []
    private static var sessionURL: URL?

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static var logsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
    }

    /// Starts a session log file and writes the device header.
    static func startSession() {
        queue.async {
            try? FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)
            cleanupOldLogs()

            let nameFormatter = DateFormatter()
            nameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let url = logsFolder.appendingPathComponent("\(nameFormatter.string(from: Date())).log")
            sessionURL = url

            let header = """
            Logs for session: \(timestampFormatter.string(from: Date()))
            App: \(appVersion)
            Device: \(UIDevice.current.model) (\(deviceIdentifier))
            OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)

            """
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
        log("Session started")
    }

    static func log(_ message: String, file: String = #fileID) {
        let entry = "\(timestampFormatter.string(from: Date())) [\(file)] \(message)"
        queue.async {
            buffer.append(entry)
            if buffer.count > maxBufferedLines {
                buffer.removeFirst(buffer.count - maxBufferedLines)
            }
            guard let sessionURL else { return }
            if let handle = try? FileHandle(forWritingTo: sessionURL) {
                handle.seekToEndOfFile()
                handle.write(Data((entry + "\n").utf8))
                try? handle.close()
            }
        }
        #if DEBUG
        print(entry)
        #endif
    }

    /// Current session log (Unity's GetCurrentLogContent).
    static func currentLogContent() -> String {
        queue.sync { buffer.joined(separator: "\n") }
    }

    /// Contents of the previous session log files (Unity's
    /// GetLatestLogFileContents), newest first.
    static func previousLogContents(limit: Int = 2) -> [String] {
        let current = queue.sync { sessionURL }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: logsFolder, includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "log" && $0 != current }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return l > r
            }
            .prefix(limit)
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    static var appVersion: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MeasureGo"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(name) \(version) (\(build))"
    }

    static var deviceIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private static func cleanupOldLogs() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: logsFolder, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let logs = urls.filter { $0.pathExtension == "log" }.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return l > r
        }
        for url in logs.dropFirst(maxLogFiles - 1) {
            try? fm.removeItem(at: url)
        }
    }
}
