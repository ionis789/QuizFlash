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

    private static let maxSessions = 24
    private static let maxEventsPerSession = 300
    private let storageKey = "diagnostics.backendTrace.sessions"
    private let legacyEventsStorageKey = "diagnostics.backendTrace.events"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var currentSessionID = UUID()

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
        var sessions = loadSessions()
        let now = Date()
        let sessionIndex = sessions.firstIndex { $0.id == currentSessionID }
        if sessionIndex == nil {
            sessions.append(
                BackendTraceSession(
                    id: currentSessionID,
                    startedAt: now,
                    updatedAt: now,
                    events: []
                )
            )
        }

        guard let index = sessions.firstIndex(where: { $0.id == currentSessionID }) else { return }
        var session = sessions[index]
        let nextSequence = (session.events.last?.sequence ?? 0) + 1
        session.events.append(
            BackendTraceEvent(
                sequence: nextSequence,
                date: now,
                layer: sanitize(layer),
                event: sanitize(event),
                detail: detailString(from: details)
            )
        )
        session.updatedAt = now

        if session.events.count > Self.maxEventsPerSession {
            session.events.removeFirst(session.events.count - Self.maxEventsPerSession)
        }

        sessions[index] = session
        sessions.sort { $0.startedAt < $1.startedAt }
        if sessions.count > Self.maxSessions {
            sessions.removeFirst(sessions.count - Self.maxSessions)
        }

        persist(sessions)
    }

    func clear() {
        userDefaults.removeObject(forKey: storageKey)
        userDefaults.removeObject(forKey: legacyEventsStorageKey)
        currentSessionID = UUID()
    }

    func eventCount() -> Int {
        loadSessions().reduce(0) { $0 + $1.events.count }
    }

    func sessionSummaries() -> [BackendTraceSessionSummary] {
        loadSessions()
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { session in
                BackendTraceSessionSummary(
                    id: session.id,
                    startedAt: session.startedAt,
                    updatedAt: session.updatedAt,
                    eventCount: session.events.count,
                    isCurrent: session.id == currentSessionID
                )
            }
    }

    func report() -> String {
        report(sessionID: nil)
    }

    func report(sessionID: UUID?) -> String {
        let sessions = loadSessions()
        let session = sessionID
            .flatMap { id in sessions.first { $0.id == id } }
            ?? sessions.first { $0.id == currentSessionID }
            ?? sessions.sorted { $0.updatedAt > $1.updatedAt }.first
        let events = session?.events ?? []
        var lines = [
            "QuizFlash Backend Trace",
            "generatedAt=\(format(Date()))",
            "sessionID=\(session?.id.uuidString ?? "<none>")",
            "sessionStartedAt=\(session.map { format($0.startedAt) } ?? "<none>")",
            "sessionUpdatedAt=\(session.map { format($0.updatedAt) } ?? "<none>")",
            "sessionEventCount=\(events.count)",
            "totalSessions=\(sessions.count)",
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

    private func loadSessions() -> [BackendTraceSession] {
        guard let data = userDefaults.data(forKey: storageKey),
              let sessions = try? decoder.decode([BackendTraceSession].self, from: data) else {
            return []
        }
        return sessions
    }

    private func persist(_ sessions: [BackendTraceSession]) {
        guard let data = try? encoder.encode(sessions) else { return }
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

struct BackendTraceSessionSummary: Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    let updatedAt: Date
    let eventCount: Int
    let isCurrent: Bool
}

private struct BackendTraceSession: Codable {
    let id: UUID
    let startedAt: Date
    var updatedAt: Date
    var events: [BackendTraceEvent]
}

private struct BackendTraceEvent: Codable {
    let sequence: Int
    let date: Date
    let layer: String
    let event: String
    let detail: String
}
