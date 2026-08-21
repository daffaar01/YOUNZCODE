part of '../main.dart';

extension _AgentTurnWorkflow on _AgentHomePageState {
  bool get _hasRetryablePrompt =>
      _entries.any((entry) => entry.role == ChatRole.user);

  void _prepareCheckpointContinuation() {
    if (_busy || _agentCheckpoint.isEmpty) return;
    if (_promptController.text.trim().isNotEmpty) {
      _showMessage(
        'Composer sudah berisi teks. Kosongkan atau edit teks tersebut sebelum '
        'menyiapkan lanjutan checkpoint.',
      );
      _promptFocusNode.requestFocus();
      return;
    }
    const prompt =
        'Lanjutkan tugas dari checkpoint terakhir. Tinjau hasil yang sudah '
        'selesai, lalu kerjakan bagian yang masih belum selesai.';
    _preparedCheckpointPrompt = prompt;
    _useSuggestion(prompt);
    _showMessage('Draf lanjutan siap. Periksa lalu tekan Kirim.');
  }

  Future<void> _continueFromCheckpoint() async {
    if (_busy || _agentCheckpoint.isEmpty) return;
    await _runAgentOperation((agent) => agent.continueFromCheckpoint());
  }

  void _prepareRetryLastPrompt() {
    if (_busy) return;
    if (_promptController.text.trim().isNotEmpty) {
      _showMessage(
        'Composer sudah berisi teks. Kirim atau hapus teks tersebut sebelum '
        'menyiapkan retry.',
      );
      _promptFocusNode.requestFocus();
      return;
    }
    final lastPrompt = _entries.reversed
        .where((entry) => entry.role == ChatRole.user)
        .map((entry) => entry.content.trim())
        .firstWhere((content) => content.isNotEmpty, orElse: () => '');
    if (lastPrompt.isEmpty) {
      _showMessage('Belum ada prompt pengguna yang bisa diulang.');
      return;
    }
    _preparedCheckpointPrompt = null;
    _useSuggestion(lastPrompt);
    _showMessage('Draf retry siap. Periksa lalu tekan Kirim.');
  }

