//
//  AppState.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import Foundation
import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: "com.betterfasterwhisper", category: "AppState")

// MARK: - Notifications
extension Notification.Name {
    static let hideOverlay = Notification.Name("com.betterfasterwhisper.hideOverlay")
}

/// Global application state observable from any view.
@MainActor
final class AppState: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AppState()
    
    // MARK: - Published Properties
    
    /// Current recording state.
    @Published var isRecording = false
    
    /// Current transcription in progress.
    @Published var isTranscribing = false
    
    /// Last transcription result.
    @Published var lastTranscription: TranscriptionResult?
    
    /// Current selected mode.
    @Published var currentMode: TranscriptionMode = .voice
    
    /// Error message to display.
    @Published var errorMessage: String?
    
    /// Whether the engine is initialized.
    @Published var isEngineReady = false
    
    /// Recording duration in seconds.
    @Published var recordingDuration: TimeInterval = 0
    
    /// Audio level (0.0 - 1.0).
    @Published var audioLevel: Float = 0
    
    // MARK: - Private Properties
    
    private var recordingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    /// Timer for progressive transcription during long recordings
    private var progressiveTranscriptionTimer: Timer?
    
    /// Accumulated transcription results from progressive chunks
    private var progressiveTranscriptions: [String] = []
    
    /// Sample index up to which we've already transcribed
    private var lastTranscribedSampleIndex: Int = 0
    
    /// Whether a progressive transcription is currently in progress
    private var isProgressiveTranscribing: Bool = false
    
    /// Threshold in seconds before starting progressive transcription
    private let progressiveTranscriptionThreshold: TimeInterval = 10.0
    
    /// Interval between progressive transcription checks
    private let progressiveTranscriptionInterval: TimeInterval = 10.0
    
    // MARK: - Initialization
    
    private init() {
        setupBindings()
    }
    
    private func setupBindings() {
        // Listen to whisper service state changes
        WhisperService.shared.$isInitialized
            .receive(on: DispatchQueue.main)
            .assign(to: &$isEngineReady)
    }
    
    // MARK: - Actions
    
    /// Toggles recording state.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Starts audio recording.
    func startRecording() {
        guard isEngineReady else {
            errorMessage = "Engine not ready"
            return
        }
        
        guard !isRecording else { return }
        
        isRecording = true
        recordingDuration = 0
        errorMessage = nil
        
        // Reset progressive transcription state
        progressiveTranscriptions = []
        lastTranscribedSampleIndex = 0
        isProgressiveTranscribing = false
        
        // Start recording timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.recordingDuration += 0.1
            }
        }

        // Start progressive transcription timer (checks every 10s after initial 10s)
        progressiveTranscriptionTimer = Timer.scheduledTimer(withTimeInterval: progressiveTranscriptionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                await self.performProgressiveTranscription()
            }
        }
        
        // Start actual recording
        Task {
            do {
                try await AudioRecorder.shared.startRecording()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isRecording = false
                }
            }
        }
        
        // Show recording panel
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showRecordingPanel()
        }
    }
    
    /// Stops recording and starts transcription.
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        progressiveTranscriptionTimer?.invalidate()
        progressiveTranscriptionTimer = nil
        
        // Stop recording and transcribe
        Task {
            isTranscribing = true
            AudioLevelManager.shared.setTranscribing(true)
            
            do {
                // Use stopRecordingAndGetSamples for efficiency (avoids Float→Data→Float conversion)
                let allSamples = try await AudioRecorder.shared.stopRecordingAndGetSamples()
                
                // Get only the remaining samples that haven't been transcribed yet
                let remainingSamples: [Float]
                if lastTranscribedSampleIndex > 0 && lastTranscribedSampleIndex < allSamples.count {
                    remainingSamples = Array(allSamples[lastTranscribedSampleIndex...])
                    logger.info("Progressive: transcribing remaining \(remainingSamples.count) samples (from \(self.lastTranscribedSampleIndex))")
                } else {
                    remainingSamples = allSamples
                    logger.info("Progressive: transcribing all \(remainingSamples.count) samples (no progressive chunks)")
                }
                
                // Use the configured language (defaults to French)
                let language = WhisperService.shared.transcriptionLanguage
                
                // Transcribe remaining samples (if any)
                var finalText = ""
                if !remainingSamples.isEmpty {
                    // Only transcribe if we have at least 0.5s of audio
                    if remainingSamples.count >= 8000 {
                        let result = try await WhisperService.shared.transcribe(samples: remainingSamples, language: language)
                        finalText = result.text
                    }
                }
                
                // Combine progressive transcriptions with final chunk
                let allTexts = progressiveTranscriptions + (finalText.isEmpty ? [] : [finalText])
                let combinedText = allTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Calculate total audio duration
                let audioDuration = Double(allSamples.count) / 16000.0
                
                logger.info("Progressive: combined \(allTexts.count) chunks into final text (\(combinedText.count) chars)")
                
                let finalResult = TranscriptionResult(
                    text: combinedText,
                    segments: [],
                    language: language ?? "unknown",
                    processingTime: 0, // Not meaningful for progressive
                    audioDuration: audioDuration
                )
                
                await MainActor.run {
                    self.lastTranscription = finalResult
                    
                    // Hide overlay immediately (before resetting isTranscribing to avoid flash back to waveform)
                    NotificationCenter.default.post(name: .hideOverlay, object: nil)
                    
                    self.isTranscribing = false
                    AudioLevelManager.shared.setTranscribing(false)
                    
                    // Copy to clipboard and paste
                    self.copyAndPaste(finalResult.text)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    
                    // Hide overlay immediately on error too
                    NotificationCenter.default.post(name: .hideOverlay, object: nil)
                    
                    self.isTranscribing = false
                    AudioLevelManager.shared.setTranscribing(false)
                }
            }
        }
    }
    
    /// Performs progressive transcription of accumulated audio during recording.
    /// Called periodically to transcribe chunks while still recording.
    private func performProgressiveTranscription() async {
        // Atomically check and set the flag to prevent concurrent transcriptions
        guard !isProgressiveTranscribing else {
            logger.info("Progressive: skipping, transcription already in progress")
            return
        }

        // Only transcribe if we're still recording
        guard isRecording else { return }

        // Get current sample count
        let currentSampleCount = await AudioRecorder.shared.getCurrentSampleCount()

        // Calculate how many new samples we have since last transcription
        let newSamplesCount = currentSampleCount - lastTranscribedSampleIndex

        // Need at least 8000 samples (0.5s at 16kHz) to transcribe
        guard newSamplesCount >= 8000 else {
            logger.info("Progressive: not enough new samples (\(newSamplesCount))")
            return
        }

        logger.info("Progressive: starting transcription of \(newSamplesCount) samples (from index \(self.lastTranscribedSampleIndex))")

        // Atomically set flag before async operation
        isProgressiveTranscribing = true
        defer { isProgressiveTranscribing = false }

        // Get samples from last transcribed index
        let samples = await AudioRecorder.shared.getSamplesFrom(index: lastTranscribedSampleIndex)

        guard !samples.isEmpty else {
            return
        }

        // Remember where we're transcribing up to BEFORE we start
        // (more samples may arrive during transcription)
        let transcribingUpToIndex = currentSampleCount

        do {
            let language = WhisperService.shared.transcriptionLanguage
            let result = try await WhisperService.shared.transcribe(samples: samples, language: language)

            // Only save result if we're still recording (user might have stopped)
            if isRecording {
                let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    progressiveTranscriptions.append(trimmedText)
                    lastTranscribedSampleIndex = transcribingUpToIndex
                    logger.info("Progressive: saved chunk '\(trimmedText.prefix(50))...' (total \(self.progressiveTranscriptions.count) chunks)")
                }
            }
        } catch {
            logger.error("Progressive transcription failed: \(error.localizedDescription)")
        }
    }
    
    /// Cancels the current recording without transcribing.
    func cancelRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        progressiveTranscriptionTimer?.invalidate()
        progressiveTranscriptionTimer = nil
        
        // Reset progressive transcription state
        progressiveTranscriptions = []
        lastTranscribedSampleIndex = 0
        isProgressiveTranscribing = false
        
        Task {
            await AudioRecorder.shared.cancelRecording()
        }
        
        // Hide recording panel
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.hideRecordingPanel()
        }
    }
    
    /// Changes the current transcription mode.
    func setMode(_ mode: TranscriptionMode) {
        currentMode = mode
    }
    
    // MARK: - Clipboard

    private func copyAndPaste(_ text: String) {
        guard !text.isEmpty else {
            logger.warning("copyAndPaste: empty text, skipping")
            return
        }

        logger.info("copyAndPaste: copying \(text.count) chars to clipboard")

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Use ClipboardManager for safe auto-paste if enabled
        Task { @MainActor in
            await ClipboardManager.shared.copyAndPaste(text)
        }
    }
}
