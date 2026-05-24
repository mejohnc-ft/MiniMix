import Carbon
import Foundation

@MainActor
protocol PushToTalkHotkeyControlling: AnyObject {
    var statusText: String { get }
    func start(onPress: @escaping @MainActor () -> Void, onRelease: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class PushToTalkHotkeyController: PushToTalkHotkeyControlling {
    private static weak var activeController: PushToTalkHotkeyController?
    private static var eventHandler: EventHandlerRef?

    private var hotKeyRef: EventHotKeyRef?
    private var onPress: (@MainActor () -> Void)?
    private var onRelease: (@MainActor () -> Void)?
    private(set) var statusText = "Hotkey inactive"

    func start(onPress: @escaping @MainActor () -> Void, onRelease: @escaping @MainActor () -> Void) {
        stop()

        self.onPress = onPress
        self.onRelease = onRelease

        do {
            try Self.installEventHandlerIfNeeded()
            try registerHotkey()
            Self.activeController = self
            statusText = "Hold Control-Option-Space"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    private func registerHotkey() throws {
        let hotKeyID = EventHotKeyID(signature: Self.fourCharacterCode("MMix"), id: 1)
        var registeredHotKey: EventHotKeyRef?
        let modifiers = UInt32(controlKey | optionKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        guard status == noErr, let registeredHotKey else {
            throw PushToTalkHotkeyError.registrationFailed(status)
        }

        hotKeyRef = registeredHotKey
    }

    private static func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            eventTypes.count,
            &eventTypes,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            throw PushToTalkHotkeyError.handlerInstallFailed(status)
        }
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, byte in
            (result << 8) + OSType(byte)
        }
    }

    private static let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
        guard let event else {
            return noErr
        }

        let eventKind = GetEventKind(event)
        Task { @MainActor in
            switch eventKind {
            case UInt32(kEventHotKeyPressed):
                activeController?.onPress?()
            case UInt32(kEventHotKeyReleased):
                activeController?.onRelease?()
            default:
                break
            }
        }

        return noErr
    }
}

private enum PushToTalkHotkeyError: LocalizedError {
    case handlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .handlerInstallFailed(status):
            "Hotkey handler failed with OSStatus \(status)"
        case let .registrationFailed(status):
            "Control-Option-Space unavailable, OSStatus \(status)"
        }
    }
}
