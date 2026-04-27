import 'package:whisper_flutter_new/whisper_flutter_new.dart';

/// Represents a downloadable whisper model with UI metadata.
/// For models not in [WhisperModel] enum (large-v3, large-v3-turbo),
/// we store them in a dedicated subdirectory using an equivalent enum entry,
/// since whisper.cpp determines model architecture from the binary header.
class AppWhisperModel {
  final String id;
  final String displayName;
  final String description;
  final int sizeMb;

  /// The WhisperModel enum value used to instantiate [Whisper].
  /// For large-v3 and large-v3-turbo this maps to an existing enum.
  final WhisperModel whisperEnum;

  /// Subdirectory name within the base model directory.
  /// Standard models share a flat directory; custom ones get their own subdir.
  final String subDir;

  const AppWhisperModel({
    required this.id,
    required this.displayName,
    required this.description,
    required this.sizeMb,
    required this.whisperEnum,
    required this.subDir,
  });

  /// Returns the file name that [WhisperModel.getPath] expects.
  String get modelFileName => 'ggml-${whisperEnum.modelName}.bin';

  /// Unique download file name used as the source URL filename component.
  /// For standard models this equals [modelFileName].
  /// For extended models (large-v3, large-v3-turbo) this is their real name.
  String get downloadFileName => 'ggml-$id.bin';

  static const List<AppWhisperModel> builtIn = [
    AppWhisperModel(
      id: 'tiny',
      displayName: 'Tiny',
      description: '~39 MB · 最快，适合简单场景',
      sizeMb: 39,
      whisperEnum: WhisperModel.tiny,
      subDir: 'models',
    ),
    AppWhisperModel(
      id: 'base',
      displayName: 'Base',
      description: '~74 MB · 快速，适合日常使用',
      sizeMb: 74,
      whisperEnum: WhisperModel.base,
      subDir: 'models',
    ),
    AppWhisperModel(
      id: 'small',
      displayName: 'Small',
      description: '~244 MB · 平衡速度与精度',
      sizeMb: 244,
      whisperEnum: WhisperModel.small,
      subDir: 'models',
    ),
    AppWhisperModel(
      id: 'medium',
      displayName: 'Medium',
      description: '~769 MB · 精度较高',
      sizeMb: 769,
      whisperEnum: WhisperModel.medium,
      subDir: 'models',
    ),
    AppWhisperModel(
      id: 'large-v1',
      displayName: 'Large V1',
      description: '~1.5 GB · 高精度',
      sizeMb: 1500,
      whisperEnum: WhisperModel.largeV1,
      subDir: 'models',
    ),
    AppWhisperModel(
      id: 'large-v2',
      displayName: 'Large V2',
      description: '~1.5 GB · 高精度（推荐）',
      sizeMb: 1550,
      whisperEnum: WhisperModel.largeV2,
      subDir: 'models',
    ),
    // large-v3 uses largeV2 enum inside its own subdir so filenames don't clash
    AppWhisperModel(
      id: 'large-v3',
      displayName: 'Large V3',
      description: '~1.5 GB · 最新 Large 版本',
      sizeMb: 1550,
      whisperEnum: WhisperModel.largeV2,
      subDir: 'models_large_v3',
    ),
    // large-v3-turbo is a smaller/faster large variant (~800 MB)
    AppWhisperModel(
      id: 'large-v3-turbo',
      displayName: 'Large V3 Turbo',
      description: '~800 MB · 最新高速大模型',
      sizeMb: 800,
      whisperEnum: WhisperModel.medium,
      subDir: 'models_large_v3_turbo',
    ),
  ];
}

/// Custom model entry persisted to SharedPreferences.
class CustomWhisperModel {
  final String id; // uuid or derived
  final String displayName;
  final String filePath; // full path to the downloaded .bin file
  final int sizeMb;

  const CustomWhisperModel({
    required this.id,
    required this.displayName,
    required this.filePath,
    required this.sizeMb,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'filePath': filePath,
        'sizeMb': sizeMb,
      };

  factory CustomWhisperModel.fromJson(Map<String, dynamic> j) =>
      CustomWhisperModel(
        id: j['id'] as String,
        displayName: j['displayName'] as String,
        filePath: j['filePath'] as String,
        sizeMb: j['sizeMb'] as int,
      );
}
