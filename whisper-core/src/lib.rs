//! # Whisper Core
//!
//! High-performance Whisper transcription engine with Swift FFI bindings.
//! This crate provides the core audio processing and transcription functionality
//! for the BetterFasterWhisper application.

pub mod audio;
pub mod config;
pub mod error;
pub mod ffi;
pub mod transcription;

pub use config::WhisperConfig;
pub use error::{WhisperError, Result};
pub use transcription::{TranscriptionEngine, TranscriptionResult, Segment};
