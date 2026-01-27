#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <ostream>
#include <new>

/// Audio sample rate expected by Whisper (16kHz).
constexpr static const uint32_t WHISPER_SAMPLE_RATE = 16000;

/// Result codes for FFI functions.
enum class WhisperResultCode {
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
};

/// C-compatible configuration.
struct CWhisperConfig {
  /// Path to the model file (null-terminated UTF-8).
  const char *model_path;
  /// Model size enum value.
  int32_t model_size;
  /// Language code (null-terminated UTF-8).
  const char *language;
  /// Whether to translate to English.
  bool translate;
  /// Number of threads (0 = auto).
  uint32_t n_threads;
  /// Enable GPU acceleration.
  bool use_gpu;
};

/// C-compatible transcription result.
struct CTranscriptionResult {
  /// Transcribed text (null-terminated UTF-8).
  char *text;
  /// Detected language code.
  char *language;
  /// Number of segments.
  int32_t segment_count;
  /// Processing time in milliseconds.
  uint64_t processing_time_ms;
  /// Audio duration in milliseconds.
  uint64_t audio_duration_ms;
  /// Result code.
  WhisperResultCode result_code;
  /// Error message if result_code != Success.
  char *error_message;
};

extern "C" {

/// Initializes the Whisper engine with the given configuration.
///
/// # Safety
/// The `config` pointer must be valid and properly initialized.
WhisperResultCode whisper_init(const CWhisperConfig *config);

/// Initializes the Whisper engine with default configuration.
WhisperResultCode whisper_init_default();

/// Transcribes audio samples.
///
/// # Safety
/// - `samples` must be a valid pointer to `sample_count` f32 values.
/// - The returned `CTranscriptionResult` must be freed with `whisper_free_result`.
CTranscriptionResult whisper_transcribe(const float *samples,
                                        uintptr_t sample_count,
                                        uint32_t sample_rate);

/// Transcribes audio from a file.
///
/// # Safety
/// - `file_path` must be a valid null-terminated UTF-8 string.
/// - The returned `CTranscriptionResult` must be freed with `whisper_free_result`.
CTranscriptionResult whisper_transcribe_file(const char *file_path);

/// Frees a transcription result.
///
/// # Safety
/// The `result` pointer must be valid and have been returned by a whisper_transcribe* function.
void whisper_free_result(CTranscriptionResult *result);

/// Shuts down the Whisper engine and releases resources.
void whisper_shutdown();

/// Returns the library version.
const char *whisper_version();

/// Checks if the engine is initialized.
bool whisper_is_initialized();

} // extern "C"
