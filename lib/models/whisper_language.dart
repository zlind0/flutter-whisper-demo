class WhisperLanguage {
  final String code;
  final String nativeName;
  final String chineseName;

  const WhisperLanguage({
    required this.code,
    required this.nativeName,
    required this.chineseName,
  });

  String get displayName => '$chineseName ($nativeName)';

  static const WhisperLanguage auto = WhisperLanguage(
    code: 'auto',
    nativeName: 'Auto Detect',
    chineseName: '自动检测',
  );

  static const List<WhisperLanguage> all = [
    auto,
    WhisperLanguage(code: 'zh', nativeName: '中文', chineseName: '中文'),
    WhisperLanguage(code: 'en', nativeName: 'English', chineseName: '英语'),
    WhisperLanguage(code: 'ja', nativeName: '日本語', chineseName: '日语'),
    WhisperLanguage(code: 'ko', nativeName: '한국어', chineseName: '韩语'),
    WhisperLanguage(code: 'fr', nativeName: 'Français', chineseName: '法语'),
    WhisperLanguage(code: 'de', nativeName: 'Deutsch', chineseName: '德语'),
    WhisperLanguage(code: 'es', nativeName: 'Español', chineseName: '西班牙语'),
    WhisperLanguage(code: 'it', nativeName: 'Italiano', chineseName: '意大利语'),
    WhisperLanguage(code: 'pt', nativeName: 'Português', chineseName: '葡萄牙语'),
    WhisperLanguage(code: 'ru', nativeName: 'Русский', chineseName: '俄语'),
    WhisperLanguage(code: 'ar', nativeName: 'العربية', chineseName: '阿拉伯语'),
    WhisperLanguage(code: 'hi', nativeName: 'हिन्दी', chineseName: '印地语'),
    WhisperLanguage(code: 'th', nativeName: 'ภาษาไทย', chineseName: '泰语'),
    WhisperLanguage(code: 'vi', nativeName: 'Tiếng Việt', chineseName: '越南语'),
    WhisperLanguage(code: 'id', nativeName: 'Bahasa Indonesia', chineseName: '印尼语'),
    WhisperLanguage(code: 'ms', nativeName: 'Bahasa Melayu', chineseName: '马来语'),
    WhisperLanguage(code: 'nl', nativeName: 'Nederlands', chineseName: '荷兰语'),
    WhisperLanguage(code: 'pl', nativeName: 'Polski', chineseName: '波兰语'),
    WhisperLanguage(code: 'tr', nativeName: 'Türkçe', chineseName: '土耳其语'),
    WhisperLanguage(code: 'sv', nativeName: 'Svenska', chineseName: '瑞典语'),
    WhisperLanguage(code: 'da', nativeName: 'Dansk', chineseName: '丹麦语'),
    WhisperLanguage(code: 'fi', nativeName: 'Suomi', chineseName: '芬兰语'),
    WhisperLanguage(code: 'uk', nativeName: 'Українська', chineseName: '乌克兰语'),
  ];

  static WhisperLanguage byCode(String code) {
    return all.firstWhere(
      (l) => l.code == code,
      orElse: () => auto,
    );
  }
}
