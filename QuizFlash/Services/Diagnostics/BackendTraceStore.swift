//
//  BackendTraceStore.swift
//  QuizFlash
//
//  Persistent diagnostics for Firebase and backend communication.
//

import Foundation

// MARK: - Backend Trace Store

actor BackendTraceStore {
    static let shared = BackendTraceStore()

    private static let maxEvents = 300
    private let storageKey = "diagnostics.backendTrace.events"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func record(
        _ event: String,
        layer: String,
        details: [String: String] = [:]
    ) {
        var events = loadEvents()
        let nextSequence = (events.last?.sequence ?? 0) + 1
        events.append(
            BackendTraceEvent(
                sequence: nextSequence,
                date: Date(),
                layer: sanitize(layer),
                event: sanitize(event),
                detail: detailString(from: details)
            )
        )

        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }

        persist(events)
    }

    func clear() {
        userDefaults.removeObject(forKey: storageKey)
    }

    func eventCount() -> Int {
        loadEvents().count
    }

    func report() -> String {
        let events = loadEvents()
        var lines = [
            "QuizFlash Backend Trace",
            "generatedAt=\(format(Date()))",
            "eventCount=\(events.count)",
            "bundle=\(Bundle.main.bundleIdentifier ?? "<unknown>")",
            "appVersion=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "<unknown>")",
            "build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "<unknown>")",
            ""
        ]

        if events.isEmpty {
            lines.append("<no backend events recorded>")
        } else {
            lines.append("Decision tree:")
            lines.append("- no auth/bootstrap/listener events: app session did not start backend sync")
            lines.append("- listener count is 0: backend path has no visible documents for this UID")
            lines.append("- remote documents exist but import is skipped/rejected: local import decision owns the issue")
            lines.append("- quota response is 0: proxy/Firestore account state owns the usage issue")
            lines.append("- quota response is non-zero but Settings shows 0: SubscriptionManager/UI owns the issue")
            lines.append("")
            lines.append("Events:")
            lines.append(contentsOf: events.map { event in
                let detail = event.detail.isEmpty ? "" : " \(event.detail)"
                return "#\(event.sequence) \(format(event.date)) [\(event.layer)] \(event.event)\(detail)"
            })
        }

        return lines.joined(separator: "\n")
    }

    nonisolated static func safeUID(_ uid: String?) -> String {
        guard let uid, !uid.isEmpty else { return "<none>" }
        return "...\(uid.suffix(6))"
    }

    private func loadEvents() -> [BackendTraceEvent] {
        guard let data = userDefaults.data(forKey: storageKey),
              let events = try? decoder.decode([BackendTraceEvent].self, from: data) else {
            return []
        }
        return events
    }

    private func persist(_ events: [BackendTraceEvent]) {
        guard let data = try? encoder.encode(events) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func detailString(from details: [String: String]) -> String {
        details
            .map { key, value in
                (sanitizeKey(key), sanitizeValue(value, forKey: key))
            }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: " ")
    }

    private func sanitizeKey(_ key: String) -> String {
        sanitize(key.replacingOccurrences(of: " ", with: "_"))
    }

    private func sanitizeValue(_ value: String, forKey key: String) -> String {
        let loweredKey = key.lowercased()
        if loweredKey.contains("token")
            || loweredKey.contains("authorization")
            || loweredKey.contains("password")
            || loweredKey.contains("secret")
            || loweredKey.contains("apikey")
            || loweredKey == "email" {
            return "<redacted>"
        }

        return sanitize(value)
    }

    private func sanitize(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        guard singleLine.count > 180 else { return singleLine }
        return "\(singleLine.prefix(180))..."
    }

    private func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct BackendTraceEvent: Codable {
    let sequence: Int
    let date: Date
    let layer: String
    let event: String
    let detail: String
}
