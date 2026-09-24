//
//  LibraryHeaderLayoutDiagnostics.swift
//  QuizFlash
//
//  DEBUG-only, copyable diagnostics for Library header geometry.
//

import SwiftUI

#if DEBUG
import UIKit

// MARK: - Geometry Sample

struct LibraryHeaderGeometrySample {
    let localFrame: CGRect
    let globalFrame: CGRect
}

// MARK: - Diagnostics Store

@MainActor
enum LibraryHeaderLayoutDiagnostics {
    private struct Event {
        let sequence: Int
        let uptime: TimeInterval
        let name: String
        let details: String
    }

    private static let eventLimit = 30
    private static var sessionID = UUID()
    private static var startedAt = Date()
    private static var startedUptime = ProcessInfo.processInfo.systemUptime
    private static var sequence = 0
    private static var events: [Event] = []
    private static var snapshots: [String: [String: LibraryHeaderGeometrySample]] = [:]
    private static var lastProgressBucket: Int?

    static func mode(isSearching: Bool, progress: CGFloat) -> String {
        if !isSearching && progress <= 0.001 {
            return "normal"
        }
        if isSearching && progress >= 0.999 {
            return "search"
        }
        return "transition"
    }

    static func beginIfNeeded(isSearching: Bool, progress: CGFloat) {
        guard events.isEmpty else { return }
        record(
            "session.begin",
            details: stateDetails(isSearching: isSearching, progress: progress)
        )
    }

    static func recordState(
        event: String,
        isSearching: Bool,
        progress: CGFloat,
        isInteractive: Bool,
        isFocused: Bool
    ) {
        let bucket = Int((min(max(progress, 0), 1) * 4).rounded())
        if event == "search.progress", lastProgressBucket == bucket {
            return
        }
        lastProgressBucket = bucket

        record(
            event,
            details: [
                stateDetails(isSearching: isSearching, progress: progress),
                "interactive=\(isInteractive ? 1 : 0)",
                "focused=\(isFocused ? 1 : 0)",
            ].joined(separator: " ")
        )
    }

    static func recordFrame(
        role: String,
        mode: String,
        sample: LibraryHeaderGeometrySample
    ) {
        let previous = snapshots[mode]?[role]
        snapshots[mode, default: [:]][role] = sample

        guard previous == nil || materiallyDiffers(previous!, sample) else { return }
        record(
            "frame.changed",
            details: "mode=\(mode) role=\(role) local={\(frameText(sample.localFrame))} global={\(frameText(sample.globalFrame))}"
        )
    }

    static func recordLifecycle(_ event: String, isSearching: Bool, progress: CGFloat) {
        record(event, details: stateDetails(isSearching: isSearching, progress: progress))
    }

