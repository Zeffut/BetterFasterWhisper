//
//  HotkeyManager.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import AppKit
import Carbon.HIToolbox
import Combine
import os.log

private let logger = Logger(subsystem: "com.betterfasterwhisper", category: "HotkeyManager")

// MARK: - Classic Shortcut Model

struct ClassicShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt64

    /// Modifier mask : only Ctrl/Opt/Shift/Cmd bits
    static let modifierMask: UInt64 =
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskCommand.rawValue

    /// Key codes that are modifier keys only (should not be used as the main key)
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var displayString: String {
        var s = ""
        let flags = CGEventFlags(rawValue: modifierFlags)
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        s += Self.keyCodeToString(keyCode)
        return s
    }

    func matches(event: CGEvent) -> Bool {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let eventFlags = event.flags.rawValue & Self.modifierMask
        return eventKeyCode == keyCode && eventFlags == modifierFlags
    }

    /// Build a ClassicShortcut from a CGEvent keyDown. Returns nil if invalid.
    static func from(event: CGEvent) -> ClassicShortcut? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard !modifierKeyCodes.contains(keyCode) else { return nil }
        let flags = event.flags.rawValue & modifierMask
        guard flags != 0 else { return nil }
        return ClassicShortcut(keyCode: keyCode, modifierFlags: flags)
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
            51: "⌫", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
            118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

/// Device-dependent modifier flag masks (from IOKit/hidsystem/IOLLEvent.h)
private struct DeviceModifierFlags {
    static let leftControl:  UInt64 = 0x00000001
    static let leftShift:    UInt64 = 0x00000002
    static let rightShift:   UInt64 = 0x00000004
    static let leftCommand:  UInt64 = 0x00000008
    static let rightCommand: UInt64 = 0x00000010
    static let leftOption:   UInt64 = 0x00000020
    static let rightOption:  UInt64 = 0x00000040
    static let rightControl: UInt64 = 0x00002000
}

/// Available trigger keys for push-to-talk.
enum TriggerKey: String, CaseIterable, Identifiable, Codable {
    case leftOption = "leftOption"
    case rightOption = "rightOption"
    case leftControl = "leftControl"
    case rightControl = "rightControl"
    case leftCommand = "leftCommand"
    case rightCommand = "rightCommand"
    case fn = "fn"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .leftOption: return "Left Option ⌥"
        case .rightOption: return "Right Option ⌥"
        case .leftControl: return "Left Control ⌃"
        case .rightControl: return "Right Control ⌃"
        case .leftCommand: return "Left Command ⌘"
        case .rightCommand: return "Right Command ⌘"
        case .fn: return "Fn"
        }
    }
    
    var shortDisplayName: String {
        switch self {
        case .leftOption: return "L⌥"
        case .rightOption: return "R⌥"
        case .leftControl: return "L⌃"
        case .rightControl: return "R⌃"
        case .leftCommand: return "L⌘"
        case .rightCommand: return "R⌘"
        case .fn: return "Fn"
        }
    }
    
    /// The device-dependent flag mask for this trigger key
    var deviceFlagMask: UInt64 {
        switch self {
        case .leftOption: return DeviceModifierFlags.leftOption
        case .rightOption: return DeviceModifierFlags.rightOption
        case .leftControl: return DeviceModifierFlags.leftControl
        case .rightControl: return DeviceModifierFlags.rightControl
        case .leftCommand: return DeviceModifierFlags.leftCommand
        case .rightCommand: return DeviceModifierFlags.rightCommand
        case .fn: return UInt64(CGEventFlags.maskSecondaryFn.rawValue)
        }
    }
}

