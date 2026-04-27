import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/whisper_language.dart';
import '../providers/app_provider.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Whisper 听写'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: const _HomeBody(),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    if (!provider.isPlatformSupported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '当前平台暂不支持本地 Whisper 推理。\n请在 Android、iOS 或 macOS 上使用。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Column(
      children: [
        _LanguageBar(),
        const Divider(height: 1),
        const Expanded(child: _TranscriptionArea()),
        const Divider(height: 1),
        _ControlBar(),
      ],
    );
  }
}

// ── Language selector bar ──────────────────────────────────────────────────

class _LanguageBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final selected = WhisperLanguage.byCode(provider.selectedLanguage);
    final recents = provider.recentLanguages
        .map((c) => WhisperLanguage.byCode(c))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Main language selector
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showLanguagePicker(context, provider),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        selected.displayName,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Recent language quick buttons
          ...recents.map((lang) => Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _RecentLangButton(
                  language: lang,
                  isSelected: lang.code == provider.selectedLanguage,
                  onTap: () => provider.selectLanguage(lang.code),
                ),
              )),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, AppProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _LanguagePickerSheet(provider: provider),
    );
  }
}

class _RecentLangButton extends StatelessWidget {
  final WhisperLanguage language;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecentLangButton({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          language.nativeName,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _LanguagePickerSheet extends StatefulWidget {
  final AppProvider provider;
  const _LanguagePickerSheet({required this.provider});

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final langs = WhisperLanguage.all
        .where((l) =>
            _query.isEmpty ||
            l.chineseName.contains(_query) ||
            l.nativeName.toLowerCase().contains(_query.toLowerCase()) ||
            l.code.contains(_query))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索语言…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: langs.length,
              itemBuilder: (_, i) {
                final lang = langs[i];
                final selected =
                    lang.code == widget.provider.selectedLanguage;
                return ListTile(
                  title: Text(lang.chineseName),
                  subtitle: lang.code != 'auto'
                      ? Text(lang.nativeName)
                      : null,
                  trailing: selected
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  selected: selected,
                  onTap: () {
                    widget.provider.selectLanguage(lang.code);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transcription display ──────────────────────────────────────────────────

class _TranscriptionArea extends StatefulWidget {
  const _TranscriptionArea();

  @override
  State<_TranscriptionArea> createState() => _TranscriptionAreaState();
}

class _TranscriptionAreaState extends State<_TranscriptionArea> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    _scrollToBottom();

    final text = provider.transcriptionText;
    final statusMsg = provider.statusMessage;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: text.isEmpty
              ? Center(
                  child: Text(
                    provider.isRecording
                        ? '正在听取语音…'
                        : '点击下方麦克风按钮开始听写',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 15,
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _scrollCtrl,
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    child: SelectableText(
                      text,
                      style: const TextStyle(fontSize: 16, height: 1.6),
                    ),
                  ),
                ),
        ),
        if (statusMsg.isNotEmpty)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  statusMsg,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Control bar ────────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Clear button
            IconButton(
              tooltip: '清空识别结果',
              icon: const Icon(Icons.delete_outline),
              onPressed: provider.transcriptionText.isEmpty
                  ? null
                  : () => _confirmClear(context, provider),
            ),
            const SizedBox(width: 32),
            // Main record button
            GestureDetector(
              onTap: () async {
                if (provider.isRecording) {
                  await provider.stopDictation();
                } else {
                  await provider.startDictation();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: provider.isRecording
                      ? cs.errorContainer
                      : cs.primaryContainer,
                  boxShadow: [
                    BoxShadow(
                      color: (provider.isRecording ? cs.error : cs.primary)
                          .withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  provider.isRecording
                      ? Icons.stop_rounded
                      : Icons.mic_rounded,
                  size: 36,
                  color: provider.isRecording
                      ? cs.onErrorContainer
                      : cs.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Model indicator
            IconButton(
              tooltip: '当前模型：${provider.selectedModelId}',
              icon: const Icon(Icons.memory_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空识别结果'),
        content: const Text('确定要清空所有识别结果吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              provider.clearTranscription();
              Navigator.pop(context);
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
