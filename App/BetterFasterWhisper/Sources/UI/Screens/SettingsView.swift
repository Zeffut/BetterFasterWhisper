//
//  SettingsView.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import SwiftUI

/// Main settings window.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    private enum Tab: String, CaseIterable {
        case general = "General"
        case models = "Models"
        case shortcuts = "Shortcuts"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .models: return "cpu"
            case .shortcuts: return "keyboard"
            case .about: return "info.circle"
            }
        }
    }
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(Tab.general.rawValue, systemImage: Tab.general.icon)
                }

            ModelsSettingsView()
                .tabItem {
                    Label(Tab.models.rawValue, systemImage: Tab.models.icon)
                }
            
            ShortcutsSettingsView()
                .tabItem {
                    Label(Tab.shortcuts.rawValue, systemImage: Tab.shortcuts.icon)
                }
            
            AboutSettingsView()
                .tabItem {
                    Label(Tab.about.rawValue, systemImage: Tab.about.icon)
                }
        }
        .frame(width: 600, height: 450)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("overlayStyle") private var overlayStyle: String = "mini"
    @AppStorage("selectedLanguage") private var selectedLanguage = "auto"
    
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @ObservedObject private var mediaControlManager = MediaControlManager.shared
    
    private let languages = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("fr", "French"),
        ("de", "German"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ru", "Russian"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("tr", "Turkish"),
        ("vi", "Vietnamese"),
        ("th", "Thai"),
        ("id", "Indonesian"),
        ("uk", "Ukrainian")
    ]
    
    var body: some View {
        Form {
            Section("Application") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show in Dock", isOn: $showInDock)
                Toggle("Play sound effects", isOn: $playSound)
            }
            
            Section("Overlay") {
                Picker("Style", selection: $overlayStyle) {
                    Text("Mini (near notch)").tag("mini")
                    Text("Large (expanded waveform)").tag("large")
                }
                .pickerStyle(.menu)
                Text("The large capsule shows the waveform, status, and recording duration. Takes effect after restarting the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Media") {
                Toggle("Pause media when recording", isOn: $mediaControlManager.pauseMediaOnRecord)
                Text("Automatically pause playing media when you start recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Auto-Paste") {
                Toggle("Paste after transcription", isOn: $clipboardManager.autoPasteEnabled)
                
                if clipboardManager.autoPasteEnabled {
                    Toggle("Restore clipboard after paste", isOn: $clipboardManager.restoreClipboard)
                    
                    HStack {
                        Text("Paste delay")
                        Spacer()
                        Slider(value: $clipboardManager.pasteDelay, in: 0.05...0.5, step: 0.05)
                            .frame(width: 150)
                        Text("\(Int(clipboardManager.pasteDelay * 1000))ms")
                            .frame(width: 50)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Accessibility warning
                    if !ClipboardManager.checkAccessibilityPermissions() {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Accessibility permission required for auto-paste")
                                .font(.caption)
                            Spacer()
                            Button("Grant Access") {
                                ClipboardManager.requestAccessibilityPermissions()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section("Language") {
                Picker("Transcription language", selection: $selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Models Settings

struct ModelsSettingsView: View {
    @ObservedObject private var modelManager = ModelManager.shared
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: WhisperModel?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Whisper Models")
                        .font(.headline)
                    Text("Larger models are more accurate but slower. Recommended: \(modelManager.recommendedModel().displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    modelManager.refreshDownloadStates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            
            // Selected model indicator
            HStack {
                Text("Active model:")
                    .foregroundStyle(.secondary)
                Text(modelManager.selectedModel.displayName)
                    .fontWeight(.medium)
                
                if !modelManager.isDownloaded(modelManager.selectedModel) {
                    Text("(Not downloaded)")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.1))
            .cornerRadius(8)
            
            List {
                ForEach(WhisperModel.allCases) { model in
                    ModelRowView(
                        model: model,
                        isSelected: model == modelManager.selectedModel,
                        downloadState: modelManager.downloadStates[model] ?? .notDownloaded,
                        onSelect: {
                            if modelManager.isDownloaded(model) {
                                modelManager.selectedModel = model
                            }
                        },
                        onDownload: {
                            modelManager.downloadModel(model)
                        },
                        onCancel: {
                            modelManager.cancelDownload(model)
                        },
                        onDelete: {
                            modelToDelete = model
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
            .listStyle(.bordered)
        }
        .padding()
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    try? modelManager.deleteModel(model)
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("Are you sure you want to delete \(model.displayName)? You can re-download it later.")
            }
        }
    }
}

// MARK: - Model Row View

struct ModelRowView: View {
    let model: WhisperModel
    let isSelected: Bool
    let downloadState: DownloadState
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            } else if downloadState.isDownloaded {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.tertiary)
            }
            
            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                    
                    if model.isEnglishOnly {
                        Text("EN")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                
                HStack(spacing: 8) {
                    // Speed indicator
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Circle()
                                .fill(i < model.speedRating ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        Text("Speed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Accuracy indicator
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Circle()
                                .fill(i < model.accuracyRating ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        Text("Accuracy")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(model.recommendedRAM)GB RAM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Action buttons
            switch downloadState {
            case .notDownloaded:
                Button("Download") {
                    onDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
            case .downloading(let progress):
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
            case .downloaded, .loading, .ready:
                HStack(spacing: 8) {
                    if !isSelected {
                        Button("Select") {
                            onSelect()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
                
            case .error(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Retry") {
                        onDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if downloadState.isDownloaded {
                onSelect()
            }
        }
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    
    var body: some View {
        Form {
            Section("Push-to-Talk") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trigger Key")
                        .font(.headline)

                    Text("Hold down this key to record, release to transcribe")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Trigger Key", selection: $hotkeyManager.triggerKey) {
                        ForEach(TriggerKey.allCases) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .padding(.vertical, 8)
            }

            Section("Classic Recording") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Global Shortcut")
                        .font(.headline)

                    Text("Press once to start recording, press again (or click Stop) to transcribe. Esc cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ShortcutCaptureField(shortcut: Binding(
                        get: { hotkeyManager.classicShortcut },
                        set: { hotkeyManager.classicShortcut = $0 }
                    ))
                    .frame(height: 32)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                HStack {
                    Image(systemName: hotkeyManager.isListening ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hotkeyManager.isListening ? .green : .red)
                    Text(hotkeyManager.isListening ? "Push-to-talk is active" : "Push-to-talk is inactive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("How it works") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Press and hold the trigger key to start recording")
                            .font(.caption)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        Text("Release the key to stop and transcribe")
                            .font(.caption)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text("Text is automatically copied and pasted")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section {
                Text("Note: Accessibility permissions are required for global key detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            Text("BetterFasterWhisper")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 0.1.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("A free, open-source voice-to-text application\npowered by OpenAI Whisper")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundStyle(.secondary)
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/yourusername/BetterFasterWhisper")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/yourusername/BetterFasterWhisper/issues")!)
            }
            .font(.caption)
            
            Spacer()
            
            HStack(spacing: 16) {
                VStack {
                    Text("Built with")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 8) {
                        Text("Swift")
                        Text("Rust")
                        Text("whisper.cpp")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            
            Text("Licensed under MIT")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shortcut Capture Field

struct ShortcutCaptureField: NSViewRepresentable {
    @Binding var shortcut: ClassicShortcut?

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onShortcutChanged = { newShortcut in
            shortcut = newShortcut
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.currentShortcut = shortcut
    }
}

class ShortcutCaptureNSView: NSView {
    var currentShortcut: ClassicShortcut? { didSet { updateDisplay() } }
    var onShortcutChanged: ((ClassicShortcut?) -> Void)?

    private var isCapturing = false
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "×", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        addSubview(label)

        clearButton.bezelStyle = .rounded
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 14)
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        addSubview(clearButton)

        let click = NSClickGestureRecognizer(target: self, action: #selector(startCapture))
        addGestureRecognizer(click)

        updateDisplay()
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let btnW: CGFloat = clearButton.isHidden ? 0 : h
        clearButton.frame = NSRect(x: w - btnW, y: 0, width: btnW, height: h)
        label.frame = NSRect(x: 8, y: 0, width: w - btnW - 8, height: h)
    }

    private func updateDisplay() {
        if isCapturing {
            label.stringValue = "Press keys..."
            label.textColor = .white
            layer?.backgroundColor = NSColor.systemBlue.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            clearButton.isHidden = true
        } else if let s = currentShortcut {
            label.stringValue = s.displayString
            label.textColor = .labelColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            clearButton.isHidden = false
        } else {
            label.stringValue = "Click to record shortcut"
            label.textColor = .placeholderTextColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            clearButton.isHidden = true
        }
        needsLayout = true
    }

    @objc private func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        window?.makeFirstResponder(self)
        updateDisplay()
    }

    @objc private func clearShortcut() {
        onShortcutChanged?(nil)
        isCapturing = false
        window?.makeFirstResponder(nil)
        updateDisplay()
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels capture without changing shortcut
        if event.keyCode == 53 {
            isCapturing = false
            window?.makeFirstResponder(nil)
            updateDisplay()
            return
        }

        guard !ClassicShortcut.modifierKeyCodes.contains(event.keyCode) else { return }

        // Build modifier flags from NSEvent
        var flags: UInt64 = 0
        if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
        if event.modifierFlags.contains(.option)  { flags |= CGEventFlags.maskAlternate.rawValue }
        if event.modifierFlags.contains(.shift)   { flags |= CGEventFlags.maskShift.rawValue }
        if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }

        guard flags != 0 else { return } // Need at least one modifier

        let captured = ClassicShortcut(keyCode: event.keyCode, modifierFlags: flags)
        isCapturing = false
        onShortcutChanged?(captured)
        window?.makeFirstResponder(nil)
        updateDisplay()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
