//
//  WhisperService.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import Foundation
import WhisperKit
import os.log

private let logger = Logger(subsystem: "com.betterfasterwhisper", category: "WhisperService")

/// Error types for Whisper operations.
enum WhisperError: LocalizedError {
    case notInitialized
    case modelNotFound(String)
    case transcriptionFailed(String)
    case invalidAudioData
    case engineError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Whisper engine is not initialized"
        case .modelNotFound(let path):
            return "Model not found at: \(path)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .invalidAudioData:
            return "Invalid audio data provided"
        case .engineError(let message):
            return "Engine error: \(message)"
        }
    }
}

/// Service for managing Whisper transcription engine using WhisperKit.
@MainActor
final class WhisperService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = WhisperService()
    
    // MARK: - Published Properties
    
    @Published private(set) var isInitialized = false
    @Published private(set) var currentModelName: String = ""
    @Published private(set) var isProcessing = false
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var loadingMessage: String = ""
    
    /// Language for transcription. nil = auto-detect, "fr" = French, "en" = English, etc.
    @Published var transcriptionLanguage: String? {
        didSet {
            UserDefaults.standard.set(transcriptionLanguage, forKey: "transcriptionLanguage")
        }
    }
    
    // MARK: - Private Properties
    
    private var whisperKit: WhisperKit?
    
    // MARK: - Initialization
    
    private init() {
        // Load saved language preference (default to French)
        if let saved = UserDefaults.standard.string(forKey: "transcriptionLanguage") {
            self.transcriptionLanguage = saved
        } else {
            self.transcriptionLanguage = "fr"  // Default to French
        }
    }
    
    // MARK: - Public Methods
    
    /// Initializes the Whisper engine with the specified model variant.
    /// - Parameter modelVariant: The model variant to load (e.g., "openai_whisper-large-v3_turbo")
    func initialize(modelVariant: String = "openai_whisper-large-v3_turbo") async {
        guard !isInitialized else { return }
        
        loadingMessage = "Initializing WhisperKit..."
        loadingProgress = 0
        
        do {
            logger.info("Initializing WhisperKit with model: \(modelVariant)")
            
            // Initialize WhisperKit with the specified model
            // WhisperKit handles model downloading automatically
            whisperKit = try await WhisperKit(
                model: modelVariant,
                verbose: true,
                logLevel: .info,
                prewarm: true,
                load: true,
                useBackgroundDownloadSession: false
            )
            
            isInitialized = true
            currentModelName = modelVariant
            loadingProgress = 1.0
            loadingMessage = "Ready"
            logger.info("WhisperKit initialized successfully")
            
        } catch {
            loadingMessage = "Failed to initialize: \(error.localizedDescription)"
            logger.error("Failed to initialize WhisperKit: \(error.localizedDescription)")
        }
    }
    
    /// Transcribes audio samples.
    /// - Parameters:
    ///   - samples: Audio samples as Float array (mono, 16kHz)
    ///   - language: Optional language code (nil for auto-detect)
    /// - Returns: Transcription result
    func transcribe(samples: [Float], language: String? = nil) async throws -> TranscriptionResult {
        guard let whisperKit = whisperKit, isInitialized else {
            throw WhisperError.notInitialized
        }
        
        guard !samples.isEmpty else {
            throw WhisperError.invalidAudioData
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let startTime = Date()
        
        do {
            // Configure decoding options
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: language,
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 5,
                sampleLength: 224,
                topK: 5,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: false,
                suppressBlank: true,
                supressTokens: nil,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: nil,
                noSpeechThreshold: 0.6,
                concurrentWorkerCount: 0,
                chunkingStrategy: nil
            )
            
            // Perform transcription
            let results = try await whisperKit.transcribe(
                audioArray: samples,
                decodeOptions: options
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            let audioDuration = Double(samples.count) / 16000.0
            
            // Combine all result texts
            let fullText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // Convert segments
            let segments: [TranscriptionSegment] = results.flatMap { result -> [TranscriptionSegment] in
                result.segments.map { segment in
                    TranscriptionSegment(
                        startTime: Double(segment.start),
                        endTime: Double(segment.end),
                        text: segment.text
                    )
                }
            }
            
            // Detect language from first result
            let detectedLanguage = results.first?.language ?? "unknown"
            
            logger.info("Transcription completed in \(String(format: "%.2f", processingTime))s")
            logger.info("Text: \(fullText.prefix(100))...")
            
            return TranscriptionResult(
                text: fullText,
                segments: segments,
                language: detectedLanguage,
                processingTime: processingTime,
                audioDuration: audioDuration
            )
            
        } catch {
            throw WhisperError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    /// Transcribes audio data (raw PCM).
    /// - Parameters:
    ///   - audioData: Raw audio data (16-bit PCM, mono, 16kHz)
    ///   - language: Optional language code
    /// - Returns: Transcription result
    func transcribe(audioData: Data, language: String? = nil) async throws -> TranscriptionResult {
        let samples = audioDataToSamples(audioData)
        return try await transcribe(samples: samples, language: language)
    }
    
    /// Transcribes an audio file.
    /// - Parameters:
    ///   - url: URL to the audio file
    ///   - language: Optional language code
    /// - Returns: Transcription result
    func transcribeFile(at url: URL, language: String? = nil) async throws -> TranscriptionResult {
        guard let _ = whisperKit, isInitialized else {
            throw WhisperError.notInitialized
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let startTime = Date()
        
        do {
            // Load audio from file using WhisperKit's AudioProcessor
            let audioBuffer = try await Task.detached {
                try AudioProcessor.loadAudio(fromPath: url.path)
            }.value
            
            // Convert AVAudioPCMBuffer to [Float]
            guard let floatChannelData = audioBuffer.floatChannelData else {
                throw WhisperError.invalidAudioData
            }
            
            let frameLength = Int(audioBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameLength))
            
            // Use the samples-based transcription
            let result = try await transcribe(samples: samples, language: language)
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            return TranscriptionResult(
                text: result.text,
                segments: result.segments,
                language: result.language,
                processingTime: processingTime,
                audioDuration: result.audioDuration
            )
            
        } catch {
            throw WhisperError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    /// Shuts down the engine and releases resources.
    func shutdown() {
        whisperKit = nil
        isInitialized = false
        currentModelName = ""
        loadingProgress = 0
        loadingMessage = ""
        print("[WhisperService] WhisperKit shut down")
    }
    
    /// Returns available model variants from WhisperKit.
    func availableModels() async -> [String] {
        do {
            let models = try await WhisperKit.fetchAvailableModels()
            return models
        } catch {
            print("[WhisperService] Failed to fetch available models: \(error)")
            return []
        }
    }
    
    // MARK: - Private Methods
    
    private func audioDataToSamples(_ data: Data) -> [Float] {
        // Convert raw audio data to float samples
        // Assuming 16-bit PCM mono at 16kHz
        let sampleCount = data.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)
        
        data.withUnsafeBytes { buffer in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }
        
        return samples
    }
}
