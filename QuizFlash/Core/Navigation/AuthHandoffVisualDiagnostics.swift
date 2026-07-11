//
//  AuthHandoffVisualDiagnostics.swift
//  QuizFlash
//
//  DEBUG-only diagnostics for the rendered handoff from authentication to Home.
//

import SwiftUI

#if DEBUG
import QuartzCore
import UIKit
#endif

// MARK: - Visual Handoff Timeline

/// Records the UIKit, SwiftUI-hosting, Core Animation, and display-link state around the
/// authenticated root swap. The diagnostics are intentionally inert in release builds.
@MainActor
enum AuthHandoffVisualDiagnostics {
#if DEBUG
    private static var registeredProbes: [String: WeakAuthHandoffProbe] = [:]
#endif

    static func beginRootReleaseMonitoring(handoffID: UUID) {
#if DEBUG
        AuthHandoffDisplayLinkMonitor.shared.start(
            handoffID: handoffID,
            authAttemptID: AuthFlowDebugTrace.currentAttemptID
        )
        AuthFlowDebugTrace.record(
            "root-release.monitor.started",
            layer: "visual-handoff",
            details: ["handoff": handoffID.uuidString]
        )
#endif
    }

    static func schedulePostReleaseCheckpoints(handoffID: UUID) {
#if DEBUG
        for delayMilliseconds in [250, 1_000] {
            Task { @MainActor in
                if delayMilliseconds > 0 {
                    do {
                        try await Task.sleep(for: .milliseconds(delayMilliseconds))
                    } catch {
                        return
                    }
                }

                if delayMilliseconds == 250 {
                    recordLightweightCheckpoint(
                        "root-release.checkpoint.250ms",
                        expectedRoot: "main",
                        details: ["handoff": handoffID.uuidString]
                    )
                } else {
                    recordCheckpoint(
                        "root-release.checkpoint.1000ms",
                        expectedRoot: "main",
                        details: ["handoff": handoffID.uuidString]
                    )
                }
            }
        }
#endif
    }

    private static func recordLightweightCheckpoint(
        _ event: String,
        expectedRoot: String,
        details additionalDetails: [String: String]
    ) {
#if DEBUG
        var details = additionalDetails
        details["expectedRoot"] = expectedRoot
        details["applicationState"] = String(describing: UIApplication.shared.applicationState)
        details["runLoopMode"] = RunLoop.current.currentMode?.rawValue ?? "none"
        details["scenes"] = sceneSummary()
        details["window"] = diagnosticWindow().map(windowSummary) ?? "none"
        AuthFlowDebugTrace.record(event, layer: "visual-handoff", details: details)
#endif
    }

    static func recordCheckpoint(
        _ event: String,
        expectedRoot: String,
        details additionalDetails: [String: String] = [:]
    ) {
#if DEBUG
        var details = additionalDetails
        details["expectedRoot"] = expectedRoot
        details["applicationState"] = String(describing: UIApplication.shared.applicationState)
        details["runLoopMode"] = RunLoop.current.currentMode?.rawValue ?? "none"
        details["scenes"] = sceneSummary()

        if let window = diagnosticWindow() {
            details["window"] = windowSummary(window)
            appendChunked(
                viewControllerTree(from: window.rootViewController),
                prefix: "controllers",
                into: &details
            )
            appendChunked(centerHitChain(in: window), prefix: "hitChain", into: &details)
            appendChunked(viewTree(from: window), prefix: "viewTree", into: &details)
            appendChunked(layerTree(from: window.layer), prefix: "layerTree", into: &details)
            let candidates = renderedCandidates(in: window)
            appendChunked(candidates.fullScreen, prefix: "fullScreenViews", into: &details)
            appendChunked(candidates.transitions, prefix: "transitionViews", into: &details)
        } else {
            details["window"] = "none"
        }

        AuthFlowDebugTrace.record(
            event,
            layer: "visual-handoff",
            details: details
        )
#endif
    }

    static func snapshotProbe(
        role: String,
        event: String,
        details: [String: String] = [:]
    ) {
#if DEBUG
        guard let probe = registeredProbes[role]?.value else {
            AuthFlowDebugTrace.record(
                "probe.snapshot.missing",
                layer: "render-probe",
                details: details.merging(["role": role, "requestedEvent": event]) { current, _ in current }
            )
            return
        }
        probe.record(
            event,
            includesPresentationChain: true,
            extra: details
        )
#endif
    }

#if DEBUG
    fileprivate static func registerProbe(_ probe: AuthHandoffProbeView, role: String) {
        registeredProbes[role] = WeakAuthHandoffProbe(probe)
    }

