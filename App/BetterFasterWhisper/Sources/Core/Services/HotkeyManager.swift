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

        // Create event tap for flagsChanged events
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

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
    
    private func handleCGEvent(_ event: CGEvent) {
        let currentFlags = event.flags.rawValue
        let flagMask = triggerKey.deviceFlagMask
        
        // Log every event at warning level so we can see it
        logger.warning("CGEvent flags=\(currentFlags, format: .hex), mask=\(flagMask, format: .hex)")
        
        // Compare previous state with current state
        let wasPressed = (previousFlags & flagMask) != 0
        let isPressed = (currentFlags & flagMask) != 0
        
        // Update previous flags for next comparison
        previousFlags = currentFlags
        
        // Detect state change
        if isPressed && !wasPressed {
            // Key just pressed
            logger.warning(">>> KEY DOWN (\(self.triggerKey.displayName))")
            print("[HotkeyManager] >>> KEY DOWN")
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onKeyDown?()
            }
        } else if !isPressed && wasPressed {
            // Key just released
            logger.warning(">>> KEY UP (\(self.triggerKey.displayName))")
            print("[HotkeyManager] >>> KEY UP")
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onKeyUp?()
            }
        }
    }
    
    deinit {
        stopPermissionPolling()
        stopListening()
    }
}
