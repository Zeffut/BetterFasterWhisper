//
//  AppDelegate.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import AppKit
import SwiftUI
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.betterfasterwhisper", category: "AppDelegate")

/// Main application delegate handling system-level events and global shortcuts.
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var miniOverlayWindow: NSWindow?
    static var shared: AppDelegate?
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Hide dock icon (menu bar only app)
        NSApp.setActivationPolicy(.accessory)
        
        logger.info("BetterFasterWhisper starting...")
        
        // Request accessibility permission FIRST (this adds app to the list)
        requestAccessibilityPermission()
        
        // Request microphone permission
        requestMicrophonePermission()
        
        // Initialize whisper engine
        Task {
            AudioLevelManager.shared.setLoading(true, message: "Loading model...")
            logger.info("Starting WhisperKit initialization...")
            await WhisperService.shared.initialize()
            logger.info("WhisperKit initialized, isInitialized: \(WhisperService.shared.isInitialized)")
            AudioLevelManager.shared.setLoading(false)
        }
        
        // Setup push-to-talk hotkey
        setupPushToTalk()
        
        // Setup audio level callback
        setupAudioLevelCallback()
        
        // Listen for hide overlay notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideOverlayNotification),
            name: .hideOverlay,
            object: nil
        )
        
        logger.info("BetterFasterWhisper started successfully")
    }
    
    @objc private func handleHideOverlayNotification() {
        logger.info("Received hide overlay notification")
        DispatchQueue.main.async { [weak self] in
            self?.hideMiniOverlay()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stopListening()
        WhisperService.shared.shutdown()
        print("BetterFasterWhisper terminated")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Push-to-Talk Setup
    
    private func setupPushToTalk() {
        Task { @MainActor in
            let hotkeyManager = HotkeyManager.shared

            hotkeyManager.onKeyDown = { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.handleKeyDown()
                }
            }

            hotkeyManager.onKeyUp = { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.handleKeyUp()
                }
            }
            
            hotkeyManager.startListening()
            print("Push-to-talk registered: \(hotkeyManager.triggerKey.displayName)")
        }
    }
    
    private func setupAudioLevelCallback() {
        Task {
            await AudioRecorder.shared.setAudioLevelCallback { levels in
                AudioLevelManager.shared.updateLevels(levels)
            }
        }
    }
    
    @MainActor
    private func handleKeyDown() {
        logger.info("handleKeyDown - isRecording: \(AppState.shared.isRecording), isEngineReady: \(AppState.shared.isEngineReady)")
        guard !AppState.shared.isRecording else { return }
        
        // Always show the overlay
        showMiniOverlay()
        
        // Check if engine is ready
        if !AppState.shared.isEngineReady {
            // Show loading state in overlay
            AudioLevelManager.shared.setLoading(true, message: "Loading model...")
            logger.warning("Engine not ready, showing loading state")
            return
        }
        
        // Pause any playing media
        MediaControlManager.shared.pauseMedia()
        
        // Engine is ready, start recording
        AudioLevelManager.shared.setLoading(false)
        logger.info("Starting recording...")
        AppState.shared.startRecording()
    }
    
    @MainActor
    private func handleKeyUp() {
        logger.info("handleKeyUp - isRecording: \(AppState.shared.isRecording)")
        if AppState.shared.isRecording {
            logger.info("Stopping recording and starting transcription...")
            AppState.shared.stopRecording()
            
            // Resume media playback
            MediaControlManager.shared.resumeMedia()
            
            // Fallback: hide overlay after max wait time (in case transcription fails)
            scheduleHideOverlay(delay: 10.0)
        } else {
            // Recording wasn't started (engine not ready), reset media state
            MediaControlManager.shared.reset()
            hideMiniOverlay()
        }
    }
    
    private func scheduleHideOverlay(delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            let isRecording = AppState.shared.isRecording
            let isTranscribing = AppState.shared.isTranscribing
            logger.info("scheduleHideOverlay check - isRecording: \(isRecording), isTranscribing: \(isTranscribing)")
            
            // Only hide if not recording and not transcribing
            if !isRecording && !isTranscribing {
                self?.hideMiniOverlay()
            }
        }
    }
    
    // MARK: - Permissions
    
    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("Microphone access authorized")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print(granted ? "Microphone access granted" : "Microphone access denied")
            }
        case .denied, .restricted:
            print("Microphone access denied or restricted")
        @unknown default:
            break
        }
    }
    
    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print(accessEnabled ? "Accessibility access granted" : "Accessibility access needed - prompting user")
    }
    
    // MARK: - Mini Overlay
    
    func showMiniOverlay() {
        // Re-create window if size changed (e.g. style switched in Settings)
        if let existing = miniOverlayWindow,
           existing.frame.size != overlaySize {
            existing.orderOut(nil)
            miniOverlayWindow = nil
        }

        if miniOverlayWindow == nil {
            createMiniOverlay()
        }

        AudioLevelManager.shared.reset()
        positionMiniOverlay()
        miniOverlayWindow?.orderFront(nil)
    }
    
    func hideMiniOverlay() {
        miniOverlayWindow?.orderOut(nil)
        AudioLevelManager.shared.reset()
    }
    
    private var overlaySize: NSSize {
        let style = UserDefaults.standard.string(forKey: "overlayStyle") ?? "mini"
        return style == "large"
            ? NSSize(width: 520, height: 120)
            : NSSize(width: 72, height: 28)
    }

    private func createMiniOverlay() {
        let overlayView = AudioWaveformOverlay()
        let hostingView = NSHostingView(rootView: overlayView)
        
        // Fixed window size matching the SwiftUI view size
        let windowWidth = overlaySize.width
        let windowHeight = overlaySize.height
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hasShadow = false // Shadow is handled by SwiftUI
        window.ignoresMouseEvents = true
        window.contentView = hostingView
        
        // Force layout before positioning
        hostingView.layoutSubtreeIfNeeded()
        
        miniOverlayWindow = window
    }
    
    private func positionMiniOverlay() {
        guard let window = miniOverlayWindow,
              let screen = NSScreen.main else { return }
        
        let screenFrame = screen.frame
        
        // Fixed window size
        let windowWidth = overlaySize.width
        let windowHeight = overlaySize.height
        
        // Ensure window has correct size
        window.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        
        // Calculate the menu bar / notch height
        let notchSafeHeight: CGFloat
        if #available(macOS 12.0, *) {
            let safeAreaTop = screen.safeAreaInsets.top
            notchSafeHeight = max(safeAreaTop, 38)
        } else {
            notchSafeHeight = 38
        }
        
        // Center horizontally on screen, position below notch
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.maxY - notchSafeHeight - windowHeight - 10
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    func showRecordingPanel() {
        showMiniOverlay()
    }
    
    func hideRecordingPanel() {
        hideMiniOverlay()
    }
}