/// Manages global hotkey registration for push-to-talk using CGEvent tap.
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    
    /// Current trigger key configuration.
    @Published var triggerKey: TriggerKey {
        didSet {
            saveTriggerKey()
            // Restart listening with new key
            if isListening {
                stopListening()
                startListening()
            }
        }
    }
    
    /// Whether the hotkey listener is active.
    @Published private(set) var isListening: Bool = false
    
    /// Whether the key is currently being held down.
    @Published private(set) var isKeyDown: Bool = false
    
    /// Whether accessibility permission is granted.
    @Published private(set) var hasAccessibilityPermission: Bool = false
    
    /// Callback when key is pressed down.
    var onKeyDown: (() -> Void)?
    
    /// Callback when key is released.
    var onKeyUp: (() -> Void)?

    /// Current classic recording shortcut.
    @Published var classicShortcut: ClassicShortcut? {
        didSet { saveClassicShortcut() }
    }

    /// Called when the classic shortcut is pressed (toggle start/stop).
    var onClassicToggle: (() -> Void)?

    /// Called when Escape is pressed (cancel classic recording).
    var onClassicEscape: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: UInt64 = 0
    private var permissionCheckTimer: Timer?
    
    private init() {
        // Load saved trigger key or use default (right option)
        if let savedKey = UserDefaults.standard.string(forKey: "triggerKey"),
           let key = TriggerKey(rawValue: savedKey) {
            self.triggerKey = key
        } else {
            self.triggerKey = .rightOption
        }
        
        // Load classic recording shortcut
        if let data = UserDefaults.standard.data(forKey: "classicRecordingShortcut"),
           let shortcut = try? JSONDecoder().decode(ClassicShortcut.self, from: data) {
            self.classicShortcut = shortcut
        } else {
            self.classicShortcut = nil
        }

        // Check accessibility permission
        checkAccessibilityPermission()
    }
    
    /// Check if we have accessibility permission.
    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        logger.info("Accessibility permission: \(self.hasAccessibilityPermission)")
    }
    
    /// Request accessibility permission (shows system dialog).
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        hasAccessibilityPermission = trusted
        logger.info("Requested accessibility permission, trusted: \(trusted)")
    }
    
    /// Start polling for permission and auto-start when granted.
    func startPermissionPolling() {
        // Stop any existing timer
        permissionCheckTimer?.invalidate()
        
        // Check every 1 second
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let wasGranted = self.hasAccessibilityPermission
            self.hasAccessibilityPermission = AXIsProcessTrusted()
            
            // Permission just granted
            if self.hasAccessibilityPermission && !wasGranted {
                logger.info("Accessibility permission granted! Starting listener...")
                self.stopPermissionPolling()
                self.startListening()
            }
            
            // Already listening, stop polling
            if self.isListening {
                self.stopPermissionPolling()
            }
        }
    }
    
    /// Stop polling for permission.
    func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
    
    /// Start listening for the trigger key using CGEvent tap.
    func startListening() {
        guard !isListening else { return }

        // Check permission first
        guard AXIsProcessTrusted() else {
            logger.warning("Cannot start listening - no accessibility permission")
            requestAccessibilityPermission()
            // Start polling for permission to auto-start when granted
            startPermissionPolling()
            return
        }

        // Stop polling if we were polling
        stopPermissionPolling()

        // Create event tap for flagsChanged and keyDown events
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        // We need to use a static callback, so we pass self as userInfo
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                // Handle tap disabled events
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    logger.warning("Event tap was disabled, re-enabling...")
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                manager.handleCGEvent(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            logger.error("Failed to create event tap - check accessibility permissions")
            return
        }

        eventTap = tap

        // Create run loop source and add to MAIN run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        isListening = true
        hasAccessibilityPermission = true
        previousFlags = 0
        logger.warning("Push-to-talk listening started: \(self.triggerKey.displayName)")
        print("[HotkeyManager] Push-to-talk listening started: \(self.triggerKey.displayName)")
    }
    
    /// Stop listening for the trigger key.
    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        
        stopPermissionPolling()
        eventTap = nil
        isListening = false
        isKeyDown = false
        previousFlags = 0
        logger.info("Push-to-talk listening stopped")
    }
    
    private func saveTriggerKey() {
        UserDefaults.standard.set(triggerKey.rawValue, forKey: "triggerKey")
        logger.info("Trigger key saved: \(self.triggerKey.displayName)")
    }

    private func saveClassicShortcut() {
        if let shortcut = classicShortcut,
           let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "classicRecordingShortcut")
        } else {
            UserDefaults.standard.removeObject(forKey: "classicRecordingShortcut")
        }
    }

    private func handleCGEvent(_ event: CGEvent) {
        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            handleKeyDown(event)
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let currentFlags = event.flags.rawValue
        let flagMask = triggerKey.deviceFlagMask

        logger.warning("CGEvent flags=\(currentFlags, format: .hex), mask=\(flagMask, format: .hex)")

        let wasPressed = (previousFlags & flagMask) != 0
        let isPressed = (currentFlags & flagMask) != 0
        previousFlags = currentFlags

        if isPressed && !wasPressed {
            logger.warning(">>> KEY DOWN (\(self.triggerKey.displayName))")
            print("[HotkeyManager] >>> KEY DOWN")
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
        } else if !isPressed && wasPressed {
            logger.warning(">>> KEY UP (\(self.triggerKey.displayName))")
            print("[HotkeyManager] >>> KEY UP")
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Escape → cancel classic recording
        if keyCode == 53 {
            DispatchQueue.main.async { [weak self] in
                self?.onClassicEscape?()
            }
            return
        }

        // Classic shortcut match
        if let shortcut = classicShortcut, shortcut.matches(event: event) {
            DispatchQueue.main.async { [weak self] in
                self?.onClassicToggle?()
            }
        }
    }
    
    deinit {
        stopPermissionPolling()
        stopListening()
    }
}
