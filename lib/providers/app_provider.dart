import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../models/app_whisper_model.dart';
import '../services/model_manager.dart';
import '../services/whisper_service.dart';

class DownloadTask {
  final double progress; // 0.0 – 1.0
  final CancelToken cancelToken;
  const DownloadTask(this.progress, this.cancelToken);
}

class AppProvider extends ChangeNotifier {
  AppProvider() {
    _modelManager = ModelManager();
    _whisperService = WhisperService();
    _load();
  }

  late final ModelManager _modelManager;
  late WhisperService _whisperService;
  StreamSubscription<String>? _transcriptionSub;

  // ── Settings ──────────────────────────────────────────────────────────────
  String _selectedModelId = 'base';
  String _selectedLanguage = 'auto';
  List<String> _recentLanguages = ['zh', 'en'];
  DownloadSource _downloadSource = DownloadSource.huggingface;
  String _customDownloadBaseUrl = '';
  List<CustomWhisperModel> _customModels = [];

  // ── Transcription ─────────────────────────────────────────────────────────
  String _transcriptionText = '';
  bool _isRecording = false;
  String _statusMessage = '';

  // ── Downloads ─────────────────────────────────────────────────────────────
  // modelId → ongoing DownloadTask
  final Map<String, DownloadTask> _activeTasks = {};

  // ── Getters ───────────────────────────────────────────────────────────────
  String get selectedModelId => _selectedModelId;
  String get selectedLanguage => _selectedLanguage;
  List<String> get recentLanguages => List.unmodifiable(_recentLanguages);
  DownloadSource get downloadSource => _downloadSource;
  String get customDownloadBaseUrl => _customDownloadBaseUrl;
  List<CustomWhisperModel> get customModels => List.unmodifiable(_customModels);
  String get transcriptionText => _transcriptionText;
  bool get isRecording => _isRecording;
  String get statusMessage => _statusMessage;

  AppWhisperModel? get selectedBuiltInModel {
    try {
      return AppWhisperModel.builtIn
          .firstWhere((m) => m.id == _selectedModelId);
    } catch (_) {
      return null;
    }
  }

  /// Whether the current platform has native Whisper support.
  bool get isPlatformSupported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  double? downloadProgressFor(String modelId) =>
      _activeTasks[modelId]?.progress;

  bool isDownloading(String modelId) => _activeTasks.containsKey(modelId);

  // ── Settings mutations ────────────────────────────────────────────────────
  void selectModel(String id) {
    _selectedModelId = id;
    _save();
    notifyListeners();
  }

  void selectLanguage(String code) {
    if (code == _selectedLanguage) return;
    // Update recents: keep at most 2, no duplicates
    final updated = [_selectedLanguage, ..._recentLanguages]
        .where((c) => c != code && c != 'auto')
        .toList();
    _recentLanguages = updated.take(2).toList();
    _selectedLanguage = code;
    _save();
    notifyListeners();
  }

  void setDownloadSource(DownloadSource source) {
    _downloadSource = source;
    _save();
    notifyListeners();
  }

  void setCustomDownloadBaseUrl(String url) {
    _customDownloadBaseUrl = url.trim();
    _save();
    notifyListeners();
  }

  // ── Model availability ────────────────────────────────────────────────────
  Future<bool> isBuiltInModelDownloaded(AppWhisperModel model) =>
      _modelManager.isModelDownloaded(model);

  Future<String> modelFilePath(AppWhisperModel model) =>
      _modelManager.modelFilePath(model);

