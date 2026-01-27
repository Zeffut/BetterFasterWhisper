//! Error types for the Whisper Core library.

use thiserror::Error;

/// Result type alias for WhisperError.
pub type Result<T> = std::result::Result<T, WhisperError>;

/// Errors that can occur during transcription operations.
#[derive(Error, Debug)]
pub enum WhisperError {
    /// Failed to load the Whisper model.
    #[error("Failed to load model: {0}")]
    ModelLoadError(String),

    /// Failed to initialize the transcription context.
    #[error("Failed to initialize context: {0}")]
    ContextInitError(String),

    /// Audio processing error.
    #[error("Audio processing error: {0}")]
    AudioError(String),

    /// Transcription failed.
    #[error("Transcription failed: {0}")]
    TranscriptionError(String),

    /// Invalid configuration.
    #[error("Invalid configuration: {0}")]
    ConfigError(String),

    /// File I/O error.
    #[error("File I/O error: {0}")]
    IoError(#[from] std::io::Error),

    /// Model not found at the specified path.
    #[error("Model not found: {0}")]
    ModelNotFound(String),

    /// Unsupported audio format.
    #[error("Unsupported audio format: {0}")]
    UnsupportedFormat(String),

    /// Recording device error.
    #[error("Recording device error: {0}")]
    DeviceError(String),

    /// FFI error when crossing language boundaries.
    #[error("FFI error: {0}")]
    FfiError(String),
}

impl WhisperError {
    /// Returns an error code for FFI communication.
    pub fn error_code(&self) -> i32 {
        match self {
            WhisperError::ModelLoadError(_) => -1,
            WhisperError::ContextInitError(_) => -2,
            WhisperError::AudioError(_) => -3,
            WhisperError::TranscriptionError(_) => -4,
            WhisperError::ConfigError(_) => -5,
            WhisperError::IoError(_) => -6,
            WhisperError::ModelNotFound(_) => -7,
            WhisperError::UnsupportedFormat(_) => -8,
            WhisperError::DeviceError(_) => -9,
            WhisperError::FfiError(_) => -10,
        }
    }
}
