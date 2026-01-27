//! Transcription engine using Whisper.

use crate::audio::AudioBuffer;
use crate::config::WhisperConfig;
use crate::error::{Result, WhisperError};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

/// A single transcription segment with timing information.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[repr(C)]
pub struct Segment {
    /// Start time in milliseconds.
    pub start_ms: i64,
    /// End time in milliseconds.
    pub end_ms: i64,
    /// Transcribed text for this segment.
    pub text: String,
    /// Confidence score (0.0 - 1.0).
    pub confidence: f32,
    /// Speaker ID if diarization is enabled.
    pub speaker_id: Option<u32>,
}

impl Segment {
    /// Creates a new segment.
    pub fn new(start_ms: i64, end_ms: i64, text: String) -> Self {
        Self {
            start_ms,
            end_ms,
            text,
            confidence: 1.0,
            speaker_id: None,
        }
    }

    /// Returns the duration in milliseconds.
    pub fn duration_ms(&self) -> i64 {
        self.end_ms - self.start_ms
    }
}

/// Result of a transcription operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionResult {
    /// Full transcribed text.
    pub text: String,
    /// Individual segments with timing.
    pub segments: Vec<Segment>,
    /// Detected language code.
    pub language: String,
    /// Processing time in milliseconds.
    pub processing_time_ms: u64,
    /// Audio duration in milliseconds.
    pub audio_duration_ms: u64,
}

impl TranscriptionResult {
    /// Creates a new empty result.
    pub fn empty() -> Self {
        Self {
            text: String::new(),
            segments: Vec::new(),
            language: String::new(),
            processing_time_ms: 0,
            audio_duration_ms: 0,
        }
    }

    /// Returns the real-time factor (processing time / audio duration).
    pub fn realtime_factor(&self) -> f64 {
        if self.audio_duration_ms == 0 {
            return 0.0;
        }
        self.processing_time_ms as f64 / self.audio_duration_ms as f64
    }
}

/// The main transcription engine.
pub struct TranscriptionEngine {
    config: WhisperConfig,
    ctx: Option<Arc<WhisperContext>>,
    is_initialized: bool,
}

// Implement Send and Sync for thread safety
unsafe impl Send for TranscriptionEngine {}
unsafe impl Sync for TranscriptionEngine {}

impl TranscriptionEngine {
    /// Creates a new transcription engine with the given configuration.
    pub fn new(config: WhisperConfig) -> Self {
        Self {
            config,
            ctx: None,
            is_initialized: false,
        }
    }

    /// Creates an engine with default configuration.
    pub fn with_defaults() -> Self {
        Self::new(WhisperConfig::default())
    }

    /// Initializes the engine by loading the model.
    pub fn initialize(&mut self) -> Result<()> {
        let model_path = if self.config.model_path.is_empty() {
            // Use default model path based on model size
            self.get_default_model_path()?
        } else {
            self.config.model_path.clone()
        };

        if !Path::new(&model_path).exists() {
            return Err(WhisperError::ModelNotFound(model_path));
        }

        tracing::info!("Loading Whisper model from: {}", model_path);

        // Create context parameters
        let params = WhisperContextParameters::default();

        // Load the model
        let ctx = WhisperContext::new_with_params(&model_path, params)
            .map_err(|e| WhisperError::ContextInitError(format!("Failed to load model: {}", e)))?;

        self.ctx = Some(Arc::new(ctx));
        self.is_initialized = true;
        
        tracing::info!("Whisper model loaded successfully");
        Ok(())
    }

    /// Returns the default model path for the configured model size.
    fn get_default_model_path(&self) -> Result<String> {
        let home = std::env::var("HOME")
            .map_err(|_| WhisperError::ConfigError("HOME not set".to_string()))?;
        
        let models_dir = format!(
            "{}/Library/Application Support/BetterFasterWhisper/Models",
            home
        );

        Ok(format!("{}/{}", models_dir, self.config.model_size.filename()))
    }

