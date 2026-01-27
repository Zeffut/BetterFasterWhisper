//! Configuration types for Whisper transcription.

use serde::{Deserialize, Serialize};

/// Whisper model size variants.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(C)]
pub enum ModelSize {
    /// Tiny model (~75MB) - Fastest, least accurate
    Tiny,
    /// Base model (~142MB) - Fast, good for simple tasks
    Base,
    /// Small model (~466MB) - Balanced speed/accuracy
    Small,
    /// Medium model (~1.5GB) - Good accuracy
    Medium,
    /// Large model (~2.9GB) - Best accuracy
    Large,
    /// Large-v2 model - Improved large model
    LargeV2,
    /// Large-v3 model - Latest and most accurate
    LargeV3,
    /// Large-v3-turbo - Optimized for speed
    LargeV3Turbo,
}

impl ModelSize {
    /// Returns the model filename.
    pub fn filename(&self) -> &'static str {
        match self {
            ModelSize::Tiny => "ggml-tiny.bin",
            ModelSize::Base => "ggml-base.bin",
            ModelSize::Small => "ggml-small.bin",
            ModelSize::Medium => "ggml-medium.bin",
            ModelSize::Large => "ggml-large.bin",
            ModelSize::LargeV2 => "ggml-large-v2.bin",
            ModelSize::LargeV3 => "ggml-large-v3.bin",
            ModelSize::LargeV3Turbo => "ggml-large-v3-turbo.bin",
        }
    }

    /// Returns approximate model size in bytes.
    pub fn size_bytes(&self) -> u64 {
        match self {
            ModelSize::Tiny => 75_000_000,
            ModelSize::Base => 142_000_000,
            ModelSize::Small => 466_000_000,
            ModelSize::Medium => 1_500_000_000,
            ModelSize::Large => 2_900_000_000,
            ModelSize::LargeV2 => 2_900_000_000,
            ModelSize::LargeV3 => 2_900_000_000,
            ModelSize::LargeV3Turbo => 1_600_000_000,
        }
    }
}

impl Default for ModelSize {
    fn default() -> Self {
        ModelSize::Base
    }
}

/// Language configuration for transcription.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LanguageConfig {
    /// Source language code (e.g., "en", "fr", "auto").
    pub source: String,
    /// Whether to translate to English.
    pub translate_to_english: bool,
}

impl Default for LanguageConfig {
    fn default() -> Self {
        Self {
            source: "auto".to_string(),
            translate_to_english: false,
        }
    }
}

/// Main configuration for Whisper transcription.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WhisperConfig {
    /// Path to the model file.
    pub model_path: String,
    /// Model size (used if model_path not specified).
    pub model_size: ModelSize,
    /// Language configuration.
    pub language: LanguageConfig,
    /// Number of threads to use (0 = auto).
    pub n_threads: u32,
    /// Enable GPU acceleration (Metal on macOS).
    pub use_gpu: bool,
    /// Enable flash attention.
    pub flash_attention: bool,
    /// Maximum audio duration to process (seconds).
    pub max_duration_seconds: u32,
    /// Temperature for sampling (0.0 = greedy).
    pub temperature: f32,
    /// Enable word-level timestamps.
    pub word_timestamps: bool,
    /// Maximum segment length in characters.
    pub max_segment_length: u32,
    /// Enable VAD (Voice Activity Detection).
    pub vad_enabled: bool,
    /// VAD threshold (0.0 - 1.0).
    pub vad_threshold: f32,
}

impl Default for WhisperConfig {
    fn default() -> Self {
        Self {
            model_path: String::new(),
            model_size: ModelSize::Base,
            language: LanguageConfig::default(),
            n_threads: 0, // Auto-detect
            use_gpu: true,
            flash_attention: true,
            max_duration_seconds: 300, // 5 minutes
            temperature: 0.0,
            word_timestamps: false,
            max_segment_length: 0, // No limit
            vad_enabled: true,
            vad_threshold: 0.5,
        }
    }
}

impl WhisperConfig {
    /// Creates a new config with the specified model path.
    pub fn with_model_path(model_path: impl Into<String>) -> Self {
        Self {
            model_path: model_path.into(),
            ..Default::default()
        }
    }

    /// Creates a new config with the specified model size.
    pub fn with_model_size(model_size: ModelSize) -> Self {
        Self {
            model_size,
            ..Default::default()
        }
    }

    /// Sets the source language.
    pub fn language(mut self, lang: impl Into<String>) -> Self {
        self.language.source = lang.into();
        self
    }

    /// Enables translation to English.
    pub fn translate(mut self) -> Self {
        self.language.translate_to_english = true;
        self
    }

    /// Sets the number of threads.
    pub fn threads(mut self, n: u32) -> Self {
        self.n_threads = n;
        self
    }

    /// Enables or disables GPU acceleration.
    pub fn gpu(mut self, enabled: bool) -> Self {
        self.use_gpu = enabled;
        self
    }
}
