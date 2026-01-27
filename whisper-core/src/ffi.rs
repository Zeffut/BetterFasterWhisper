//! FFI (Foreign Function Interface) bindings for Swift interoperability.
//!
//! This module provides C-compatible functions that can be called from Swift.
//! All functions use C types and conventions for maximum compatibility.

use crate::audio::AudioBuffer;
use crate::config::{ModelSize, WhisperConfig};
use crate::transcription::TranscriptionEngine;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::Mutex;

// Global engine instance for FFI
static ENGINE: Mutex<Option<TranscriptionEngine>> = Mutex::new(None);

/// Result codes for FFI functions.
#[repr(C)]
pub enum WhisperResultCode {
    /// Operation succeeded.
    Success = 0,
    /// Generic error.
    Error = -1,
    /// Model not found.
    ModelNotFound = -2,
    /// Engine not initialized.
    NotInitialized = -3,
    /// Invalid parameter.
    InvalidParameter = -4,
    /// Transcription failed.
    TranscriptionFailed = -5,
}

/// C-compatible transcription result.
#[repr(C)]
pub struct CTranscriptionResult {
    /// Transcribed text (null-terminated UTF-8).
    pub text: *mut c_char,
    /// Detected language code.
    pub language: *mut c_char,
    /// Number of segments.
    pub segment_count: i32,
    /// Processing time in milliseconds.
    pub processing_time_ms: u64,
    /// Audio duration in milliseconds.
    pub audio_duration_ms: u64,
    /// Result code.
    pub result_code: WhisperResultCode,
    /// Error message if result_code != Success.
    pub error_message: *mut c_char,
}

impl Default for CTranscriptionResult {
    fn default() -> Self {
        Self {
            text: ptr::null_mut(),
            language: ptr::null_mut(),
            segment_count: 0,
            processing_time_ms: 0,
            audio_duration_ms: 0,
            result_code: WhisperResultCode::Success,
            error_message: ptr::null_mut(),
        }
    }
}

/// C-compatible configuration.
#[repr(C)]
pub struct CWhisperConfig {
    /// Path to the model file (null-terminated UTF-8).
    pub model_path: *const c_char,
    /// Model size enum value.
    pub model_size: i32,
    /// Language code (null-terminated UTF-8).
    pub language: *const c_char,
    /// Whether to translate to English.
    pub translate: bool,
    /// Number of threads (0 = auto).
    pub n_threads: u32,
    /// Enable GPU acceleration.
    pub use_gpu: bool,
}

// ============================================================================
// FFI Functions
// ============================================================================

/// Initializes the Whisper engine with the given configuration.
///
/// # Safety
/// The `config` pointer must be valid and properly initialized.
#[no_mangle]
pub unsafe extern "C" fn whisper_init(config: *const CWhisperConfig) -> WhisperResultCode {
    if config.is_null() {
        return WhisperResultCode::InvalidParameter;
    }

    let c_config = &*config;

    // Convert C config to Rust config
    let model_path = if c_config.model_path.is_null() {
        String::new()
    } else {
        match CStr::from_ptr(c_config.model_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return WhisperResultCode::InvalidParameter,
        }
    };

    let language = if c_config.language.is_null() {
        "auto".to_string()
    } else {
        match CStr::from_ptr(c_config.language).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => "auto".to_string(),
        }
    };

    let model_size = match c_config.model_size {
        0 => ModelSize::Tiny,
        1 => ModelSize::Base,
        2 => ModelSize::Small,
        3 => ModelSize::Medium,
        4 => ModelSize::Large,
        5 => ModelSize::LargeV2,
        6 => ModelSize::LargeV3,
        7 => ModelSize::LargeV3Turbo,
        _ => ModelSize::Base,
    };

    let rust_config = WhisperConfig {
        model_path,
        model_size,
        language: crate::config::LanguageConfig {
            source: language,
            translate_to_english: c_config.translate,
        },
        n_threads: c_config.n_threads,
        use_gpu: c_config.use_gpu,
        ..Default::default()
    };

    let mut engine = TranscriptionEngine::new(rust_config);

    match engine.initialize() {
        Ok(()) => {
            let mut global_engine = ENGINE.lock().unwrap();
            *global_engine = Some(engine);
            WhisperResultCode::Success
        }
        Err(crate::error::WhisperError::ModelNotFound(_)) => WhisperResultCode::ModelNotFound,
        Err(_) => WhisperResultCode::Error,
    }
}

/// Initializes the Whisper engine with default configuration.
#[no_mangle]
pub extern "C" fn whisper_init_default() -> WhisperResultCode {
    let mut engine = TranscriptionEngine::with_defaults();

    match engine.initialize() {
        Ok(()) => {
            let mut global_engine = ENGINE.lock().unwrap();
            *global_engine = Some(engine);
            WhisperResultCode::Success
        }
        Err(crate::error::WhisperError::ModelNotFound(_)) => WhisperResultCode::ModelNotFound,
        Err(_) => WhisperResultCode::Error,
    }
}

