part of '../main.dart';

// Modal dialogs: model settings, permission prompts, project settings,
// add-on manager, chat history, search, quick-open, command palette, git.

class _ModelDialog extends StatefulWidget {
  const _ModelDialog({
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    required this.selectedModel,
    required this.fallbackBaseUrls,
    required this.inputCostPerMillion,
    required this.outputCostPerMillion,
    required this.monthlyTokenBudget,
    required this.onCheckForUpdates,
    required this.onShowUpdateDiagnostics,
  });

  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final String selectedModel;
  final List<String> fallbackBaseUrls;
  final double inputCostPerMillion;
  final double outputCostPerMillion;
  final int monthlyTokenBudget;
  final Future<void> Function() onCheckForUpdates;
  final VoidCallback onShowUpdateDiagnostics;

  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  late final _baseController = TextEditingController(text: widget.baseUrl);
  late final _keyController = TextEditingController(text: widget.apiKey);
  final _newModelController = TextEditingController();
  late final _fallbackController = TextEditingController(
    text: widget.fallbackBaseUrls.join('\n'),
  );
  late final _inputCostController = TextEditingController(
    text: '${widget.inputCostPerMillion}',
  );
  late final _outputCostController = TextEditingController(
    text: '${widget.outputCostPerMillion}',
  );
  late final _budgetController = TextEditingController(
    text: '${widget.monthlyTokenBudget}',
  );
  late final List<String> _models = [...widget.models];
  late String _selectedModel = widget.selectedModel;
  late String _providerLabel = _presetForBaseUrl(widget.baseUrl).label;
  bool _fetchingModels = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    // Editing the Base URL by hand flips the provider dropdown back to Custom.
    _baseController.addListener(_syncProviderLabel);
  }

  @override
  void dispose() {
    _baseController.dispose();
    _keyController.dispose();
    _newModelController.dispose();
    _fallbackController.dispose();
    _inputCostController.dispose();
    _outputCostController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  void _syncProviderLabel() {
    final label = _presetForBaseUrl(_baseController.text).label;
    if (label != _providerLabel) setState(() => _providerLabel = label);
  }

  void _applyPreset(_ProviderPreset preset) {
    setState(() {
      _providerLabel = preset.label;
      if (preset.baseUrl.isNotEmpty) _baseController.text = preset.baseUrl;
      if (preset.models.isNotEmpty) {
        _models
          ..clear()
          ..addAll(preset.models);
        _selectedModel = preset.models.first;
      }
    });
  }

  Future<void> _showProviderPicker() async {
    final searchController = TextEditingController();
    var query = '';
    final selected = await showDialog<_ProviderPreset>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = _providerPresets.where((preset) {
            final needle = query.trim().toLowerCase();
            if (needle.isEmpty) return true;
            return preset.label.toLowerCase().contains(needle) ||
                preset.baseUrl.toLowerCase().contains(needle) ||
                preset.models.any(
                  (model) => model.toLowerCase().contains(needle),
                );
          }).toList();
          return Dialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: TextField(
                      key: const ValueKey('provider-search-field'),
                      controller: searchController,
                      autofocus: true,
                      onChanged: (value) => setDialogState(() => query = value),
                      decoration: const InputDecoration(
                        hintText: 'Cari provider, endpoint, atau model...',
                        prefixIcon: Icon(Icons.search, size: 20),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  SizedBox(
                    height: 390,
                    child: filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('Provider tidak ditemukan'),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final preset = filtered[index];
                              final selected = preset.label == _providerLabel;
                              final local = preset.baseUrl.startsWith(
                                'http://',
                              );
                              return ListTile(
                                dense: true,
                                selected: selected,
                                leading: Icon(
                                  local
                                      ? Icons.dns_outlined
                                      : Icons.cloud_outlined,
                                  size: 19,
                                ),
                                title: Text(
                                  preset.label,
                                  key: ValueKey(
                                    'provider-option-${preset.label}',
                                  ),
                                  style: TextStyle(
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                subtitle: preset.baseUrl.isEmpty
                                    ? const Text('Endpoint manual')
                                    : Text(
                                        preset.baseUrl,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: selected
                                    ? Icon(
                                        Icons.check_circle,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      )
                                    : null,
                                onTap: () => Navigator.pop(context, preset),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected != null && mounted) _applyPreset(selected);
  }

  void _addModel() {
    final model = _newModelController.text.trim();
    if (model.isEmpty || _models.contains(model)) return;
    setState(() {
      _models.add(model);
      _selectedModel = model;
      _newModelController.clear();
    });
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseController.text.trim();
    if (baseUrl.isEmpty || _fetchingModels) return;
    final apiKey = _keyController.text.trim();
    final uri = Uri.tryParse(baseUrl);
    final localProvider =
        uri != null &&
        {'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase());
    if (apiKey.isEmpty && !localProvider) {
      setState(() {
        _fetchError =
            'Isi API KEY terlebih dahulu. Provider internet biasanya menolak '
            'endpoint /models tanpa Authorization.';
      });
      return;
    }
    setState(() {
      _fetchingModels = true;
      _fetchError = null;
    });
    try {
      final fetched = await fetchProviderModels(baseUrl, apiKey);
      if (!mounted) return;
      setState(() {
        if (fetched.isEmpty) {
          _fetchError = 'Endpoint tidak mengembalikan daftar model.';
          return;
        }
        // Merge so manually-added models are not lost.
        final merged = {..._models, ...fetched}.toList()..sort();
        _models
          ..clear()
          ..addAll(merged);
        if (!_models.contains(_selectedModel)) _selectedModel = _models.first;
      });
    } catch (error) {
      if (mounted) setState(() => _fetchError = 'Gagal memuat model: $error');
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  void _removeModel(String model) {
    if (_models.length == 1) return;
    setState(() {
      _models.remove(model);
      if (_selectedModel == model) _selectedModel = _models.first;
    });
  }

  void _save() {
    final baseUrl = _baseController.text.trim();
    final parsedBase = Uri.tryParse(baseUrl);
    if (baseUrl.isEmpty || parsedBase == null || !parsedBase.isAbsolute) return;
    Navigator.pop(
      context,
      _ModelSettingsResult(
        baseUrl: baseUrl,
        apiKey: _keyController.text.trim(),
        models: _models,
        selectedModel: _selectedModel,
        fallbackBaseUrls: _fallbackController.text
            .split(RegExp(r'\r?\n'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
        inputCostPerMillion:
            double.tryParse(_inputCostController.text.trim()) ?? 0,
        outputCostPerMillion:
            double.tryParse(_outputCostController.text.trim()) ?? 0,
        monthlyTokenBudget: int.tryParse(_budgetController.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ConstrainedBox(
        key: const ValueKey('model-dialog-panel'),
        constraints: BoxConstraints(
          maxWidth: 640,
          // Keep the settings popup compact; the body remains scrollable.
          maxHeight: math.max(360, MediaQuery.sizeOf(context).height - 140),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.035),
                  colors.surface,
                ),
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.hub_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MODEL CONNECTION',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Configure provider access, models, and usage limits.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Tutup',
                    icon: const Icon(Icons.close, size: 19),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SilkySingleChildScrollView(
                key: const ValueKey('model-dialog-scroll'),
                silkyConfig: _silkyScrollConfig,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('PROVIDER', icon: Icons.cloud_outlined),
                    Material(
                      color: colors.surface,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('provider-preset'),
                        onTap: _showProviderPicker,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.hub_outlined,
                                size: 18,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _providerLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                'SEARCH',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.expand_more, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _providerPresets
                          .firstWhere(
                            (preset) => preset.label == _providerLabel,
                            orElse: () => _providerPresets.first,
                          )
                          .keyHint,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _FieldLabel('CONNECTION', icon: Icons.link_outlined),
                    const _InlineFieldLabel('BASE URL'),
                    TextField(
                      controller: _baseController,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _InlineFieldLabel('FALLBACK BASE URLS'),
                    TextField(
                      controller: _fallbackController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'One HTTPS or loopback URL per line',
                        helperText:
                            'Used in order after retryable provider failures.',
                      ),
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _InlineFieldLabel('API KEY'),
                    TextField(
                      key: const ValueKey('model-api-key-field'),
                      controller: _keyController,
                      obscureText: true,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Isi API key sebelum Fetch. Key hanya disimpan di memori '
                      'dan tidak ditulis ke disk.',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fetchAction = _fetchingModels
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              )
                            : TextButton.icon(
                                key: const ValueKey('fetch-models-button'),
                                onPressed: _fetchModels,
                                icon: const Icon(
                                  Icons.cloud_download_outlined,
                                  size: 15,
                                ),
                                label: const Text(
                                  'FETCH FROM PROVIDER',
                                  style: TextStyle(fontSize: 10),
                                ),
                              );
                        if (constraints.maxWidth < 490) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _FieldLabel(
                                'AVAILABLE MODELS',
                                icon: Icons.memory_outlined,
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: fetchAction,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            const _FieldLabel(
                              'AVAILABLE MODELS',
                              icon: Icons.memory_outlined,
                            ),
                            const Spacer(),
                            fetchAction,
                          ],
                        );
                      },
                    ),
                    if (_fetchError != null) ...[
                      Text(
                        _fetchError!,
                        style: TextStyle(fontSize: 11, color: colors.error),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          colors.primary.withValues(alpha: 0.018),
                          colors.surface,
                        ),
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Material(
                        type: MaterialType.transparency,
                        child: SilkyListView.separated(
                          silkyConfig: _silkyScrollConfig,
                          shrinkWrap: true,
                          itemCount: _models.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final model = _models[index];
                            final selected = model == _selectedModel;
                            return ListTile(
                              dense: true,
                              tileColor: selected
                                  ? colors.primary.withValues(alpha: 0.07)
                                  : null,
                              onTap: () =>
                                  setState(() => _selectedModel = model),
                              leading: Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 17,
                                color: selected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                              title: Text(
                                model,
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 12,
                                ),
                              ),
                              trailing: IconButton(
                                onPressed: _models.length == 1
                                    ? null
                                    : () => _removeModel(model),
                                tooltip: 'Hapus model',
                                icon: const Icon(Icons.close, size: 16),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final modelField = TextField(
                          controller: _newModelController,
                          onSubmitted: (_) => _addModel(),
                          decoration: const InputDecoration(
                            hintText: 'Model ID, contoh gpt-4.1',
                          ),
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 12,
                          ),
                        );
                        final addButton =
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _newModelController,
                              builder: (context, value, _) => FilledButton.icon(
                                onPressed: value.text.trim().isEmpty
                                    ? null
                                    : _addModel,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('ADD MODEL'),
                              ),
                            );
                        if (constraints.maxWidth < 470) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              modelField,
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: addButton,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: modelField),
                            const SizedBox(width: 10),
                            addButton,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const _FieldLabel(
                      'USAGE & COST ESTIMATION',
                      icon: Icons.data_usage_outlined,
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final inputCost = TextField(
                          controller: _inputCostController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Input USD / 1M',
                          ),
                        );
                        final outputCost = TextField(
                          controller: _outputCostController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Output USD / 1M',
                          ),
                        );
                        if (constraints.maxWidth < 470) {
                          return Column(
                            children: [
                              inputCost,
                              const SizedBox(height: 8),
                              outputCost,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: inputCost),
                            const SizedBox(width: 8),
                            Expanded(child: outputCost),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _budgetController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monthly token budget (0 = unlimited)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.025),
                  colors.surface,
                ),
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maintenance = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.onCheckForUpdates,
                        icon: const Icon(Icons.system_update_alt, size: 16),
                        label: const Text('CHECK FOR UPDATES'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onShowUpdateDiagnostics,
                        icon: const Icon(Icons.verified_outlined, size: 16),
                        label: const Text('UPDATE DIAGNOSTICS'),
                      ),
                    ],
                  );
                  final primaryActions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('CANCEL'),
                      ),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check, size: 17),
                        label: const Text('SAVE MODELS'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 570) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        maintenance,
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: primaryActions,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: maintenance),
                      const SizedBox(width: 12),
                      primaryActions,
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: 2, child: ColoredBox(color: colors.primary)),
          ],
        ),
      ),
    );
  }
}

class _ModelSettingsResult {
  const _ModelSettingsResult({
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    required this.selectedModel,
    required this.fallbackBaseUrls,
    required this.inputCostPerMillion,
    required this.outputCostPerMillion,
    required this.monthlyTokenBudget,
  });

  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final String selectedModel;
  final List<String> fallbackBaseUrls;
  final double inputCostPerMillion;
  final double outputCostPerMillion;
  final int monthlyTokenBudget;
}

class _YounzcodeAboutDialog extends StatelessWidget {
  const _YounzcodeAboutDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      child: ConstrainedBox(
        key: const ValueKey('younzcode-about-dialog'),
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
              child: Row(
                children: [
                  Image.asset(
                    'assets/younzcode_logo_new.png',
                    width: 46,
                    height: 46,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUNZCODE 2.0',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text('AI coding workspace untuk Windows'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build v$_appVersion',
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _AboutFeature(
                      icon: Icons.dashboard_outlined,
                      title: 'Dua tampilan workspace',
                      description:
                          'Classic menghadirkan chat AI yang sederhana dengan '
                          'Projects, Recents, dan Environment. Focus menyediakan '
                          'Explorer, editor, dan Agent dalam satu layar kerja.',
                    ),
                    const _AboutFeature(
                      icon: Icons.forum_outlined,
                      title: 'Respons agent bertahap',
                      description:
                          'Agent menjelaskan langkah sebelum menjalankan tool, '
                          'menampilkan hasilnya sebagai Progress, lalu melanjutkan '
                          'hingga rangkuman akhir.',
                    ),
                    const _AboutFeature(
                      icon: Icons.hub_outlined,
                      title: 'Provider AI fleksibel',
                      description:
                          'Gunakan OpenAI, Anthropic, Gemini, OpenRouter, Groq, '
                          'DeepSeek, Ollama, 9router, dan provider kompatibel lain '
                          'melalui pencarian provider.',
                    ),
                    const _AboutFeature(
                      icon: Icons.extension_outlined,
                      title: 'Plugins dan Subagent',
                      description:
                          'Tambahkan context, aktifkan add-on atau plugin, dan '
                          'jalankan multi-agent langsung dari area composer.',
                    ),
                    const _AboutFeature(
                      icon: Icons.fact_check_outlined,
                      title: 'Environment dan perubahan',
                      description:
                          'Pantau activity, plan, file yang berubah, status Git, '
                          'terminal, dan hasil verifikasi dari panel Environment.',
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('SELESAI'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutFeature extends StatelessWidget {
  const _AboutFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    height: 1.45,
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: colors.primary),
            const SizedBox(width: 7),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineFieldLabel extends StatelessWidget {
  const _InlineFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _StaticField extends StatelessWidget {
  const _StaticField({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Text(
        value,
        style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
      ),
    );
  }
}

class _PermissionDialog extends StatelessWidget {
  const _PermissionDialog({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final command = title.toLowerCase().contains('perintah');
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      color: cs.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          command ? 'ALLOW COMMAND?' : 'ALLOW FILE CHANGE?',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          command
                              ? 'The AI is requesting permission to run this command.'
                              : 'The AI is requesting permission to apply this change.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.04),
                border: Border.all(color: cs.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SilkySingleChildScrollView(
                silkyConfig: _silkyScrollConfig,
                child: SelectableText(
                  detail,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    height: 1.5,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.03),
                border: Border(top: BorderSide(color: cs.outline)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, PermissionDecision.reject),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      side: BorderSide(color: cs.outline),
                    ),
                    child: const Text('REJECT'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, PermissionDecision.allowAlways),
                    child: const Text('ALLOW ALWAYS'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, PermissionDecision.allowOnce),
                    child: const Text('ALLOW ONCE'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalPermissionDialog extends StatelessWidget {
  const _TerminalPermissionDialog({
    required this.detail,
    required this.workspace,
  });

  final String detail;
  final String workspace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final warning = light ? const Color(0xFFB7862A) : const Color(0xFFD7A544);
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: warning.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.shield, color: warning, size: 30),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ALLOW TERMINAL COMMAND?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The AI agent is requesting permission to execute this command in the project workspace.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.04),
                border: Border.all(color: cs.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.terminal, size: 19, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      detail,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 13,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Working Directory: $workspace',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pop(context, PermissionDecision.reject),
                      child: const Text('REJECT'),
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outline),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        PermissionDecision.allowAlways,
                      ),
                      child: const Text('ALLOW ALWAYS'),
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outline),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, PermissionDecision.allowOnce),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('ALLOW ONCE'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionErrorDialog extends StatelessWidget {
  const _ConnectionErrorDialog({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: cs.error, size: 34),
                  const SizedBox(width: 14),
                  Text(
                    'CONNECTION FAILED',
                    style: TextStyle(
                      color: cs.error,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Unable to establish a secure connection with the model provider.',
                style: TextStyle(height: 1.45),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  border: Border.all(color: cs.outline),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  detail,
                  maxLines: 5,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'TROUBLESHOOTING',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '1. Check your internet connection\n'
                '2. Verify the API key in Model Settings\n'
                '3. Ensure the Base URL and model are valid',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  height: 1.65,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('MODEL SETTINGS'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('CLOSE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectSettingsDialog extends StatefulWidget {
  const _ProjectSettingsDialog({
    required this.workspace,
    required this.allowWrite,
    required this.allowTerminal,
    required this.qualityGateEnabled,
    required this.updatePingEnabled,
    required this.approvalMode,
    required this.environment,
    required this.baseUrl,
    required this.model,
    required this.models,
    required this.apiKey,
    required this.timeoutMs,
    required this.dapTimeoutMs,
    required this.headers,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onSave,
  });

  final String workspace;
  final bool allowWrite;
  final bool allowTerminal;
  final bool qualityGateEnabled;
  final bool updatePingEnabled;
  final ApprovalMode approvalMode;
  final Map<String, String> environment;
  final String baseUrl;
  final String model;
  final List<String> models;
  final String apiKey;
  final int timeoutMs;
  final int dapTimeoutMs;
  final Map<String, String> headers;
  final AppearanceSettings appearance;
  final Future<void> Function(AppearanceSettings) onAppearanceChanged;
  final Future<void> Function(
    bool allowWrite,
    bool allowTerminal,
    bool qualityGateEnabled,
    bool updatePingEnabled,
    ApprovalMode approvalMode,
    Map<String, String> environment,
    _ApiConfiguration api,
  )
  onSave;

  @override
  State<_ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<_ProjectSettingsDialog> {
  late bool _allowWrite = widget.allowWrite;
  late bool _allowTerminal = widget.allowTerminal;
  late bool _qualityGateEnabled = widget.qualityGateEnabled;
  late bool _updatePingEnabled = widget.updatePingEnabled;
  late ApprovalMode _approvalMode = widget.approvalMode;
  late final _projectController = TextEditingController(
    text: widget.workspace.isEmpty ? 'No workspace selected' : widget.workspace,
  );
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();
  late final _apiBaseController = TextEditingController(text: widget.baseUrl);
  late final _apiModelController = TextEditingController(text: widget.model);
  late final _apiKeyController = TextEditingController(text: widget.apiKey);
  late final _timeoutController = TextEditingController(
    text: '${widget.timeoutMs}',
  );
  late final _dapTimeoutController = TextEditingController(
    text: '${widget.dapTimeoutMs}',
  );
  final _headerKeyController = TextEditingController();
  final _headerValueController = TextEditingController();
  late final _environment = {...widget.environment};
  late final _headers = {...widget.headers};
  late Color _accentColor = widget.appearance.accentColor;
  late double _fontScale = widget.appearance.fontScale;
  late UiDensity _uiDensity = widget.appearance.uiDensity;
  late UiPreset _preset = widget.appearance.preset;
  late String _favoriteModel = widget.appearance.favoriteModel;
  bool _testingConnection = false;
  String? _connectionStatus;
  int _tab = 0;

  @override
  void dispose() {
    _projectController.dispose();
    _keyController.dispose();
    _valueController.dispose();
    _apiBaseController.dispose();
    _apiModelController.dispose();
    _apiKeyController.dispose();
    _timeoutController.dispose();
    _dapTimeoutController.dispose();
    _headerKeyController.dispose();
    _headerValueController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.onAppearanceChanged(
      AppearanceSettings(
        accentColor: _accentColor,
        fontScale: _fontScale,
        uiDensity: _uiDensity,
        preset: _preset,
        favoriteModel: _favoriteModel,
      ),
    );
    await widget.onSave(
      _allowWrite,
      _allowTerminal,
      _qualityGateEnabled,
      _updatePingEnabled,
      _approvalMode,
      _environment,
      _apiConfiguration,
    );
    if (mounted) Navigator.pop(context);
  }

  _ApiConfiguration get _apiConfiguration => _ApiConfiguration(
    baseUrl: _apiBaseController.text.trim(),
    model: _apiModelController.text.trim(),
    apiKey: _apiKeyController.text.trim(),
    timeoutMs: int.tryParse(_timeoutController.text) ?? 120000,
    dapTimeoutMs: int.tryParse(_dapTimeoutController.text) ?? 30000,
    headers: _headers,
  );

  Future<void> _testConnection() async {
    if (_testingConnection) return;
    setState(() {
      _testingConnection = true;
      _connectionStatus = null;
    });
    final api = _apiConfiguration;
    try {
      final base = api.baseUrl.replaceAll(RegExp(r'/$'), '');
      final response = await http
          .get(
            Uri.parse('$base/models'),
            headers: {...api.headers, 'Authorization': 'Bearer ${api.apiKey}'},
          )
          .timeout(Duration(milliseconds: api.timeoutMs));
      if (mounted) {
        setState(
          () => _connectionStatus =
              response.statusCode >= 200 && response.statusCode < 300
              ? 'CONNECTION SUCCESSFUL'
              : 'FAILED: HTTP ${response.statusCode}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _connectionStatus = 'FAILED: $error');
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tabs = const [
      'GENERAL',
      'APPEARANCE',
      'ENV VARIABLES',
      'PERMISSIONS',
      'SECURITY',
      'API',
    ];
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor),
      ),
      child: SizedBox(
        width: 820,
        height: 680,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  const Text(
                    'PROJECT SETTINGS',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Configure environment, agent capabilities, and security.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Container(
              height: 46,
              color: colors.surface,
              child: Row(
                children: [
                  for (var index = 0; index < tabs.length; index++)
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: Ink(
                          decoration: BoxDecoration(
                            color: _tab == index
                                ? colors.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                            border: _tab == index
                                ? Border(
                                    top: BorderSide(
                                      color: colors.primary,
                                      width: 2,
                                    ),
                                  )
                                : null,
                          ),
                          child: InkWell(
                            onTap: () => setState(() => _tab = index),
                            highlightColor: colors.primary.withValues(
                              alpha: 0.10,
                            ),
                            splashColor: colors.primary.withValues(alpha: 0.16),
                            child: Center(
                              child: Text(
                                tabs[index],
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: _tab == index
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: _mediumMotion,
                switchInCurve: _motionCurve,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.02, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: SilkySingleChildScrollView(
                  key: ValueKey(_tab),
                  silkyConfig: _silkyScrollConfig,
                  padding: const EdgeInsets.all(24),
                  child: _content(),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('DISCARD CHANGES'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('SAVE SETTINGS'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return switch (_tab) {
      0 => _generalTab(),
      1 => _appearanceTab(),
      2 => _environmentTab(),
      3 => _permissionsTab(),
      4 => _securityTab(),
      _ => _apiTab(),
    };
  }

  Widget _appearanceTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('PERSONALIZATION', style: _SettingsHeading.style),
      const SizedBox(height: 8),
      Text(
        'Sesuaikan tampilan workspace agar nyaman dipakai setiap hari.',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('PRESET'),
                const SizedBox(height: 6),
                DropdownButtonFormField<UiPreset>(
                  key: const ValueKey('appearance-preset'),
                  initialValue: _preset,
                  items: const [
                    DropdownMenuItem(
                      value: UiPreset.minimal,
                      child: Text('MINIMAL'),
                    ),
                    DropdownMenuItem(
                      value: UiPreset.coding,
                      child: Text('CODING'),
                    ),
                    DropdownMenuItem(
                      value: UiPreset.focus,
                      child: Text('FOCUS'),
                    ),
                    DropdownMenuItem(
                      value: UiPreset.custom,
                      child: Text('CUSTOM'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) _selectPreset(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('FAVORITE MODEL'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: const ValueKey('appearance-favorite-model'),
                  initialValue: widget.models.contains(_favoriteModel)
                      ? _favoriteModel
                      : '',
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Tidak ada favorit'),
                    ),
                    for (final model in widget.models)
                      DropdownMenuItem(value: model, child: Text(model)),
                  ],
                  onChanged: (value) =>
                      setState(() => _favoriteModel = value ?? ''),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const _FieldLabel('UI DENSITY'),
      SegmentedButton<UiDensity>(
        segments: const [
          ButtonSegment(
            value: UiDensity.compact,
            icon: Icon(Icons.density_small),
            label: Text('COMPACT'),
          ),
          ButtonSegment(
            value: UiDensity.comfortable,
            icon: Icon(Icons.density_medium),
            label: Text('COMFORTABLE'),
          ),
        ],
        selected: {_uiDensity},
        onSelectionChanged: (values) => setState(() {
          _uiDensity = values.first;
          _preset = UiPreset.custom;
        }),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          const Expanded(child: _FieldLabel('FONT SIZE')),
          Text('${(_fontScale * 100).round()}%'),
        ],
      ),
      Slider(
        key: const ValueKey('appearance-font-scale'),
        value: _fontScale,
        min: 0.85,
        max: 1.2,
        divisions: 7,
        label: '${(_fontScale * 100).round()}%',
        onChanged: (value) => setState(() {
          _fontScale = value;
          _preset = UiPreset.custom;
        }),
      ),
      const SizedBox(height: 12),
      const _FieldLabel('ACCENT COLOR'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final color in const [
            Color(0xFF5B9DFF),
            Color(0xFF7C6CF2),
            Color(0xFF2F9E69),
            Color(0xFFD97706),
            Color(0xFFE0528D),
          ])
            ChoiceChip(
              key: ValueKey('appearance-accent-${color.toARGB32()}'),
              selected: _accentColor.toARGB32() == color.toARGB32(),
              onSelected: (_) => setState(() {
                _accentColor = color;
                _preset = UiPreset.custom;
              }),
              avatar: CircleAvatar(backgroundColor: color, radius: 8),
              label: Text(
                '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
              ),
            ),
        ],
      ),
    ],
  );

  void _selectPreset(UiPreset preset) {
    setState(() {
      _preset = preset;
      switch (preset) {
        case UiPreset.minimal:
          _accentColor = const Color(0xFF5B9DFF);
          _fontScale = 0.95;
          _uiDensity = UiDensity.compact;
        case UiPreset.coding:
          _accentColor = const Color(0xFF2F9E69);
          _fontScale = 1;
          _uiDensity = UiDensity.comfortable;
        case UiPreset.focus:
          _accentColor = const Color(0xFF7C6CF2);
          _fontScale = 0.98;
          _uiDensity = UiDensity.compact;
        case UiPreset.custom:
          break;
      }
    });
  }

  Widget _generalTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('GENERAL', style: _SettingsHeading.style),
      const SizedBox(height: 16),
      const _FieldLabel('PROJECT NAME'),
      const _StaticField(value: 'YOUNZCODE WORKSPACE'),
      const SizedBox(height: 18),
      const _FieldLabel('ROOT DIRECTORY'),
      TextField(
        controller: _projectController,
        readOnly: true,
        style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
      ),
      const SizedBox(height: 18),
      const _FieldLabel('DEFAULT SHELL'),
      const _StaticField(value: 'PowerShell (Windows)'),
      const SizedBox(height: 26),
      Text(
        'Project identity and shell defaults stay separate from appearance settings.',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _environmentTab() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ENVIRONMENT VARIABLES', style: _SettingsHeading.style),
        const SizedBox(height: 8),
        Text(
          'Variables are kept in memory for this session and are never written to disk.',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final entry in _environment.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '•' * entry.value.length.clamp(4, 18),
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _environment.remove(entry.key)),
                  icon: Icon(Icons.delete_outline, size: 17, color: cs.error),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _keyController,
                decoration: const InputDecoration(hintText: 'KEY'),
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _valueController,
                decoration: const InputDecoration(hintText: 'VALUE'),
                obscureText: true,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _keyController,
              builder: (context, value, _) => FilledButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () {
                        setState(() {
                          _environment[value.text.trim()] =
                              _valueController.text;
                          _keyController.clear();
                          _valueController.clear();
                        });
                      },
                child: const Text('ADD'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _permissionsTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('AGENT CAPABILITIES', style: _SettingsHeading.style),
      const SizedBox(height: 16),
      _PermissionSetting(
        title: 'FILE MODIFICATION',
        description:
            'Allow the agent to create and modify files in the workspace.',
        value: _allowWrite,
        onChanged: (value) => setState(() => _allowWrite = value),
      ),
      _PermissionSetting(
        title: 'TERMINAL COMMAND EXECUTION',
        description:
            'Allow the agent to run PowerShell commands in the workspace.',
        value: _allowTerminal,
        onChanged: (value) => setState(() => _allowTerminal = value),
      ),
      _PermissionSetting(
        title: 'AUTOMATIC QUALITY GATE',
        description:
            'Run language checks and relevant tests after accepted agent changes.',
        value: _qualityGateEnabled,
        onChanged: (value) => setState(() => _qualityGateEnabled = value),
      ),
      _PermissionSetting(
        title: 'UPDATE TELEMETRY',
        description:
            'Report the installed version to the update-ping endpoint so '
            'release engineers can measure fleet adoption (no personal data).',
        value: _updatePingEnabled,
        onChanged: (value) => setState(() => _updatePingEnabled = value),
      ),
      const _PermissionSetting(
        title: 'NETWORK ACCESS',
        description:
            'Model requests use the configured provider. Approved terminal commands use normal system access.',
        value: true,
        locked: true,
      ),
      const SizedBox(height: 22),
      const Text(
        'HOW SHOULD AGENT ACTIONS BE APPROVED?',
        style: _SettingsHeading.style,
      ),
      const SizedBox(height: 12),
      _ApprovalModeSetting(
        value: _approvalMode,
        onChanged: (value) => setState(() => _approvalMode = value),
      ),
    ],
  );

  Widget _securityTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('SECURITY & INFRASTRUCTURE', style: _SettingsHeading.style),
      const SizedBox(height: 16),
      const _SecurityCard(
        icon: Icons.shield,
        title: 'DATA PROTECTION',
        body:
            'Built-in file tools stay in the workspace and block .env and SSH credentials.',
      ),
      const SizedBox(height: 10),
      const _SecurityCard(
        icon: Icons.list_alt,
        title: 'AUDIT LOGGING',
        body:
            'Tool activity is shown in the activity panel for the current session.',
      ),
      const SizedBox(height: 10),
      _SecurityCard(
        icon: Icons.lock,
        title: 'SESSION SECURITY',
        body: _approvalMode == ApprovalMode.askForApproval
            ? 'API keys stay in memory. Permission prompts apply once per action.'
            : 'API keys stay in memory. Action approval follows the selected permission mode.',
      ),
      const SizedBox(height: 10),
      const _SecurityCard(
        icon: Icons.terminal,
        title: 'TERMINAL ACCESS',
        body:
            'Approved PowerShell commands run with your normal Windows account permissions and are not sandboxed.',
      ),
    ],
  );

  Widget _apiTab() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('API CONFIGURATION', style: _SettingsHeading.style),
        const SizedBox(height: 8),
        Text(
          'Configure the OpenAI-compatible connection used by the agent.',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Container(
          key: const ValueKey('provider-status-card'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.07),
            border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                _connectionStatus?.startsWith('CONNECTION') == true
                    ? Icons.check_circle_outline
                    : _apiKeyController.text.trim().isEmpty
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_queue_outlined,
                color: _connectionStatus?.startsWith('CONNECTION') == true
                    ? const Color(0xFF2F9E69)
                    : cs.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _connectionStatus?.startsWith('CONNECTION') == true
                          ? 'PROVIDER CONNECTED'
                          : _apiKeyController.text.trim().isEmpty
                          ? 'PROVIDER NOT CONFIGURED'
                          : 'PROVIDER READY TO TEST',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_apiBaseController.text.trim()} · '
                      '${_apiModelController.text.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel('BASE URL'),
        TextField(
          controller: _apiBaseController,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        ),
        const SizedBox(height: 12),
        const _FieldLabel('MODEL'),
        TextField(
          controller: _apiModelController,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        ),
        const SizedBox(height: 12),
        const _FieldLabel('TOKEN VALUE'),
        TextField(
          controller: _apiKeyController,
          onChanged: (_) => setState(() {}),
          obscureText: true,
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        ),
        const SizedBox(height: 12),
        const _FieldLabel('MODEL & COMMAND INACTIVITY TIMEOUT (MS)'),
        TextField(
          controller: _timeoutController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            helperText:
                'Default 120000 (2 minutes). Increase for slow models, builds, '
                'or tests. Each task also stops after 10 minutes total.',
          ),
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        ),
        const SizedBox(height: 12),
        const _FieldLabel('DEBUG ADAPTER HANDSHAKE TIMEOUT (MS)'),
        TextField(
          key: const ValueKey('dap-timeout-field'),
          controller: _dapTimeoutController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            helperText:
                'Default 30000 (30 seconds). Increase on slow machines so the '
                'Python and Node.js debug adapters can finish their startup '
                'handshake without the session being torn down.',
          ),
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        ),
        const SizedBox(height: 18),
        const Text('GLOBAL HEADERS', style: _SettingsHeading.style),
        const SizedBox(height: 8),
        for (final entry in _headers.entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              entry.key,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: cs.primary,
              ),
            ),
            subtitle: Text(
              entry.value,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
            ),
            trailing: IconButton(
              onPressed: () => setState(() => _headers.remove(entry.key)),
              icon: Icon(Icons.delete_outline, color: cs.error),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _headerKeyController,
                decoration: const InputDecoration(hintText: 'HEADER KEY'),
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _headerValueController,
                decoration: const InputDecoration(hintText: 'VALUE'),
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _headerKeyController,
              builder: (context, value, _) => IconButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () {
                        setState(() {
                          _headers[value.text.trim()] =
                              _headerValueController.text;
                          _headerKeyController.clear();
                          _headerValueController.clear();
                        });
                      },
                icon: const Icon(Icons.add_circle),
              ),
            ),
          ],
        ),
        if (_connectionStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _connectionStatus!,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10,
                color: _connectionStatus!.startsWith('CONNECTION')
                    ? (Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFF2F9E69)
                          : const Color(0xFF57C08A))
                    : cs.error,
              ),
            ),
          ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _testingConnection ? null : _testConnection,
          icon: const Icon(Icons.network_check),
          label: Text(_testingConnection ? 'TESTING...' : 'TEST CONNECTION'),
        ),
        const SizedBox(height: 24),
        const Text('AVAILABLE TOOLS', style: _SettingsHeading.style),
        const SizedBox(height: 12),
        if (_allowWrite)
          const _ApiTool(
            name: 'list_files',
            method: 'TOOL',
            description: 'List files matching a workspace glob.',
          ),
        if (_allowWrite)
          const _ApiTool(
            name: 'read_file',
            method: 'TOOL',
            description: 'Read a text file inside the workspace.',
          ),
        if (_allowTerminal)
          const _ApiTool(
            name: 'search_text',
            method: 'TOOL',
            description: 'Search a regex using ripgrep.',
          ),
        const _ApiTool(
          name: 'write_file',
          method: 'TOOL',
          description: 'Create or overwrite a file after permission.',
        ),
        const _ApiTool(
          name: 'replace_text',
          method: 'TOOL',
          description: 'Replace one unique text occurrence after permission.',
        ),
        const _ApiTool(
          name: 'run_command',
          method: 'TOOL',
          description: 'Run PowerShell after permission.',
        ),
      ],
    );
  }
}

class _SettingsHeading {
  static const style = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.6,
  );
}

class _ApiConfiguration {
  const _ApiConfiguration({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.timeoutMs,
    required this.dapTimeoutMs,
    required this.headers,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final int timeoutMs;
  final int dapTimeoutMs;
  final Map<String, String> headers;
}

class _PermissionSetting extends StatelessWidget {
  const _PermissionSetting({
    required this.title,
    required this.description,
    required this.value,
    this.onChanged,
    this.locked = false,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(16),
      color: colors.surface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: locked ? null : onChanged),
        ],
      ),
    );
  }
}

class _ApprovalModeSetting extends StatelessWidget {
  const _ApprovalModeSetting({required this.value, required this.onChanged});

  final ApprovalMode value;
  final ValueChanged<ApprovalMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const options = [
      (
        ApprovalMode.askForApproval,
        'ASK FOR APPROVAL',
        'Always ask before file changes, terminal commands, and external tools.',
      ),
      (
        ApprovalMode.approveForMe,
        'APPROVE FOR ME',
        'Auto-approve workspace edits and safe commands. Ask for potentially unsafe or external actions.',
      ),
      (
        ApprovalMode.fullAccess,
        'FULL ACCESS',
        'Unrestricted access to the internet and any file on your computer.',
      ),
    ];
    return RadioGroup<ApprovalMode>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: Column(
        children: [
          for (final option in options)
            Material(
              color: value == option.$1
                  ? colors.primary.withValues(alpha: 0.12)
                  : colors.surface,
              child: InkWell(
                onTap: () => onChanged(option.$1),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: value == option.$1
                          ? colors.primary
                          : theme.dividerColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Radio<ApprovalMode>(value: option.$1),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.$2,
                              style: const TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              option.$3,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (value == option.$1)
                        Icon(Icons.check, color: colors.primary),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiTool extends StatelessWidget {
  const _ApiTool({
    required this.name,
    required this.method,
    required this.description,
  });

  final String name;
  final String method;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.primary, width: 2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              method,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 9,
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            name,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              color: colors.secondary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              description,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddonManagerDialog extends StatefulWidget {
  const _AddonManagerDialog({
    required this.addons,
    required this.onImportFile,
    required this.onImportFolder,
    required this.onToggle,
    required this.onRemove,
    required this.onCheckMcp,
    required this.toolPermissionPolicies,
    required this.onToolPermissionChanged,
  });

  final List<Addon> addons;
  final Future<void> Function() onImportFile;
  final Future<void> Function() onImportFolder;
  final Future<void> Function(Addon addon, bool enabled) onToggle;
  final Future<void> Function(Addon addon) onRemove;
  final Future<List<McpHealth>> Function(Addon addon) onCheckMcp;
  final Map<String, ToolPermissionPolicy> toolPermissionPolicies;
  final Future<void> Function(String pattern, ToolPermissionPolicy policy)
  onToolPermissionChanged;

  @override
  State<_AddonManagerDialog> createState() => _AddonManagerDialogState();
}

class _AddonManagerDialogState extends State<_AddonManagerDialog> {
  late final List<Addon> _addons = [...widget.addons];
  final _checkingMcp = <String>{};

  Future<void> _showMcpHealth(Addon addon) async {
    setState(() => _checkingMcp.add(addon.id));
    try {
      final health = await widget.onCheckMcp(addon);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _McpHealthDialog(
          health: health,
          policies: widget.toolPermissionPolicies,
          onPermissionChanged: widget.onToolPermissionChanged,
        ),
      );
    } finally {
      if (mounted) setState(() => _checkingMcp.remove(addon.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final warning = light ? const Color(0xFFB7862A) : const Color(0xFFD7A544);
    return Dialog(
      backgroundColor: cs.surface,
      child: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.extension_outlined, color: cs.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'ADD-ON MANAGER',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onImportFolder,
                    icon: const Icon(Icons.folder_copy_outlined, size: 16),
                    label: const Text('IMPORT FOLDER'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.onImportFile,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('IMPORT FILE'),
                  ),
                  IconButton(
                    key: const ValueKey('close-addon-manager'),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close Add-on Manager',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Text(
                'Supported: YOUNZCODE plugins, OpenCode/Claude SKILL.md, MCP JSON, and VSIX. Imported code is never executed during installation.',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: _addons.isEmpty
                  ? Center(
                      child: Text(
                        'No add-ons installed',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : SilkyListView.separated(
                      silkyConfig: _silkyScrollConfig,
                      padding: const EdgeInsets.all(14),
                      itemCount: _addons.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final addon = _addons[index];
                        return Container(
                          key: ValueKey('addon-${addon.id}'),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.04),
                            border: Border.all(color: cs.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(_addonIcon(addon.kind), color: cs.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      addon.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      addon.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _addonStatus(addon),
                                      style: TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 9,
                                        color: warning,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (addon.kind == AddonKind.mcpServer)
                                IconButton(
                                  tooltip: 'MCP health and permissions',
                                  onPressed: _checkingMcp.contains(addon.id)
                                      ? null
                                      : () => _showMcpHealth(addon),
                                  icon: _checkingMcp.contains(addon.id)
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.monitor_heart_outlined,
                                          size: 18,
                                        ),
                                ),
                              Switch(
                                value: addon.enabled,
                                onChanged: (value) async {
                                  await widget.onToggle(addon, value);
                                  if (!mounted) return;
                                  // Re-find by id: the captured index may be
                                  // stale after the await if the list changed.
                                  final i = _addons.indexWhere(
                                    (item) => item.id == addon.id,
                                  );
                                  if (i >= 0) {
                                    setState(
                                      () => _addons[i] = addon.copyWith(
                                        enabled: value,
                                      ),
                                    );
                                  }
                                },
                              ),
                              IconButton(
                                onPressed: () async {
                                  await widget.onRemove(addon);
                                  if (!mounted) return;
                                  setState(
                                    () => _addons.removeWhere(
                                      (item) => item.id == addon.id,
                                    ),
                                  );
                                },
                                tooltip: 'Remove add-on',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _addonIcon(AddonKind kind) => switch (kind) {
    AddonKind.skill => Icons.psychology_outlined,
    AddonKind.mcpServer => Icons.hub_outlined,
    AddonKind.nativePlugin => Icons.extension_outlined,
    AddonKind.vsix => Icons.inventory_2_outlined,
  };

  static String _addonStatus(Addon addon) => switch (addon.kind) {
    AddonKind.skill => 'ACTIVE AS AGENT INSTRUCTIONS',
    AddonKind.nativePlugin =>
      'MANIFEST/PROMPT ACTIVE · CODE EXECUTION DISABLED',
    AddonKind.vsix => 'STORED ONLY · VS CODE API RUNTIME NOT EMBEDDED',
    AddonKind.mcpServer =>
      (addon.metadata as McpMetadata).servers.any(
            (server) => server.transport == McpTransport.stdio,
          )
          ? 'MCP STDIO TOOLS ACTIVE'
          : 'MCP HTTP TOOLS ACTIVE',
  };
}

class _McpHealthDialog extends StatefulWidget {
  const _McpHealthDialog({
    required this.health,
    required this.policies,
    required this.onPermissionChanged,
  });

  final List<McpHealth> health;
  final Map<String, ToolPermissionPolicy> policies;
  final Future<void> Function(String pattern, ToolPermissionPolicy policy)
  onPermissionChanged;

  @override
  State<_McpHealthDialog> createState() => _McpHealthDialogState();
}

class _McpHealthDialogState extends State<_McpHealthDialog> {
  late final Map<String, ToolPermissionPolicy> _policies = {...widget.policies};

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      child: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('MCP HEALTH & PERMISSIONS'),
              subtitle: const Text(
                'Policies are stored per workspace and tool.',
              ),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SilkyListView(
                silkyConfig: _silkyScrollConfig,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final server in widget.health) ...[
                    Row(
                      children: [
                        Icon(
                          server.healthy
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 18,
                          color: server.healthy
                              ? const Color(0xFF2F9E69)
                              : colors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            server.serverName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          '${server.transport.name.toUpperCase()} · '
                          '${server.latency.inMilliseconds} ms · '
                          '${server.tools.length} tools',
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    if (server.error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          server.error,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    const SizedBox(height: 8),
                    for (final tool in server.tools)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.build_outlined, size: 16),
                        title: Text(
                          tool.name,
                          style: const TextStyle(fontFamily: 'Consolas'),
                        ),
                        subtitle: Text(
                          tool.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: DropdownButton<ToolPermissionPolicy>(
                          value:
                              _policies['mcp:${server.serverName}/${tool.name}'] ??
                              ToolPermissionPolicy.ask,
                          items: const [
                            DropdownMenuItem(
                              value: ToolPermissionPolicy.ask,
                              child: Text('ASK'),
                            ),
                            DropdownMenuItem(
                              value: ToolPermissionPolicy.allow,
                              child: Text('ALLOW'),
                            ),
                            DropdownMenuItem(
                              value: ToolPermissionPolicy.deny,
                              child: Text('DENY'),
                            ),
                          ],
                          onChanged: (policy) async {
                            if (policy == null) return;
                            final pattern =
                                'mcp:${server.serverName}/${tool.name}';
                            await widget.onPermissionChanged(pattern, policy);
                            if (mounted) {
                              setState(() => _policies[pattern] = policy);
                            }
                          },
                        ),
                      ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'CONNECTION LOG',
                        style: TextStyle(fontSize: 10),
                      ),
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: SelectableText(
                            server.logs.isEmpty
                                ? 'No log entries.'
                                : server.logs.join('\n'),
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspacePickerEntry {
  const _WorkspacePickerEntry({
    required this.path,
    required this.trusted,
    required this.sessionCount,
    required this.lastOpenedAt,
    required this.active,
    required this.pinned,
    this.branch = '',
    this.isRepository = false,
    this.dirty = false,
  });

  final String path;
  final bool trusted;
  final int sessionCount;
  final DateTime? lastOpenedAt;
  final bool active;
  final bool pinned;
  final String branch;
  final bool isRepository;
  final bool dirty;

  _WorkspacePickerEntry copyWith({bool? pinned}) => _WorkspacePickerEntry(
    path: path,
    trusted: trusted,
    sessionCount: sessionCount,
    lastOpenedAt: lastOpenedAt,
    active: active,
    pinned: pinned ?? this.pinned,
    branch: branch,
    isRepository: isRepository,
    dirty: dirty,
  );
}

class _WorkspacePickerDialog extends StatefulWidget {
  const _WorkspacePickerDialog({
    required this.entries,
    required this.onTogglePinned,
    required this.loadGitStatus,
  });

  static const browseValue = '__browse_workspace__';

  final List<_WorkspacePickerEntry> entries;
  final Future<void> Function(String workspace) onTogglePinned;
  final Future<GitStatus> Function(String workspace) loadGitStatus;

  @override
  State<_WorkspacePickerDialog> createState() => _WorkspacePickerDialogState();
}

class _WorkspacePickerDialogState extends State<_WorkspacePickerDialog> {
  String _query = '';
  late List<_WorkspacePickerEntry> _entries = List.of(widget.entries);
  final _gitStatuses = <String, GitStatus>{};

  @override
  void initState() {
    super.initState();
    for (final entry in _entries) {
      unawaited(_loadGitStatus(entry.path));
    }
  }

  @override
  void didUpdateWidget(covariant _WorkspacePickerDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      _entries = List.of(widget.entries);
      for (final entry in _entries) {
        if (!_gitStatuses.containsKey(entry.path)) {
          unawaited(_loadGitStatus(entry.path));
        }
      }
    }
  }

  Future<void> _loadGitStatus(String workspace) async {
    if (_gitStatuses.containsKey(workspace)) return;
    final status = await widget.loadGitStatus(workspace);
    if (!mounted) return;
    setState(() => _gitStatuses[workspace] = status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final query = _query.trim().toLowerCase();
    final entries = _entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.path.toLowerCase().contains(query) ||
          path.basename(entry.path).toLowerCase().contains(query);
    }).toList();
    return Dialog(
      key: const ValueKey('workspace-picker-dialog'),
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.folder_open_outlined,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PILIH WORKSPACE',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: .7,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Buka kembali proyek terakhir atau pilih folder baru.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              child: TextField(
                key: const ValueKey('workspace-picker-search'),
                autofocus: widget.entries.isNotEmpty,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Cari workspace terakhir...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Flexible(
              child: entries.isEmpty
                  ? _WorkspacePickerEmpty(hasHistory: widget.entries.isNotEmpty)
                  : SilkyListView.separated(
                      silkyConfig: _silkyScrollConfig,
                      padding: const EdgeInsets.all(14),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _WorkspacePickerTile(
                          entry: entry,
                          gitStatus: _gitStatuses[entry.path],
                          onTap: () => Navigator.pop(context, entry.path),
                          onTogglePinned: () async {
                            final index = _entries.indexOf(entry);
                            setState(() {
                              _entries[index] = entry.copyWith(
                                pinned: !entry.pinned,
                              );
                              _entries.sort((left, right) {
                                if (left.pinned != right.pinned) {
                                  return left.pinned ? -1 : 1;
                                }
                                if (left.active != right.active) {
                                  return left.active ? -1 : 1;
                                }
                                return left.path.compareTo(right.path);
                              });
                            });
                            await widget.onTogglePinned(entry.path);
                          },
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.entries.length} workspace tersimpan',
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('workspace-picker-browse'),
                    onPressed: () => Navigator.pop(
                      context,
                      _WorkspacePickerDialog.browseValue,
                    ),
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: const Text('PILIH FOLDER LAIN'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspacePickerEmpty extends StatelessWidget {
  const _WorkspacePickerEmpty({required this.hasHistory});

  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasHistory ? Icons.search_off : Icons.folder_copy_outlined,
              size: 38,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              hasHistory
                  ? 'Workspace tidak ditemukan.'
                  : 'Belum ada workspace terakhir.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Pilih folder proyek untuk mulai bekerja.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspacePickerTile extends StatelessWidget {
  const _WorkspacePickerTile({
    required this.entry,
    required this.gitStatus,
    required this.onTap,
    required this.onTogglePinned,
  });

  final _WorkspacePickerEntry entry;
  final GitStatus? gitStatus;
  final VoidCallback onTap;
  final VoidCallback onTogglePinned;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final folder = path.basename(entry.path);
    final status = gitStatus;
    final isRepository = status?.isRepository ?? entry.isRepository;
    final branch = status?.branch ?? entry.branch;
    final dirty = status?.dirty ?? entry.dirty;
    final gitLoading = status == null && !entry.isRepository;
    return Material(
      color: entry.active
          ? colors.primary.withValues(alpha: 0.1)
          : colors.onSurface.withValues(alpha: 0.025),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: entry.active
              ? colors.primary.withValues(alpha: 0.55)
              : colors.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        key: ValueKey('workspace-picker-${entry.path}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                entry.active ? Icons.folder_special : Icons.folder_outlined,
                color: colors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            folder.isEmpty ? entry.path : folder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (entry.active) ...[
                          const SizedBox(width: 8),
                          Text(
                            'AKTIF',
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        _WorkspacePickerMeta(
                          icon: entry.trusted
                              ? Icons.verified_user_outlined
                              : Icons.shield_outlined,
                          label: entry.trusted ? 'TRUSTED' : 'RESTRICTED',
                          color: entry.trusted
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        _WorkspacePickerMeta(
                          icon: Icons.chat_bubble_outline,
                          label: '${entry.sessionCount} CHAT',
                          color: colors.onSurfaceVariant,
                        ),
                        _WorkspacePickerMeta(
                          icon: gitLoading
                              ? Icons.sync_outlined
                              : Icons.account_tree_outlined,
                          label: gitLoading
                              ? 'GIT...'
                              : isRepository
                              ? (branch.isEmpty
                                    ? 'DETACHED'
                                    : branch.split('/').last)
                              : 'NO GIT',
                          color: isRepository
                              ? colors.onSurfaceVariant
                              : colors.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        if (isRepository)
                          _WorkspacePickerMeta(
                            icon: dirty
                                ? Icons.edit_note_outlined
                                : Icons.check_circle_outline,
                            label: dirty ? 'CHANGES' : 'CLEAN',
                            color: dirty ? colors.tertiary : colors.primary,
                          ),
                        if (entry.lastOpenedAt != null)
                          _WorkspacePickerMeta(
                            icon: Icons.schedule,
                            label: _formatDashboardDate(entry.lastOpenedAt!),
                            color: colors.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('workspace-picker-pin-${entry.path}'),
                tooltip: entry.pinned ? 'Unpin workspace' : 'Pin workspace',
                visualDensity: VisualDensity.compact,
                onPressed: onTogglePinned,
                icon: Icon(
                  entry.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                  color: entry.pinned
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspacePickerMeta extends StatelessWidget {
  const _WorkspacePickerMeta({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ],
  );
}

String _formatDashboardDate(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
  if (difference.inMinutes < 1) return 'BARU SAJA';
  if (difference.inHours < 1) return '${difference.inMinutes} MENIT';
  if (difference.inDays < 1) return '${difference.inHours} JAM';
  if (difference.inDays < 7) return '${difference.inDays} HARI';
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class _ChatHistoryDialog extends StatefulWidget {
  const _ChatHistoryDialog({
    required this.sessions,
    required this.activeId,
    required this.onOpen,
    required this.onDelete,
    required this.onUpdate,
  });

  final List<ChatSession> sessions;
  final String activeId;
  final ValueChanged<ChatSession> onOpen;
  final Future<void> Function(ChatSession) onDelete;
  final Future<void> Function(ChatSession) onUpdate;

  @override
  State<_ChatHistoryDialog> createState() => _ChatHistoryDialogState();
}

class _ChatHistoryDialogState extends State<_ChatHistoryDialog> {
  final _searchController = TextEditingController();
  late final List<ChatSession> _sessions = [...widget.sessions];
  String _workspaceFilter = '*';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatSession> get _visibleSessions {
    final query = _searchController.text.trim().toLowerCase();
    final visible = _sessions.where((session) {
      final matchesWorkspace =
          _workspaceFilter == '*' || session.workspace == _workspaceFilter;
      final matchesQuery =
          query.isEmpty ||
          session.title.toLowerCase().contains(query) ||
          session.workspace.toLowerCase().contains(query);
      return matchesWorkspace && matchesQuery;
    }).toList();
    visible.sort((left, right) {
      if (left.pinned != right.pinned) return left.pinned ? -1 : 1;
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return visible;
  }

  Future<void> _update(ChatSession session) async {
    setState(() {
      final index = _sessions.indexWhere((item) => item.id == session.id);
      if (index >= 0) _sessions[index] = session;
    });
    await widget.onUpdate(session);
  }

  Future<void> _rename(ChatSession session) async {
    final controller = TextEditingController(text: session.title);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RENAME CHAT'),
        content: TextField(
          key: const ValueKey('history-rename-field'),
          autofocus: true,
          controller: controller,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Judul chat'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );
    controller.dispose();
    final title = value?.trim() ?? '';
    if (title.isEmpty || !mounted) return;
    await _update(session.copyWith(customTitle: title));
  }

  Future<void> _delete(ChatSession session) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('HAPUS CHAT?'),
        content: Text(
          'Percakapan "${session.title}" akan dihapus dari history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            key: const ValueKey('history-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await widget.onDelete(session);
    if (mounted) {
      setState(() => _sessions.removeWhere((item) => item.id == session.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visibleSessions = _visibleSessions;
    final workspaces = _sessions.map((session) => session.workspace).toSet()
      ..remove('');
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history, size: 20),
          const SizedBox(width: 9),
          const Expanded(child: Text('CHAT HISTORY')),
          Text(
            '${visibleSessions.length}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 470,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('history-search'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Cari judul atau workspace...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                if (workspaces.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: DropdownButton<String>(
                      key: const ValueKey('history-workspace-filter'),
                      value: _workspaceFilter,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(
                          value: '*',
                          child: Text(
                            'ALL WORKSPACES',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        for (final workspace in workspaces)
                          DropdownMenuItem(
                            value: workspace,
                            child: Text(
                              path.basename(workspace),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _workspaceFilter = value ?? '*'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: visibleSessions.isEmpty
                  ? Center(
                      child: Text(
                        _sessions.isEmpty
                            ? 'Belum ada percakapan tersimpan.'
                            : 'Tidak ada chat yang cocok dengan filter.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : SilkyListView.separated(
                      silkyConfig: _silkyScrollConfig,
                      itemCount: visibleSessions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final session = visibleSessions[index];
                        final active = session.id == widget.activeId;
                        return ListTile(
                          key: ValueKey('chat-session-${session.id}'),
                          selected: active,
                          leading: Icon(
                            session.pinned
                                ? Icons.push_pin
                                : active
                                ? Icons.chat_bubble
                                : Icons.chat_bubble_outline,
                            color: session.pinned
                                ? cs.tertiary
                                : active
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          title: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${session.entries.length} pesan  ·  '
                            '${_formatChatDate(session.updatedAt)}  ·  '
                            '${path.basename(session.workspace)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          onTap: () => widget.onOpen(session),
                          trailing: PopupMenuButton<String>(
                            key: ValueKey('chat-menu-${session.id}'),
                            onSelected: (value) {
                              if (value == 'pin') {
                                _update(
                                  session.copyWith(pinned: !session.pinned),
                                );
                              } else if (value == 'rename') {
                                _rename(session);
                              } else if (value == 'delete') {
                                _delete(session);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'pin',
                                child: Text(
                                  session.pinned ? 'Unpin chat' : 'Pin chat',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('TUTUP'),
        ),
      ],
    );
  }

  static String _formatChatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _SearchView extends StatelessWidget {
  const _SearchView({
    super.key,
    required this.controller,
    required this.results,
    required this.busy,
    required this.onSearch,
    required this.onClose,
    required this.onOpenResult,
  });

  final TextEditingController controller;
  final List<String> results;
  final bool busy;
  final VoidCallback onSearch;
  final VoidCallback onClose;
  final void Function(String path, int line) onOpenResult;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          color: cs.onSurface.withValues(alpha: 0.04),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'SEARCH WORKSPACE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        'HYBRID INDEX',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                onSubmitted: (_) {
                  if (!busy && controller.text.trim().isNotEmpty) onSearch();
                },
                style: const TextStyle(fontFamily: 'Consolas'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search files, symbols, or code...',
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => IconButton(
                      onPressed: busy || value.text.trim().isEmpty
                          ? null
                          : onSearch,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : results.isEmpty
              ? Center(
                  child: Text(
                    controller.text.isEmpty
                        ? 'ENTER A QUERY TO SEARCH THE WORKSPACE'
                        : 'NO MATCHES FOUND',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : SilkyListView.builder(
                  silkyConfig: _silkyScrollConfig,
                  padding: const EdgeInsets.all(24),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final line = results[index];
                    final firstColon = line.indexOf(':');
                    final secondColon = firstColon < 0
                        ? -1
                        : line.indexOf(':', firstColon + 1);
                    final path = firstColon > 0
                        ? line.substring(0, firstColon)
                        : line;
                    final number = secondColon > firstColon
                        ? line.substring(firstColon + 1, secondColon)
                        : '';
                    final content = secondColon >= 0
                        ? line.substring(secondColon + 1)
                        : '';
                    return InkWell(
                      onTap: () =>
                          onOpenResult(path, int.tryParse(number) ?? 1),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.04),
                          border: Border(
                            left: BorderSide(color: cs.primary, width: 2),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 220,
                              child: Text(
                                path,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 10,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 42,
                              child: Text(
                                number,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                content,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _QuickFileDialog extends StatefulWidget {
  const _QuickFileDialog({required this.files});

  final List<String> files;

  @override
  State<_QuickFileDialog> createState() => _QuickFileDialogState();
}

class _QuickFileDialogState extends State<_QuickFileDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.toLowerCase();
    final matches = widget.files
        .where((file) => file.toLowerCase().contains(query))
        .take(100)
        .toList();
    return Dialog(
      child: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('quick-file-search'),
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search files by name...  Ctrl+P',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: SilkyListView.builder(
                silkyConfig: _silkyScrollConfig,
                itemCount: matches.length,
                itemBuilder: (context, index) => ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 17,
                  ),
                  title: Text(
                    matches[index],
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, matches[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickSwitcherItem {
  const _QuickSwitcherItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({required this.items});

  static const commands = <_QuickSwitcherItem>[
    _QuickSwitcherItem(
      id: 'file',
      title: 'Open File',
      subtitle: 'Cari dan buka file workspace',
      category: 'COMMAND',
      icon: Icons.file_open_outlined,
    ),
    _QuickSwitcherItem(
      id: 'chat',
      title: 'New Chat',
      subtitle: 'Mulai percakapan baru',
      category: 'COMMAND',
      icon: Icons.add_comment_outlined,
    ),
    _QuickSwitcherItem(
      id: 'search',
      title: 'Search Workspace',
      subtitle: 'Cari teks atau simbol di workspace',
      category: 'COMMAND',
      icon: Icons.manage_search,
    ),
    _QuickSwitcherItem(
      id: 'images',
      title: 'Image Generation',
      subtitle: 'Buka Image Studio',
      category: 'COMMAND',
      icon: Icons.image_outlined,
    ),
    _QuickSwitcherItem(
      id: 'browser',
      title: 'Agent Browser',
      subtitle: 'Buka browser agent',
      category: 'COMMAND',
      icon: Icons.travel_explore,
    ),
    _QuickSwitcherItem(
      id: 'terminal',
      title: 'Toggle Terminal',
      subtitle: 'Tampilkan atau sembunyikan terminal',
      category: 'COMMAND',
      icon: Icons.terminal,
    ),
    _QuickSwitcherItem(
      id: 'settings',
      title: 'Project Settings',
      subtitle: 'Appearance, API, Git, dan quality gate',
      category: 'SETTINGS',
      icon: Icons.tune,
    ),
    _QuickSwitcherItem(
      id: 'model',
      title: 'Switch Model',
      subtitle: 'Provider dan model AI',
      category: 'SETTINGS',
      icon: Icons.psychology_outlined,
    ),
    _QuickSwitcherItem(
      id: 'plan',
      title: 'Toggle Plan Mode',
      subtitle: 'Rencanakan sebelum mengubah workspace',
      category: 'COMMAND',
      icon: Icons.account_tree_outlined,
    ),
    _QuickSwitcherItem(
      id: 'retry',
      title: 'Prepare Retry Prompt',
      subtitle: 'Siapkan ulang prompt terakhir',
      category: 'COMMAND',
      icon: Icons.replay,
    ),
    _QuickSwitcherItem(
      id: 'continue',
      title: 'Prepare Checkpoint Continue',
      subtitle: 'Lanjutkan dari checkpoint terakhir',
      category: 'COMMAND',
      icon: Icons.play_arrow_outlined,
    ),
  ];

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();

  final List<_QuickSwitcherItem> items;
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final matches = widget.items
        .where(
          (item) =>
              query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              item.subtitle.toLowerCase().contains(query) ||
              item.category.toLowerCase().contains(query),
        )
        .take(100)
        .toList();
    return Dialog(
      child: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.keyboard_command_key),
                title: Text('COMMAND PALETTE'),
                subtitle: Text(
                  'Quick switcher · commands, files, chats, workspaces, settings',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  key: const ValueKey('command-palette-search'),
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Cari command, file, chat, workspace...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: matches.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(28),
                        child: Text('Tidak ada perintah yang cocok.'),
                      )
                    : SilkyListView.builder(
                        silkyConfig: _silkyScrollConfig,
                        shrinkWrap: true,
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final item = matches[index];
                          return ListTile(
                            leading: Icon(item.icon, size: 18),
                            title: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.category} · ${item.subtitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 12,
                            ),
                            onTap: () => Navigator.pop(context, item.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptTemplate {
  const _PromptTemplate({
    required this.title,
    required this.description,
    required this.prompt,
    required this.icon,
  });

  final String title;
  final String description;
  final String prompt;
  final IconData icon;
}

class _PromptTemplatesDialog extends StatelessWidget {
  const _PromptTemplatesDialog();

  static const templates = <_PromptTemplate>[
    _PromptTemplate(
      title: 'Generate Feature',
      description: 'Buat fitur baru dengan rencana, implementasi, dan test.',
      prompt:
          'Tambahkan fitur baru secara bertahap. Jelaskan rencana singkat, '
          'implementasikan dengan pola yang sudah ada, lalu tambahkan atau '
          'jalankan test yang relevan.',
      icon: Icons.auto_awesome,
    ),
    _PromptTemplate(
      title: 'Fix Bug',
      description: 'Cari akar masalah, perbaiki, dan verifikasi regresi.',
      prompt:
          'Investigasi bug ini dari akar masalahnya. Tunjukkan file yang '
          'terlibat, terapkan perbaikan minimal, lalu verifikasi dengan test '
          'yang relevan.',
      icon: Icons.bug_report_outlined,
    ),
    _PromptTemplate(
      title: 'Explain Codebase',
      description: 'Dapatkan ringkasan arsitektur dan alur data.',
      prompt:
          'Jelaskan struktur codebase ini dalam bahasa sederhana. Fokus pada '
          'entry point, alur data utama, dan file yang paling penting.',
      icon: Icons.account_tree_outlined,
    ),
    _PromptTemplate(
      title: 'Write Tests',
      description: 'Tambahkan test untuk perilaku yang belum terlindungi.',
      prompt:
          'Tinjau area yang relevan lalu tambahkan test untuk perilaku utama, '
          'edge case, dan regresi yang paling mungkin terjadi.',
      icon: Icons.fact_check_outlined,
    ),
    _PromptTemplate(
      title: 'Review Changes',
      description: 'Periksa diff untuk bug, regresi, dan kualitas.',
      prompt:
          'Review perubahan workspace saat ini. Prioritaskan bug, regresi, '
          'masalah keamanan, dan test yang masih kurang. Jangan mengubah file '
          'sebelum menjelaskan temuan.',
      icon: Icons.rate_review_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('prompt-templates-dialog'),
    title: const Text('PROMPT TEMPLATES'),
    content: SizedBox(
      width: 620,
      child: SilkyListView(
        silkyConfig: _silkyScrollConfig,
        shrinkWrap: true,
        children: [
          for (final template in templates)
            ListTile(
              key: ValueKey('prompt-template-${template.title}'),
              leading: Icon(template.icon),
              title: Text(template.title),
              subtitle: Text(template.description),
              trailing: const Icon(Icons.arrow_forward_ios, size: 13),
              onTap: () => Navigator.pop(context, template.prompt),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('CLOSE'),
      ),
    ],
  );
}

class _PromptHistoryDialog extends StatefulWidget {
  const _PromptHistoryDialog({required this.prompts});

  final List<String> prompts;

  @override
  State<_PromptHistoryDialog> createState() => _PromptHistoryDialogState();
}

class _PromptHistoryDialogState extends State<_PromptHistoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final prompts = widget.prompts
        .where((prompt) => prompt.toLowerCase().contains(query))
        .take(30)
        .toList();
    return AlertDialog(
      key: const ValueKey('prompt-history-dialog'),
      title: const Text('PROMPT HISTORY'),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('prompt-history-search'),
              controller: _controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari prompt sebelumnya...',
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: prompts.isEmpty
                  ? const Center(child: Text('Belum ada prompt yang cocok.'))
                  : SilkyListView.builder(
                      silkyConfig: _silkyScrollConfig,
                      itemCount: prompts.length,
                      itemBuilder: (context, index) => ListTile(
                        key: ValueKey('prompt-history-item-$index'),
                        leading: const Icon(Icons.history, size: 18),
                        title: Text(
                          prompts[index],
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, prompts[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}

class _GitDialog extends StatefulWidget {
  const _GitDialog({
    required this.service,
    required this.workspace,
    required this.onChanged,
    required this.onOpenFile,
    required this.onNotice,
  });

  final GitService service;
  final String workspace;
  final Future<void> Function() onChanged;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onNotice;

  @override
  State<_GitDialog> createState() => _GitDialogState();
}

class _GitDialogState extends State<_GitDialog> {
  final _branchController = TextEditingController();
  final _commitController = TextEditingController();
  final _changesFilterController = TextEditingController();
  GitStatus _status = const GitStatus(isRepository: true);
  GitSyncStatus _sync = const GitSyncStatus();
  List<String> _branches = const [];
  List<GitWorktree> _worktrees = const [];
  String _diff = '';
  String _history = '';
  String? _branchError;
  String? _operationError;
  String? _operationNotice;
  bool _loading = true;
  bool _mutating = false;
  String? _operationLabel;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _branchController.dispose();
    _commitController.dispose();
    _changesFilterController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait([
        widget.service.status(widget.workspace),
        widget.service.syncStatus(widget.workspace),
        widget.service.diff(widget.workspace),
        widget.service.history(widget.workspace),
        widget.service.branches(widget.workspace),
        widget.service.worktrees(widget.workspace),
      ]);
      if (!mounted) return;
      setState(() {
        _status = values[0] as GitStatus;
        _sync = values[1] as GitSyncStatus;
        _diff = values[2] as String;
        _history = values[3] as String;
        _branches = values[4] as List<String>;
        _worktrees = values[5] as List<GitWorktree>;
        _loading = false;
        _operationError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _operationError = '$error';
        });
      }
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool clearCommit = false,
    String? successMessage,
    String operationLabel = 'Memproses Git...',
  }) async {
    if (_mutating) return;
    setState(() {
      _mutating = true;
      _operationLabel = operationLabel;
      _operationError = null;
      _operationNotice = null;
    });
    try {
      await action();
      if (clearCommit) _commitController.clear();
      await widget.onChanged();
      await _refresh();
      if (mounted && successMessage != null) {
        setState(() => _operationNotice = successMessage);
        widget.onNotice(successMessage);
      }
    } catch (error) {
      if (mounted) setState(() => _operationError = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _mutating = false;
          _operationLabel = null;
        });
      }
    }
  }

  Future<void> _discard(GitFileStatus entry) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard file changes?'),
        content: Text(
          entry.untracked
              ? '${entry.path} akan dihapus permanen.'
              : '${entry.path} akan dikembalikan ke versi repository.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _run(() => widget.service.discard(widget.workspace, entry));
    }
  }

  Future<void> _push() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Push branch?'),
        content: Text(
          'Push "${_status.branch}" ke remote "origin"? Ini mengubah '
          'repository remote.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('PUSH'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _run(
        () => widget.service.pushCurrent(widget.workspace),
        operationLabel: 'Mendorong branch ke origin...',
        successMessage: 'Branch berhasil di-push ke origin.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final diffStats = _GitDiffStats.fromDiff(_diff);
    return Dialog(
      key: const ValueKey('git-dialog'),
      child: SizedBox(
        width: math.min(980.0, math.max(320.0, size.width - 32)),
        height: math.min(720.0, math.max(420.0, size.height - 32)),
        child: DefaultTabController(
          length: 4,
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(18, 10, 8, 4),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.account_tree_outlined,
                    color: colors.primary,
                  ),
                ),
                title: Text(_status.branch.isEmpty ? 'Git' : _status.branch),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status.dirty
                          ? 'Review, stage, dan commit perubahan workspace.'
                          : 'Workspace sinkron dengan commit terakhir.',
                    ),
                    const SizedBox(height: 5),
                    _GitStateBadge(status: _status),
                    const SizedBox(height: 5),
                    _GitSyncBadge(sync: _sync),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _mutating ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: 'Push current branch',
                      onPressed: _mutating ? null : _push,
                      icon: const Icon(Icons.cloud_upload_outlined),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Container(
                  key: const ValueKey('git-summary'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.42,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _GitSummaryMetric(
                          key: const ValueKey('git-stat-files'),
                          icon: Icons.description_outlined,
                          value: '${_status.entries.length}',
                          label: 'FILES',
                        ),
                      ),
                      Expanded(
                        child: _GitSummaryMetric(
                          icon: Icons.add_task_outlined,
                          value:
                              '${_status.entries.where((entry) => entry.staged).length}',
                          label: 'STAGED',
                          color: colors.primary,
                        ),
                      ),
                      Expanded(
                        child: _GitSummaryMetric(
                          icon: Icons.add,
                          value: '+${diffStats.additions}',
                          label: 'ADDED',
                          color: const Color(0xFF2F9E69),
                        ),
                      ),
                      Expanded(
                        child: _GitSummaryMetric(
                          icon: Icons.remove,
                          value: '-${diffStats.deletions}',
                          label: 'REMOVED',
                          color: colors.error,
                        ),
                      ),
                      Expanded(
                        child: _GitSummaryMetric(
                          icon: Icons.warning_amber_rounded,
                          value: '${_status.conflicts.length}',
                          label: 'CONFLICTS',
                          color: _status.conflicts.isEmpty
                              ? colors.onSurfaceVariant
                              : colors.error,
                        ),
                      ),
                      Expanded(
                        child: _GitSummaryMetric(
                          key: const ValueKey('git-stat-sync'),
                          icon: Icons.sync_alt,
                          value: _sync.hasUpstream
                              ? '↑${_sync.ahead} ↓${_sync.behind}'
                              : '—',
                          label: 'SYNC',
                          color: _sync.diverged
                              ? colors.error
                              : _sync.synced
                              ? const Color(0xFF2F9E69)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_operationError != null)
                Container(
                  width: double.infinity,
                  color: colors.error.withValues(alpha: 0.12),
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    _operationError!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.error),
                  ),
                ),
              if (_operationNotice != null)
                Container(
                  key: const ValueKey('git-operation-success'),
                  width: double.infinity,
                  color: const Color(0xFF2F9E69).withValues(alpha: 0.12),
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 17,
                        color: Color(0xFF2F9E69),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _operationNotice!,
                          style: const TextStyle(color: Color(0xFF2F9E69)),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_mutating)
                Column(
                  children: [
                    const LinearProgressIndicator(minHeight: 2),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 5, 18, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _operationLabel ?? 'Memproses Git...',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const TabBar(
                tabs: [
                  Tab(text: 'CHANGES'),
                  Tab(text: 'DIFF'),
                  Tab(text: 'HISTORY'),
                  Tab(text: 'BRANCHES'),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _changesTab(),
                          _GitDiffPreview(value: _diff),
                          _CodeOutput(
                            _history.isEmpty ? 'No commits.' : _history,
                          ),
                          _branchesTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _changesTab() {
    final colors = Theme.of(context).colorScheme;
    final query = _changesFilterController.text.trim().toLowerCase();
    final entries = _status.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.path.toLowerCase().contains(query) ||
          entry.displayStatus.toLowerCase().contains(query);
    }).toList();
    return SilkyListView(
      silkyConfig: _silkyScrollConfig,
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const ValueKey('git-changes-filter'),
          controller: _changesFilterController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Filter changed files...',
            prefixIcon: const Icon(Icons.filter_list),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Hapus filter',
                    onPressed: () {
                      _changesFilterController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (_status.entries.isEmpty)
          Container(
            key: const ValueKey('git-empty-state'),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F9E69).withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF2F9E69),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'WORKING TREE CLEAN',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tidak ada perubahan lokal yang perlu ditinjau.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        if (_status.entries.isNotEmpty && entries.isEmpty)
          Container(
            key: const ValueKey('git-filter-empty-state'),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              children: [
                Icon(Icons.search_off, size: 30),
                SizedBox(height: 10),
                Text(
                  'TIDAK ADA FILE YANG COCOK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: _GitFileStatusBadge(entry: entry),
                title: Text(
                  entry.path,
                  style: const TextStyle(fontFamily: 'Consolas'),
                ),
                subtitle: entry.conflicted
                    ? const Text(
                        'CONFLICT — edit file, lalu stage sebagai resolved',
                      )
                    : Text(entry.staged ? 'STAGED' : 'UNSTAGED'),
                onTap: () => widget.onOpenFile(entry.path),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      key: ValueKey('git-open-${entry.path}'),
                      tooltip: 'Buka di editor',
                      onPressed: () => widget.onOpenFile(entry.path),
                      icon: const Icon(Icons.open_in_new, size: 18),
                    ),
                    IconButton(
                      tooltip: entry.staged ? 'Unstage' : 'Stage',
                      onPressed: _mutating
                          ? null
                          : () => _run(
                              () => entry.staged
                                  ? widget.service.unstage(widget.workspace, [
                                      entry.path,
                                    ])
                                  : widget.service.stage(widget.workspace, [
                                      entry.path,
                                    ]),
                            ),
                      icon: Icon(
                        entry.staged
                            ? Icons.remove_circle_outline
                            : Icons.add_circle_outline,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Discard',
                      onPressed: _mutating ? null : () => _discard(entry),
                      icon: const Icon(Icons.undo),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (entries.isNotEmpty) ...[
          const Divider(),
          Row(
            children: [
              OutlinedButton(
                onPressed: _mutating
                    ? null
                    : () => _run(
                        () => widget.service.stage(
                          widget.workspace,
                          entries.map((entry) => entry.path),
                        ),
                      ),
                child: Text(query.isEmpty ? 'STAGE ALL' : 'STAGE FILTERED'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _mutating || !_status.hasStaged
                    ? null
                    : () => _run(
                        () => widget.service.unstage(
                          widget.workspace,
                          _status.entries
                              .where((entry) => entry.staged)
                              .map((entry) => entry.path),
                        ),
                      ),
                child: const Text('UNSTAGE ALL'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commitController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Commit message',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _mutating || !_status.hasStaged
                    ? null
                    : () => _run(
                        () => widget.service.commit(
                          widget.workspace,
                          _commitController.text,
                        ),
                        operationLabel: 'Membuat commit...',
                        clearCommit: true,
                        successMessage: 'Commit berhasil dibuat.',
                      ),
                icon: const Icon(Icons.commit),
                label: const Text('COMMIT'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _branchesTab() {
    return SilkyListView(
      silkyConfig: _silkyScrollConfig,
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _branchController,
          decoration: InputDecoration(
            labelText: 'Branch name',
            errorText: _branchError,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _mutating
                  ? null
                  : () => _run(
                      () => widget.service.createBranch(
                        widget.workspace,
                        _branchController.text.trim(),
                      ),
                    ),
              child: const Text('CREATE'),
            ),
            OutlinedButton(
              onPressed: _mutating
                  ? null
                  : () => _run(
                      () => widget.service.switchBranch(
                        widget.workspace,
                        _branchController.text.trim(),
                      ),
                    ),
              child: const Text('SWITCH'),
            ),
            OutlinedButton(
              onPressed: _mutating
                  ? null
                  : () => _run(
                      () => widget.service.mergeBranch(
                        widget.workspace,
                        _branchController.text.trim(),
                      ),
                    ),
              child: const Text('MERGE INTO CURRENT'),
            ),
            if (_status.conflicts.isNotEmpty)
              TextButton(
                onPressed: _mutating
                    ? null
                    : () => _run(
                        () => widget.service.abortMerge(widget.workspace),
                      ),
                child: const Text('ABORT MERGE'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'LOCAL BRANCHES',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
        for (final branch in _branches)
          ListTile(
            dense: true,
            leading: Icon(
              branch == _status.branch
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
            ),
            title: Text(branch, style: const TextStyle(fontFamily: 'Consolas')),
            onTap: branch == _status.branch
                ? null
                : () {
                    _branchController.text = branch;
                  },
          ),
        const Divider(),
        const Text(
          'WORKTREES',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
        for (final worktree in _worktrees)
          ListTile(
            dense: true,
            leading: const Icon(Icons.account_tree, size: 16),
            title: Text(
              worktree.branch.isEmpty ? worktree.head : worktree.branch,
              style: const TextStyle(fontFamily: 'Consolas'),
            ),
            subtitle: Text(
              worktree.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing:
                worktree.path == widget.workspace ||
                    !worktree.branch.startsWith('codex/agent-')
                ? null
                : IconButton(
                    tooltip: 'Remove agent worktree',
                    onPressed: _mutating
                        ? null
                        : () => _run(
                            () => widget.service.removeWorktree(
                              widget.workspace,
                              worktree,
                            ),
                          ),
                    icon: const Icon(Icons.delete_outline),
                  ),
          ),
      ],
    );
  }
}

class _GitDiffStats {
  const _GitDiffStats({required this.additions, required this.deletions});

  factory _GitDiffStats.fromDiff(String diff) {
    var additions = 0;
    var deletions = 0;
    for (final line in diff.split('\n')) {
      if (line.startsWith('+') && !line.startsWith('+++')) {
        additions++;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        deletions++;
      }
    }
    return _GitDiffStats(additions: additions, deletions: deletions);
  }

  final int additions;
  final int deletions;
}

class _GitSummaryMetric extends StatelessWidget {
  const _GitSummaryMetric({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final metricColor = color ?? colors.onSurface;
    return Semantics(
      label: '$label $value',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: metricColor),
              const SizedBox(width: 5),
              Text(
                value,
                style: TextStyle(
                  color: metricColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _GitStateBadge extends StatelessWidget {
  const _GitStateBadge({required this.status});

  final GitStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final conflict = status.conflicts.isNotEmpty;
    final dirty = status.dirty;
    final color = conflict
        ? colors.error
        : dirty
        ? colors.tertiary
        : const Color(0xFF2F9E69);
    final label = conflict
        ? '${status.conflicts.length} CONFLICT'
        : dirty
        ? '${status.entries.length} FILE BERUBAH'
        : 'WORKING TREE CLEAN';
    return Container(
      key: const ValueKey('git-state-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            conflict
                ? Icons.warning_amber_rounded
                : dirty
                ? Icons.edit_note_outlined
                : Icons.check_circle_outline,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GitSyncBadge extends StatelessWidget {
  const _GitSyncBadge({required this.sync});

  final GitSyncStatus sync;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = !sync.hasUpstream
        ? colors.onSurfaceVariant
        : sync.diverged
        ? colors.error
        : sync.synced
        ? const Color(0xFF2F9E69)
        : colors.tertiary;
    final label = !sync.hasUpstream
        ? 'NO UPSTREAM'
        : sync.synced
        ? 'SYNCED'
        : '↑${sync.ahead} AHEAD · ↓${sync.behind} BEHIND';
    return Container(
      key: const ValueKey('git-sync-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync_alt, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GitFileStatusBadge extends StatelessWidget {
  const _GitFileStatusBadge({required this.entry});

  final GitFileStatus entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (entry.displayStatus) {
      'A' => const Color(0xFF2F9E69),
      'D' => colors.error,
      'R' => colors.tertiary,
      '!' => colors.error,
      _ => colors.primary,
    };
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        entry.displayStatus,
        style: TextStyle(
          color: color,
          fontFamily: 'Consolas',
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GitDiffPreview extends StatefulWidget {
  const _GitDiffPreview({required this.value});

  final String value;

  @override
  State<_GitDiffPreview> createState() => _GitDiffPreviewState();
}

class _GitDiffPreviewState extends State<_GitDiffPreview> {
  bool _split = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (widget.value.trim().isEmpty) {
      return Center(
        child: Container(
          key: const ValueKey('git-diff-empty-state'),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.difference_outlined, size: 30),
              SizedBox(height: 10),
              Text(
                'NO DIFF TO PREVIEW',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
    }

    final lines = widget.value.split('\n');
    final stats = _GitDiffStats.fromDiff(widget.value);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
          child: Row(
            children: [
              const Icon(Icons.difference_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                _split ? 'SPLIT DIFF' : 'UNIFIED DIFF',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 12),
              Text(
                '+${stats.additions}',
                style: const TextStyle(
                  color: Color(0xFF2F9E69),
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${stats.deletions}',
                style: TextStyle(
                  color: colors.error,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('UNIFIED')),
                  ButtonSegment(value: true, label: Text('SPLIT')),
                ],
                selected: {_split},
                onSelectionChanged: (selection) =>
                    setState(() => _split = selection.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: 9, fontFamily: 'Consolas'),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 5),
              IconButton(
                key: const ValueKey('copy-git-diff'),
                tooltip: 'Copy diff',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.value));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Diff disalin.')),
                  );
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: _split
              ? _GitSplitDiffPreview(value: widget.value)
              : SilkyListView.builder(
                  key: const ValueKey('git-diff-preview'),
                  silkyConfig: _silkyScrollConfig,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: lines.length,
                  itemBuilder: (context, index) =>
                      _GitDiffLine(lineNumber: index + 1, value: lines[index]),
                ),
        ),
      ],
    );
  }
}

class _GitSplitDiffRow {
  const _GitSplitDiffRow({
    this.oldNumber,
    this.newNumber,
    this.oldText,
    this.newText,
    this.header = false,
  });

  final int? oldNumber;
  final int? newNumber;
  final String? oldText;
  final String? newText;
  final bool header;
}

class _GitSplitDiffPreview extends StatelessWidget {
  const _GitSplitDiffPreview({required this.value});

  final String value;

  List<_GitSplitDiffRow> _rows() {
    final lines = value.split('\n');
    final rows = <_GitSplitDiffRow>[];
    var oldLine = 0;
    var newLine = 0;
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      if (line.startsWith('@@')) {
        final match = RegExp(r'@@ -(\d+).* \+(\d+)').firstMatch(line);
        oldLine = int.tryParse(match?.group(1) ?? '') ?? oldLine;
        newLine = int.tryParse(match?.group(2) ?? '') ?? newLine;
        rows.add(_GitSplitDiffRow(oldText: line, newText: line, header: true));
        index++;
        continue;
      }
      if (line.startsWith('diff --git') ||
          line.startsWith('index ') ||
          line.startsWith('---') ||
          line.startsWith('+++')) {
        rows.add(_GitSplitDiffRow(oldText: line, newText: line, header: true));
        index++;
        continue;
      }
      if (line.startsWith(' ')) {
        final text = line.substring(1);
        rows.add(
          _GitSplitDiffRow(
            oldNumber: oldLine++,
            newNumber: newLine++,
            oldText: text,
            newText: text,
          ),
        );
        index++;
        continue;
      }
      final deletions = <String>[];
      while (index < lines.length &&
          lines[index].startsWith('-') &&
          !lines[index].startsWith('---')) {
        deletions.add(lines[index].substring(1));
        index++;
      }
      final additions = <String>[];
      while (index < lines.length &&
          lines[index].startsWith('+') &&
          !lines[index].startsWith('+++')) {
        additions.add(lines[index].substring(1));
        index++;
      }
      if (deletions.isEmpty && additions.isEmpty) {
        rows.add(_GitSplitDiffRow(oldText: line, newText: line, header: true));
        index++;
        continue;
      }
      final count = math.max(deletions.length, additions.length);
      for (var offset = 0; offset < count; offset++) {
        rows.add(
          _GitSplitDiffRow(
            oldNumber: offset < deletions.length ? oldLine++ : null,
            newNumber: offset < additions.length ? newLine++ : null,
            oldText: offset < deletions.length ? deletions[offset] : null,
            newText: offset < additions.length ? additions[offset] : null,
          ),
        );
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return SilkyListView.builder(
      key: const ValueKey('git-split-diff-preview'),
      silkyConfig: _silkyScrollConfig,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _GitSplitDiffCell(
                  number: row.oldNumber,
                  text: row.oldText,
                  removed: row.oldText != null && row.newText == null,
                  header: row.header,
                ),
              ),
              Container(width: 1, color: Theme.of(context).dividerColor),
              Expanded(
                child: _GitSplitDiffCell(
                  number: row.newNumber,
                  text: row.newText,
                  added: row.newText != null && row.oldText == null,
                  header: row.header,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GitSplitDiffCell extends StatelessWidget {
  const _GitSplitDiffCell({
    this.number,
    this.text,
    this.added = false,
    this.removed = false,
    this.header = false,
  });

  final int? number;
  final String? text;
  final bool added;
  final bool removed;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = added
        ? const Color(0xFF2F9E69)
        : removed
        ? colors.error
        : header
        ? colors.tertiary
        : colors.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minHeight: 25),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      color: (added || removed || header)
          ? color.withValues(alpha: header ? 0.08 : 0.11)
          : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              number?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 9,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: SelectableText(
              text ?? '',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10,
                height: 1.35,
                color: text == null ? colors.onSurfaceVariant : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GitDiffLine extends StatelessWidget {
  const _GitDiffLine({required this.lineNumber, required this.value});

  final int lineNumber;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isAddition = value.startsWith('+') && !value.startsWith('+++');
    final isDeletion = value.startsWith('-') && !value.startsWith('---');
    final isHunk = value.startsWith('@@');
    final isHeader =
        value.startsWith('diff --git') ||
        value.startsWith('index ') ||
        value.startsWith('---') ||
        value.startsWith('+++');
    final accent = isAddition
        ? const Color(0xFF2F9E69)
        : isDeletion
        ? colors.error
        : isHunk
        ? colors.tertiary
        : isHeader
        ? colors.primary
        : Colors.transparent;
    final background = accent == Colors.transparent
        ? Colors.transparent
        : accent.withValues(alpha: isHunk || isHeader ? 0.08 : 0.11);
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(
          left: BorderSide(
            color: accent,
            width: accent == Colors.transparent ? 0 : 3,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                fontFamily: 'Consolas',
                fontSize: 10,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value.isEmpty ? ' ' : value,
              style: TextStyle(
                color: isAddition || isDeletion || isHunk || isHeader
                    ? accent
                    : colors.onSurface,
                fontFamily: 'Consolas',
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeOutput extends StatelessWidget {
  const _CodeOutput(this.value);
  final String value;

  @override
  Widget build(BuildContext context) => SilkySingleChildScrollView(
    silkyConfig: _silkyScrollConfig,
    padding: const EdgeInsets.all(16),
    child: SelectableText(
      value,
      style: const TextStyle(fontFamily: 'Consolas', fontSize: 11, height: 1.4),
    ),
  );
}

class _ProviderUsageDialog extends StatelessWidget {
  const _ProviderUsageDialog({
    required this.records,
    required this.monthlyTokenBudget,
    required this.onClear,
  });

  final List<ProviderUsageRecord> records;
  final int monthlyTokenBudget;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final monthly = ProviderUsageStore.summarize(
      records,
      since: DateTime(now.year, now.month),
    );
    final allTime = ProviderUsageStore.summarize(records);
    final budgetProgress = monthlyTokenBudget <= 0
        ? 0.0
        : (monthly.totalTokens / monthlyTokenBudget).clamp(0.0, 1.0);
    return Dialog(
      child: SizedBox(
        width: 840,
        height: 650,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.query_stats),
              title: const Text('PROVIDER USAGE'),
              subtitle: const Text(
                'Cost is an estimate based on the rates in Model Settings.',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: records.isEmpty
                        ? null
                        : () async {
                            final approved = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Clear usage history?'),
                                content: const Text(
                                  'Semua riwayat token untuk workspace ini '
                                  'akan dihapus.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('CANCEL'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('CLEAR'),
                                  ),
                                ],
                              ),
                            );
                            if (approved == true) {
                              await onClear();
                              if (context.mounted) Navigator.pop(context);
                            }
                          },
                    child: const Text('CLEAR'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SilkyListView(
                silkyConfig: _silkyScrollConfig,
                padding: const EdgeInsets.all(18),
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _UsageMetric(
                        label: 'THIS MONTH',
                        value: '${monthly.totalTokens} tokens',
                      ),
                      _UsageMetric(
                        label: 'INPUT / OUTPUT',
                        value:
                            '${monthly.promptTokens} / '
                            '${monthly.completionTokens}',
                      ),
                      _UsageMetric(
                        label: 'ESTIMATED COST',
                        value:
                            '\$${monthly.estimatedCostUsd.toStringAsFixed(4)}',
                      ),
                      _UsageMetric(
                        label: 'ALL TIME',
                        value: '${allTime.totalTokens} tokens',
                      ),
                    ],
                  ),
                  if (monthlyTokenBudget > 0) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text(
                          'MONTHLY BUDGET',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${monthly.totalTokens} / $monthlyTokenBudget',
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: budgetProgress,
                      color: budgetProgress >= 0.8
                          ? colors.error
                          : colors.primary,
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'USAGE BY ROUTE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (final entry in monthly.byRoute.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.key),
                      trailing: Text(
                        '${entry.value}',
                        style: const TextStyle(fontFamily: 'Consolas'),
                      ),
                    ),
                  const Divider(height: 28),
                  const Text(
                    'RECENT REQUESTS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  for (final record in records.take(100))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${record.model} · '
                        '${Uri.tryParse(record.baseUrl)?.host ?? record.baseUrl}',
                      ),
                      subtitle: Text(
                        record.timestamp.toLocal().toString(),
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 10,
                        ),
                      ),
                      trailing: Text(
                        '${record.totalTokens} · '
                        '\$${record.estimatedCostUsd.toStringAsFixed(4)}',
                        style: const TextStyle(fontFamily: 'Consolas'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageMetric extends StatelessWidget {
  const _UsageMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: 185,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

class _QualityGateDialog extends StatelessWidget {
  const _QualityGateDialog({required this.result});

  final QualityGateResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.rule_folder_outlined, color: colors.error),
      title: const Text('Quality gate failed'),
      content: SizedBox(
        width: 760,
        height: 460,
        child: SilkyListView(
          silkyConfig: _silkyScrollConfig,
          children: [
            const Text(
              'Perubahan sudah diterapkan dan memiliki checkpoint. '
              'Tinjau hasil berikut sebelum memilih keep atau revert.',
            ),
            const SizedBox(height: 14),
            for (final check in result.checks) ...[
              Row(
                children: [
                  Icon(
                    check.passed
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: check.passed
                        ? const Color(0xFF2F9E69)
                        : colors.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      check.check.label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    check.timedOut
                        ? 'TIMEOUT'
                        : '${check.duration.inSeconds}s · exit ${check.exitCode}',
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              if (check.output.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8, bottom: 14),
                  padding: const EdgeInsets.all(10),
                  color: colors.onSurface.withValues(alpha: 0.04),
                  child: SelectableText(
                    check.output,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('KEEP CHANGES'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('REVERT TURN'),
        ),
      ],
    );
  }
}