    fileprivate static func unregisterProbe(_ probe: AuthHandoffProbeView, role: String) {
        guard registeredProbes[role]?.value === probe else { return }
        registeredProbes.removeValue(forKey: role)
    }

    static func probeDetails(
        for view: UIView,
        role: String,
        instanceID: String,
        includesPresentationChain: Bool
    ) -> [String: String] {
        let presentation = view.layer.presentation()
        let hierarchyState = hierarchyState(for: view)
        var details = [
            "role": role,
            "instance": instanceID,
            "window": view.window.map(objectID) ?? "none",
            "windowKey": String(view.window?.isKeyWindow ?? false),
            "superview": view.superview.map(shortTypeName) ?? "none",
            "superviewFrame": view.superview.map { rectSummary($0.frame) } ?? "none",
            "frame": rectSummary(view.frame),
            "bounds": rectSummary(view.bounds),
            "frameInWindow": hierarchyState.frameInWindow,
            "visibleIntersection": hierarchyState.visibleIntersection,
            "effectiveAlpha": hierarchyState.effectiveAlpha,
            "hiddenAncestor": hierarchyState.hiddenAncestor,
            "alpha": numberSummary(view.alpha),
            "hidden": String(view.isHidden),
            "transform": transformSummary(view.transform),
            "layerAnimations": animationSummary(view.layer),
            "presentationOpacity": presentation.map { numberSummary(CGFloat($0.opacity)) } ?? "none",
            "presentationFrame": presentation.map { rectSummary($0.frame) } ?? "none",
            "runLoopMode": RunLoop.current.currentMode?.rawValue ?? "none"
        ]
        if includesPresentationChain {
            appendChunked(hierarchyState.ancestorChain, prefix: "ancestors", into: &details)
            appendChunked(superlayerChain(from: view.layer), prefix: "superlayers", into: &details)
        }
        return details
    }