/// Transcribes audio samples.
///
/// # Safety
/// - `samples` must be a valid pointer to `sample_count` f32 values.
/// - The returned `CTranscriptionResult` must be freed with `whisper_free_result`.
#[no_mangle]
pub unsafe extern "C" fn whisper_transcribe(
    samples: *const f32,
    sample_count: usize,
    sample_rate: u32,
) -> CTranscriptionResult {
    let mut result = CTranscriptionResult::default();

    if samples.is_null() || sample_count == 0 {
        result.result_code = WhisperResultCode::InvalidParameter;
        result.error_message = string_to_c_char("Invalid audio samples");
        return result;
    }

    let engine_guard = ENGINE.lock().unwrap();
    let engine = match engine_guard.as_ref() {
        Some(e) => e,
        None => {
            result.result_code = WhisperResultCode::NotInitialized;
            result.error_message = string_to_c_char("Engine not initialized");
            return result;
        }
    };

    // Create audio buffer from samples
    let samples_slice = std::slice::from_raw_parts(samples, sample_count);
    let audio = AudioBuffer::from_samples(samples_slice.to_vec(), sample_rate);

    match engine.transcribe(&audio) {
        Ok(transcription) => {
            result.text = string_to_c_char(&transcription.text);
            result.language = string_to_c_char(&transcription.language);
            result.segment_count = transcription.segments.len() as i32;
            result.processing_time_ms = transcription.processing_time_ms;
            result.audio_duration_ms = transcription.audio_duration_ms;
            result.result_code = WhisperResultCode::Success;
        }
        Err(e) => {
            result.result_code = WhisperResultCode::TranscriptionFailed;
            result.error_message = string_to_c_char(&e.to_string());
        }
    }

    result
}

/// Transcribes audio from a file.
///
/// # Safety
/// - `file_path` must be a valid null-terminated UTF-8 string.
/// - The returned `CTranscriptionResult` must be freed with `whisper_free_result`.
#[no_mangle]
pub unsafe extern "C" fn whisper_transcribe_file(file_path: *const c_char) -> CTranscriptionResult {
    let mut result = CTranscriptionResult::default();

    if file_path.is_null() {
        result.result_code = WhisperResultCode::InvalidParameter;
        result.error_message = string_to_c_char("File path is null");
        return result;
    }

    let path = match CStr::from_ptr(file_path).to_str() {
        Ok(s) => s,
        Err(_) => {
            result.result_code = WhisperResultCode::InvalidParameter;
            result.error_message = string_to_c_char("Invalid file path encoding");
            return result;
        }
    };

    let engine_guard = ENGINE.lock().unwrap();
    let engine = match engine_guard.as_ref() {
        Some(e) => e,
        None => {
            result.result_code = WhisperResultCode::NotInitialized;
            result.error_message = string_to_c_char("Engine not initialized");
            return result;
        }
    };

    match engine.transcribe_file(path) {
        Ok(transcription) => {
            result.text = string_to_c_char(&transcription.text);
            result.language = string_to_c_char(&transcription.language);
            result.segment_count = transcription.segments.len() as i32;
            result.processing_time_ms = transcription.processing_time_ms;
            result.audio_duration_ms = transcription.audio_duration_ms;
            result.result_code = WhisperResultCode::Success;
        }
        Err(e) => {
            result.result_code = WhisperResultCode::TranscriptionFailed;
            result.error_message = string_to_c_char(&e.to_string());
        }
    }

    result
}

/// Frees a transcription result.
///
/// # Safety
/// The `result` pointer must be valid and have been returned by a whisper_transcribe* function.
#[no_mangle]
pub unsafe extern "C" fn whisper_free_result(result: *mut CTranscriptionResult) {
    if result.is_null() {
        return;
    }

    let result = &mut *result;

    if !result.text.is_null() {
        drop(CString::from_raw(result.text));
        result.text = ptr::null_mut();
    }

    if !result.language.is_null() {
        drop(CString::from_raw(result.language));
        result.language = ptr::null_mut();
    }

    if !result.error_message.is_null() {
        drop(CString::from_raw(result.error_message));
        result.error_message = ptr::null_mut();
    }
}

/// Shuts down the Whisper engine and releases resources.
#[no_mangle]
pub extern "C" fn whisper_shutdown() {
    let mut engine_guard = ENGINE.lock().unwrap();
    if let Some(mut engine) = engine_guard.take() {
        engine.shutdown();
    }
}

/// Returns the library version.
#[no_mangle]
pub extern "C" fn whisper_version() -> *const c_char {
    static VERSION: &[u8] = b"0.1.0\0";
    VERSION.as_ptr() as *const c_char
}

/// Checks if the engine is initialized.
#[no_mangle]
pub extern "C" fn whisper_is_initialized() -> bool {
    let engine_guard = ENGINE.lock().unwrap();
    engine_guard
        .as_ref()
        .map(|e| e.is_initialized())
        .unwrap_or(false)
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Converts a Rust string to a C string pointer.
fn string_to_c_char(s: &str) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}
