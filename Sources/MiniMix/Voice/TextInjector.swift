import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol TextInjecting {
    func insert(_ text: String) throws
}

enum TextInjectionError: LocalizedError {
    case accessibilityNotTrusted

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            "Accessibility permission is required to paste dictated text."
        }
    }
}

struct PasteboardTextInjector: TextInjecting {
    func insert(_ text: String) throws {
        guard !text.isEmpty else {
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw TextInjectionError.accessibilityNotTrusted
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        pasteFromClipboard()
    }

    private func pasteFromClipboard() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
