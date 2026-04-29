import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

/// Handles VAD-based real-time transcription.
///
/// Instead of cutting audio at fixed intervals, this service uses
/// energy-based Voice Activity Detection to find natural speech pauses
/// and chunk at those boundaries. Each chunk is a complete utterance.
class WhisperService {
  WhisperService();

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<String> _streamController =
      StreamController<String>.broadcast();

  bool _running = false;
  int _chunkIndex = 0;
  String _tmpDir = '';

  // Stored for final flush on stop()
  String _modelDir = '';
  WhisperModel _whisperEnum = WhisperModel.base;
  String _language = 'auto';

  // ── VAD state ─────────────────────────────────────────────────────────────
  final List<double> _speechBuffer = [];
  bool _isSpeaking = false;
  int _silenceFrameCount = 0;
  int _speechFrameCount = 0;

  // Adaptive noise floor tracking
  double _noiseFloor = 0.005;
  double _peakEnergy = 0.01;

  StreamSubscription<Uint8List>? _audioSub;

  // ── VAD parameters ────────────────────────────────────────────────────────
  static const int _sampleRate = 16000;
  static const int _frameSize = 480; // 30ms at 16kHz
  static const int _silenceFramesThreshold = 20; // 600ms of silence → end of utterance
  static const int _minSpeechFrames = 10; // 300ms minimum speech to avoid noise
  static const int _maxChunkFrames = 1000; // 30s max chunk duration

  Stream<String> get transcriptionStream => _streamController.stream;
  bool get isRunning => _running;

  /// Starts real-time dictation with VAD-based chunking.
  Future<void> start({
    required String modelDir,
    required WhisperModel whisperEnum,
    required String language,
    required String tmpDir,
  }) async {
    if (_running) return;

    if (!await _recorder.hasPermission()) {
      throw Exception('麦克风权限未授权');
    }

    _running = true;
    _chunkIndex = 0;
    _tmpDir = tmpDir;
    _modelDir = modelDir;
    _whisperEnum = whisperEnum;
    _language = language;
    _speechBuffer.clear();
    _isSpeaking = false;
    _silenceFrameCount = 0;
    _speechFrameCount = 0;
    _noiseFloor = 0.005;
    _peakEnergy = 0.01;

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    );

    final stream = await _recorder.startStream(config);

