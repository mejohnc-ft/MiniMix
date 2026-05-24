import AppKit

final class MiniMixPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        false
    }
}

@MainActor
final class MiniMixStatusController: NSObject, NSWindowDelegate {
    private static let panelSize = NSSize(width: 360, height: 460)

    private let model: MiniMixModel
    private let statusItem: NSStatusItem
    private let contentController: MiniMixMenuViewController
    private var panel: NSPanel?
    private var lastForegroundApplication: NSRunningApplication?
    private var eventMonitors: [Any] = []

    init(model: MiniMixModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.contentController = MiniMixMenuViewController(model: model)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "MiniMix")
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = "MiniMix"
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPanelFromAutomation(_:)),
            name: .miniMixShowPanel,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceActivatedApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        rememberForegroundApplication(NSWorkspace.shared.frontmostApplication)
    }

    deinit {
        MainActor.assumeIsolated {
            DistributedNotificationCenter.default().removeObserver(self)
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            removeEventMonitors()
            panel?.close()
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel(relativeTo: button)
        }
    }

    @objc private func showPanelFromAutomation(_ notification: Notification) {
        showPanelForAutomation()
    }

    func showPanelForAutomation() {
        showPanel(relativeTo: statusItem.button)
    }

    private func showPanel(relativeTo button: NSStatusBarButton?) {
        contentController.refreshFromModel()
        let panel = panel ?? makePanel()
        self.panel = panel
        if let button {
            panel.setFrame(panelFrame(relativeTo: button), display: true)
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrame(
                NSRect(
                    x: frame.midX - Self.panelSize.width / 2,
                    y: frame.midY - Self.panelSize.height / 2,
                    width: Self.panelSize.width,
                    height: Self.panelSize.height
                ),
                display: true
            )
        }
        let appToRestore = lastForegroundApplication
        panel.orderFront(nil)
        installEventMonitors()
        restoreFocus(to: appToRestore)
    }

    private func makePanel() -> NSPanel {
        let panel = MiniMixPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = contentController
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.level = .statusBar
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .windowBackgroundColor
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        return panel
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        removeEventMonitors()
    }

    @objc private func workspaceActivatedApplication(_ notification: Notification) {
        rememberForegroundApplication(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }

    private func rememberForegroundApplication(_ application: NSRunningApplication?) {
        guard let application else {
            return
        }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        lastForegroundApplication = application
    }

    private func restoreFocus(to application: NSRunningApplication?) {
        NSApplication.shared.deactivate()
        guard
            let application,
            !application.isTerminated
        else {
            return
        }
        application.activate(options: [])
    }

    private func installEventMonitors() {
        removeEventMonitors()

        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                Task { @MainActor in
                    self?.hidePanel()
                }
            }
        ) {
            eventMonitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
            handler: { [weak self] event in
                guard let self else {
                    return event
                }
                if event.type == .keyDown, event.keyCode == 53 {
                    hidePanel()
                    return nil
                }
                if let panel, event.window !== panel {
                    hidePanel()
                }
                return event
            }
        ) {
            eventMonitors.append(monitor)
        }
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private func panelFrame(relativeTo button: NSStatusBarButton) -> NSRect {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else {
            return NSRect(origin: .zero, size: Self.panelSize)
        }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visibleFrame = screen.visibleFrame
        let x = min(max(buttonFrame.midX - Self.panelSize.width / 2, visibleFrame.minX + 8), visibleFrame.maxX - Self.panelSize.width - 8)
        let y = max(buttonFrame.minY - Self.panelSize.height - 8, visibleFrame.minY + 8)
        return NSRect(x: x, y: y, width: Self.panelSize.width, height: Self.panelSize.height)
    }

}

private extension Notification.Name {
    static let miniMixShowPanel = Notification.Name("com.mejohncft.MiniMix.showPanel")
}

@MainActor
final class MiniMixMenuViewController: NSViewController {
    private let model: MiniMixModel
    private let rootStack = NSStackView()
    private var refreshTimer: Timer?

    init(model: MiniMixModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MiniMixMenuViewController does not support NSCoder.")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 460))
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshFromModel()
        startRefreshTimer()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        stopRefreshTimer()
    }

