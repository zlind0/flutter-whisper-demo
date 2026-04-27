import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

/// Handles chunked real-time transcription.
///
/// Strategy: record audio in [chunkDuration] windows. As each chunk
/// finishes the next begins immediately (minimal gap). Each finished
/// chunk is transcribed in the background and text is emitted via
/// [transcriptionStream].
class WhisperService {
  WhisperService({
    this.chunkDuration = const Duration(seconds: 5),
  });

  final Duration chunkDuration;

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<String> _streamController =
      StreamController<String>.broadcast();

  bool _running = false;
  int _chunkIndex = 0;
  String _tmpDir = '';

  Stream<String> get transcriptionStream => _streamController.stream;
  bool get isRunning => _running;

  /// Starts real-time dictation.
  /// [modelDir] is the directory that contains the model binary.
  /// [whisperEnum] is the WhisperModel enum value that maps to the binary.
  /// [language] is the ISO code ('zh', 'en', 'auto', …).
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

    _loop(modelDir: modelDir, whisperEnum: whisperEnum, language: language);
  }

  Future<void> _loop({
    required String modelDir,
    required WhisperModel whisperEnum,
    required String language,
  }) async {
    final config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    );

    // Start first chunk
    String currentPath = _chunkPath(_chunkIndex);
    await _recorder.start(config, path: currentPath);

    while (_running) {
      await Future.delayed(chunkDuration);

      if (!_running) break;

      final pathToProcess = currentPath;
      _chunkIndex++;
      currentPath = _chunkPath(_chunkIndex);

      // Stop current chunk and immediately start the next
      await _recorder.stop();
      if (_running) {
        await _recorder.start(config, path: currentPath);
      }

      // Process finished chunk in background
      _transcribeChunk(
        path: pathToProcess,
        modelDir: modelDir,
        whisperEnum: whisperEnum,
        language: language,
      );
    }

    // Process any final chunk
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _transcribeChunk(
      path: currentPath,
      modelDir: modelDir,
      whisperEnum: whisperEnum,
      language: language,
    );
  }

  Future<void> _transcribeChunk({
    required String path,
    required String modelDir,
    required WhisperModel whisperEnum,
    required String language,
  }) async {
    final file = File(path);
    if (!file.existsSync()) return;

    // Skip very small files (no meaningful audio)
    if (file.lengthSync() < 2048) {
      _safeDelete(file);
      return;
    }

    try {
      final whisper = Whisper(
        model: whisperEnum,
        modelDir: modelDir,
      );
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
      // Silently drop failed chunks; caller sees nothing rather than a crash
    } finally {
      _safeDelete(file);
    }
  }

  void _safeDelete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  String _chunkPath(int index) =>
      '$_tmpDir/chunk_$index.wav';

  Future<void> stop() async {
    _running = false;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
    await _streamController.close();
  }
}
