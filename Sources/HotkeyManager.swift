// HotkeyManager.swift
// Global keyboard shortcut (⌥⌘C) to toggle the menu bar popover

import Cocoa
import Carbon.HIToolbox

class HotkeyManager {

    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Register ⌥⌘C as global hotkey
    func register() {
        guard hotKeyRef == nil else { return }

        // Carbon event handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            HotkeyManager.togglePopover()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // ⌥⌘C — key code 8 = 'C'
        var hotkeyID = EventHotKeyID(
            signature: OSType(0x434C4744), // "CLGD"
            id: 1
        )

        let modifiers: UInt32 = UInt32(optionKey | cmdKey)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        print("[ClaudeGod] Global hotkey ⌥⌘C registered")
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    /// Toggle the MenuBarExtra popover by simulating a click on the status item
    private static func togglePopover() {
        DispatchQueue.main.async {
            // Find our status item button and click it
            guard let button = findStatusItemButton() else {
                print("[ClaudeGod] Could not find status item button")
                return
            }
            button.performClick(nil)
        }
    }

    /// Find the NSStatusBarButton for our app
    private static func findStatusItemButton() -> NSStatusBarButton? {
        // Iterate through all windows to find the status bar button
        for window in NSApp.windows {
            // NSStatusBarWindow contains the status item
            let windowName = String(describing: type(of: window))
            if windowName.contains("NSStatusBarWindow") {
                // The contentView of a status bar window contains the button
                if let button = window.contentView?.subviews.first as? NSStatusBarButton {
                    return button
                }
                // Try finding button in the view hierarchy
                if let button = findButton(in: window.contentView) {
                    return button
                }
            }
        }
        return nil
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view = view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let found = findButton(in: subview) {
                return found
            }
        }
        return nil
    }
}
