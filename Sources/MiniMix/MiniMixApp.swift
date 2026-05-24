import AppKit
import Foundation

@main
enum MiniMixMain {
    @MainActor private static var appDelegate: MiniMixAppDelegate?

    @MainActor
    static func main() {
        if MiniMixGainHarness.shouldRun {
            Foundation.exit(MiniMixGainHarness.run())
        }

        let application = NSApplication.shared
        let delegate = MiniMixAppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class MiniMixAppDelegate: NSObject, NSApplicationDelegate {
    private let model = MiniMixModel()
    private let automationToken = MiniMixAppDelegate.argument(after: "--automation-token")
    private var statusController: MiniMixStatusController?
    private var isHandlingTermination = false
    private var didCompleteShutdown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = MiniMixStatusController(model: model)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !didCompleteShutdown else {
            return
        }

        removeEventHandlers()
        statusController = nil
        model.shutdown()
        didCompleteShutdown = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if didCompleteShutdown {
            return .terminateNow
        }

        guard !isHandlingTermination else {
            return .terminateLater
        }

        isHandlingTermination = true
        Task { @MainActor in
            await performShutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func performShutdown() async {
        guard !didCompleteShutdown else {
            return
        }

        removeEventHandlers()
        statusController = nil
        await model.shutdownNow()
        didCompleteShutdown = true
    }

    private func removeEventHandlers() {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard
            let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: rawURL),
            url.scheme == "minimix"
        else {
            return
        }

        switch url.host {
        case "show-panel":
            statusController?.showPanelForAutomation()
        case "start-dictation":
            guard automationIsAuthorized(for: url) else {
                return
            }
            model.startDictation()
        case "stop-dictation":
            guard automationIsAuthorized(for: url) else {
                return
            }
            model.stopDictation()
        case "automation-status":
            guard automationIsAuthorized(for: url) else {
                return
            }
            writeAutomationStatus(for: url)
        default:
            return
        }
    }

    private func automationIsAuthorized(for url: URL) -> Bool {
        guard
            let automationToken,
            !automationToken.isEmpty,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.first(where: { $0.name == "token" })?.value == automationToken
        else {
            return false
        }

        return true
    }

    private func writeAutomationStatus(for url: URL) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
            !path.isEmpty
        else {
            return
        }

        do {
            try model.automationStatusLine().write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            try? "miniMixAutomationStatus error=writeFailed\n".write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
