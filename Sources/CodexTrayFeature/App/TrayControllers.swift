import AppKit
import Combine
import SwiftUI

public final class CodexTrayAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: TrayCoordinator?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = TrayCoordinator()
        coordinator?.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
final class TrayCoordinator: NSObject {
    private let store = UsageStore()
    private var statusItemController: StatusItemController?
    private var hotspotController: NotchHotspotController?
    private var panelController: PanelWindowController?
    private var refreshTimer: Timer?
    private var screenObserver: Any?

    func start() {
        statusItemController = StatusItemController(store: store, target: self, action: #selector(togglePanel))
        hotspotController = NotchHotspotController(store: store, target: self, action: #selector(togglePanel))
        hotspotController?.show()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAnchors()
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.store.refresh() }
        }
        Task { [weak self] in
            await self?.store.refresh()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        panelController?.close()
        statusItemController?.tearDown()
        hotspotController?.close()
    }

    @objc private func togglePanel() {
        hotspotController?.updateFrame()
        let panelController = ensurePanelController()
        panelController.toggle(anchoredTo: hotspotController?.anchorFrame)
    }

    private func updateAnchors() {
        hotspotController?.updateFrame()
        if let anchor = hotspotController?.anchorFrame {
            panelController?.reposition(anchoredTo: anchor)
        }
    }

    private func ensurePanelController() -> PanelWindowController {
        if let panelController {
            return panelController
        }

        let panelController = PanelWindowController(
            store: store,
            onQuit: { NSApp.terminate(nil) },
            onVisibilityChange: { [weak self] isVisible in
                if isVisible {
                    self?.hotspotController?.hide()
                } else {
                    self?.hotspotController?.show()
                }
            }
        )
        self.panelController = panelController
        return panelController
    }
}

@MainActor
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellable: AnyCancellable?

    init(store: UsageStore, target: AnyObject, action: Selector) {
        if let button = statusItem.button {
            button.target = target
            button.action = action
            button.image = NSImage(systemSymbolName: "sparkles.rectangle.stack.fill", accessibilityDescription: "Codex Tray")
            button.imagePosition = .imageLeading
        }

        update(snapshot: store.snapshot)
        cancellable = store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.update(snapshot: snapshot)
            }
    }

    func tearDown() {
        cancellable?.cancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func update(snapshot: UsageSnapshot) {
        statusItem.button?.title = ""
        statusItem.button?.toolTip = snapshot.primaryLimit.map { "CodexTray • 5h \($0.shortLabel)" } ?? "CodexTray"
    }
}

@MainActor
final class NotchHotspotController {
    private let window: NSWindow
    private let hostingView: NSHostingView<HotspotBadgeView>
    private var cancellable: AnyCancellable?

    var anchorFrame: CGRect {
        window.frame
    }

    init(store: UsageStore, target: AnyObject, action: Selector) {
        let rootView = HotspotBadgeView(store: store)
        hostingView = NSHostingView(rootView: rootView)
        let initialFrame = ScreenLayout.hotspotFrame() ?? CGRect(x: 0, y: 0, width: 332, height: 38)
        window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.contentView = hostingView
        window.alphaValue = 0

        let gestureRecognizer = NSClickGestureRecognizer(target: target, action: action)
        hostingView.addGestureRecognizer(gestureRecognizer)

        cancellable = store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.window.title = "Codex \(snapshot.primaryLimit?.shortLabel ?? "")"
            }
    }

    func show() {
        updateFrame()
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    func close() {
        cancellable?.cancel()
        window.close()
    }

    func updateFrame() {
        guard let frame = ScreenLayout.hotspotFrame() else { return }
        window.setFrame(frame, display: true)
    }
}

@MainActor
final class PanelWindowController: NSObject, NSWindowDelegate {
    private let store: UsageStore
    private let panel: FloatingPanel
    private let hostingView: NSHostingView<PanelRootView>
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resizeTimer: Timer?
    private var currentAnchorFrame: CGRect?
    private var currentHeatmapRange: HeatmapRange = .year
    private var isAnimating = false
    private let onVisibilityChange: (Bool) -> Void

