//
//  TranscriptionResult.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import Foundation

/// A segment of transcribed text with timing information.
struct TranscriptionSegment: Codable, Identifiable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let confidence: Float
    let speakerId: Int?
    
    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        confidence: Float = 1.0,
        speakerId: Int? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
        self.speakerId = speakerId
    }
    
    /// Duration of this segment in seconds.
    var duration: TimeInterval {
        endTime - startTime
    }
}

/// Complete result of a transcription operation.
struct TranscriptionResult: Codable, Identifiable {
    let id: UUID
    let text: String
    let segments: [TranscriptionSegment]
    let language: String
    let processingTime: TimeInterval
    let audioDuration: TimeInterval
    let timestamp: Date
    let mode: TranscriptionMode
    
    init(
        id: UUID = UUID(),
        text: String,
        segments: [TranscriptionSegment] = [],
        language: String = "auto",
        processingTime: TimeInterval = 0,
        audioDuration: TimeInterval = 0,
        timestamp: Date = Date(),
        mode: TranscriptionMode = .voice
    ) {
        self.id = id
        self.text = text
        self.segments = segments
        self.language = language
        self.processingTime = processingTime
        self.audioDuration = audioDuration
        self.timestamp = timestamp
        self.mode = mode
    }
    
    /// Real-time factor (processing time / audio duration).
    /// Values < 1.0 mean faster than real-time.
    var realtimeFactor: Double {
        guard audioDuration > 0 else { return 0 }
        return processingTime / audioDuration
    }
    
    /// Empty result placeholder.
    static let empty = TranscriptionResult(text: "")
}

/// History item for storing past transcriptions.
struct TranscriptionHistoryItem: Codable, Identifiable {
    let id: UUID
    let result: TranscriptionResult
    let audioFilePath: String?
    let isFavorite: Bool
    
    init(
        id: UUID = UUID(),
        result: TranscriptionResult,
        audioFilePath: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.result = result
        self.audioFilePath = audioFilePath
        self.isFavorite = isFavorite
    }
}