    func refreshFromModel() {
        model.refresh()
        render()
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else {
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromModel()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func render() {
        rootStack.arrangedSubviews.forEach { view in
            rootStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        rootStack.addArrangedSubview(headerView())
        rootStack.addArrangedSubview(mixerSectionView())
        rootStack.addArrangedSubview(separator())
        rootStack.addArrangedSubview(voiceSectionView())
        rootStack.addArrangedSubview(separator())
        rootStack.addArrangedSubview(footerView())
    }

    private func headerView() -> NSView {
        let title = label("MiniMix", font: .systemFont(ofSize: 13, weight: .semibold))
        let status = label(model.mixer.statusText, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        let labels = verticalStack([title, status], spacing: 2)

        let refresh = iconButton("arrow.clockwise", action: #selector(refreshTapped(_:)), help: "Refresh")
        return horizontalStack([labels, spacer(), refresh], spacing: 8)
    }

    private func mixerSectionView() -> NSView {
        let stack = verticalStack([], spacing: 10)
        stack.addArrangedSubview(sectionLabel("App Audio", symbolName: "speaker.wave.2"))

        let allApps = NSSwitch()
        allApps.state = model.mixer.includesInactiveApps ? .on : .off
        allApps.target = self
        allApps.action = #selector(allAppsChanged(_:))
        let allAppsRow = horizontalStack([label("All Apps", font: .systemFont(ofSize: 11)), spacer(), allApps], spacing: 8)
        stack.addArrangedSubview(allAppsRow)

        if model.mixer.apps.isEmpty {
            stack.addArrangedSubview(label(model.mixer.includesInactiveApps ? "No running apps found." : "No active audio apps yet.", font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        } else {
            for app in model.mixer.apps {
                stack.addArrangedSubview(appRow(app))
            }
        }

        return stack
    }

    private func appRow(_ app: ManagedAudioApp) -> NSView {
        let name = label(app.displayName, font: .systemFont(ofSize: 13))
        let details = label(app.detailText, font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
        details.lineBreakMode = .byTruncatingTail
        details.maximumNumberOfLines = 1
        let textStack = verticalStack([name, details], spacing: 1)

        let mute = textButton(app.isMuted ? "Unmute" : "Mute", action: #selector(muteTapped(_:)))
        mute.identifier = NSUserInterfaceItemIdentifier(app.id)
        let reset = textButton("Reset", action: #selector(resetTapped(_:)))
        reset.identifier = NSUserInterfaceItemIdentifier(app.id)

        let top = horizontalStack([textStack, spacer(), mute, reset], spacing: 8)

        let slider = NSSlider(value: app.effectiveVolume, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged(_:)))
        slider.identifier = NSUserInterfaceItemIdentifier(app.id)
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 235).isActive = true

        let percent = label(app.volumePercentText, font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        percent.alignment = .right
        percent.widthAnchor.constraint(equalToConstant: 42).isActive = true
        let sliderRow = horizontalStack([slider, percent], spacing: 8)

        let row = verticalStack([top, sliderRow], spacing: 6)
        row.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(app.isDucked ? 0.20 : 0.10).cgColor
        return row
    }

    private func voiceSectionView() -> NSView {
        let stack = verticalStack([], spacing: 10)
        stack.addArrangedSubview(horizontalStack([
            sectionLabel("Voice Input", symbolName: "mic"),
            spacer(),
            label(model.voice.label, font: .systemFont(ofSize: 11), color: model.voice.isActive ? .controlAccentColor : .secondaryLabelColor)
        ], spacing: 8))

        stack.addArrangedSubview(label(model.pushToTalkStatus, font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        stack.addArrangedSubview(label(model.voicePermissions.summary, font: .systemFont(ofSize: 10), color: model.voicePermissions.readiness == .ready ? .secondaryLabelColor : .systemOrange))
        stack.addArrangedSubview(label(model.voicePermissions.detailText, font: .systemFont(ofSize: 10), color: .secondaryLabelColor))

        if model.voicePermissions.readiness != .ready {
            stack.addArrangedSubview(textButton("Permissions", action: #selector(permissionsTapped(_:))))
        }

        let start = textButton("Start", action: #selector(startVoiceTapped(_:)))
        start.isEnabled = !model.voice.isActive
        let stop = textButton("Stop", action: #selector(stopVoiceTapped(_:)))
        stop.isEnabled = model.voice.isActive
        let preview = textButton("Preview Duck", action: #selector(previewDuckTapped(_:)))
        preview.isEnabled = !model.voice.isActive
        let restore = textButton("Restore", action: #selector(restoreTapped(_:)))
        restore.isEnabled = model.voice.isActive
        stack.addArrangedSubview(horizontalStack([start, stop, preview, restore], spacing: 8))

        if let transcript = model.voice.lastTranscript, !transcript.isEmpty {
            stack.addArrangedSubview(label(transcript, font: .systemFont(ofSize: 11)))
        }

        if let errorMessage = model.voice.errorMessage {
            stack.addArrangedSubview(label(errorMessage, font: .systemFont(ofSize: 11), color: .systemRed))
        }

        return stack
    }

    private func footerView() -> NSView {
        let stack = verticalStack([], spacing: 8)
        if let error = model.mixer.audioEngineLastError {
            stack.addArrangedSubview(label(error, font: .systemFont(ofSize: 10), color: .systemRed))
        }

        let footer = NSMutableArray(array: [
            label(model.mixer.footerText, font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
        ])

        if model.mixer.audioEngineRestartCount > 0 {
            footer.add(label("Restarts \(model.mixer.audioEngineRestartCount)", font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular), color: .secondaryLabelColor))
        }

        footer.add(spacer())
        footer.add(textButton("Quit", action: #selector(quitTapped(_:))))
        stack.addArrangedSubview(horizontalStack(footer.compactMap { $0 as? NSView }, spacing: 8))
        return stack
    }

    @objc private func refreshTapped(_ sender: NSButton) {
        refreshFromModel()
    }

    @objc private func allAppsChanged(_ sender: NSSwitch) {
        model.setIncludesInactiveApps(sender.state == .on)
        render()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let appID = sender.identifier?.rawValue else {
            return
        }
        model.setVolume(for: appID, to: sender.doubleValue)
        render()
    }

    @objc private func muteTapped(_ sender: NSButton) {
        guard let appID = sender.identifier?.rawValue else {
            return
        }
        model.toggleMute(for: appID)
        render()
    }

    @objc private func resetTapped(_ sender: NSButton) {
        guard let appID = sender.identifier?.rawValue else {
            return
        }
        model.resetApp(appID)
        render()
    }

    @objc private func startVoiceTapped(_ sender: NSButton) {
        model.startDictation()
        renderAfterAsyncVoiceUpdate()
    }

    @objc private func stopVoiceTapped(_ sender: NSButton) {
        model.stopDictation()
        renderAfterAsyncVoiceUpdate()
    }

    @objc private func permissionsTapped(_ sender: NSButton) {
        model.requestVoicePermissions()
        renderAfterAsyncVoiceUpdate()
    }

    @objc private func previewDuckTapped(_ sender: NSButton) {
        model.beginVoicePreview()
        render()
    }

    @objc private func restoreTapped(_ sender: NSButton) {
        model.endVoicePreview()
        render()
    }

    @objc private func quitTapped(_ sender: NSButton) {
        sender.isEnabled = false
        Task { @MainActor in
            await model.shutdownNow()
            NSApplication.shared.terminate(nil)
        }
    }

    private func renderAfterAsyncVoiceUpdate() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            render()
        }
    }

    private func sectionLabel(_ text: String, symbolName: String) -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: text) ?? NSImage())
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        image.widthAnchor.constraint(equalToConstant: 16).isActive = true
        return horizontalStack([image, label(text, font: .systemFont(ofSize: 12, weight: .semibold))], spacing: 6)
    }

    private func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 3
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func iconButton(_ symbolName: String, action: Selector, help: String) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: help) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.setAccessibilityHelp(help)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func textButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(title)
        return button
    }

    private func horizontalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 332).isActive = true
        return stack
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 332).isActive = true
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 332).isActive = true
        return box
    }
}
