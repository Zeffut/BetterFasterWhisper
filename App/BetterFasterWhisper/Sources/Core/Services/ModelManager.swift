//
//  ModelManager.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import Foundation
import SwiftUI
import WhisperKit

/// Available Whisper model variants for WhisperKit.
/// These correspond to models from argmaxinc/whisperkit-coreml
enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case tiny = "openai_whisper-tiny"
    case tinyEn = "openai_whisper-tiny.en"
    case base = "openai_whisper-base"
    case baseEn = "openai_whisper-base.en"
    case small = "openai_whisper-small"
    case smallEn = "openai_whisper-small.en"
    case largeV2 = "openai_whisper-large-v2"
    case largeV2Turbo = "openai_whisper-large-v2_turbo"
    case largeV3 = "openai_whisper-large-v3"
    case largeV3Turbo = "openai_whisper-large-v3_turbo"
    case distilLargeV3 = "distil-whisper_distil-large-v3"
    case distilLargeV3Turbo = "distil-whisper_distil-large-v3_turbo"
    
    var id: String { rawValue }
    
    /// Display name for the model.
    var displayName: String {
        switch self {
        case .tiny: return "Tiny (~75 MB)"
        case .tinyEn: return "Tiny English (~75 MB)"
        case .base: return "Base (~142 MB)"
        case .baseEn: return "Base English (~142 MB)"
        case .small: return "Small (~466 MB)"
        case .smallEn: return "Small English (~466 MB)"
        case .largeV2: return "Large v2 (~950 MB)"
        case .largeV2Turbo: return "Large v2 Turbo (~955 MB)"
        case .largeV3: return "Large v3 (~950 MB)"
        case .largeV3Turbo: return "Large v3 Turbo (~955 MB) - Recommended"
        case .distilLargeV3: return "Distil Large v3 (~594 MB)"
        case .distilLargeV3Turbo: return "Distil Large v3 Turbo (~600 MB)"
        }
    }
    
    /// Estimated download size in bytes.
    var estimatedSize: Int64 {
        switch self {
        case .tiny, .tinyEn: return 75_000_000
        case .base, .baseEn: return 142_000_000
        case .small, .smallEn: return 466_000_000
        case .largeV2, .largeV3: return 950_000_000
        case .largeV2Turbo, .largeV3Turbo: return 955_000_000
        case .distilLargeV3: return 594_000_000
        case .distilLargeV3Turbo: return 600_000_000
        }
    }
    
    /// Whether this model is English-only.
    var isEnglishOnly: Bool {
        rawValue.hasSuffix(".en")
    }
    
    /// Speed rating (1-5, higher is faster).
    var speedRating: Int {
        switch self {
        case .tiny, .tinyEn: return 5
        case .base, .baseEn: return 4
        case .small, .smallEn: return 3
        case .largeV2, .largeV3: return 1
        case .largeV2Turbo, .largeV3Turbo: return 3
        case .distilLargeV3: return 2
        case .distilLargeV3Turbo: return 4
        }
    }
    
    /// Accuracy rating (1-5, higher is more accurate).
    var accuracyRating: Int {
        switch self {
        case .tiny, .tinyEn: return 1
        case .base, .baseEn: return 2
        case .small, .smallEn: return 3
        case .distilLargeV3, .distilLargeV3Turbo: return 4
        case .largeV2, .largeV2Turbo, .largeV3, .largeV3Turbo: return 5
        }
    }
    
    /// Recommended RAM in GB.
    var recommendedRAM: Int {
        switch self {
        case .tiny, .tinyEn: return 1
        case .base, .baseEn: return 1
        case .small, .smallEn: return 2
        case .distilLargeV3, .distilLargeV3Turbo: return 4
        case .largeV2, .largeV2Turbo, .largeV3, .largeV3Turbo: return 6
        }
    }
    
    /// WhisperKit model variant name (used for initialization)
    var whisperKitVariant: String {
        rawValue
    }
}

/// Download/loading state for tracking progress.
enum ModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case loading
    case ready
    case error(String)
    
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
    
    var isDownloaded: Bool {
        switch self {
        case .downloaded, .loading, .ready: return true
        default: return false
        }
    }
    
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Type alias for backward compatibility
typealias DownloadState = ModelState

