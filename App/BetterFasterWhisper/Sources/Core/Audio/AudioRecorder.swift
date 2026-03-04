//
//  AudioRecorder.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import Foundation
import AVFoundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.betterfasterwhisper", category: "AudioRecorder")

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
    private let waveformBarCount = 20   // 20 FFT frequency bands
    private let fftSize = 1024
    private let fftBandCount = 20
    private let fftMinHz: Float = 80
    private let fftMaxHz: Float = 8000
    private var fftSetup: FFTSetup?
    private var fftWindow: [Float] = []
    private var fftRollingBuffer: [Float] = []
    
    /// Recent audio levels for waveform display
    private var recentLevels: [Float] = []
    
    // MARK: - Initialization
    
    private init() {
        recentLevels = Array(repeating: 0, count: waveformBarCount)
        // FFT setup
        let log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        fftWindow = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&fftWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        fftRollingBuffer = [Float](repeating: 0, count: fftSize)
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
        fftRollingBuffer = [Float](repeating: 0, count: fftSize)
        
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

            if let error = error {
                logger.error("Audio conversion error: \(error.localizedDescription)")
                return
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

        // Accumulate into rolling FFT buffer
        fftRollingBuffer.append(contentsOf: samplesToAdd)
        if fftRollingBuffer.count > fftSize {
            fftRollingBuffer.removeFirst(fftRollingBuffer.count - fftSize)
        }

        // Compute FFT bands once we have a full window
        if fftRollingBuffer.count == fftSize {
            let bands = computeFFTBands(from: fftRollingBuffer)
            recentLevels = bands
            let callback = audioLevelCallback
            DispatchQueue.main.async {
                callback?(bands)
            }
        }
    }
    
    private func computeFFTBands(from samples: [Float]) -> [Float] {
        guard let setup = fftSetup, samples.count == fftSize else {
            return [Float](repeating: 0, count: fftBandCount)
        }

        // Apply Hann window
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, fftWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        // Pack real samples into split-complex format
        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)
        let log2n = vDSP_Length(log2(Float(fftSize)))
        var result = [Float](repeating: 0, count: fftBandCount)

        realPart.withUnsafeMutableBufferPointer { rBuf in
            imagPart.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                windowed.withUnsafeBytes { rawBytes in
                    rawBytes.bindMemory(to: DSPComplex.self).baseAddress.map { cPtr in
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
                        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

                        let hzPerBin = Float(targetSampleRate) / Float(fftSize)
                        magnitudes.withUnsafeBufferPointer { magBuf in
                            for i in 0..<fftBandCount {
                                let fLow  = fftMinHz * pow(fftMaxHz / fftMinHz, Float(i)     / Float(fftBandCount))
                                let fHigh = fftMinHz * pow(fftMaxHz / fftMinHz, Float(i + 1) / Float(fftBandCount))
                                let binLow  = max(1, Int(fLow  / hzPerBin))
                                let binHigh = min(fftSize / 2 - 1, Int(fHigh / hzPerBin))
                                guard binLow <= binHigh else { continue }
                                var avg: Float = 0
                                vDSP_meanv(magBuf.baseAddress!.advanced(by: binLow), 1, &avg, vDSP_Length(binHigh - binLow + 1))
                                // dB normalization: map [-80dB, 0dB] → [0, 1]
                                let db = 10 * log10f(avg + 1e-10)
                                result[i] = max(0, min(1, (db + 80) / 80))
                            }
                        }
                    }
                }
            }
        }
        return result
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