    private static func diagnosticWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0 }

        return windows.first(where: \.isKeyWindow)
            ?? windows.max(by: { $0.windowLevel.rawValue < $1.windowLevel.rawValue })
    }

    private static func sceneSummary() -> String {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { String(describing: $0.activationState) < String(describing: $1.activationState) }

        guard !scenes.isEmpty else { return "none" }

        return scenes.enumerated().map { sceneIndex, scene in
            let windows = scene.windows.enumerated().map { windowIndex, window in
                "w\(windowIndex){id:\(objectID(window)),key:\(window.isKeyWindow),"
                    + "hidden:\(window.isHidden),alpha:\(numberSummary(window.alpha)),"
                    + "level:\(Int(window.windowLevel.rawValue)),root:"
                    + "\(window.rootViewController.map(shortTypeName) ?? "none")}"
            }.joined(separator: ",")
            return "s\(sceneIndex){state:\(String(describing: scene.activationState)),\(windows)}"
        }.joined(separator: ";")
    }

    private static func windowSummary(_ window: UIWindow) -> String {
        let rootView = window.rootViewController?.viewIfLoaded
        return "id:\(objectID(window)),key:\(window.isKeyWindow),hidden:\(window.isHidden),"
            + "alpha:\(numberSummary(window.alpha)),level:\(Int(window.windowLevel.rawValue)),"
            + "frame:\(rectSummary(window.frame)),screenFPS:\(window.screen.maximumFramesPerSecond),"
            + "rootLoaded:\(rootView != nil),rootWindow:\(rootView?.window.map(objectID) ?? "none"),"
            + "rootFrame:\(rootView.map { rectSummary($0.frame) } ?? "none"),"
            + "windowAnimations:\(animationSummary(window.layer))"
    }

    private static func viewControllerTree(from root: UIViewController?) -> String {
        guard let root else { return "none" }

        var queue: [(UIViewController, Int)] = [(root, 0)]
        var nodes: [String] = []

        while !queue.isEmpty, nodes.count < 16 {
            let (controller, depth) = queue.removeFirst()
            let loadedView = controller.viewIfLoaded
            nodes.append(
                "d\(depth):\(shortTypeName(controller)){id:\(objectID(controller)),"
                    + "loaded:\(loadedView != nil),window:\(loadedView?.window.map(objectID) ?? "none"),"
                    + "presented:\(controller.presentedViewController.map(shortTypeName) ?? "none")}"
            )
            if depth < 3 {
                queue.append(contentsOf: controller.children.map { ($0, depth + 1) })
                if let presented = controller.presentedViewController {
                    queue.append((presented, depth + 1))
                }
            }
        }

        return nodes.joined(separator: "|")
    }

    private static func centerHitChain(in window: UIWindow) -> String {
        let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        guard var current = window.hitTest(center, with: nil) else { return "none" }

        var chain: [String] = []
        while chain.count < 14 {
            chain.append(
                "\(shortTypeName(current)){id:\(objectID(current)),hidden:\(current.isHidden),"
                    + "alpha:\(numberSummary(current.alpha)),frame:\(rectSummary(current.frame))}"
            )
            guard let superview = current.superview else { break }
            current = superview
        }
        return chain.joined(separator: ">")
    }

    private static func viewTree(from window: UIWindow) -> String {
        var queue: [(UIView, Int)] = [(window, 0)]
        var nodes: [String] = []

        while !queue.isEmpty, nodes.count < 18 {
            let (view, depth) = queue.removeFirst()
            let presentation = view.layer.presentation()
            nodes.append(
                "d\(depth):\(shortTypeName(view)){id:\(objectID(view)),hidden:\(view.isHidden),"
                    + "alpha:\(numberSummary(view.alpha)),frame:\(rectSummary(view.frame)),"
                    + "pOpacity:\(presentation.map { numberSummary(CGFloat($0.opacity)) } ?? "none"),"
                    + "animations:\(animationSummary(view.layer))}"
            )
            if depth < 4 {
                queue.append(contentsOf: view.subviews.map { ($0, depth + 1) })
            }
        }

        return nodes.joined(separator: "|")
    }

    private static func layerTree(from root: CALayer) -> String {
        var queue: [(CALayer, Int)] = [(root, 0)]
        var nodes: [String] = []

        while !queue.isEmpty, nodes.count < 20 {
            let (layer, depth) = queue.removeFirst()
            let presentation = layer.presentation()
            nodes.append(
                "d\(depth):\(shortTypeName(layer)){id:\(objectID(layer)),name:\(layer.name ?? "none"),"
                    + "hidden:\(layer.isHidden),opacity:\(numberSummary(CGFloat(layer.opacity))),"
                    + "frame:\(rectSummary(layer.frame)),"
                    + "pOpacity:\(presentation.map { numberSummary(CGFloat($0.opacity)) } ?? "none"),"
                    + "animations:\(animationSummary(layer))}"
            )
            if depth < 4 {
                queue.append(contentsOf: (layer.sublayers ?? []).map { ($0, depth + 1) })
            }
        }

        return nodes.joined(separator: "|")
    }

    private static func renderedCandidates(
        in window: UIWindow
    ) -> (fullScreen: String, transitions: String) {
        let transitionTerms = [
            "snapshot",
            "transition",
            "replicant",
            "presentation",
            "portal",
            "dimming",
            "remote"
        ]
        let windowArea = max(window.bounds.width * window.bounds.height, 1)
        var queue: [(UIView, String, Int)] = [(window, "0", 0)]
        var visitedCount = 0
        var fullScreenNodes: [String] = []
        var transitionNodes: [String] = []

        while !queue.isEmpty, visitedCount < 400 {
            let (view, path, depth) = queue.removeFirst()
            visitedCount += 1

            let frameInWindow = view.convert(view.bounds, to: window)
            let intersection = frameInWindow.intersection(window.bounds)
            let intersectionArea = intersection.isNull
                ? 0
                : max(intersection.width, 0) * max(intersection.height, 0)
            let coverage = intersectionArea / windowArea
            let visibility = effectiveVisibility(of: view)
            let node = "p\(path):\(shortTypeName(view)){id:\(objectID(view)),"
                + "frame:\(rectSummary(frameInWindow)),coverage:\(numberSummary(coverage)),"
                + "effectiveAlpha:\(numberSummary(visibility.alpha)),"
                + "hiddenAncestor:\(visibility.hiddenAncestor),"
                + "transform:\(transformSummary(view.transform)),"
                + "animations:\(animationSummary(view.layer))}"

            if coverage >= 0.80, fullScreenNodes.count < 16 {
                fullScreenNodes.append(node)
            }

            let typeName = shortTypeName(view).lowercased()
            if transitionTerms.contains(where: { typeName.contains($0) }),
               transitionNodes.count < 20 {
                transitionNodes.append(node)
            }

            if depth < 18 {
                queue.append(contentsOf: view.subviews.enumerated().map { index, subview in
                    (subview, "\(path).\(index)", depth + 1)
                })
            }
        }

        return (
            fullScreen: fullScreenNodes.isEmpty ? "none" : fullScreenNodes.joined(separator: "|"),
            transitions: transitionNodes.isEmpty ? "none" : transitionNodes.joined(separator: "|")
        )
    }

    private static func effectiveVisibility(
        of view: UIView
    ) -> (alpha: CGFloat, hiddenAncestor: String) {
        var alpha: CGFloat = 1
        var hiddenAncestor = "none"
        var current: UIView? = view

        while let candidate = current {
            alpha *= candidate.alpha
            if hiddenAncestor == "none", candidate.isHidden {
                hiddenAncestor = shortTypeName(candidate)
            }
            current = candidate.superview
        }

        return (alpha, hiddenAncestor)
    }

    private static func appendChunked(
        _ value: String,
        prefix: String,
        into details: inout [String: String]
    ) {
        let chunkSize = 560
        var remaining = value[...]
        var index = 0

        repeat {
            let endIndex = remaining.index(
                remaining.startIndex,
                offsetBy: min(chunkSize, remaining.count),
                limitedBy: remaining.endIndex
            ) ?? remaining.endIndex
            details["\(prefix)\(String(format: "%02d", index))"] = String(remaining[..<endIndex])
            remaining = remaining[endIndex...]
            index += 1
        } while !remaining.isEmpty
    }

    private static func animationSummary(_ layer: CALayer) -> String {
        let keys = layer.animationKeys() ?? []
        return keys.isEmpty ? "none" : keys.sorted().joined(separator: ",")
    }

    private static func superlayerChain(from layer: CALayer) -> String {
        var nodes: [String] = []
        var current: CALayer? = layer

        while let candidate = current, nodes.count < 16 {
            let presentation = candidate.presentation()
            nodes.append(
                "\(shortTypeName(candidate)){id:\(objectID(candidate)),name:\(candidate.name ?? "none"),"
                    + "opacity:\(numberSummary(CGFloat(candidate.opacity))),"
                    + "pOpacity:\(presentation.map { numberSummary(CGFloat($0.opacity)) } ?? "none"),"
                    + "transform:\(transform3DSummary(candidate.transform)),"
                    + "pTransform:\(presentation.map { transform3DSummary($0.transform) } ?? "none"),"
                    + "animations:\(animationSummary(candidate))}"
            )
            current = candidate.superlayer
        }

        return nodes.joined(separator: ">")
    }

    private static func hierarchyState(
        for view: UIView
    ) -> (
        frameInWindow: String,
        visibleIntersection: String,
        effectiveAlpha: String,
        hiddenAncestor: String,
        ancestorChain: String
    ) {
        var effectiveAlpha: CGFloat = 1
        var hiddenAncestor = "none"
        var chain: [String] = []
        var current: UIView? = view

        while let candidate = current, chain.count < 14 {
            effectiveAlpha *= candidate.alpha
            if hiddenAncestor == "none", candidate.isHidden {
                hiddenAncestor = shortTypeName(candidate)
            }
            chain.append("\(shortTypeName(candidate)){id:\(objectID(candidate))}")
            current = candidate.superview
        }

        guard let window = view.window else {
            return (
                frameInWindow: "none",
                visibleIntersection: "none",
                effectiveAlpha: numberSummary(effectiveAlpha),
                hiddenAncestor: hiddenAncestor,
                ancestorChain: chain.joined(separator: ">")
            )
        }

        let frameInWindow = view.convert(view.bounds, to: window)
        let intersection = frameInWindow.intersection(window.bounds)
        return (
            frameInWindow: rectSummary(frameInWindow),
            visibleIntersection: intersection.isNull ? "none" : rectSummary(intersection),
            effectiveAlpha: numberSummary(effectiveAlpha),
            hiddenAncestor: hiddenAncestor,
            ancestorChain: chain.joined(separator: ">")
        )
    }

    private static func shortTypeName(_ value: AnyObject) -> String {
        String(describing: type(of: value)).replacingOccurrences(of: " ", with: "_")
    }

    private static func objectID(_ value: AnyObject) -> String {
        String(describing: Unmanaged.passUnretained(value).toOpaque())
    }

    private static func rectSummary(_ rect: CGRect) -> String {
        "[\(numberSummary(rect.origin.x)),\(numberSummary(rect.origin.y)),"
            + "\(numberSummary(rect.width)),\(numberSummary(rect.height))]"
    }

    private static func transformSummary(_ transform: CGAffineTransform) -> String {
        "[\(numberSummary(transform.a)),\(numberSummary(transform.b)),"
            + "\(numberSummary(transform.c)),\(numberSummary(transform.d)),"
            + "\(numberSummary(transform.tx)),\(numberSummary(transform.ty))]"
    }

    private static func transform3DSummary(_ transform: CATransform3D) -> String {
        "[\(numberSummary(transform.m11)),\(numberSummary(transform.m12)),"
            + "\(numberSummary(transform.m21)),\(numberSummary(transform.m22)),"
            + "\(numberSummary(transform.m33)),\(numberSummary(transform.m41)),"
            + "\(numberSummary(transform.m42)),\(numberSummary(transform.m43))]"
    }

    private static func numberSummary(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
#endif
}