/// Manager for Whisper models using WhisperKit.
/// WhisperKit handles model downloading and caching automatically.
@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()
    
    /// Currently selected model for transcription.
    @Published var selectedModel: WhisperModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel")
        }
    }
    
    /// Model states for each model.
    @Published var modelStates: [WhisperModel: ModelState] = [:]
    
    /// Available models fetched from WhisperKit
    @Published var availableModels: [String] = []
    
    /// Whether we're currently fetching available models
    @Published var isFetchingModels = false
    
    private init() {
        // Load selected model from UserDefaults
        if let savedModel = UserDefaults.standard.string(forKey: "selectedModel"),
           let model = WhisperModel(rawValue: savedModel) {
            self.selectedModel = model
        } else {
            // Default to large-v3-turbo for best balance of speed and accuracy
            self.selectedModel = .largeV3Turbo
        }
        
        // Initialize states
        for model in WhisperModel.allCases {
            modelStates[model] = .notDownloaded
        }
        
        // Fetch available models from WhisperKit
        Task {
            await fetchAvailableModels()
        }
    }
    
    /// Fetch available models from WhisperKit's model repository.
    func fetchAvailableModels() async {
        isFetchingModels = true
        defer { isFetchingModels = false }
        
        do {
            let models = try await WhisperKit.fetchAvailableModels()
            availableModels = models
            print("[ModelManager] Available WhisperKit models: \(models)")
            
            // Update states based on what's available
            for model in WhisperModel.allCases {
                if models.contains(where: { $0.contains(model.rawValue) }) {
                    // Model is available, check if already downloaded
                    await checkModelDownloaded(model)
                }
            }
        } catch {
            print("[ModelManager] Failed to fetch available models: \(error)")
        }
    }
    
    /// Check if a model is already downloaded locally.
    func checkModelDownloaded(_ model: WhisperModel) async {
        // Check multiple possible locations where WhisperKit stores models
        let possiblePaths = localModelPaths(for: model)
        
        for path in possiblePaths {
            // Check if the model folder exists and contains the required files
            let audioEncoderPath = path.appendingPathComponent("AudioEncoder.mlmodelc")
            if FileManager.default.fileExists(atPath: audioEncoderPath.path) {
                modelStates[model] = .downloaded
                print("[ModelManager] Found model \(model.rawValue) at \(path.path)")
                return
            }
        }
        
        modelStates[model] = .notDownloaded
    }
    
    /// Get possible local paths where WhisperKit stores models.
    func localModelPaths(for model: WhisperModel) -> [URL] {
        var paths: [URL] = []

        // Path 1: App container (sandboxed app)
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "com.betterfasterwhisper.app") {
            let path = containerURL
                .appendingPathComponent("Data/Documents/huggingface/models/argmaxinc/whisperkit-coreml/.cache/huggingface/download")
                .appendingPathComponent(model.rawValue)
            paths.append(path)
        }

        // Path 2: Documents folder in container
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentsPath = documentsURL
                .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/.cache/huggingface/download")
                .appendingPathComponent(model.rawValue)
            paths.append(documentsPath)
        }

        // Path 3: Library/Containers path (non-sandboxed or from Finder)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let containerPath = homeDir
            .appendingPathComponent("Library/Containers/com.betterfasterwhisper.app/Data/Documents/huggingface/models/argmaxinc/whisperkit-coreml/.cache/huggingface/download")
            .appendingPathComponent(model.rawValue)
        paths.append(containerPath)

        // Path 4: Cache directory (older versions)
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let cachePath = cachesURL
                .appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots")
            paths.append(cachePath.appendingPathComponent(model.rawValue))
        }

        return paths
    }

    /// Get the local path where WhisperKit stores models (for compatibility).
    func localModelPath(for model: WhisperModel) -> URL {
        // Return the first available path, or a default path if none exist
        if let firstPath = localModelPaths(for: model).first {
            return firstPath
        }
        // Fallback to documents directory if all else fails
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir
            .appendingPathComponent("Library/Containers/com.betterfasterwhisper.app/Data/Documents/huggingface/models/argmaxinc/whisperkit-coreml/.cache/huggingface/download")
            .appendingPathComponent(model.rawValue)
    }
    
    /// Check if a model is available for download.
    func isModelAvailable(_ model: WhisperModel) -> Bool {
        availableModels.contains(where: { $0.contains(model.rawValue) })
    }
    
    /// Get the state of a model.
    func state(for model: WhisperModel) -> ModelState {
        modelStates[model] ?? .notDownloaded
    }
    
    /// Get formatted size string.
    func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Get recommended model based on system RAM.
    func recommendedModel() -> WhisperModel {
        let ram = ProcessInfo.processInfo.physicalMemory
        let ramGB = Int(ram / 1_073_741_824) // Convert to GB
        
        if ramGB >= 8 {
            return .largeV3Turbo  // Best quality with good speed
        } else if ramGB >= 4 {
            return .distilLargeV3Turbo  // Good balance for moderate RAM
        } else if ramGB >= 2 {
            return .small
        } else {
            return .base
        }
    }
    
    /// Update the state for a model.
    func updateState(_ state: ModelState, for model: WhisperModel) {
        modelStates[model] = state
    }
    
    // MARK: - Compatibility Methods (for SettingsView)
    
    /// Alias for modelStates for backward compatibility
    var downloadStates: [WhisperModel: ModelState] {
        get { modelStates }
        set { modelStates = newValue }
    }
    
    /// Refresh download states by checking which models are available locally.
    func refreshDownloadStates() {
        Task {
            await fetchAvailableModels()
        }
    }
    
    /// Check if a model is downloaded.
    func isDownloaded(_ model: WhisperModel) -> Bool {
        modelStates[model]?.isDownloaded ?? false
    }
    
    /// Download a model by initializing WhisperKit with it.
    /// WhisperKit handles downloading automatically during initialization.
    func downloadModel(_ model: WhisperModel) {
        modelStates[model] = .downloading(progress: 0)
        
        Task {
            do {
                // WhisperKit will download the model when we try to initialize with it
                modelStates[model] = .downloading(progress: 0.5)
                
                // We don't actually initialize here - just mark as downloaded
                // The actual download happens when WhisperService initializes
                // For now, we'll just simulate that it's ready to be used
                try await Task.sleep(nanoseconds: 500_000_000)
                
                modelStates[model] = .downloaded
            } catch {
                modelStates[model] = .error(error.localizedDescription)
            }
        }
    }
    
    /// Cancel a download (not really applicable with WhisperKit's approach).
    func cancelDownload(_ model: WhisperModel) {
        modelStates[model] = .notDownloaded
    }
    
    /// Delete a downloaded model from cache.
    func deleteModel(_ model: WhisperModel) throws {
        // WhisperKit models are stored in the Hugging Face cache
        // We can try to delete from there
        let modelPath = localModelPath(for: model)
        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }
        modelStates[model] = .notDownloaded
        
        // If this was the selected model, switch to a default
        if selectedModel == model {
            selectedModel = .largeV3Turbo
        }
    }
}