  Future<void> _runAgentOperation(
    Future<String> Function(AgentService agent) operation, {
    ChatEntry? userEntry,
    bool driveGoal = false,
  }) async {
    final agent = _ensureAgent();
    _updateState(() {
      _browserTurnNavigation.beginTurn();
      _busy = true;
      _timeoutContinuationCancelled = false;
      _executionSummaryVisible = false;
      _turnState = _AgentTurnState.running;
      _agentStatus = 'Menyiapkan konteks';
      _activities.clear();
      _lastQualityGateResult = null;
      _turnStartedAt = DateTime.now();
      if (userEntry != null) _entries.add(userEntry);
    });
    await _persistActiveChat();
    _scrollToBottom();
    try {
      final answer = await _executeWithAdaptiveTimeout(agent, operation);
      if (!mounted) return;
      if (driveGoal && _goal?.status == AgentGoalStatus.active) {
        await _consumeGoalAnswers(answer);
      } else {
        _updateState(() {
          _entries.add(ChatEntry(role: ChatRole.assistant, content: answer));
        });
        await _persistActiveChat();
      }
      if (mounted) {
        _updateState(() {
          _providerVerified = true;
          _turnState = _AgentTurnState.success;
        });
        _notify(
          'Tugas selesai',
          'Agent menyelesaikan task dalam ${_elapsedSinceTurn().inSeconds}s.',
          category: _NotificationCategory.agent,
        );
        _showMessage(
          'Tugas selesai. Hasil dan perubahan siap ditinjau.',
          action: SnackBarAction(
            label: 'DETAIL',
            onPressed: () {
              if (mounted) {
                _updateState(() => _executionSummaryVisible = true);
              }
            },
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final turnState = _turnStateForError(error);
      final message = _friendlyAgentError(error);
      _updateState(() {
        _turnState = turnState;
        final goal = _goal;
        if (driveGoal &&
            goal != null &&
            goal.status == AgentGoalStatus.active) {
          _goal = goal.copyWith(
            status: AgentGoalStatus.paused,
            updatedAt: DateTime.now(),
            lastDetail:
                'Goal dijeda karena turn gagal. Gunakan "/goal resume".',
          );
        }
        _entries.add(
          ChatEntry(
            role: turnState == _AgentTurnState.paused
                ? ChatRole.assistant
                : ChatRole.error,
            content: message,
          ),
        );
      });
      await _persistActiveChat();
      if (turnState == _AgentTurnState.cancelled) {
        _agent = null;
      } else if (error is AgentTurnTimeoutException) {
        if (identical(_agent, agent)) _agent = null;
        await agent.dispose();
      } else if (turnState != _AgentTurnState.paused &&
          error is! AgentEmptyResponseException) {
        await _showConnectionError(message);
      }
    } finally {
      if (mounted) {
        _updateState(() {
          final returnToChat = _browserTurnNavigation.completeTurn(
            browserIsVisible: _browserMode,
          );
          if (returnToChat) {
            _activeFile = null;
            _searchMode = false;
            _imageGenerationMode = false;
            _browserMode = false;
          }
          _busy = false;
          _agentStatus = _goalIdleStatus();
          _lastTurnDuration = _turnStartedAt == null
              ? Duration.zero
              : DateTime.now().difference(_turnStartedAt!);
        });
      }
      _scrollToBottom();
    }
  }

  Future<String> _executeWithAdaptiveTimeout(
    AgentService initialAgent,
    Future<String> Function(AgentService agent) operation,
  ) async {
    var currentAgent = initialAgent;
    var firstAttempt = true;
    var timeoutContinuations = 0;
    while (true) {
      try {
        return await _executeWithFallback(
          currentAgent,
          () => firstAttempt
              ? operation(currentAgent)
              : currentAgent.continueFromCheckpoint(),
        );
      } catch (error) {
        if (error is! AgentTurnTimeoutException) rethrow;

        final nextDuration = nextAgentTurnDuration(error.limit);
        final activeAgent = _agent ?? currentAgent;
        if (identical(_agent, activeAgent)) _agent = null;
        await activeAgent.dispose();
        if (!mounted || _timeoutContinuationCancelled || !_busy) {
          throw const AgentCancelledException();
        }
        if (_agentCheckpoint.isEmpty) rethrow;

        timeoutContinuations++;
        _updateState(() {
          _agentStatus =
              'Batas ${error.limit.inMinutes} menit tercapai; '
              'melanjutkan otomatis dengan ${nextDuration.inMinutes} menit '
              '(percobaan $timeoutContinuations)';
        });
        _notify(
          'Timeout ditangani otomatis',
          'Checkpoint tersimpan. Melanjutkan dengan batas '
              '${nextDuration.inMinutes} menit.',
          category: _NotificationCategory.agent,
        );

        currentAgent = _createAgent(
          baseUrl: activeAgent.baseUrl,
          model: activeAgent.model,
          maxTurnDuration: nextDuration,
        );
        currentAgent.restoreMessages(_agentCheckpoint);
        _agent = currentAgent;
        firstAttempt = false;
      }
    }
  }

  Future<String> _executeWithFallback(
    AgentService agent,
    Future<String> Function() operation,
  ) async {
    try {
      return await operation();
    } catch (error) {
      final recovered = await _continueWithFallbackProvider(
        error,
        agent.baseUrl,
      );
      if (recovered == null) rethrow;
      return recovered;
    }
  }

  Future<void> _consumeGoalAnswers(String firstAnswer) async {
    var answer = firstAnswer;
    var autoContinuations = 0;
    while (mounted) {
      final goal = _goal;
      if (goal == null || goal.status != AgentGoalStatus.active) return;
      final result = _goalCoordinator.parseAnswer(answer);
      final nextTurnCount = goal.turnCount + 1;
      final nextStatus = switch (result.decision) {
        GoalTurnDecision.complete => AgentGoalStatus.completed,
        GoalTurnDecision.blocked => AgentGoalStatus.blocked,
        GoalTurnDecision.continueWorking => AgentGoalStatus.active,
      };
      _updateState(() {
        _entries.add(
          ChatEntry(role: ChatRole.assistant, content: result.answer),
        );
        _goal = goal.copyWith(
          status: nextStatus,
          turnCount: nextTurnCount,
          updatedAt: DateTime.now(),
          lastDetail: switch (result.decision) {
            GoalTurnDecision.complete =>
              'Goal selesai dan ditandai terverifikasi oleh agent.',
            GoalTurnDecision.blocked =>
              'Agent membutuhkan keputusan pengguna atau perubahan eksternal.',
            GoalTurnDecision.continueWorking =>
              'Turn $nextTurnCount selesai; melanjutkan otomatis.',
          },
        );
      });
      await _persistActiveChat();
      _scrollToBottom();
      if (result.decision == GoalTurnDecision.complete) {
        _notify(
          'Goal selesai',
          goal.objective,
          category: _NotificationCategory.agent,
        );
        return;
      }
      if (result.decision == GoalTurnDecision.blocked) {
        _notify(
          'Goal membutuhkan bantuan',
          'Buka chat dan periksa pertanyaan agent.',
          category: _NotificationCategory.agent,
        );
        return;
      }
      if (autoContinuations >= GoalCoordinator.maxAutoContinuations) {
        final activeGoal = _goal;
        if (activeGoal != null) {
          _updateState(() {
            _goal = activeGoal.copyWith(
              status: AgentGoalStatus.paused,
              updatedAt: DateTime.now(),
              lastDetail:
                  'Dijeda setelah ${GoalCoordinator.maxAutoContinuations} '
                  'kelanjutan otomatis untuk mencegah loop. Gunakan '
                  '"/goal resume" untuk batch berikutnya.',
            );
          });
          await _persistActiveChat();
        }
        _notify(
          'Goal dijeda',
          'Batas kelanjutan otomatis tercapai; progres tetap tersimpan.',
          category: _NotificationCategory.agent,
        );
        return;
      }
      autoContinuations++;
      final activeGoal = _goal;
      if (activeGoal == null) return;
      _updateState(() {
        _agentStatus =
            'Goal turn ${activeGoal.turnCount + 1} · melanjutkan otomatis';
      });
      final currentAgent = _ensureAgent();
      answer = await _executeWithAdaptiveTimeout(
        currentAgent,
        (agent) => agent.continueWithPrompt(
          _goalCoordinator.continuationPrompt(activeGoal),
        ),
      );
    }
  }

  String _goalIdleStatus() => switch (_goal?.status) {
    AgentGoalStatus.active => 'Goal aktif',
    AgentGoalStatus.completed => 'Goal selesai',
    AgentGoalStatus.blocked => 'Goal membutuhkan bantuan',
    AgentGoalStatus.paused => 'Goal dijeda',
    AgentGoalStatus.stopped => 'Goal dihentikan',
    null => 'Siap menerima tugas',
  };

  Duration _elapsedSinceTurn() => _turnStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(_turnStartedAt!);

  void _notify(
    String title,
    String body, {
    bool error = false,
    _NotificationCategory category = _NotificationCategory.system,
  }) {
    if (!mounted) return;
    _updateState(() {
      _notifications.insert(
        0,
        _AppNotification(
          title: title,
          body: body,
          createdAt: DateTime.now(),
          error: error,
          category: category,
        ),
      );
    });
    _notificationRevision.value++;
  }

  Future<void> _showNotifications() => showDialog<void>(
    context: context,
    builder: (context) => _NotificationDialog(
      notifications: _notifications,
      revision: _notificationRevision,
      onDelete: (notification) {
        if (mounted) _updateState(() => _notifications.remove(notification));
        _notificationRevision.value++;
      },
      onClear: () {
        if (mounted) _updateState(_notifications.clear);
        _notificationRevision.value++;
      },
      onRead: (notification) {
        if (notification.read) return;
        if (mounted) _updateState(() => notification.read = true);
        _notificationRevision.value++;
      },
      onMarkAllRead: () {
        if (mounted) {
          _updateState(() {
            for (final notification in _notifications) {
              notification.read = true;
            }
          });
        }
        _notificationRevision.value++;
      },
    ),
  );

  Future<void> _showOnboarding() async {
    if (_onboardingShown || !mounted) return;
    _onboardingShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _OnboardingDialog(
        workspaceConfigured: _workspace.isNotEmpty,
        providerConfigured: _apiKey.isNotEmpty,
        model: _model,
        onWorkspace: () async {
          await _chooseWorkspace();
          return _workspace.isNotEmpty;
        },
        onProvider: () async {
          await _openSettings();
          return _apiKey.isNotEmpty;
        },
        onEnvironment: _openEnvironmentPanel,
        onComposer: () async => _promptFocusNode.requestFocus(),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('onboarding_complete', true);
  }

  Future<void> _reviewChanges() async {
    final changes = _pendingChanges;
    final agent = _agent;
    if (changes == null || agent == null || !mounted) return;
    final accepted = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ChangesReviewDialog(changes: changes),
    );
    if (accepted == null) return;
    if (accepted.isEmpty) {
      agent.rejectPendingChanges();
      _updateState(() => _pendingChanges = null);
      _showMessage('Semua perubahan agent ditolak.');
      return;
    }
    final applied = await agent.applyPendingChanges(hunkIds: accepted);
    if (!mounted || applied == null) return;
    _updateState(() {
      _lastAppliedTurn = applied;
      _changeHistory.insert(0, applied);
      _pendingChanges = null;
      _lastQualityGateResult = null;
    });
    await _checkpointStore.save(_workspace, applied);
    await _reloadChangedDocuments(applied.files);
    await _refreshGit();
    _showMessage('${applied.files.length} file diterapkan.');
    if (_qualityGateEnabled) await _runQualityGate(applied);
  }

  Future<void> _runQualityGate(WorkspaceTurnChanges turn) async {
    if (_workspace.isEmpty) return;
    _updateState(() {
      _busy = true;
      _agentStatus = 'Menyiapkan quality gate';
    });
    late final QualityGateResult result;
    try {
      result = await _qualityGateService.run(
        _workspace,
        turn.files.map((file) => file.path),
        onStatus: (status) {
          if (mounted) _updateState(() => _agentStatus = status);
        },
      );
    } finally {
      if (mounted) {
        _updateState(() {
          _busy = false;
          _agentStatus = 'Siap menerima tugas';
        });
      }
    }
    if (!mounted) return;
    _updateState(() => _lastQualityGateResult = result);
    await _refreshGit();
    if (!mounted) return;
    if (result.skipped) {
      _showMessage('Perubahan diterapkan; tidak ada quality check yang cocok.');
      return;
    }
    if (result.passed) {
      _showMessage('${result.checks.length} quality check lulus.');
      return;
    }
    final revert = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QualityGateDialog(result: result),
    );
    if (revert == true) {
      await _revertAppliedTurn(turn);
    }
  }

  Future<void> _revertAppliedTurn(WorkspaceTurnChanges turn) async {
    final agent = _agent;
    if (agent == null || _lastAppliedTurn?.id != turn.id) return;
    await agent.revertLastTurn();
    await _checkpointStore.remove(_workspace, turn.id);
    if (!mounted) return;
    _updateState(() {
      _changeHistory.removeWhere((item) => item.id == turn.id);
      _lastAppliedTurn = null;
    });
    await _reloadChangedDocuments(turn.files);
    await _refreshGit();
    _showMessage('Turn dikembalikan karena quality gate gagal.');
  }

  Future<void> _revertTurn() async {
    final agent = _agent;
    final turn = _lastAppliedTurn;
    if (agent == null || turn == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revert agent turn?'),
        content: Text(
          'Pulihkan ${turn.files.length} file ke kondisi sebelum prompt ini?\n\n'
          '${turn.prompt}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REVERT TURN'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await agent.revertLastTurn();
    if (!mounted) return;
    await _checkpointStore.remove(_workspace, turn.id);
    _updateState(() {
      _changeHistory.removeWhere((item) => item.id == turn.id);
      _lastAppliedTurn = null;
    });
    await _reloadChangedDocuments(turn.files);
    await _refreshGit();
    _showMessage('Perubahan turn dipulihkan.');
  }

  // Retained for checkpoints created by the detailed inspector UI.
  // ignore: unused_element
  Future<void> _restoreCheckpoint(WorkspaceTurnChanges turn) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore checkpoint?'),
        content: Text(
          'Pulihkan ${turn.files.length} file ke kondisi sebelum turn ini?\n\n'
          '${turn.prompt}\n\n'
          'Pemulihan hanya diteruskan bila file masih sama dengan hasil turn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('RESTORE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _checkpointStore.restore(_workspace, turn);
      await _disposeAgent();
      if (!mounted) return;
      _updateState(() {
        _changeHistory.removeWhere((item) => item.id == turn.id);
        if (_lastAppliedTurn?.id == turn.id) _lastAppliedTurn = null;
      });
      await _reloadChangedDocuments(turn.files);
      _showMessage('Checkpoint dipulihkan.');
    } on WorkspaceCheckpointConflict catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _reloadChangedDocuments(
    List<WorkspaceFileChange> changes,
  ) async {
    var keptUnsaved = false;
    for (final change in changes) {
      final normalized = File(
        '$_workspace${Platform.pathSeparator}${change.path}',
      ).path;
      final matching = _documents.where(
        (document) =>
            document.path == normalized || document.path == change.path,
      );
      for (final document in matching) {
        // Don't overwrite the user's unsaved edits with the on-disk version.
        if (document.controller.text != document.savedContent) {
          keptUnsaved = true;
          continue;
        }
        final file = File(document.path);
        final content = await file.exists() ? await file.readAsString() : '';
        document.controller.text = content;
        document.savedContent = content;
      }
    }
    if (mounted) _updateState(() {});
    unawaited(
      _codeIntelligence?.refreshPaths(changes.map((change) => change.path)),
    );
    if (keptUnsaved) {
      _showMessage(
        'Beberapa file terbuka punya perubahan belum disimpan dan tidak '
        'dimuat ulang otomatis.',
      );
    }
  }

  Future<String?> _continueWithFallbackProvider(
    Object initialError,
    String failedBaseUrl,
  ) async {
    if (_agentCheckpoint.isEmpty ||
        !ProviderRoutingService.shouldFailover(initialError)) {
      return null;
    }
    final routes = _providerRouter.routes(
      primaryBaseUrl: _baseUrl,
      model: _model,
      fallbackBaseUrls: _fallbackBaseUrls,
    );
    var error = initialError;
    var currentBaseUrl = failedBaseUrl;
    var attempted = false;
    while (ProviderRoutingService.shouldFailover(error)) {
      if (!mounted) return null;
      _updateState(() => _agentStatus = 'Mencari provider fallback');
      final route = await _providerRouter.selectFallback(
        error: error,
        currentBaseUrl: currentBaseUrl,
        routes: routes,
        apiKey: _apiKey,
        headers: _apiHeaders,
      );
      if (route == null) {
        if (attempted) throw error;
        return null;
      }
      attempted = true;
      currentBaseUrl = route.baseUrl;
      await _disposeAgent();
      if (!mounted) return null;
      _updateState(() {
        _providerVerified = true;
        _agentStatus =
            'Fallback ${Uri.parse(route.baseUrl).host} tersedia; '
            'melanjutkan checkpoint';
      });
      _notify(
        'Provider fallback',
        'Task dilanjutkan melalui ${route.baseUrl}.',
        category: _NotificationCategory.agent,
      );
      final recoveredAgent = _createAgent(
        baseUrl: route.baseUrl,
        model: route.model,
      );
      _agent = recoveredAgent;
      recoveredAgent.restoreMessages(_agentCheckpoint);
      try {
        return await recoveredAgent.continueFromCheckpoint();
      } catch (nextError) {
        error = nextError;
      }
    }
    throw error;
  }

  Future<void> _cancelAgent() async {
    if (!_busy) return;
    _timeoutContinuationCancelled = true;
    final goal = _goal;
    if (goal != null && goal.status == AgentGoalStatus.active) {
      _updateState(() {
        _goal = goal.copyWith(
          status: AgentGoalStatus.paused,
          updatedAt: DateTime.now(),
          lastDetail:
              'Dijeda oleh pengguna. Gunakan "/goal resume" untuk '
              'melanjutkan dari checkpoint.',
        );
      });
      unawaited(_persistActiveChat());
    }
    if (_mediaDownloadService.running) {
      _updateState(() => _agentStatus = 'Membatalkan unduhan media');
      await _mediaDownloadService.cancel();
      return;
    }
    final agent = _agent;
    _agent = null;
    _updateState(() => _agentStatus = 'Membatalkan request dan proses aktif');
    await agent?.cancel();
  }

  _AgentTurnState _turnStateForError(Object error) {
    if (error is AgentCancelledException) return _AgentTurnState.cancelled;
    if (error is AgentStepLimitException) return _AgentTurnState.paused;
    if (error is TimeoutException) return _AgentTurnState.timedOut;
    if (error is AgentHttpException &&
        {408, 504, 522, 524}.contains(error.statusCode)) {
      return _AgentTurnState.timedOut;
    }
    return _AgentTurnState.failed;
  }

  String _friendlyAgentError(Object error) {
    if (error is AgentCancelledException) {
      return 'Tugas dibatalkan. Checkpoint dan hasil tool yang sudah selesai '
          'tetap disimpan.';
    }
    if (error is AgentEmptyResponseException) {
      return '${error.message} Coba kirim ulang pesan atau pilih model/provider '
          'lain jika masalah berulang.';
    }
    if (error is AgentStepLimitException) return '$error';
    if (error is AgentTurnTimeoutException) {
      return '${error.message} Proses yang masih aktif telah dihentikan. '
          'Checkpoint dan hasil tool yang sudah selesai tetap tersimpan; '
          'aplikasi akan melanjutkan otomatis dengan batas waktu bertahap. '
          'Gunakan BATAL bila ingin menghentikan proses.';
    }
    if (error is TimeoutException) {
      final detail = error.message?.trim();
      return '${detail == null || detail.isEmpty ? 'Operasi melewati batas waktu.' : detail} '
          'Checkpoint tersimpan dan dapat dilanjutkan. Jika operasi memang '
          'memerlukan waktu lebih lama, naikkan DEFAULT TIMEOUT (MS) di '
          'PROJECT SETTINGS > API.';
    }
    if (error is AgentHttpException && error.statusCode == 524) {
      return 'Gateway API model mengalami timeout (HTTP 524). Checkpoint '
          'tersimpan; gunakan CONTINUE FROM CHECKPOINT setelah koneksi pulih.';
    }
    if (error is AgentHttpException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      return 'Autentikasi provider ditolak (HTTP ${error.statusCode}). Buka '
          'MODEL SETTINGS dan masukkan API key yang valid. Checkpoint tetap '
          'tersimpan dan dapat dilanjutkan setelah key diperbaiki.';
    }
    if (error is http.ClientException) {
      return 'Koneksi streaming ke provider terputus setelah beberapa kali '
          'percobaan. Checkpoint tetap tersimpan. Provider 9router lokal juga '
          'tidak dapat digunakan untuk melanjutkan otomatis.';
    }
    return '$error';
  }
}
