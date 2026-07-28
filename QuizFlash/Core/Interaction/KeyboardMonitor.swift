//
//  KeyboardMonitor.swift
//  QuizFlash
//

import Observation
import QuartzCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class KeyboardMonitor {
    static let shared = KeyboardMonitor()

    private(set) var isVisible = false
    private(set) var visibleHeight: CGFloat = 0
    private(set) var animationDuration: TimeInterval = 0.25
    private(set) var animationOptions: UIView.AnimationOptions = [.curveEaseInOut]

    private var observers: [NSObjectProtocol] = []

    private init(notificationCenter: NotificationCenter = .default) {
        let names: [NSNotification.Name] = [
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardDidHideNotification
        ]

        observers = names.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let receivedAt = CACurrentMediaTime()
                let notificationName = notification.name
                let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
                let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
                Task { @MainActor [weak self] in
                    self?.handle(
                        notificationName: notificationName,
                        endFrame: endFrame,
                        animationDuration: duration,
                        animationCurveRaw: curveRaw,
                        receivedAt: receivedAt
                    )
                }
            }
        }
    }

    private func handle(
        notificationName: NSNotification.Name,
        endFrame: CGRect?,
        animationDuration: TimeInterval?,
        animationCurveRaw: Int?,
        receivedAt: CFTimeInterval
    ) {
#if DEBUG
        SheetKeyboardDebugTrace.recordForActive(
            event: "keyboard.notification.handle",
            details: [
                "name": notificationName.rawValue,
                "dispatchDelayMs": debugMilliseconds(CACurrentMediaTime() - receivedAt),
                "duration": debugTimeInterval(animationDuration),
                "curve": animationCurveRaw.map(String.init) ?? "nil",
                "endFrame": debugKeyboardFrame(endFrame),
                "previousVisible": String(isVisible),
                "previousHeight": debugKeyboardValue(visibleHeight)
            ]
        )
#endif

        if let animationDuration {
            self.animationDuration = animationDuration
        }
        if let animationCurveRaw {
            self.animationOptions = UIView.AnimationOptions(rawValue: UInt(animationCurveRaw << 16))
        }

        if notificationName == UIResponder.keyboardWillHideNotification
            || notificationName == UIResponder.keyboardDidHideNotification {
            isVisible = false
            visibleHeight = 0
#if DEBUG
            SheetKeyboardDebugTrace.recordForActive(
                event: "keyboard.state.applied",
                details: [
                    "name": notificationName.rawValue,
                    "visible": String(isVisible),
                    "height": debugKeyboardValue(visibleHeight),
                    "duration": debugTimeInterval(self.animationDuration),
                    "optionsRaw": String(self.animationOptions.rawValue)
                ]
            )
#endif
            return
        }

        guard let endFrame else {
#if DEBUG
            SheetKeyboardDebugTrace.recordForActive(
                event: "keyboard.notification.rejected",
                details: [
                    "name": notificationName.rawValue,
                    "reason": "missing-end-frame"
                ]
            )
#endif
            return
        }
        let window = activeKeyWindow()
        let screenBounds = window?.bounds ?? UIScreen.main.bounds
        let convertedFrame = window?.convert(endFrame, from: nil) ?? endFrame
        let intersection = screenBounds.intersection(convertedFrame)
        let safeBottom = window?.safeAreaInsets.bottom ?? 0
        let height = max(0, intersection.height - safeBottom)

        visibleHeight = height
        isVisible = height > 0

#if DEBUG
        SheetKeyboardDebugTrace.recordForActive(
            event: "keyboard.state.applied",
            details: [
                "name": notificationName.rawValue,
                "visible": String(isVisible),
                "height": debugKeyboardValue(visibleHeight),
                "safeBottom": debugKeyboardValue(safeBottom),
                "intersection": debugKeyboardFrame(intersection),
                "duration": debugTimeInterval(self.animationDuration),
                "optionsRaw": String(self.animationOptions.rawValue)
            ]
        )
#endif
    }

    private func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

