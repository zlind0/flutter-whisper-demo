import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_whisper_model.dart';

enum DownloadSource {
  huggingface,
  hfMirror,
}

extension DownloadSourceExt on DownloadSource {
  String get label {
    switch (this) {
      case DownloadSource.huggingface:
        return 'HuggingFace';
      case DownloadSource.hfMirror:
        return 'HF-Mirror (中国镜像)';
    }
  }

  String get baseUrl {
    switch (this) {
      case DownloadSource.huggingface:
        return 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';
      case DownloadSource.hfMirror:
        return 'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main';
    }
  }
}

class DownloadProgress {
  final String modelId;
  final double progress; // 0.0 – 1.0
  final bool isComplete;
  final String? error;

  const DownloadProgress({
    required this.modelId,
    required this.progress,
    this.isComplete = false,
    this.error,
  });
}

class ModelManager {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 30),
  ));

  /// Returns the base directory where models are stored.
  Future<String> _baseDir() async {
    final Directory dir = Platform.isAndroid
        ? await getApplicationSupportDirectory()
        : await getLibraryDirectory();
    return dir.path;
  }

  /// Returns the directory path for a given [AppWhisperModel].
  Future<String> modelDir(AppWhisperModel model) async {
    final base = await _baseDir();
    final dir = Directory('$base/${model.subDir}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Returns the full file path for a given [AppWhisperModel].
  Future<String> modelFilePath(AppWhisperModel model) async {
    final dir = await modelDir(model);
    return '$dir/${model.modelFileName}';
  }

  /// Returns true if the model binary is present on disk.
  Future<bool> isModelDownloaded(AppWhisperModel model) async {
    final path = await modelFilePath(model);
    return File(path).existsSync();
  }

  /// Downloads [model] from [source], calling [onProgress] with 0–1 values.
  /// Throws on network or I/O errors.
  Future<void> downloadModel({
    required AppWhisperModel model,
    required DownloadSource source,
    required void Function(double) onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = '${source.baseUrl}/${model.downloadFileName}';
    await _downloadFromUrl(
      url: url,
      destPath: await modelFilePath(model),
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// Downloads a model from an arbitrary [url], saving to [destPath].
  Future<void> downloadFromCustomUrl({
    required String url,
    required String destPath,
    required void Function(double) onProgress,
    CancelToken? cancelToken,
  }) async {
    await _downloadFromUrl(
      url: url,
      destPath: destPath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<void> _downloadFromUrl({
    required String url,
    required String destPath,
    required void Function(double) onProgress,
    CancelToken? cancelToken,
  }) async {
    await _dio.download(
      url,
      destPath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress(received / total);
        }
      },
      options: Options(
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );
  }

  /// Deletes the model binary for [model]. No-op if not present.
  Future<void> deleteModel(AppWhisperModel model) async {
    final path = await modelFilePath(model);
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  /// Cancels a running download by calling [cancelToken.cancel].
  void cancelDownload(CancelToken token) {
    token.cancel('User cancelled');
  }

  /// Returns a temporary directory path for audio chunk files.
  Future<String> tempDir() async {
    final dir = await getTemporaryDirectory();
    final chunkDir = Directory('${dir.path}/whisper_chunks');
    if (!chunkDir.existsSync()) chunkDir.createSync(recursive: true);
    return chunkDir.path;
  }

  /// Cleans up any leftover audio chunk files.
  Future<void> cleanTempChunks() async {
    final dir = Directory(await tempDir());
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        try {
          f.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }
}