// MARK: - Audio Level Manager

class AudioLevelManager: ObservableObject {
    static let shared = AudioLevelManager()
    
    @Published var audioLevels: [Float] = Array(repeating: 0.05, count: 12)
    @Published var isModelLoading: Bool = true
    @Published var isTranscribing: Bool = false
    @Published var statusMessage: String = "Loading model..."
    @Published var recordingDuration: TimeInterval = 0
    @Published var isClassicRecording: Bool = false

    var statusColor: Color {
        if isModelLoading { return .gray }
        if isTranscribing { return .orange }
        return .blue  // recording
    }

    func updateLevels(_ levels: [Float]) {
        DispatchQueue.main.async {
            self.audioLevels = levels
        }
    }
    
    func reset() {
        audioLevels = Array(repeating: 0.05, count: 12)
    }
    
    func setLoading(_ loading: Bool, message: String = "") {
        DispatchQueue.main.async {
            self.isModelLoading = loading
            self.statusMessage = message
        }
    }
    
    func setTranscribing(_ transcribing: Bool) {
        DispatchQueue.main.async {
            self.isTranscribing = transcribing
        }
    }
}

// MARK: - Audio Waveform Overlay View

struct AudioWaveformOverlay: View {
    @ObservedObject var levelManager = AudioLevelManager.shared
    @AppStorage("overlayStyle") private var overlayStyle: String = "mini"

    // Dimensions
    private let waveformWidth: CGFloat = 72
    private let waveformHeight: CGFloat = 28
    private let spinnerWidth: CGFloat = 45  // Wider for 3 dots
    private let spinnerHeight: CGFloat = 24 // Shorter height
    private let barCount = 12

    /// Current width based on state
    private var currentWidth: CGFloat {
        levelManager.isTranscribing ? spinnerWidth : waveformWidth
    }

    /// Current height based on state
    private var currentHeight: CGFloat {
        levelManager.isTranscribing ? spinnerHeight : waveformHeight
    }

    var body: some View {
        if overlayStyle == "large" {
            LargeOverlayContent()
        } else {
            miniBody
        }
    }

