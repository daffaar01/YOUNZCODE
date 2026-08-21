part of '../main.dart';

extension _WorkspaceLifecycle on _AgentHomePageState {
  Future<void> _loadSettings() async {
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final results = await Future.wait([
      _settingsStore.load().catchError(
        (_) => const AppSettings(
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4.1-mini',
          workspace: '',
          models: ['gpt-4.1-mini'],
        ),
      ),
      _chatSessionStore.load().catchError((_) => <ChatSession>[]),
      _addonService
          .ensureBundledSkills(
            '$executableDirectory${Platform.pathSeparator}skills',
          )
          .catchError((_) => <Addon>[]),
    ]);
    final settings = results[0] as AppSettings;
    final sessions = results[1] as List<ChatSession>;
    final addons = results[2] as List<Addon>;
    var workspace = settings.workspace;
    if (workspace.isNotEmpty) {
      try {
        final directory = Directory(workspace);
        if (!await directory.exists()) {
          workspace = '';
        }
      } on FileSystemException {
        workspace = '';
      }
    }
    var trusted = false;
    try {
      trusted = await _trustService.isTrusted(workspace);
    } catch (_) {}
    final toolPolicies = await _toolPermissionStore
        .load(workspace)
        .catchError((_) => <String, ToolPermissionPolicy>{});
    var workspaceLayout = _WorkspaceLayout.classic;
    var composerDensity = _ComposerDensity.comfortable;
    var uiPreset = UiPreset.custom;
    var recentWorkspaces = <String>[];
    var pinnedWorkspaces = <String>[];
    try {
      final preferences = await SharedPreferences.getInstance();
      workspaceLayout = preferences.getString('workspace_layout') == 'focus'
          ? _WorkspaceLayout.focus
          : _WorkspaceLayout.classic;
      composerDensity = preferences.getString(_composerDensityKey) == 'compact'
          ? _ComposerDensity.compact
          : _ComposerDensity.comfortable;
      uiPreset = switch (preferences.getString(_uiPresetKey)) {
        'minimal' => UiPreset.minimal,
        'coding' => UiPreset.coding,
        'focus' => UiPreset.focus,
        _ => UiPreset.custom,
      };
      switch (uiPreset) {
        case UiPreset.minimal:
          workspaceLayout = _WorkspaceLayout.classic;
          composerDensity = _ComposerDensity.compact;
        case UiPreset.coding:
          workspaceLayout = _WorkspaceLayout.classic;
          composerDensity = _ComposerDensity.comfortable;
        case UiPreset.focus:
          workspaceLayout = _WorkspaceLayout.focus;
          composerDensity = _ComposerDensity.compact;
        case UiPreset.custom:
          break;
      }
      recentWorkspaces = preferences.getStringList(_recentWorkspacesKey) ?? [];
      pinnedWorkspaces = preferences.getStringList(_pinnedWorkspacesKey) ?? [];
      final promptHistory = preferences.getStringList(_promptHistoryKey) ?? [];
      _promptHistory
        ..clear()
        ..addAll(promptHistory.take(30));
    } catch (_) {}
    final knownWorkspaces =
        <String>{
              if (workspace.isNotEmpty) workspace,
              ...pinnedWorkspaces,
              ...recentWorkspaces,
              for (final session in sessions)
                if (session.workspace.isNotEmpty) session.workspace,
            }
            .where((path) {
              try {
                return Directory(path).existsSync();
              } catch (_) {
                return false;
              }
            })
            .take(8)
            .toList();
    if (!mounted) return;
    final workspaceSessions = sessions
        .where((session) => session.workspace == workspace)
        .toList();
    _updateState(() {
      _baseUrl = settings.baseUrl;
      _fallbackBaseUrls = List.of(settings.fallbackBaseUrls);
      _inputCostPerMillion = settings.inputCostPerMillion;
      _outputCostPerMillion = settings.outputCostPerMillion;
      _monthlyTokenBudget = settings.monthlyTokenBudget;
      _qualityGateEnabled = settings.qualityGateEnabled;
      _updatePingEnabled = settings.updatePingEnabled;
      _model = settings.model;
      _models
        ..clear()
        ..addAll(settings.models);
      _workspace = workspace;
      _allowWrite = settings.allowWrite;
      _allowTerminal = settings.allowTerminal;
      _approvalMode = settings.approvalMode;
      _timeoutMs = settings.timeoutMs;
      _dapTimeoutMs = settings.dapTimeoutMs;
      _workspaceLayout = workspaceLayout;
      _composerDensity = composerDensity;
      if (uiPreset == UiPreset.focus) _explorerPanelVisible = true;
      _chatSessions
        ..clear()
        ..addAll(sessions);
      _recentWorkspaces
        ..clear()
        ..addAll(knownWorkspaces);
      _pinnedWorkspaces
        ..clear()
        ..addAll(pinnedWorkspaces);
      _addons
        ..clear()
        ..addAll(addons);
      _toolPermissionPolicies
        ..clear()
        ..addAll(toolPolicies);
      if (workspaceSessions.isNotEmpty) {
        _activeChatId = workspaceSessions.first.id;
        _entries
          ..clear()
          ..addAll(workspaceSessions.first.entries);
        _agentCheckpoint
          ..clear()
          ..addAll(workspaceSessions.first.agentMessages);
        _goal = _goalRestoredFromSession(workspaceSessions.first.goal);
        _taskGraph = workspaceSessions.first.taskGraph;
      }
      _loading = false;
      _workspaceTrusted = trusted;
    });
    if (workspace != settings.workspace) unawaited(_saveSettings());
    if (knownWorkspaces.length != recentWorkspaces.length ||
        !knownWorkspaces.every(recentWorkspaces.contains)) {
      unawaited(_saveRecentWorkspaces());
    }
    if (_entries.isNotEmpty) _scrollToBottom();
    unawaited(_refreshGit());
    unawaited(_loadCheckpointHistory(workspace));
    unawaited(_initializeCodeIntelligence(workspace));
    // Startup version ping for fleet adoption telemetry.
    unawaited(_sendUpdatePing());
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!(preferences.getBool('onboarding_complete') ?? false) && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showOnboarding());
      }
    } catch (_) {}
  }

  Future<void> _chooseWorkspace() async {
    if (_busy) {
      _showMessage('Tunggu agent selesai sebelum mengganti workspace.');
      return;
    }
    final candidates = <String>[];
    void addCandidate(String candidate) {
      if (candidate.isEmpty || candidates.contains(candidate)) return;
      try {
        if (Directory(candidate).existsSync()) candidates.add(candidate);
      } catch (_) {}
    }

    for (final workspace in _pinnedWorkspaces) {
      addCandidate(workspace);
    }
    addCandidate(_workspace);
    for (final workspace in _recentWorkspaces) {
      addCandidate(workspace);
    }
    for (final session in _chatSessions) {
      addCandidate(session.workspace);
    }
    if (candidates.length > 12) candidates.removeRange(12, candidates.length);
    final trustEntries = await Future.wait(
      candidates.map((path) async {
        final trusted = await _trustService
            .isTrusted(path)
            .catchError((_) => false);
        final sessionCount = _chatSessions
            .where((session) => session.workspace == path)
            .length;
        final latest = _chatSessions
            .where((session) => session.workspace == path)
            .map((session) => session.updatedAt)
            .fold<DateTime?>(
              null,
              (current, value) =>
                  current == null || value.isAfter(current) ? value : current,
            );
        return _WorkspacePickerEntry(
          path: path,
          trusted: trusted,
          sessionCount: sessionCount,
          lastOpenedAt: latest,
          active: path == _workspace,
          pinned: _pinnedWorkspaces.contains(path),
        );
      }),
    );
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _WorkspacePickerDialog(
        entries: trustEntries,
        onTogglePinned: _toggleWorkspacePinned,
        loadGitStatus: (workspace) => _gitService
            .status(workspace)
            .catchError((_) => const GitStatus(isRepository: false)),
      ),
    );
    if (selected == null) return;
    if (selected == _WorkspacePickerDialog.browseValue) {
      await _browseWorkspace();
      return;
    }
    await _activateWorkspace(selected);
  }

  Future<void> _browseWorkspace() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pilih workspace proyek',
      initialDirectory: _workspace.isEmpty ? null : _workspace,
    );
    if (selected == null) return;
    await _activateWorkspace(selected);
  }

  Future<void> _activateWorkspace(String selected) async {
    if (_busy) {
      _showMessage('Tunggu agent selesai sebelum mengganti workspace.');
      return;
    }
    if (!mounted) return;
    var trusted = await _trustService
        .isTrusted(selected)
        .catchError((_) => false);
    if (!mounted) return;
    if (!trusted) {
      final trust = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.shield_outlined),
          title: const Text('Trust Workspace?'),
          content: Text(
            '$selected\n\nRestricted Mode menonaktifkan write, terminal, add-on, dan MCP lokal.',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('RESTRICTED MODE'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('TRUST WORKSPACE'),
            ),
          ],
        ),
      );
      trusted = trust == true;
      await _trustService.setTrusted(selected, trusted);
    }
    final toolPolicies = await _toolPermissionStore
        .load(selected)
        .catchError((_) => <String, ToolPermissionPolicy>{});
    await _persistActiveChat();
    await _agent?.dispose();
    await _terminalService.dispose();
    _updateState(() {
      for (final document in _documents) {
        document.dispose();
      }
      _documents.clear();
      _recentFiles.clear();
      _activeFile = null;
      _contextFiles.clear();
      _terminalOutput.clear();
      _workspace = selected;
      _workspaceTrusted = trusted;
      _browserMode = false;
      _browserInitialUrl = null;
      _budgetWarningShown = false;
      _agent = null;
      _entries.clear();
      _agentCheckpoint.clear();
      _goal = null;
      _taskGraph = null;
      _toolPermissionPolicies
        ..clear()
        ..addAll(toolPolicies);
      final workspaceSessions =
          _chatSessions
              .where((session) => session.workspace == selected)
              .toList()
            ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      if (workspaceSessions.isNotEmpty) {
        _activeChatId = workspaceSessions.first.id;
        _entries.addAll(workspaceSessions.first.entries);
        _agentCheckpoint.addAll(workspaceSessions.first.agentMessages);
        _goal = _goalRestoredFromSession(workspaceSessions.first.goal);
        _taskGraph = workspaceSessions.first.taskGraph;
      } else {
        _activeChatId = DateTime.now().microsecondsSinceEpoch.toString();
      }
      _activities.clear();
      _turnState = _AgentTurnState.idle;
      _searchResults = [];
      _searchBusy = false;
      _searchController.clear();
    });
    await _rememberWorkspace(selected);
    await _saveSettings();
    await _refreshGit();
    await _loadCheckpointHistory(selected);
    await _initializeCodeIntelligence(selected);
    if (_entries.isNotEmpty) _scrollToBottom();
  }

  Future<void> _rememberWorkspace(String workspace) async {
    if (workspace.isEmpty) return;
    _updateState(() {
      _recentWorkspaces
        ..remove(workspace)
        ..insert(0, workspace);
      if (_recentWorkspaces.length > 8) {
        _recentWorkspaces.removeRange(8, _recentWorkspaces.length);
      }
    });
    await _saveRecentWorkspaces();
  }

  Future<void> _toggleWorkspacePinned(String workspace) async {
    _updateState(() {
      if (!_pinnedWorkspaces.add(workspace)) {
        _pinnedWorkspaces.remove(workspace);
      }
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _pinnedWorkspacesKey,
      _pinnedWorkspaces.toList(growable: false),
    );
  }

  Future<void> _saveRecentWorkspaces() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _recentWorkspacesKey,
      List.unmodifiable(_recentWorkspaces),
    );
  }

  Future<void> _loadCheckpointHistory(String workspace) async {
    final history = await _checkpointStore.load(workspace);
    if (!mounted || workspace != _workspace) return;
    _updateState(() {
      _changeHistory
        ..clear()
        ..addAll(history);
      _lastAppliedTurn = null;
    });
  }

  Future<void> _initializeCodeIntelligence(String workspace) async {
    final service = workspace.isEmpty
        ? null
        : CodeIntelligenceService(workspace);
    _codeIntelligence = service;
    _contextEngine = service == null
        ? null
        : ContextEngine(workspace, intelligence: service);
    if (service == null) return;
    await service.ensureIndexed();
    if (!mounted || workspace != _workspace || _codeIntelligence != service) {
      return;
    }
    final identifiers = service.symbolNames;
    for (final document in _documents) {
      document.controller.workspaceIdentifiers = identifiers;
    }
  }

  void _openSearch() {
    if (_busy) {
      _showMessage('Tunggu agent selesai sebelum membuka pencarian.');
      return;
    }
    if (_workspace.isEmpty) {
      _showMessage('Pilih workspace sebelum melakukan pencarian.');
      return;
    }
    _updateState(() {
      _searchMode = true;
      _imageGenerationMode = false;
      _browserMode = false;
    });
  }

  void _openImageGeneration() {
    if (_busy) {
      _showMessage('Tunggu agent selesai sebelum membuka Image Generation.');
      return;
    }
    _updateState(() {
      _activeFile = null;
      _searchMode = false;
      _imageGenerationMode = true;
      _browserMode = false;
    });
  }

  Future<void> _searchWorkspace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searchBusy) return;
    final service = _codeIntelligence ?? CodeIntelligenceService(_workspace);
    _codeIntelligence = service;
    final guard = WorkspaceSearchGuard(workspace: _workspace, service: service);
    _updateState(() {
      _searchBusy = true;
      _searchResults = [];
    });
    try {
      final result = await service.search(query, limit: 500);
      if (!mounted ||
          !guard.isCurrent(workspace: _workspace, service: _codeIntelligence)) {
        return;
      }
      _updateState(() {
        _searchResults = result.map((item) => item.displayLine).toList();
      });
    } catch (error) {
      if (mounted &&
          guard.isCurrent(workspace: _workspace, service: _codeIntelligence)) {
        _showMessage('Pencarian gagal: $error');
      }
    } finally {
      if (mounted &&
          guard.isCurrent(workspace: _workspace, service: _codeIntelligence)) {
        _updateState(() => _searchBusy = false);
      }
    }
  }
}
