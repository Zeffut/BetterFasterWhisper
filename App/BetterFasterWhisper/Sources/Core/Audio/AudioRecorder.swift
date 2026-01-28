//
//  AudioRecorder.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import Foundation
import AVFoundation

/// Error types for audio recording.
enum AudioRecorderError: LocalizedError {
    case notAuthorized
    case deviceNotAvailable
    case recordingFailed(String)
    case noDataRecorded
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Microphone access not authorized"
        case .deviceNotAvailable:
            return "No audio input device available"
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
        case .noDataRecorded:
            return "No audio data was recorded"
        }
    }
}

/// Handles audio recording from the microphone.
actor AudioRecorder {
    
    // MARK: - Singleton
    
    static let shared = AudioRecorder()
    
    // MARK: - Properties
    
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var isRecording = false
    
    /// Sample rate for recording (Whisper expects 16kHz).
    private let targetSampleRate: Double = 16000
    
    /// Callback for real-time audio levels (array of recent samples for waveform)
    private var audioLevelCallback: (([Float]) -> Void)?
    
    /// Number of bars in the waveform visualization
    private let waveformBarCount = 12
    
    /// Recent audio levels for waveform display
    private var recentLevels: [Float] = []
    
    // MARK: - Initialization
    
    private init() {
        recentLevels = Array(repeating: 0, count: waveformBarCount)
    }
    
    // MARK: - Public Methods
    
    /// Sets the callback for real-time audio level updates.
    func setAudioLevelCallback(_ callback: (([Float]) -> Void)?) {
        audioLevelCallback = callback
    }
    
    // MARK: - Public Methods
    
    /// Starts recording audio from the default input device.
    func startRecording() async throws {
        guard !isRecording else { return }
        
        // Check authorization
        guard await checkAuthorization() else {
            throw AudioRecorderError.notAuthorized
        }
        
        // Setup audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Get the native format
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
        guard nativeFormat.sampleRate > 0 else {
            throw AudioRecorderError.deviceNotAvailable
        }
        
        // Create format for recording (mono, 16kHz)
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.recordingFailed("Failed to create audio format")
        }
        
        // Create a converter if sample rates differ
        let converter = AVAudioConverter(from: nativeFormat, to: recordingFormat)
        
        // Clear previous buffer
        audioBuffer.removeAll()
        recentLevels = Array(repeating: 0, count: waveformBarCount)
        
        // Install tap on input
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            Task {
                await self?.processAudioBuffer(buffer, converter: converter, outputFormat: recordingFormat)
            }
        }
        
        // Start engine
        do {
            try engine.start()
            audioEngine = engine
            isRecording = true
            print("Recording started")
        } catch {
            throw AudioRecorderError.recordingFailed(error.localizedDescription)
        }
    }
    
    /// Stops recording and returns the recorded audio data.
    func stopRecording() async throws -> Data {
        guard isRecording, let engine = audioEngine else {
            throw AudioRecorderError.noDataRecorded
        }
        
        // Stop engine
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        isRecording = false
        audioEngine = nil
        
        print("Recording stopped. Samples: \(audioBuffer.count)")
        
        guard !audioBuffer.isEmpty else {
            throw AudioRecorderError.noDataRecorded
        }
        
        // Convert float samples to Data (16-bit PCM)
        let data = samplesToData(audioBuffer)
        audioBuffer.removeAll()
        
        return data
    }
    
    /// Stops recording and returns the audio samples directly (more efficient for WhisperKit).
    func stopRecordingAndGetSamples() async throws -> [Float] {
        guard isRecording, let engine = audioEngine else {
            throw AudioRecorderError.noDataRecorded
        }
        
        // Stop engine
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        isRecording = false
        audioEngine = nil
        
        print("Recording stopped. Samples: \(audioBuffer.count)")
        
        guard !audioBuffer.isEmpty else {
            throw AudioRecorderError.noDataRecorded
        }
        
        // Return samples directly (no conversion needed)
        let samples = audioBuffer
        audioBuffer.removeAll()
        
        return samples
    }
    
    /// Cancels the current recording without returning data.
    func cancelRecording() async {
        guard isRecording, let engine = audioEngine else { return }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        isRecording = false
        audioEngine = nil
        audioBuffer.removeAll()
        
        print("Recording cancelled")
    }
    
    /// Returns the current audio level (0.0 - 1.0).
    func currentLevel() -> Float {
        guard !audioBuffer.isEmpty else { return 0 }
        
        // Calculate RMS of last 1600 samples (0.1 seconds at 16kHz)
        let sampleCount = min(1600, audioBuffer.count)
        let recentSamples = audioBuffer.suffix(sampleCount)
        
        let sumOfSquares = recentSamples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(sampleCount))
        
        // Normalize to 0-1 range (assuming typical voice levels)
        return min(1.0, rms * 5)
    }
    
    /// Returns the current sample count without stopping recording.
    func getCurrentSampleCount() -> Int {
        return audioBuffer.count
    }
    
    /// Returns a copy of samples from a given index without stopping recording.
    /// Used for progressive transcription during long recordings.
    /// - Parameter fromIndex: Starting sample index (0-based)
    /// - Returns: Array of samples from the given index to current position
    func getSamplesFrom(index: Int) -> [Float] {
        guard index < audioBuffer.count else { return [] }
        return Array(audioBuffer[index...])
    }
    
    /// Returns all accumulated samples without stopping recording.
    /// Used for progressive transcription during long recordings.
    func getAllSamples() -> [Float] {
        return audioBuffer
    }
    
    // MARK: - Private Methods
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
    
    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat
    ) {
        guard let floatData = buffer.floatChannelData else { return }
        
        var samplesToAdd: [Float] = []
        
        if let converter = converter {
            // Need to convert sample rate
            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCount
            ) else { return }
            
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if status == .haveData, let outputData = outputBuffer.floatChannelData {
                samplesToAdd = Array(UnsafeBufferPointer(
                    start: outputData[0],
                    count: Int(outputBuffer.frameLength)
                ))
            }
        } else {
            // Direct copy (same sample rate)
            let samples = Array(UnsafeBufferPointer(
                start: floatData[0],
                count: Int(buffer.frameLength)
            ))
            
            // Convert stereo to mono if needed
            if buffer.format.channelCount == 2, let rightChannel = buffer.floatChannelData?[1] {
                let rightSamples = Array(UnsafeBufferPointer(
                    start: rightChannel,
                    count: Int(buffer.frameLength)
                ))
                samplesToAdd = zip(samples, rightSamples).map { ($0 + $1) / 2 }
            } else {
                samplesToAdd = samples
            }
        }
        
        // Add to main buffer
        audioBuffer.append(contentsOf: samplesToAdd)
        
        // Calculate current level and update waveform
        if !samplesToAdd.isEmpty {
            let rms = calculateRMS(samples: samplesToAdd)
            let normalizedLevel = min(1.0, rms * 8) // Amplify for visibility
            
            // Shift levels and add new one
            recentLevels.removeFirst()
            recentLevels.append(normalizedLevel)
            
            // Publish levels on main thread
            let levels = recentLevels
            let callback = audioLevelCallback
            DispatchQueue.main.async {
                callback?(levels)
            }
        }
    }
    
    private func calculateRMS(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
    
    private func samplesToData(_ samples: [Float]) -> Data {
        // Convert float samples to 16-bit PCM
        var data = Data(capacity: samples.count * 2)
        
        for sample in samples {
            // Clamp to [-1, 1] and convert to Int16
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16Value.littleEndian) { data.append(contentsOf: $0) }
        }
        
        return data
    }
}