    init(
        store: UsageStore,
        onQuit: @escaping () -> Void,
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.store = store
        self.onVisibilityChange = onVisibilityChange
        let rootView = PanelRootView(
            store: store,
            onQuit: onQuit,
            onHeatmapRangeChange: { _ in }
        )
        hostingView = NSHostingView(rootView: rootView)
        panel = FloatingPanel(
            contentRect: CGRect(origin: .zero, size: ScreenLayout.panelSize(for: .year)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.alphaValue = 0
        hostingView.rootView.onHeatmapRangeChange = { [weak self] range in
            self?.updatePanelLayout(for: range)
        }
    }

    func toggle(anchoredTo anchorFrame: CGRect?) {
        guard !isAnimating else { return }
        if panel.isVisible {
            close()
        } else {
            show(anchoredTo: anchorFrame)
        }
    }

    func reposition(anchoredTo anchorFrame: CGRect) {
        guard panel.isVisible else { return }
        currentAnchorFrame = anchorFrame
        panel.setFrame(ScreenLayout.panelFrame(anchoredTo: anchorFrame, range: currentHeatmapRange), display: true)
    }

    func close() {
        guard panel.isVisible, !isAnimating else { return }
        isAnimating = true
        resizeTimer?.invalidate()
        resizeTimer = nil
        removeMonitors()
        let anchorFrame = currentAnchorFrame ?? ScreenLayout.hotspotFrame() ?? .zero
        let collapsedFrame = ScreenLayout.collapsedPanelFrame(anchoredTo: anchorFrame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(collapsedFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.panel.orderOut(nil)
                self?.panel.setFrame(collapsedFrame, display: false)
                self?.isAnimating = false
                self?.onVisibilityChange(false)
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func show(anchoredTo anchorFrame: CGRect?) {
        let anchor = anchorFrame ?? ScreenLayout.hotspotFrame() ?? .zero
        currentAnchorFrame = anchor
        let finalFrame = ScreenLayout.panelFrame(anchoredTo: anchor, range: currentHeatmapRange)
        let collapsedFrame = ScreenLayout.collapsedPanelFrame(anchoredTo: anchor)
        panel.setFrame(collapsedFrame, display: false)
        panel.alphaValue = 0
        onVisibilityChange(true)
        panel.makeKeyAndOrderFront(nil)
        Task { await store.refresh() }
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.isAnimating = false
                self?.installMonitors()
            }
        }
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleOutsideClick()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleOutsideClick()
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
    }

    private func handleOutsideClick() {
        let mouseLocation = NSEvent.mouseLocation
        if !panel.frame.contains(mouseLocation) {
            close()
        }
    }

    private func updatePanelLayout(for range: HeatmapRange) {
        currentHeatmapRange = range
        let panelSize = ScreenLayout.panelSize(for: range)
        guard panel.isVisible, !isAnimating else {
            hostingView.setFrameSize(panelSize)
            return
        }
        animatePanelResizeKeepingTop(to: panelSize)
    }

    private func animatePanelResizeKeepingTop(to panelSize: CGSize) {
        resizeTimer?.invalidate()

        let startFrame = panel.frame
        let fixedTop = startFrame.maxY
        let targetFrame = CGRect(
            x: startFrame.minX,
            y: fixedTop - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )

        guard startFrame != targetFrame else { return }

        let startTime = CACurrentMediaTime()
        let duration = 0.18

        resizeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                
                let elapsed = CACurrentMediaTime() - startTime
                let rawProgress = min(max(elapsed / duration, 0), 1)
                let easedProgress = 1 - pow(1 - rawProgress, 3)
                let interpolatedHeight = startFrame.height + ((targetFrame.height - startFrame.height) * easedProgress)
                let interpolatedY = fixedTop - interpolatedHeight
                let interpolatedFrame = CGRect(
                    x: startFrame.minX,
                    y: interpolatedY,
                    width: panelSize.width,
                    height: interpolatedHeight
                )

                self.hostingView.setFrameSize(interpolatedFrame.size)
                self.panel.setFrame(interpolatedFrame, display: true)

                if rawProgress >= 1 {
                    self.hostingView.setFrameSize(targetFrame.size)
                    self.panel.setFrame(targetFrame, display: true)
                    self.resizeTimer?.invalidate()
                    self.resizeTimer = nil
                }
            }
        }

        RunLoop.main.add(resizeTimer!, forMode: .common)
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum ScreenLayout {
    private static let panelHorizontalPadding: CGFloat = 12
    private static let baseExpandedPanelHeight: CGFloat = 518
    private static let minimumPanelWidth: CGFloat = 780
    private static let additionalPanelWidth: CGFloat = 420

    static var notchMetrics: NotchMetrics {
        notchMetrics(for: NSScreen.main ?? NSScreen.screens.first)
    }

    static var collapsedIslandSize: CGSize {
        let metrics = notchMetrics
        let width = max(380, metrics.notchWidth + 180)
        return CGSize(width: width, height: metrics.bandHeight)
    }

    static var panelWidth: CGFloat {
        max(minimumPanelWidth, collapsedIslandSize.width + additionalPanelWidth)
    }

    static func panelSize(for range: HeatmapRange) -> CGSize {
        let height = baseExpandedPanelHeight + (range.heatmapHeight - HeatmapRange.year.heatmapHeight)
        return CGSize(width: panelWidth, height: height)
    }

    static func hotspotFrame() -> CGRect? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let size = collapsedIslandSize
        let x = screen.frame.midX - (size.width / 2)
        let y = screen.frame.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func panelFrame(anchoredTo anchorFrame: CGRect, range: HeatmapRange) -> CGRect {
        let panelSize = panelSize(for: range)
        let width = panelSize.width
        let height = panelSize.height
        let screen = screenContaining(point: CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)) ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: width, height: height)
        let desiredX = anchorFrame.midX - (width / 2)
        let x = min(max(screenFrame.minX + panelHorizontalPadding, desiredX), screenFrame.maxX - width - panelHorizontalPadding)
        let y = screenFrame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func collapsedPanelFrame(anchoredTo anchorFrame: CGRect) -> CGRect {
        anchorFrame
    }

    private static func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private static func notchMetrics(for screen: NSScreen?) -> NotchMetrics {
        guard let screen else {
            return NotchMetrics(bandHeight: 38, notchWidth: 220, topBandMinY: 0)
        }

        if let leftArea = screen.auxiliaryTopLeftArea, let rightArea = screen.auxiliaryTopRightArea {
            return NotchMetrics(
                bandHeight: max(leftArea.height, rightArea.height),
                notchWidth: max(0, rightArea.minX - leftArea.maxX),
                topBandMinY: min(leftArea.minY, rightArea.minY)
            )
        }

        let fallbackHeight = max(38, screen.safeAreaInsets.top)
        return NotchMetrics(
            bandHeight: fallbackHeight,
            notchWidth: 220,
            topBandMinY: screen.frame.maxY - fallbackHeight
        )
    }
}

struct NotchMetrics {
    let bandHeight: CGFloat
    let notchWidth: CGFloat
    let topBandMinY: CGFloat
}