    static func copyReport() {
        record("report.copied", details: "snapshotModes=\(snapshots.keys.sorted().joined(separator: ","))")
        UIPasteboard.general.string = report()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private static func report() -> String {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let safeArea = window?.safeAreaInsets ?? .zero
        let screenScale = window?.screen.scale ?? 0

        var lines: [String] = [
            "QuizFlash Library Header Layout Debug",
            "sessionID: \(sessionID.uuidString)",
            "startedAt: \(timestamp(startedAt))",
            "copiedAt: \(timestamp(Date()))",
            "screenScale: \(decimal(screenScale))",
            "windowBounds: \(frameText(window?.bounds ?? .zero))",
            "safeArea: top=\(decimal(safeArea.top)) left=\(decimal(safeArea.left)) bottom=\(decimal(safeArea.bottom)) right=\(decimal(safeArea.right))",
            "constants: actionButton=\(decimal(UIConstants.Size.actionButton)) capsuleHeight=\(decimal(UIConstants.Size.capsuleHeight)) hitTarget=\(decimal(LibraryTopBarChromeMetrics.expandedHitTargetSize)) horizontalInset=\(decimal(UIConstants.Layout.compactScreenEdgeInset)) topPadding=\(decimal(UIConstants.Layout.deckNavigationTopPadding))",
            "",
            "== Derived Comparisons ==",
        ]

        lines.append(contentsOf: comparisonLines(mode: "normal", leadingRole: "search.circle.surface", trailingRole: "more.circle.surface"))
        lines.append(contentsOf: comparisonLines(mode: "search", leadingRole: "search.field.surface", trailingRole: "close.circle.surface"))

        lines.append("")
        lines.append("== Final Snapshots ==")
        for mode in ["normal", "search", "transition"] {
            guard let modeSnapshots = snapshots[mode], !modeSnapshots.isEmpty else {
                lines.append("[\(mode)] none")
                continue
            }
            lines.append("[\(mode)]")
            for role in modeSnapshots.keys.sorted() {
                guard let sample = modeSnapshots[role] else { continue }
                lines.append("\(role) local={\(frameText(sample.localFrame))} global={\(frameText(sample.globalFrame))}")
            }
        }

        lines.append("")
        lines.append("== Event Timeline (last \(eventLimit)) ==")
        for event in events {
            lines.append("#\(event.sequence) +\(decimal(event.uptime))s \(event.name) \(event.details)")
        }

        return lines.joined(separator: "\n")
    }

    private static func comparisonLines(
        mode: String,
        leadingRole: String,
        trailingRole: String
    ) -> [String] {
        guard
            let chrome = snapshots[mode]?["chrome.container"]?.globalFrame,
            let leading = snapshots[mode]?[leadingRole]?.globalFrame,
            let trailing = snapshots[mode]?[trailingRole]?.globalFrame
        else {
            return ["\(mode): incomplete"]
        }

        return [
            "\(mode): leading=\(leadingRole) trailing=\(trailingRole)",
            "\(mode): sizeDelta width=\(decimal(trailing.width - leading.width)) height=\(decimal(trailing.height - leading.height))",
            "\(mode): positionDelta minY=\(decimal(trailing.minY - leading.minY)) midY=\(decimal(trailing.midY - leading.midY)) maxY=\(decimal(trailing.maxY - leading.maxY))",
            "\(mode): edgeInsets leading=\(decimal(leading.minX - chrome.minX)) trailing=\(decimal(chrome.maxX - trailing.maxX)) delta=\(decimal((chrome.maxX - trailing.maxX) - (leading.minX - chrome.minX)))",
        ]
    }

    private static func record(_ name: String, details: String) {
        sequence += 1
        events.append(
            Event(
                sequence: sequence,
                uptime: ProcessInfo.processInfo.systemUptime - startedUptime,
                name: name,
                details: details
            )
        )
        if events.count > eventLimit {
            events.removeFirst(events.count - eventLimit)
        }
    }

    private static func materiallyDiffers(
        _ lhs: LibraryHeaderGeometrySample,
        _ rhs: LibraryHeaderGeometrySample
    ) -> Bool {
        let values: [(CGFloat, CGFloat)] = [
            (lhs.localFrame.minX, rhs.localFrame.minX),
            (lhs.localFrame.minY, rhs.localFrame.minY),
            (lhs.localFrame.width, rhs.localFrame.width),
            (lhs.localFrame.height, rhs.localFrame.height),
            (lhs.globalFrame.minX, rhs.globalFrame.minX),
            (lhs.globalFrame.minY, rhs.globalFrame.minY),
            (lhs.globalFrame.width, rhs.globalFrame.width),
            (lhs.globalFrame.height, rhs.globalFrame.height),
        ]
        return values.contains { abs($0.0 - $0.1) >= 4 }
    }

    private static func stateDetails(isSearching: Bool, progress: CGFloat) -> String {
        "mode=\(mode(isSearching: isSearching, progress: progress)) isSearching=\(isSearching ? 1 : 0) progress=\(decimal(progress))"
    }

    private static func frameText(_ frame: CGRect) -> String {
        "x=\(decimal(frame.minX)) y=\(decimal(frame.minY)) w=\(decimal(frame.width)) h=\(decimal(frame.height)) midX=\(decimal(frame.midX)) midY=\(decimal(frame.midY)) maxX=\(decimal(frame.maxX)) maxY=\(decimal(frame.maxY))"
    }

    private static func decimal(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    private static func decimal(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

// MARK: - Geometry Probe

extension View {
    func libraryHeaderDebugFrame(role: String, mode: String) -> some View {
        onGeometryChange(for: [CGRect].self) { proxy in
            [
                proxy.frame(in: .named(kLibraryChromeSpace)),
                proxy.frame(in: .global),
            ]
        } action: { frames in
            guard frames.count == 2 else { return }
            LibraryHeaderLayoutDiagnostics.recordFrame(
                role: role,
                mode: mode,
                sample: LibraryHeaderGeometrySample(
                    localFrame: frames[0],
                    globalFrame: frames[1]
                )
            )
        }
    }
}

struct LibraryHeaderDebugSurfaceProbe: View {
    let role: String
    let mode: String
    let size: CGSize

    var body: some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .libraryHeaderDebugFrame(role: role, mode: mode)
            .allowsHitTesting(false)
    }
}

struct LibraryHeaderDebugCopyButton: View {
    var body: some View {
        Button {
            LibraryHeaderLayoutDiagnostics.copyReport()
        } label: {
            Label("Copy Header Debug", systemImage: "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.purple.opacity(0.90), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy Library header debug data")
    }
}
#else
extension View {
    func libraryHeaderDebugFrame(role: String, mode: String) -> some View {
        self
    }
}
#endif

extension LibraryTopBarView {
    var headerDebugMode: String {
#if DEBUG
        LibraryHeaderLayoutDiagnostics.mode(
            isSearching: viewModel.isSearching,
            progress: searchProgress
        )
#else
        ""
#endif
    }
}