    /// Transcribes audio from a buffer.
    pub fn transcribe(&self, audio: &AudioBuffer) -> Result<TranscriptionResult> {
        if !self.is_initialized {
            return Err(WhisperError::ContextInitError(
                "Engine not initialized. Call initialize() first.".to_string(),
            ));
        }

        if audio.is_empty() {
            return Ok(TranscriptionResult::empty());
        }

        let ctx = self.ctx.as_ref()
            .ok_or_else(|| WhisperError::ContextInitError("Context not available".to_string()))?;

        let start_time = std::time::Instant::now();
        let audio_duration_ms = (audio.duration_seconds() * 1000.0) as u64;

        // Resample to 16kHz if necessary (Whisper requires 16kHz)
        let samples = if audio.sample_rate() != 16000 {
            resample_to_16khz(audio.samples(), audio.sample_rate())
        } else {
            audio.samples().to_vec()
        };

        // Create transcription parameters
        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });

        // Set language
        if self.config.language.source != "auto" {
            params.set_language(Some(&self.config.language.source));
        }

        // Configure parameters
        params.set_translate(self.config.language.translate_to_english);
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);
        params.set_suppress_blank(true);
        params.set_suppress_non_speech_tokens(true);

        // Set thread count
        if self.config.n_threads > 0 {
            params.set_n_threads(self.config.n_threads as i32);
        }

        // Create state and run inference
        let mut state = ctx.create_state()
            .map_err(|e| WhisperError::TranscriptionError(format!("Failed to create state: {}", e)))?;

        state.full(params, &samples)
            .map_err(|e| WhisperError::TranscriptionError(format!("Transcription failed: {}", e)))?;

        // Extract results
        let num_segments = state.full_n_segments()
            .map_err(|e| WhisperError::TranscriptionError(format!("Failed to get segments: {}", e)))?;

        let mut segments = Vec::new();
        let mut full_text = String::new();

        for i in 0..num_segments {
            let segment_text = state.full_get_segment_text(i)
                .map_err(|e| WhisperError::TranscriptionError(format!("Failed to get segment text: {}", e)))?;
            
            let start_timestamp = state.full_get_segment_t0(i)
                .map_err(|e| WhisperError::TranscriptionError(format!("Failed to get start time: {}", e)))?;
            
            let end_timestamp = state.full_get_segment_t1(i)
                .map_err(|e| WhisperError::TranscriptionError(format!("Failed to get end time: {}", e)))?;

            // Whisper timestamps are in centiseconds (1/100 of a second)
            let start_ms = (start_timestamp as i64) * 10;
            let end_ms = (end_timestamp as i64) * 10;

            if !segment_text.trim().is_empty() {
                full_text.push_str(&segment_text);
                segments.push(Segment::new(start_ms, end_ms, segment_text));
            }
        }

        // Detect language if auto
        let language = if self.config.language.source == "auto" {
            // Try to detect language from the state or default to "en"
            state.full_lang_id_from_state()
                .map(|id| whisper_rs::get_lang_str(id).unwrap_or("en").to_string())
                .unwrap_or_else(|_| "en".to_string())
        } else {
            self.config.language.source.clone()
        };

        let processing_time_ms = start_time.elapsed().as_millis() as u64;

        let result = TranscriptionResult {
            text: full_text.trim().to_string(),
            segments,
            language,
            processing_time_ms,
            audio_duration_ms,
        };

        tracing::info!(
            "Transcription complete: {} chars in {}ms (RTF: {:.2})",
            result.text.len(),
            result.processing_time_ms,
            result.realtime_factor()
        );

        Ok(result)
    }

    /// Transcribes audio from a file.
    pub fn transcribe_file(&self, path: &str) -> Result<TranscriptionResult> {
        let audio = crate::audio::load_wav_file(path)?;
        self.transcribe(&audio)
    }

    /// Returns whether the engine is initialized.
    pub fn is_initialized(&self) -> bool {
        self.is_initialized
    }

    /// Returns a reference to the current configuration.
    pub fn config(&self) -> &WhisperConfig {
        &self.config
    }

    /// Updates the configuration (requires re-initialization).
    pub fn set_config(&mut self, config: WhisperConfig) {
        self.config = config;
        self.is_initialized = false;
        self.ctx = None;
    }

    /// Releases resources and unloads the model.
    pub fn shutdown(&mut self) {
        self.ctx = None;
        self.is_initialized = false;
        tracing::info!("Whisper engine shut down");
    }
}

impl Drop for TranscriptionEngine {
    fn drop(&mut self) {
        self.shutdown();
    }
}

/// Resamples audio from source sample rate to 16kHz.
fn resample_to_16khz(samples: &[f32], source_rate: u32) -> Vec<f32> {
    if source_rate == 16000 {
        return samples.to_vec();
    }

    let ratio = source_rate as f64 / 16000.0;
    let new_len = (samples.len() as f64 / ratio) as usize;
    let mut resampled = Vec::with_capacity(new_len);

    for i in 0..new_len {
        let src_idx = (i as f64 * ratio) as usize;
        if src_idx < samples.len() {
            // Linear interpolation
            let frac = (i as f64 * ratio) - src_idx as f64;
            let sample = if src_idx + 1 < samples.len() {
                samples[src_idx] * (1.0 - frac as f32) + samples[src_idx + 1] * frac as f32
            } else {
                samples[src_idx]
            };
            resampled.push(sample);
        }
    }

    resampled
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_segment_duration() {
        let segment = Segment::new(1000, 2500, "test".to_string());
        assert_eq!(segment.duration_ms(), 1500);
    }

    #[test]
    fn test_result_realtime_factor() {
        let result = TranscriptionResult {
            text: "test".to_string(),
            segments: vec![],
            language: "en".to_string(),
            processing_time_ms: 500,
            audio_duration_ms: 1000,
        };
        assert_eq!(result.realtime_factor(), 0.5);
    }

    #[test]
    fn test_resample() {
        // Simple test: 48kHz to 16kHz should reduce length by 1/3
        let samples: Vec<f32> = (0..48000).map(|i| (i as f32 / 48000.0).sin()).collect();
        let resampled = resample_to_16khz(&samples, 48000);
        assert_eq!(resampled.len(), 16000);
    }
}