// MARK: - SwiftUI Render Probe

extension View {
    /// Adds a zero-size, noninteractive UIKit lifecycle probe in DEBUG builds.
    @ViewBuilder
    func authHandoffRenderProbe(_ role: String) -> some View {
#if DEBUG
        background(alignment: .topLeading) {
            AuthHandoffRenderProbe(role: role)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
#else
        self
#endif
    }
}

#if DEBUG
@MainActor
fileprivate final class WeakAuthHandoffProbe {
    weak var value: AuthHandoffProbeView?

    init(_ value: AuthHandoffProbeView) {
        self.value = value
    }
}

@MainActor
private struct AuthHandoffRenderProbe: UIViewRepresentable {
    let role: String

    func makeUIView(context: Context) -> AuthHandoffProbeView {
        let view = AuthHandoffProbeView(role: role)
        AuthHandoffVisualDiagnostics.registerProbe(view, role: role)
        return view
    }

    func updateUIView(_ uiView: AuthHandoffProbeView, context: Context) {
        uiView.update(role: role)
    }

    static func dismantleUIView(_ uiView: AuthHandoffProbeView, coordinator: ()) {
        uiView.record("probe.dismantle", includesPresentationChain: true)
        AuthHandoffVisualDiagnostics.unregisterProbe(uiView, role: uiView.currentRole)
    }
}

@MainActor
fileprivate final class AuthHandoffProbeView: UIView {
    private let instanceID = String(UUID().uuidString.prefix(8))
    private var role: String
    private var eventCounts: [String: Int] = [:]

    var currentRole: String { role }

    init(role: String) {
        self.role = role
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.name = "QFAuthProbe-\(role)-\(instanceID)"
        record("probe.make")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(role newRole: String) {
        if role != newRole {
            let previousRole = role
            AuthHandoffVisualDiagnostics.unregisterProbe(self, role: previousRole)
            role = newRole
            layer.name = "QFAuthProbe-\(newRole)-\(instanceID)"
            AuthHandoffVisualDiagnostics.registerProbe(self, role: newRole)
            record("probe.role-changed", extra: ["from": previousRole])
        } else {
            record("probe.update", maximumCount: 2)
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        record("probe.did-move-superview", maximumCount: 3)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        record(
            "probe.did-move-window",
            maximumCount: 3,
            includesPresentationChain: true
        )
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        record("probe.layout", maximumCount: 2)
    }

    func record(
        _ event: String,
        maximumCount: Int = 1,
        includesPresentationChain: Bool = false,
        extra: [String: String] = [:]
    ) {
        let count = (eventCounts[event] ?? 0) + 1
        eventCounts[event] = count
        guard count <= maximumCount else { return }

        var details = AuthHandoffVisualDiagnostics.probeDetails(
            for: self,
            role: role,
            instanceID: instanceID,
            includesPresentationChain: includesPresentationChain
        )
        details.merge(extra) { _, newValue in newValue }
        details["eventCount"] = String(count)

        AuthFlowDebugTrace.record(
            event,
            layer: "render-probe",
            details: details
        )
    }
}

// MARK: - Display-Link And Background Watchdog

private struct AuthHandoffHeartbeatSnapshot: Sendable {
    let tickCount: Int
    let lastTickUptime: TimeInterval
    let maximumTickGap: TimeInterval
}

private final class AuthHandoffHeartbeatStore: @unchecked Sendable {
    private let lock = NSLock()
    private var tickCount = 0
    private var lastTickUptime: TimeInterval
    private var maximumTickGap: TimeInterval = 0

    init(startUptime: TimeInterval) {
        lastTickUptime = startUptime
    }

    func noteTick(at uptime: TimeInterval) {
        lock.lock()
        maximumTickGap = max(maximumTickGap, uptime - lastTickUptime)
        lastTickUptime = uptime
        tickCount += 1
        lock.unlock()
    }

    func snapshot() -> AuthHandoffHeartbeatSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return AuthHandoffHeartbeatSnapshot(
            tickCount: tickCount,
            lastTickUptime: lastTickUptime,
            maximumTickGap: maximumTickGap
        )
    }
}

@MainActor
private final class AuthHandoffDisplayLinkMonitor: NSObject {
    static let shared = AuthHandoffDisplayLinkMonitor()

    private var displayLink: CADisplayLink?
    private var heartbeatStore: AuthHandoffHeartbeatStore?
    private var startUptime: TimeInterval = 0
    private var handoffID = "none"
    private var nextMainCheckpointIndex = 0
    private let mainCheckpointSeconds: [TimeInterval] = [0, 0.10, 0.50, 1.00, 2.00, 3.00]

    func start(handoffID: UUID, authAttemptID: String) {
        displayLink?.invalidate()

        let startUptime = ProcessInfo.processInfo.systemUptime
        let heartbeatStore = AuthHandoffHeartbeatStore(startUptime: startUptime)
        self.startUptime = startUptime
        self.heartbeatStore = heartbeatStore
        self.handoffID = handoffID.uuidString
        nextMainCheckpointIndex = 0

        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink

        AuthFlowDebugTrace.record(
            "display-link.started",
            layer: "visual-watchdog",
            details: ["handoff": handoffID.uuidString]
        )

        scheduleBackgroundCheckpoints(
            authAttemptID: authAttemptID,
            handoffID: handoffID.uuidString,
            startUptime: startUptime,
            heartbeatStore: heartbeatStore
        )
    }

    @objc
    private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        guard let heartbeatStore else { return }

        let now = ProcessInfo.processInfo.systemUptime
        heartbeatStore.noteTick(at: now)
        let elapsed = now - startUptime

        if nextMainCheckpointIndex < mainCheckpointSeconds.count,
           elapsed >= mainCheckpointSeconds[nextMainCheckpointIndex] {
            let checkpoint = mainCheckpointSeconds[nextMainCheckpointIndex]
            nextMainCheckpointIndex += 1
            let snapshot = heartbeatStore.snapshot()
            AuthFlowDebugTrace.record(
                "display-link.checkpoint",
                layer: "visual-watchdog",
                details: [
                    "handoff": handoffID,
                    "checkpoint": String(format: "%.2f", checkpoint),
                    "elapsed": String(format: "%.3f", elapsed),
                    "ticks": String(snapshot.tickCount),
                    "maxGap": String(format: "%.3f", snapshot.maximumTickGap),
                    "duration": String(format: "%.4f", displayLink.duration)
                ]
            )
        }

        if elapsed >= 3.2 {
            displayLink.invalidate()
            self.displayLink = nil
            self.heartbeatStore = nil
            AuthFlowDebugTrace.record(
                "display-link.stopped",
                layer: "visual-watchdog",
                details: ["handoff": handoffID, "elapsed": String(format: "%.3f", elapsed)]
            )
        }
    }

    private func scheduleBackgroundCheckpoints(
        authAttemptID: String,
        handoffID: String,
        startUptime: TimeInterval,
        heartbeatStore: AuthHandoffHeartbeatStore
    ) {
        for delay in [0.25, 0.75, 1.50, 3.00] {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                let now = ProcessInfo.processInfo.systemUptime
                let snapshot = heartbeatStore.snapshot()
                let lastTickAge = now - snapshot.lastTickUptime
                let line = "QF_AUTH_TRACE attempt=\(authAttemptID) seq=watchdog-"
                    + "\(Int(delay * 1_000))ms time=\(String(format: "%.3f", Date().timeIntervalSince1970)) "
                    + "main=\(Thread.isMainThread) layer=visual-watchdog "
                    + "event=background.checkpoint handoff=\(handoffID) "
                    + "elapsed=\(String(format: "%.3f", now - startUptime)) "
                    + "ticks=\(snapshot.tickCount) "
                    + "lastTickAge=\(String(format: "%.3f", lastTickAge)) "
                    + "maxGap=\(String(format: "%.3f", snapshot.maximumTickGap))"
                print(line)
            }
        }
    }
}
#endif
