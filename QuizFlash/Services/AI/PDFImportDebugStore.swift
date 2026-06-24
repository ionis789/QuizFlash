//
//  PDFImportDebugStore.swift
//  QuizFlash
//
//  Persistent diagnostics for PDF picker/import flows in constrained runtimes.
//

import Foundation

nonisolated enum PDFImportDebugStore {
    private static let storageKey = "diagnostics.pdfImport.events"
    private static let maxEvents = 140

    private struct Event: Codable {
        let sequence: Int
        let date: Date
        let stage: String
        let detail: String
    }

    static func record(_ stage: String, details: [String: String] = [:]) {
        var events = loadEvents()
        let nextSequence = (events.last?.sequence ?? 0) + 1
        let detail = details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        events.append(
            Event(
                sequence: nextSequence,
                date: Date(),
                stage: stage,
                detail: detail
            )
        )

        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }

        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static func report() -> String {
        let events = loadEvents()
        var lines = [
            "QuizFlash PDF Import Debug",
            "generatedAt=\(format(Date()))",
            "eventCount=\(events.count)",
            "bundle=\(Bundle.main.bundleIdentifier ?? "<unknown>")",
            "appVersion=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "<unknown>")",
            "build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "<unknown>")",
            "documentsDirectory=\(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "<none>")",
            "applicationSupportDirectory=\(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? "<none>")",
            ""
        ]

        if events.isEmpty {
            lines.append("<no pdf import events recorded>")
        } else {
            lines.append("Events:")
            lines.append(contentsOf: events.map { event in
                let detail = event.detail.isEmpty ? "" : " \(event.detail)"
                return "#\(event.sequence) \(format(event.date)) \(event.stage)\(detail)"
            })
        }

        return lines.joined(separator: "\n")
    }

    static func eventCount() -> Int {
        loadEvents().count
    }

    private static func loadEvents() -> [Event] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([Event].self, from: data) else {
            return []
        }
        return events
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