    _audioSub = stream.listen(
      (Uint8List data) {
        if (!_running) return;
        _processAudioData(
          data: data,
          modelDir: modelDir,
          whisperEnum: whisperEnum,
          language: language,
        );
      },
      onError: (e) {
        // Stream error — stop gracefully
        stop();
      },
      onDone: () {
        // Stream ended
        if (_running) stop();
      },
    );
  }

  /// Processes incoming PCM audio data through the VAD pipeline.
  void _processAudioData({
    required Uint8List data,
    required String modelDir,
    required WhisperModel whisperEnum,
    required String language,
  }) {
    // Convert PCM16 bytes to float32 samples
    final samples = _bytesToFloat32(data);

    // Process in frame-sized chunks
    int offset = 0;
    while (offset + _frameSize <= samples.length) {
      final frame = Float32List.sublistView(samples, offset, offset + _frameSize);
      _processFrame(
        frame: frame,
        modelDir: modelDir,
        whisperEnum: whisperEnum,
        language: language,
      );
      offset += _frameSize;
    }

    // Handle remaining samples (less than a full frame) — add to buffer if speaking
    if (offset < samples.length && _isSpeaking) {
      _speechBuffer.addAll(samples.sublist(offset));
    }
  }

  /// Processes a single 30ms audio frame through the VAD state machine.
  void _processFrame({
    required Float32List frame,
    required String modelDir,
    required WhisperModel whisperEnum,
    required String language,
  }) {
    final energy = _rms(frame);

    // Update adaptive noise floor (only during silence)
    if (!_isSpeaking) {
      _noiseFloor = _noiseFloor * 0.995 + energy * 0.005;
    }

    // Dynamic threshold: at least 3x noise floor, with a minimum of 0.01
    final threshold = max(_noiseFloor * 3.0, 0.01);

    // Track peak energy for normalization
    if (energy > _peakEnergy) {
      _peakEnergy = energy;
    }

    final isSpeech = energy > threshold;

    if (!_isSpeaking) {
      // ── WAITING state ──
      if (isSpeech) {
        _isSpeaking = true;
        _speechFrameCount = 1;
        _silenceFrameCount = 0;
        _speechBuffer.addAll(frame);
      }
    } else {
      // ── SPEAKING state ──
      _speechBuffer.addAll(frame);
      _speechFrameCount++;

      if (isSpeech) {
        _silenceFrameCount = 0;
      } else {
        _silenceFrameCount++;
      }

      // Check if we should flush:
      // 1. Silence detected after speech (natural pause)
      // 2. Max chunk duration reached (safety)
      final shouldFlushOnSilence =
          _silenceFrameCount >= _silenceFramesThreshold &&
              _speechFrameCount >= _minSpeechFrames;
      final shouldFlushOnMax = _speechFrameCount >= _maxChunkFrames;

      if (shouldFlushOnSilence || shouldFlushOnMax) {
        _isSpeaking = false;
        _flushBuffer(
          modelDir: modelDir,
          whisperEnum: whisperEnum,
          language: language,
        );
      }
    }
  }

  /// Flushes the speech buffer, writes a WAV file, and starts transcription.
  void _flushBuffer({
    required String modelDir,
    required WhisperModel whisperEnum,
    required String language,
  }) {
    final samples = List<double>.from(_speechBuffer);
    _speechBuffer.clear();
    _speechFrameCount = 0;
    _silenceFrameCount = 0;

    // Skip very short audio (likely noise)
    if (samples.length < _minSpeechFrames * _frameSize) return;

    // Write WAV and transcribe in background
    _writeAndTranscribe(
      samples: samples,
      modelDir: modelDir,
      whisperEnum: whisperEnum,
      language: language,
    );
  }

  /// Writes PCM samples to a WAV file and transcribes it.
  Future<void> _writeAndTranscribe({
    required List<double> samples,
    required String modelDir,
    required WhisperModel whisperEnum,
    required String language,
  }) async {
    String? path;
    try {
      path = _chunkPath(_chunkIndex);
      _chunkIndex++;
      _writeWavFile(path, samples);

      final file = File(path);
      if (!file.existsSync()) return;
      if (file.lengthSync() < 2048) {
        _safeDelete(file);
        return;
      }

      final whisper = Whisper(model: whisperEnum, modelDir: modelDir);
      final response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: path,
          language: language,
          isTranslate: false,
          isNoTimestamps: true,
        ),
      );
      final text = response.text.trim();
      if (text.isNotEmpty && !_streamController.isClosed) {
        _streamController.add(text);
      }
    } catch (e) {
      // Silently drop failed transcriptions
    } finally {
      if (path != null) {
        _safeDelete(File(path));
      }
    }
  }

  /// Converts PCM16 bytes to float32 samples.
  Float32List _bytesToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final samples = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      // Little-endian PCM16 to float32
      final int16 = (bytes[i * 2] & 0xFF) | ((bytes[i * 2 + 1] & 0xFF) << 8);
      // Sign extend from 16-bit
      final signed = int16 >= 0x8000 ? int16 - 0x10000 : int16;
      samples[i] = signed / 32768.0;
    }
    return samples;
  }

  /// Calculates RMS (root mean square) energy of a frame.
  double _rms(Float32List frame) {
    double sum = 0;
    for (int i = 0; i < frame.length; i++) {
      sum += frame[i] * frame[i];
    }
    return sqrt(sum / frame.length);
  }

  /// Writes PCM float32 samples to a WAV file (16-bit, 16kHz, mono).
  void _writeWavFile(String path, List<double> samples) {
    final pcmData = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      // Clamp to [-1, 1] and convert to PCM16
      final clamped = samples[i].clamp(-1.0, 1.0);
      final int16 = (clamped * 32767).round();
      pcmData.setInt16(i * 2, int16, Endian.little);
    }

    final dataSize = samples.length * 2;
    final file = File(path);
    final sink = file.openSync(mode: FileMode.write);

    // WAV header (44 bytes)
    final header = ByteData(44);
    // "RIFF"
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    // File size - 8
    header.setUint32(4, 36 + dataSize, Endian.little);
    // "WAVE"
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // "fmt "
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    // Subchunk1 size (16 for PCM)
    header.setUint32(16, 16, Endian.little);
    // Audio format (1 = PCM)
    header.setUint16(20, 1, Endian.little);
    // Number of channels (1 = mono)
    header.setUint16(22, 1, Endian.little);
    // Sample rate
    header.setUint32(24, _sampleRate, Endian.little);
    // Byte rate
    header.setUint32(28, _sampleRate * 2, Endian.little);
    // Block align
    header.setUint16(32, 2, Endian.little);
    // Bits per sample
    header.setUint16(34, 16, Endian.little);
    // "data"
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    // Data size
    header.setUint32(40, dataSize, Endian.little);

    sink.writeFromSync(header.buffer.asUint8List());
    sink.writeFromSync(pcmData.buffer.asUint8List());
    sink.closeSync();
  }

  String _chunkPath(int index) => '$_tmpDir/vad_chunk_$index.wav';

  void _safeDelete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> stop() async {
    _running = false;
    await _audioSub?.cancel();
    _audioSub = null;

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    // Flush any remaining audio in the buffer
    if (_speechBuffer.isNotEmpty &&
        _speechBuffer.length >= _minSpeechFrames * _frameSize) {
      final samples = List<double>.from(_speechBuffer);
      _speechBuffer.clear();
      // Transcribe the final chunk in background
      _writeAndTranscribe(
        samples: samples,
        modelDir: _modelDir,
        whisperEnum: _whisperEnum,
        language: _language,
      );
    } else {
      _speechBuffer.clear();
    }
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
    await _streamController.close();
  }
}