#if DEBUG
/// Bounded, copyable timeline for diagnosing custom-sheet keyboard transitions.
///
/// Every line starts with `QF_SHEET_`, allowing the runtime tester to copy one
/// filtered console stream without unrelated application output.
@MainActor
enum SheetKeyboardDebugTrace {
    private struct Session {
        let id: String
        let startedAt: CFTimeInterval
        var sequence = 0
        var bufferedEvents: [String] = []
    }

    private static let maximumBufferedEvents = 30
    private static var sessions: [String: Session] = [:]

    static func begin(
        identifier: String,
        details: [String: String] = [:]
    ) {
        sessions[identifier] = Session(
            id: String(UUID().uuidString.prefix(8)),
            startedAt: CACurrentMediaTime()
        )
        record(
            identifier: identifier,
            event: "session.begin",
            details: details
        )
    }

    static func isActive(identifier: String) -> Bool {
        sessions[identifier] != nil
    }

    static func recordForActive(
        event: String,
        details: [String: String] = [:],
        buffered: Bool = true
    ) {
        for identifier in sessions.keys.sorted() {
            record(
                identifier: identifier,
                event: event,
                details: details,
                buffered: buffered
            )
        }
    }

    static func record(
        identifier: String,
        event: String,
        details: [String: String] = [:],
        buffered: Bool = true
    ) {
        guard var session = sessions[identifier] else { return }

        session.sequence += 1
        let detailText = details
            .map { key, value in "\(sanitize(key))=\(sanitize(value))" }
            .sorted()
            .joined(separator: " ")
        let suffix = detailText.isEmpty ? "" : " \(detailText)"
        let line = [
            "QF_SHEET_TRACE",
            "sheet=\(sanitize(identifier))",
            "session=\(session.id)",
            "seq=\(session.sequence)",
            "time=\(String(format: "%.3f", Date().timeIntervalSince1970))",
            "elapsedMs=\(debugMilliseconds(CACurrentMediaTime() - session.startedAt))",
            "main=\(Thread.isMainThread)",
            "event=\(sanitize(event))\(suffix)"
        ].joined(separator: " ")

        if buffered {
            session.bufferedEvents.append(line)
            if session.bufferedEvents.count > maximumBufferedEvents {
                session.bufferedEvents.removeFirst(
                    session.bufferedEvents.count - maximumBufferedEvents
                )
            }
        }

        sessions[identifier] = session
        print(line)
    }

    static func end(identifier: String) {
        guard sessions[identifier] != nil else { return }
        record(identifier: identifier, event: "session.end")
        guard let session = sessions.removeValue(forKey: identifier) else { return }

        print("QF_SHEET_EXPORT_BEGIN sheet=\(sanitize(identifier)) session=\(session.id)")
        session.bufferedEvents.forEach { print($0) }
        print("QF_SHEET_EXPORT_END sheet=\(sanitize(identifier)) session=\(session.id)")
    }

    private static func sanitize(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: " ", with: "_")
        return String(singleLine.prefix(900))
    }
}

private func debugKeyboardFrame(_ frame: CGRect?) -> String {
    guard let frame else { return "nil" }
    return [
        "x:\(debugKeyboardValue(frame.minX))",
        "y:\(debugKeyboardValue(frame.minY))",
        "w:\(debugKeyboardValue(frame.width))",
        "h:\(debugKeyboardValue(frame.height))"
    ].joined(separator: ",")
}

private func debugKeyboardValue(_ value: CGFloat) -> String {
    String(format: "%.2f", value)
}

private func debugTimeInterval(_ value: TimeInterval?) -> String {
    value.map { String(format: "%.3f", $0) } ?? "nil"
}

private func debugMilliseconds(_ value: CFTimeInterval) -> String {
    String(format: "%.2f", value * 1_000)
}
#endif