    private var miniBody: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.9))
                .frame(width: currentWidth, height: currentHeight)

            if levelManager.isModelLoading {
                HStack(spacing: 4) {
                    PulsingDotsView()
                    Text("Loading...")
                        .foregroundColor(.white)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
            } else if levelManager.isTranscribing {
                PulsingDotsView()
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white)
                            .frame(width: 2, height: barHeight(for: levelManager.audioLevels[index % levelManager.audioLevels.count]))
                    }
                }
                .animation(.easeOut(duration: 0.08), value: levelManager.audioLevels)
            }
        }
        .frame(width: waveformWidth, height: waveformHeight)
        .animation(.easeInOut(duration: 0.2), value: levelManager.isTranscribing)
    }

    private func barHeight(for level: Float) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 18
        // Amplify the level for more visible movement
        let amplifiedLevel = min(1.0, level * 1.8)
        return minHeight + CGFloat(amplifiedLevel) * (maxHeight - minHeight)
    }
}

// MARK: - Pulsing Dots Spinner

struct PulsingDotsView: View {
    @State private var animationPhase: Int = 0
    @State private var animationTimer: Timer?

    private let dotCount = 3
    private let dotSize: CGFloat = 5
    private let spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(scaleForDot(at: index))
                    .opacity(opacityForDot(at: index))
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }

    private func scaleForDot(at index: Int) -> CGFloat {
        animationPhase == index ? 1.3 : 0.8
    }

    private func opacityForDot(at index: Int) -> Double {
        animationPhase == index ? 1.0 : 0.4
    }

    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                animationPhase = (animationPhase + 1) % dotCount
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

#Preview {
    AudioWaveformOverlay()
        .padding()
        .background(Color.gray)
}

// MARK: - Large Overlay Content

struct LargeOverlayContent: View {
    @ObservedObject var levelManager = AudioLevelManager.shared

    private let barCount = 40
    private let panelWidth: CGFloat = 520
    private let panelHeight: CGFloat = 120
    private let waveformHeight: CGFloat = 76
    private let controlBarHeight: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.88))
                .frame(width: panelWidth, height: panelHeight)

            VStack(spacing: 0) {
                waveformArea
                    .frame(width: panelWidth, height: waveformHeight)
                    .clipped()

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                controlBar
                    .frame(width: panelWidth, height: controlBarHeight)
            }
        }
        .frame(width: panelWidth, height: panelHeight)
    }

    // MARK: Waveform

    @ViewBuilder
    private var waveformArea: some View {
        if levelManager.isModelLoading {
            Text("Loading model...")
                .foregroundColor(.white.opacity(0.45))
                .font(.system(size: 13, weight: .medium))
        } else if levelManager.isTranscribing {
            PulsingDotsView()
        } else {
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = levelManager.audioLevels[index % levelManager.audioLevels.count]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 3, height: barHeight(for: level))
                }
            }
            .animation(.easeOut(duration: 0.06), value: levelManager.audioLevels)
        }
    }

    // MARK: Control Bar

    private var controlBar: some View {
        HStack(spacing: 0) {
            // Left: status dot + state label
            HStack(spacing: 6) {
                Circle()
                    .fill(levelManager.statusColor)
                    .frame(width: 8, height: 8)
                Text(stateLabel)
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(width: 110, alignment: .leading)
            .padding(.leading, 16)

            Spacer()

            // Center: timer (hidden during transcription/loading)
            if !levelManager.isModelLoading && !levelManager.isTranscribing {
                Text(formatDuration(levelManager.recordingDuration))
                    .foregroundColor(.white.opacity(0.45))
                    .font(.system(size: 12, weight: .light, design: .monospaced))
            }

            Spacer()

            // Right: Stop + Cancel (classic recording only)
            if levelManager.isClassicRecording {
                HStack(spacing: 8) {
                    Button("Stop") {
                        AudioLevelManager.shared.isClassicRecording = false
                        AppState.shared.stopRecording()
                    }
                    .buttonStyle(OverlayButtonStyle(isDestructive: false))

                    Button("Cancel") {
                        AudioLevelManager.shared.isClassicRecording = false
                        AppState.shared.cancelRecording()
                    }
                    .buttonStyle(OverlayButtonStyle(isDestructive: true))
                }
                .padding(.trailing, 16)
            } else {
                Spacer().frame(width: 16)
            }
        }
    }

    // MARK: Helpers

    private var stateLabel: String {
        if levelManager.isModelLoading { return "Loading..." }
        if levelManager.isTranscribing { return "Processing..." }
        return "Voice"
    }

    private func barHeight(for level: Float) -> CGFloat {
        let minH: CGFloat = 3
        let maxH: CGFloat = 64
        let amplified = min(1.0, level * 3.5)
        return minH + CGFloat(amplified) * (maxH - minH)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Overlay Button Style

struct OverlayButtonStyle: ButtonStyle {
    let isDestructive: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDestructive ? Color.red.opacity(0.9) : Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(configuration.isPressed ? 0.25 : 0.12))
            .clipShape(Capsule())
    }
}

#Preview("Large Overlay") {
    LargeOverlayContent()
        .padding()
        .background(Color.gray.opacity(0.3))
}
