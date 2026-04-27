import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_whisper_model.dart';
import '../providers/app_provider.dart';
import '../services/model_manager.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: const _SettingsBody(),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        _DownloadSourceSection(),
        Divider(),
        _BuiltInModelsSection(),
        Divider(),
        _CustomDownloadSection(),
        _CustomModelsSection(),
        SizedBox(height: 32),
      ],
    );
  }
}

// ── Download source ────────────────────────────────────────────────────────

class _DownloadSourceSection extends StatelessWidget {
  const _DownloadSourceSection();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: '下载源'),
        RadioGroup<DownloadSource>(
          groupValue: provider.downloadSource,
          onChanged: (v) {
            if (v != null) provider.setDownloadSource(v);
          },
          child: Column(
            children: DownloadSource.values
                .map((src) => RadioListTile<DownloadSource>(
                      title: Text(src.label),
                      subtitle: Text(
                        src.baseUrl,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: src,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ── Built-in models ────────────────────────────────────────────────────────

class _BuiltInModelsSection extends StatelessWidget {
  const _BuiltInModelsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: '内置模型'),
        ...AppWhisperModel.builtIn
            .map((m) => _BuiltInModelTile(model: m)),
      ],
    );
  }
}

class _BuiltInModelTile extends StatefulWidget {
  final AppWhisperModel model;
  const _BuiltInModelTile({required this.model});

  @override
  State<_BuiltInModelTile> createState() => _BuiltInModelTileState();
}

class _BuiltInModelTileState extends State<_BuiltInModelTile> {
  bool? _isDownloaded;

  @override
  void initState() {
    super.initState();
    _checkDownloaded();
  }

  Future<void> _checkDownloaded() async {
    final provider = context.read<AppProvider>();
    final result = await provider.isBuiltInModelDownloaded(widget.model);
    if (mounted) setState(() => _isDownloaded = result);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final model = widget.model;
    final isSelected = provider.selectedModelId == model.id;
    final isDownloading = provider.isDownloading(model.id);
    final progress = provider.downloadProgressFor(model.id);

    // Re-check after a download finishes
    if (!isDownloading && _isDownloaded == false) {
      _checkDownloaded();
    }

    return ListTile(
      leading: _modelIcon(isSelected, _isDownloaded),
      title: Row(
        children: [
          Text(model.displayName),
          if (isSelected) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check_circle, size: 14, color: Colors.green),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(model.description),
          if (isDownloading && progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: progress),
            ),
        ],
      ),
      isThreeLine: isDownloading,
      trailing: _buildActions(context, provider, model, isDownloading),
      onTap: _isDownloaded == true
          ? () => provider.selectModel(model.id)
          : null,
    );
  }

  Widget _modelIcon(bool isSelected, bool? isDownloaded) {
    if (isDownloaded == null) {
      return const SizedBox(
          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (!isDownloaded) {
      return const Icon(Icons.cloud_download_outlined,
          color: Colors.grey);
    }
    return Icon(Icons.memory_outlined,
        color: isSelected ? Colors.green : null);
  }

  Widget _buildActions(
    BuildContext context,
    AppProvider provider,
    AppWhisperModel model,
    bool isDownloading,
  ) {
    if (isDownloading) {
      return IconButton(
        tooltip: '取消下载',
        icon: const Icon(Icons.cancel_outlined),
        onPressed: () => provider.cancelDownload(model.id),
      );
    }

    if (_isDownloaded == true) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '选择此模型',
            icon: const Icon(Icons.play_arrow_outlined),
            onPressed: () => provider.selectModel(model.id),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, provider, model),
          ),
        ],
      );
    }

    return IconButton(
      tooltip: '下载',
      icon: const Icon(Icons.download_outlined),
      onPressed: !provider.isPlatformSupported
          ? null
          : () async {
              await provider.downloadBuiltInModel(model);
              _checkDownloaded();
            },
    );
  }

  void _confirmDelete(
      BuildContext context, AppProvider provider, AppWhisperModel model) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('删除 ${model.displayName}'),
        content: Text(
            '确定要删除模型 "${model.displayName}"？删除后需要重新下载才能使用。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await provider.deleteBuiltInModel(model);
              _checkDownloaded();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ── Custom download ────────────────────────────────────────────────────────

class _CustomDownloadSection extends StatefulWidget {
  const _CustomDownloadSection();

  @override
  State<_CustomDownloadSection> createState() =>
      _CustomDownloadSectionState();
}

class _CustomDownloadSectionState extends State<_CustomDownloadSection> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDownloading = provider.isDownloading('custom');
    final progress = provider.downloadProgressFor('custom');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: '自定义模型下载'),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: '模型下载 URL',
              hintText: 'https://…/ggml-xxx.bin',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '模型名称（可选）',
              hintText: '例：My Custom Whisper',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (isDownloading && progress != null) ...[
            LinearProgressIndicator(value: progress),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '下载中… ${(progress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isDownloading)
                TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('取消'),
                  onPressed: () => provider.cancelDownload('custom'),
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('下载'),
                  onPressed: _urlCtrl.text.isEmpty
                      ? null
                      : () => _startDownload(context, provider),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload(
      BuildContext context, AppProvider provider) async {
    final url = _urlCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (url.isEmpty) return;

    await provider.downloadCustomModel(url: url, displayName: name);
    _urlCtrl.clear();
    _nameCtrl.clear();
  }
}

// ── Custom models list ─────────────────────────────────────────────────────

class _CustomModelsSection extends StatelessWidget {
  const _CustomModelsSection();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final models = provider.customModels;
    if (models.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        _SectionHeader(label: '已下载自定义模型'),
        ...models.map((cm) => ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: Text(cm.displayName),
              subtitle: Text('${cm.sizeMb} MB · ${cm.filePath}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => provider.deleteCustomModel(cm.id),
              ),
            )),
      ],
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