  // ── Download management ───────────────────────────────────────────────────
  Future<void> downloadBuiltInModel(AppWhisperModel model) async {
    if (_activeTasks.containsKey(model.id)) return;

    final cancelToken = CancelToken();
    _activeTasks[model.id] = DownloadTask(0.0, cancelToken);
    notifyListeners();

    try {
      await _modelManager.downloadModel(
        model: model,
        source: _downloadSource,
        onProgress: (p) {
          _activeTasks[model.id] = DownloadTask(p, cancelToken);
          notifyListeners();
        },
        cancelToken: cancelToken,
      );
      _setStatus('${model.displayName} 下载完成');
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) {
        _setStatus('下载失败：${e.message}');
      }
    } catch (e) {
      _setStatus('下载失败：$e');
    } finally {
      _activeTasks.remove(model.id);
      notifyListeners();
    }
  }

  void cancelDownload(String modelId) {
    _activeTasks[modelId]?.cancelToken.cancel();
  }

  Future<void> deleteBuiltInModel(AppWhisperModel model) async {
    await _modelManager.deleteModel(model);
    if (_selectedModelId == model.id) {
      _selectedModelId = 'base';
      _save();
    }
    notifyListeners();
  }

  /// Downloads a model from a user-specified URL and registers it as a custom model.
  Future<void> downloadCustomModel({
    required String url,
    required String displayName,
  }) async {
    const id = 'custom';
    if (_activeTasks.containsKey(id)) return;

    final destDir = Directory('${(await _modelManager.tempDir()).replaceAll('/whisper_chunks', '')}/custom_models');
    if (!destDir.existsSync()) destDir.createSync(recursive: true);

    final fileName = Uri.parse(url).pathSegments.last.isNotEmpty
        ? Uri.parse(url).pathSegments.last
        : 'custom_model.bin';
    final destPath = '${destDir.path}/$fileName';

    final cancelToken = CancelToken();
    _activeTasks[id] = DownloadTask(0.0, cancelToken);
    notifyListeners();

    try {
      await _modelManager.downloadFromCustomUrl(
        url: url,
        destPath: destPath,
        onProgress: (p) {
          _activeTasks[id] = DownloadTask(p, cancelToken);
          notifyListeners();
        },
        cancelToken: cancelToken,
      );

      final file = File(destPath);
      final sizeMb = (file.lengthSync() / 1024 / 1024).round();
      final customId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      final cm = CustomWhisperModel(
        id: customId,
        displayName: displayName.isEmpty ? fileName : displayName,
        filePath: destPath,
        sizeMb: sizeMb,
      );
      _customModels = [..._customModels, cm];
      _setStatus('自定义模型 "${cm.displayName}" 下载完成');
      _save();
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) {
        _setStatus('下载失败：${e.message}');
      }
    } catch (e) {
      _setStatus('下载失败：$e');
    } finally {
      _activeTasks.remove(id);
      notifyListeners();
    }
  }

  void deleteCustomModel(String customId) {
    final model = _customModels.firstWhere((m) => m.id == customId,
        orElse: () => throw StateError('not found'));
    try {
      final f = File(model.filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _customModels = _customModels.where((m) => m.id != customId).toList();
    _save();
    notifyListeners();
  }

  // ── Transcription ─────────────────────────────────────────────────────────
  Future<void> startDictation() async {
    if (_isRecording || !isPlatformSupported) return;

    final model = selectedBuiltInModel;
    if (model == null) {
      _setStatus('未选择模型');
      return;
    }

    final downloaded = await _modelManager.isModelDownloaded(model);
    if (!downloaded) {
      _setStatus('模型尚未下载，请前往设置页面下载');
      return;
    }

    final dir = await _modelManager.modelDir(model);
    final tmpDir = await _modelManager.tempDir();
    await _modelManager.cleanTempChunks();

    // Re-create service each session (avoids stale stream)
    _transcriptionSub?.cancel();
    _whisperService = WhisperService();
    _transcriptionSub =
        _whisperService.transcriptionStream.listen(_onChunkResult);

    try {
      await _whisperService.start(
        modelDir: dir,
        whisperEnum: model.whisperEnum,
        language: _selectedLanguage,
        tmpDir: tmpDir,
      );
      _isRecording = true;
      _setStatus('正在听写…');
    } catch (e) {
      _setStatus('启动失败：$e');
    }
    notifyListeners();
  }

  Future<void> stopDictation() async {
    if (!_isRecording) return;
    await _whisperService.stop();
    _isRecording = false;
    _setStatus('');
    notifyListeners();
  }

  void _onChunkResult(String text) {
    _transcriptionText = _transcriptionText.isEmpty
        ? text
        : '$_transcriptionText $text';
    notifyListeners();
  }

  void clearTranscription() {
    _transcriptionText = '';
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _setStatus(String msg) {
    _statusMessage = msg;
    notifyListeners();
  }

  // ── Persistence ───────────────────────────────────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedModelId = prefs.getString('selectedModelId') ?? 'base';
    _selectedLanguage = prefs.getString('selectedLanguage') ?? 'auto';
    _recentLanguages =
        prefs.getStringList('recentLanguages') ?? ['zh', 'en'];
    _downloadSource = DownloadSource.values[
        prefs.getInt('downloadSource') ?? 0];
    _customDownloadBaseUrl =
        prefs.getString('customDownloadBaseUrl') ?? '';

    final customJson = prefs.getStringList('customModels') ?? [];
    _customModels = customJson
        .map((s) =>
            CustomWhisperModel.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();

    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedModelId', _selectedModelId);
    await prefs.setString('selectedLanguage', _selectedLanguage);
    await prefs.setStringList('recentLanguages', _recentLanguages);
    await prefs.setInt('downloadSource', _downloadSource.index);
    await prefs.setString('customDownloadBaseUrl', _customDownloadBaseUrl);
    await prefs.setStringList(
        'customModels', _customModels.map((m) => jsonEncode(m.toJson())).toList());
  }

  @override
  void dispose() {
    _transcriptionSub?.cancel();
    _whisperService.dispose();
    super.dispose();
  }
}
