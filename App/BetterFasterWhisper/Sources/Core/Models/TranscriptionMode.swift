//
//  TranscriptionMode.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import Foundation

/// Predefined transcription modes that control output formatting.
enum TranscriptionMode: String, CaseIterable, Identifiable, Codable {
    case voice = "voice"
    case message = "message"
    case email = "email"
    case notes = "notes"
    case code = "code"
    case custom = "custom"
    
    var id: String { rawValue }
    
    /// Display name for the mode.
    var displayName: String {
        switch self {
        case .voice: return "Voice"
        case .message: return "Message"
        case .email: return "Email"
        case .notes: return "Notes"
        case .code: return "Code"
        case .custom: return "Custom"
        }
    }
    
    /// Description of what the mode does.
    var description: String {
        switch self {
        case .voice:
            return "Raw transcription with minimal formatting"
        case .message:
            return "Casual tone, suitable for chat and messaging"
        case .email:
            return "Professional tone with proper email formatting"
        case .notes:
            return "Structured notes with bullet points"
        case .code:
            return "Optimized for code-related dictation"
        case .custom:
            return "User-defined custom mode"
        }
    }
    
    /// SF Symbol icon name.
    var iconName: String {
        switch self {
        case .voice: return "waveform"
        case .message: return "message"
        case .email: return "envelope"
        case .notes: return "note.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    /// System prompt for LLM processing (if enabled).
    var systemPrompt: String {
        switch self {
        case .voice:
            return """
            Clean up the following transcription by fixing obvious errors, \
            removing filler words (um, uh, like), and ensuring proper punctuation. \
            Preserve the original meaning and tone. Do not add or remove content.
            """
        case .message:
            return """
            Format the following transcription as a casual message. \
            Keep it conversational and friendly. Fix any errors and ensure proper punctuation. \
            Keep it concise and natural-sounding.
            """
        case .email:
            return """
            Format the following transcription as a professional email. \
            Add appropriate greeting and sign-off if not present. \
            Ensure proper grammar, punctuation, and professional tone.
            """
        case .notes:
            return """
            Format the following transcription as structured notes. \
            Use bullet points where appropriate. \
            Organize information logically and highlight key points.
            """
        case .code:
            return """
            The following is code-related dictation. \
            Format it appropriately, recognizing programming terms, \
            variable names, and code syntax. Keep technical accuracy.
            """
        case .custom:
            return ""
        }
    }
}

/// Configuration for a custom mode.
struct CustomModeConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var iconName: String
    var useLanguageModel: Bool
    var languageModelId: String?
    
    init(
        id: UUID = UUID(),
        name: String = "Custom Mode",
        systemPrompt: String = "",
        iconName: String = "slider.horizontal.3",
        useLanguageModel: Bool = true,
        languageModelId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.iconName = iconName
        self.useLanguageModel = useLanguageModel
        self.languageModelId = languageModelId
    }
}
