//
//  ClipboardManager.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import AppKit
import Carbon.HIToolbox

/// Manages clipboard operations and auto-paste functionality.
@MainActor
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    /// Whether auto-paste is enabled.
    @Published var autoPasteEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPasteEnabled")
        }
    }
    
    /// Delay before pasting (in seconds).
    @Published var pasteDelay: Double {
        didSet {
            UserDefaults.standard.set(pasteDelay, forKey: "pasteDelay")
        }
    }
    
    /// Whether to restore original clipboard after paste.
    @Published var restoreClipboard: Bool {
        didSet {
            UserDefaults.standard.set(restoreClipboard, forKey: "restoreClipboard")
        }
    }
    
    private var savedClipboardContent: String?
    
    private init() {
        self.autoPasteEnabled = UserDefaults.standard.bool(forKey: "autoPasteEnabled")
        self.pasteDelay = UserDefaults.standard.double(forKey: "pasteDelay")
        self.restoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboard")
        
        // Set defaults if not set
        if pasteDelay == 0 {
            pasteDelay = 0.1
        }
        if !UserDefaults.standard.bool(forKey: "autoPasteEnabledSet") {
            autoPasteEnabled = true
            UserDefaults.standard.set(true, forKey: "autoPasteEnabledSet")
        }
    }
    
    // MARK: - Clipboard Operations
    
    /// Copy text to clipboard.
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        
        // Save current clipboard if restore is enabled
        if restoreClipboard {
            savedClipboardContent = pasteboard.string(forType: .string)
        }
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Get current clipboard content.
    func getClipboardContent() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
    
    /// Restore previously saved clipboard content.
    func restoreOriginalClipboard() {
        guard let saved = savedClipboardContent else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(saved, forType: .string)
        savedClipboardContent = nil
    }
    
    // MARK: - Auto-Paste
    
    /// Copy text and paste it to the frontmost application.
    func copyAndPaste(_ text: String) async {
        copyToClipboard(text)
        
        if autoPasteEnabled {
            // Small delay to ensure clipboard is ready
            try? await Task.sleep(nanoseconds: UInt64(pasteDelay * 1_000_000_000))
            
            simulatePaste()
            
            // Restore clipboard after a delay
            if restoreClipboard {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                restoreOriginalClipboard()
            }
        }
    }
    
    /// Simulate Cmd+V keystroke to paste.
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key down: Cmd + V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        
        // Key up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
    
    /// Type text character by character (alternative to paste).
    func typeText(_ text: String) {
        for char in text {
            typeCharacter(char)
            // Small delay between characters
            usleep(10000) // 10ms
        }
    }
    
    private func typeCharacter(_ char: Character) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Create key event
        if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            var chars = [UniChar](String(char).utf16)
            event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            event.post(tap: .cghidEventTap)
        }
        
        // Key up
        if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Accessibility
    
    /// Check if accessibility permissions are granted.
    static func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Request accessibility permissions.
    static func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Open System Preferences to accessibility settings.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
