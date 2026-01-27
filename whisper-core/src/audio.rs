//! Audio capture and processing utilities.

use crate::error::{Result, WhisperError};
use std::sync::{Arc, Mutex};

/// Audio sample rate expected by Whisper (16kHz).
pub const WHISPER_SAMPLE_RATE: u32 = 16000;

/// Audio format for Whisper processing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioFormat {
    /// 16-bit signed integer PCM
    I16,
    /// 32-bit floating point
    F32,
}

/// Audio buffer for storing recorded samples.
#[derive(Debug, Clone)]
pub struct AudioBuffer {
    /// Audio samples (f32, mono, 16kHz).
    samples: Vec<f32>,
    /// Sample rate of the buffer.
    sample_rate: u32,
}

impl AudioBuffer {
    /// Creates a new empty audio buffer.
    pub fn new() -> Self {
        Self {
            samples: Vec::new(),
            sample_rate: WHISPER_SAMPLE_RATE,
        }
    }

    /// Creates a buffer with pre-allocated capacity.
    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            samples: Vec::with_capacity(capacity),
            sample_rate: WHISPER_SAMPLE_RATE,
        }
    }

    /// Creates a buffer from existing samples.
    pub fn from_samples(samples: Vec<f32>, sample_rate: u32) -> Self {
        Self {
            samples,
            sample_rate,
        }
    }

    /// Returns the samples as a slice.
    pub fn samples(&self) -> &[f32] {
        &self.samples
    }

    /// Returns the sample rate.
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    /// Returns the duration in seconds.
    pub fn duration_seconds(&self) -> f32 {
        self.samples.len() as f32 / self.sample_rate as f32
    }

    /// Returns the number of samples.
    pub fn len(&self) -> usize {
        self.samples.len()
    }

    /// Returns true if the buffer is empty.
    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }

    /// Appends samples to the buffer.
    pub fn append(&mut self, samples: &[f32]) {
        self.samples.extend_from_slice(samples);
    }

    /// Clears all samples from the buffer.
    pub fn clear(&mut self) {
        self.samples.clear();
    }

    /// Resamples the audio to the target sample rate if needed.
    pub fn resample(&self, target_rate: u32) -> Result<AudioBuffer> {
        if self.sample_rate == target_rate {
            return Ok(self.clone());
        }

        let ratio = target_rate as f64 / self.sample_rate as f64;
        let new_len = (self.samples.len() as f64 * ratio) as usize;
        let mut resampled = Vec::with_capacity(new_len);

        for i in 0..new_len {
            let src_idx = i as f64 / ratio;
            let idx_floor = src_idx.floor() as usize;
            let idx_ceil = (idx_floor + 1).min(self.samples.len() - 1);
            let frac = src_idx - idx_floor as f64;

            let sample = self.samples[idx_floor] as f64 * (1.0 - frac)
                + self.samples[idx_ceil] as f64 * frac;
            resampled.push(sample as f32);
        }

        Ok(AudioBuffer::from_samples(resampled, target_rate))
    }

    /// Converts stereo audio to mono by averaging channels.
    pub fn stereo_to_mono(left: &[f32], right: &[f32]) -> Vec<f32> {
        left.iter()
            .zip(right.iter())
            .map(|(l, r)| (l + r) / 2.0)
            .collect()
    }

    /// Normalizes audio to the range [-1.0, 1.0].
    pub fn normalize(&mut self) {
        if self.samples.is_empty() {
            return;
        }

        let max_abs = self
            .samples
            .iter()
            .map(|s| s.abs())
            .fold(0.0f32, |a, b| a.max(b));

        if max_abs > 0.0 && max_abs != 1.0 {
            let scale = 1.0 / max_abs;
            for sample in &mut self.samples {
                *sample *= scale;
            }
        }
    }

    /// Applies a simple noise gate.
    pub fn apply_noise_gate(&mut self, threshold: f32) {
        for sample in &mut self.samples {
            if sample.abs() < threshold {
                *sample = 0.0;
            }
        }
    }
}

impl Default for AudioBuffer {
    fn default() -> Self {
        Self::new()
    }
}

/// Thread-safe audio recorder state.
pub struct AudioRecorderState {
    /// Whether recording is active.
    pub is_recording: bool,
    /// The current audio buffer.
    pub buffer: AudioBuffer,
}

impl AudioRecorderState {
    pub fn new() -> Self {
        Self {
            is_recording: false,
            buffer: AudioBuffer::new(),
        }
    }
}

/// Shared state type for the audio recorder.
pub type SharedRecorderState = Arc<Mutex<AudioRecorderState>>;

/// Creates a new shared recorder state.
pub fn create_shared_state() -> SharedRecorderState {
    Arc::new(Mutex::new(AudioRecorderState::new()))
}

/// Loads audio from a WAV file.
pub fn load_wav_file(path: &str) -> Result<AudioBuffer> {
    let reader = hound::WavReader::open(path)
        .map_err(|e| WhisperError::IoError(std::io::Error::new(
            std::io::ErrorKind::Other,
            e.to_string(),
        )))?;

    let spec = reader.spec();
    let sample_rate = spec.sample_rate;

    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => {
            reader
                .into_samples::<f32>()
                .filter_map(|s| s.ok())
                .collect()
        }
        hound::SampleFormat::Int => {
            let max_value = (1 << (spec.bits_per_sample - 1)) as f32;
            reader
                .into_samples::<i32>()
                .filter_map(|s| s.ok())
                .map(|s| s as f32 / max_value)
                .collect()
        }
    };

    // Convert to mono if stereo
    let mono_samples = if spec.channels == 2 {
        samples
            .chunks(2)
            .map(|chunk| (chunk[0] + chunk.get(1).unwrap_or(&0.0)) / 2.0)
            .collect()
    } else {
        samples
    };

    let mut buffer = AudioBuffer::from_samples(mono_samples, sample_rate);
    
    // Resample to Whisper's expected rate if needed
    if sample_rate != WHISPER_SAMPLE_RATE {
        buffer = buffer.resample(WHISPER_SAMPLE_RATE)?;
    }

    Ok(buffer)
}
