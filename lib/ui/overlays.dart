part of '../main.dart';

// Transient overlays: notifications, onboarding, execution summary, and the
// animated agent-working card.

class _AppNotification {
  const _AppNotification({
    required this.title,
    required this.body,
    required this.createdAt,
    required this.error,
  });

  final String title;
  final String body;
  final DateTime createdAt;
  final bool error;
}

class _NotificationDialog extends StatefulWidget {
  const _NotificationDialog({
    required this.notifications,
    required this.revision,
    required this.onDelete,
    required this.onClear,
  });

  final List<_AppNotification> notifications;
  final Listenable revision;
  final ValueChanged<_AppNotification> onDelete;
  final VoidCallback onClear;

  @override
  State<_NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<_NotificationDialog> {
  _AppNotification? _selected;

  void _delete(_AppNotification notification) {
    widget.onDelete(notification);
    setState(() {
      if (identical(_selected, notification)) _selected = null;
    });
  }

  void _clear() {
    widget.onClear();
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.revision,
    builder: (context, _) => AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Notifications')),
          if (widget.notifications.isNotEmpty)
            TextButton(
              key: const ValueKey('clear-all-notifications'),
              onPressed: _clear,
              child: const Text('CLEAR ALL'),
            ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 420,
        child: widget.notifications.isEmpty
            ? const Center(child: Text('No notifications.'))
            : Column(
                children: [
                  if (_selected != null)
                    Container(
                      key: const ValueKey('notification-detail'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selected!.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(_selected!.body),
                        ],
                      ),
                    ),
                  Expanded(
                    child: SilkyListView.builder(
                      silkyConfig: _silkyScrollConfig,
                      itemCount: widget.notifications.length,
                      itemBuilder: (context, index) {
                        final item = widget.notifications[index];
                        return ListTile(
                          key: ValueKey('notification-item-$index'),
                          selected: identical(_selected, item),
                          onTap: () => setState(() => _selected = item),
                          leading: Icon(
                            item.error
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: item.error
                                ? Theme.of(context).colorScheme.error
                                : (Theme.of(context).brightness ==
                                          Brightness.light
                                      ? const Color(0xFF2F9E69)
                                      : const Color(0xFF57C08A)),
                          ),
                          title: Text(item.title),
                          subtitle: Text(
                            item.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${item.createdAt.hour.toString().padLeft(2, '0')}:${item.createdAt.minute.toString().padLeft(2, '0')}',
                              ),
                              IconButton(
                                key: ValueKey('delete-notification-$index'),
                                tooltip: 'Delete notification',
                                onPressed: () => _delete(item),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    ),
  );
}

class _OnboardingDialog extends StatelessWidget {
  const _OnboardingDialog({
    required this.workspaceConfigured,
    required this.providerConfigured,
    required this.model,
    required this.onWorkspace,
    required this.onProvider,
  });

  final bool workspaceConfigured;
  final bool providerConfigured;
  final String model;
  final Future<void> Function() onWorkspace;
  final Future<void> Function() onProvider;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.rocket_launch_outlined),
    title: const Text('Set Up YOUNZCODE'),
    content: SizedBox(
      width: 540,
      child: SilkySingleChildScrollView(
        silkyConfig: _silkyScrollConfig,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OnboardingStep(
              number: 1,
              title: 'Choose workspace',
              complete: workspaceConfigured,
              onTap: onWorkspace,
            ),
            _OnboardingStep(
              number: 2,
              title: 'Configure provider and test connection',
              complete: providerConfigured,
              onTap: onProvider,
            ),
            _OnboardingStep(
              number: 3,
              title: 'Selected model: $model',
              complete: true,
              onTap: onProvider,
            ),
            const _OnboardingStep(
              number: 4,
              title: 'Send your first prompt',
              complete: false,
            ),
            const SizedBox(height: 8),
            const Text(
              'Compatible templates: OpenAI, Ollama, LM Studio, and 9router through MODEL SETTINGS.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('START CODING'),
      ),
    ],
  );
}

class _OnboardingStep extends StatelessWidget {
  const _OnboardingStep({
    required this.number,
    required this.title,
    required this.complete,
    this.onTap,
  });

  final int number;
  final String title;
  final bool complete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: CircleAvatar(
      child: complete ? const Icon(Icons.check, size: 17) : Text('$number'),
    ),
    title: Text(title),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _AgentStickyStatus extends StatefulWidget {
  const _AgentStickyStatus({
    required this.busy,
    required this.status,
    required this.activities,
    required this.turnState,
    required this.startedAt,
    required this.duration,
    required this.onShowSummary,
  });

  final bool busy;
  final String status;
  final List<_AgentActivity> activities;
  final _AgentTurnState turnState;
  final DateTime? startedAt;
  final Duration duration;
  final VoidCallback onShowSummary;

  @override
  State<_AgentStickyStatus> createState() => _AgentStickyStatusState();
}

class _AgentStickyStatusState extends State<_AgentStickyStatus> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.busy) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _elapsedLabel() {
    final elapsed = widget.busy && widget.startedAt != null
        ? DateTime.now().difference(widget.startedAt!)
        : widget.duration;
    final seconds = elapsed.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final accent = widget.busy
        ? colors.primary
        : widget.turnState == _AgentTurnState.success
        ? (light ? const Color(0xFF2F9E69) : const Color(0xFF57C08A))
        : widget.turnState == _AgentTurnState.cancelled ||
              widget.turnState == _AgentTurnState.paused
        ? (light ? const Color(0xFFB7862A) : const Color(0xFFD7A544))
        : colors.error;
    final label = widget.busy
        ? widget.status
        : switch (widget.turnState) {
            _AgentTurnState.success => 'Task selesai',
            _AgentTurnState.cancelled => 'Task dibatalkan',
            _AgentTurnState.paused => 'Checkpoint tersimpan',
            _AgentTurnState.timedOut => 'Task melewati batas waktu',
            _AgentTurnState.failed => 'Task gagal',
            _ => widget.status,
          };
    return Container(
      key: const ValueKey('agent-sticky-status'),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          if (widget.busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            )
          else
            Icon(
              widget.turnState == _AgentTurnState.success
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              size: 16,
              color: accent,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          Text(
            '${widget.activities.length} tools · ${_elapsedLabel()}',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 9,
              color: colors.onSurfaceVariant,
            ),
          ),
          if (!widget.busy) ...[
            const SizedBox(width: 6),
            IconButton(
              key: const ValueKey('sticky-show-summary'),
              tooltip: 'Tampilkan ringkasan task',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onShowSummary,
              icon: const Icon(Icons.expand_more, size: 17),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExecutionSummary extends StatelessWidget {
  const _ExecutionSummary({
    required this.activities,
    required this.turnState,
    this.onRetry,
    this.onContinue,
    required this.duration,
    required this.pendingChanges,
    required this.canRevert,
    this.onReviewChanges,
    this.onRevert,
    required this.onHide,
  });

  final List<_AgentActivity> activities;
  final _AgentTurnState turnState;
  final VoidCallback? onRetry;
  final VoidCallback? onContinue;
  final Duration duration;
  final WorkspaceTurnChanges? pendingChanges;
  final bool canRevert;
  final VoidCallback? onReviewChanges;
  final VoidCallback? onRevert;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final light = theme.brightness == Brightness.light;
    // Semantic state colours, kept distinct from the single blue accent.
    final good = light ? const Color(0xFF2F9E69) : const Color(0xFF57C08A);
    final warn = light ? const Color(0xFFB7862A) : const Color(0xFFD7A544);
    final bad = cs.error;
    final complete = activities.where((item) => item.completed).length;
    final failedTools = activities.where((item) => item.failed).length;
    final warningTools = activities.where((item) => item.warning).length;
    final toolIssues = failedTools + warningTools;
    final activityOutcome = turnState == _AgentTurnState.success
        ? toolIssues == 0
              ? ''
              : ' · $toolIssues tool warning${toolIssues == 1 ? '' : 's'}'
        : '${failedTools == 0 ? '' : ' · $failedTools failed'}'
              '${warningTools == 0 ? '' : ' · $warningTools skipped'}';
    final status = switch (turnState) {
      _AgentTurnState.success => ('STATUS: SUCCESS', Icons.check_circle, good),
      _AgentTurnState.cancelled => (
        'STATUS: CANCELLED',
        Icons.stop_circle_outlined,
        warn,
      ),
      _AgentTurnState.timedOut => (
        'STATUS: TIMED OUT',
        Icons.timer_off_outlined,
        bad,
      ),
      _AgentTurnState.paused => (
        'STATUS: CHECKPOINT SAVED',
        Icons.pause_circle_outline,
        warn,
      ),
      _AgentTurnState.failed => ('STATUS: FAILED', Icons.error_outline, bad),
      _ => ('STATUS: COMPLETED WITH ERRORS', Icons.error_outline, bad),
    };
    final canRetry =
        onRetry != null &&
        {
          _AgentTurnState.cancelled,
          _AgentTurnState.timedOut,
          _AgentTurnState.paused,
          _AgentTurnState.failed,
        }.contains(turnState);
    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.$2, color: status.$3, size: 18),
              const SizedBox(width: 8),
              const Text(
                'EXECUTION SUMMARY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const ValueKey('hide-execution-summary'),
                tooltip: 'Hide execution summary',
                onPressed: onHide,
                icon: const Icon(Icons.expand_more, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Text(
                status.$1,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 9,
                  color: status.$3,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          if (turnState != _AgentTurnState.success) ...[
            Container(
              key: const ValueKey('execution-recovery-card'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bad.withValues(alpha: 0.07),
                border: Border.all(color: bad.withValues(alpha: 0.28)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.build_circle_outlined, size: 18, color: bad),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      turnState == _AgentTurnState.paused ||
                              turnState == _AgentTurnState.cancelled
                          ? 'Checkpoint tersimpan. Tinjau hasil yang sudah selesai '
                                'atau siapkan lanjutan dari composer.'
                          : 'Task belum selesai. Periksa detail tool, edit prompt '
                                'atau coba ulang dengan provider lain.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            '${activities.length} tool events · $complete completed'
            '$activityOutcome · '
            '${duration.inSeconds}s',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (activities.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final activity in activities)
              Container(
                key: ValueKey('completed-tool-${activity.id}'),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: activity.failed
                          ? bad
                          : activity.warning
                          ? warn
                          : good,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 58,
                      child: Text(
                        activity.label,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        activity.detail,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 10,
                          height: 1.4,
                          color: activity.failed
                              ? bad
                              : activity.warning
                              ? warn
                              : cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (pendingChanges != null || canRevert) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (pendingChanges != null)
                  FilledButton.icon(
                    key: const ValueKey('summary-review-changes'),
                    onPressed: onReviewChanges,
                    icon: const Icon(Icons.difference_outlined, size: 16),
                    label: Text('REVIEW ${pendingChanges!.files.length} FILES'),
                  ),
                if (canRevert)
                  OutlinedButton.icon(
                    key: const ValueKey('summary-revert-turn'),
                    onPressed: onRevert,
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('REVERT TURN'),
                  ),
              ],
            ),
          ],
          if (canRetry && (onRetry != null || onContinue != null)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onRetry != null)
                  OutlinedButton.icon(
                    key: const ValueKey('retry-last-prompt'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.replay, size: 16),
                    label: const Text('EDIT LAST PROMPT'),
                  ),
                if (onContinue != null)
                  OutlinedButton.icon(
                    key: const ValueKey('continue-from-checkpoint'),
                    onPressed: onContinue,
                    icon: const Icon(Icons.play_arrow_outlined, size: 16),
                    label: const Text('PREPARE CONTINUE'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ExecutionSummaryToggle extends StatelessWidget {
  const _ExecutionSummaryToggle({
    required this.turnState,
    required this.duration,
    required this.onShow,
  });

  final _AgentTurnState turnState;
  final Duration duration;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final color = turnState == _AgentTurnState.success
        ? (light ? const Color(0xFF2F9E69) : const Color(0xFF57C08A))
        : turnState == _AgentTurnState.cancelled ||
              turnState == _AgentTurnState.paused
        ? (light ? const Color(0xFFB7862A) : const Color(0xFFD7A544))
        : theme.colorScheme.error;
    final label = turnState == _AgentTurnState.success
        ? 'SUCCESS'
        : turnState.name.toUpperCase();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('show-execution-summary'),
        onPressed: onShow,
        icon: Icon(Icons.expand_less, size: 17, color: color),
        label: Text(
          'SHOW EXECUTION SUMMARY  ·  $label  ·  ${duration.inSeconds}s',
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _AgentWorkingCard extends StatefulWidget {
  const _AgentWorkingCard({required this.status, required this.activities});

  final String status;
  final List<_AgentActivity> activities;

  @override
  State<_AgentWorkingCard> createState() => _AgentWorkingCardState();
}

class _AgentWorkingCardState extends State<_AgentWorkingCard>
    with SingleTickerProviderStateMixin {
  bool _showActivities = false;
  final _elapsed = Stopwatch()..start();
  late final Timer _elapsedTimer;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _elapsedTimer.cancel();
    _elapsed.stop();
    _controller.dispose();
    super.dispose();
  }

  String get _elapsedLabel {
    final totalSeconds = _elapsed.elapsed.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AgentWorkingPalette.fromTheme(Theme.of(context));
    final activeStep = _activeProgressStep(widget.status, widget.activities);
    return TweenAnimationBuilder<double>(
      duration: _mediumMotion,
      curve: _motionCurve,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const ValueKey('agent-working-card'),
          constraints: const BoxConstraints(maxWidth: 760),
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: palette.background,
            border: Border.all(color: palette.border),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
              bottomLeft: Radius.circular(3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AgentProgressTimeline(activeStep: activeStep),
              const SizedBox(height: 14),
              if (widget.activities.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('toggle-live-tool-activity'),
                    onPressed: () =>
                        setState(() => _showActivities = !_showActivities),
                    icon: Icon(
                      _showActivities ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                    ),
                    label: Text(
                      _showActivities
                          ? 'HIDE TOOL ACTIVITY'
                          : 'SHOW TOOL ACTIVITY (${widget.activities.length})',
                    ),
                  ),
                ),
              if (_showActivities)
                for (final activity in widget.activities)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 18,
                          child: activity.succeeded
                              ? Icon(
                                  Icons.check,
                                  size: 14,
                                  color: palette.accent,
                                )
                              : activity.failed
                              ? Icon(
                                  Icons.close,
                                  size: 14,
                                  color: palette.error,
                                )
                              : activity.warning
                              ? Icon(
                                  Icons.remove,
                                  size: 14,
                                  color: palette.mutedText,
                                )
                              : SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: AnimatedBuilder(
                                    animation: _controller,
                                    builder: (context, _) => CustomPaint(
                                      painter: _AgentOrbitPainter(
                                        _controller.value,
                                        orbitColor: palette.orbit,
                                        dotColor: palette.accent,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 54,
                          child: Text(
                            activity.label,
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: palette.activity,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Tooltip(
                            message: activity.detail,
                            child: Text(
                              activity.detail,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 11,
                                height: 1.35,
                                color: activity.failed
                                    ? palette.error
                                    : activity.warning
                                    ? palette.mutedText
                                    : palette.primaryText,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (_showActivities && widget.activities.isNotEmpty)
                const Divider(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    key: const ValueKey('response-loading-animation'),
                    width: 120,
                    height: 86,
                    child: Lottie.asset(
                      'assets/younzcode_cat_loading.lottie',
                      decoder: decodeDotLottie,
                      fit: BoxFit.contain,
                      repeat: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: SizedBox(
                      width: 64,
                      child: Text(
                        'Thinking',
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: palette.accent,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedSwitcher(
                            duration: _fastMotion,
                            child: Text(
                              widget.status,
                              key: ValueKey(widget.status),
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 11,
                                color: palette.secondaryText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_elapsedLabel  ·  '
                            '${widget.activities.where((item) => item.completed).length} '
                            'of ${widget.activities.length} actions completed',
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 10,
                              color: palette.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _activeProgressStep(String status, List<_AgentActivity> activities) {
    final normalized = status.toLowerCase();
    if (normalized.contains('review') ||
        normalized.contains('quality') ||
        normalized.contains('diff') ||
        normalized.contains('checkpoint')) {
      return 4;
    }
    if (activities.any(
      (activity) =>
          activity.name == 'write_file' ||
          activity.name == 'replace_text' ||
          activity.name == 'apply_patch' ||
          activity.name == 'commit',
    )) {
      return 3;
    }
    if (activities.isNotEmpty) return 2;
    if (normalized.contains('anal') ||
        normalized.contains('mencari') ||
        normalized.contains('memeriksa')) {
      return 1;
    }
    return 0;
  }
}

class _AgentProgressTimeline extends StatelessWidget {
  const _AgentProgressTimeline({required this.activeStep});

  final int activeStep;

  static const _steps = <(String, IconData)>[
    ('Konteks', Icons.layers_outlined),
    ('Analisis', Icons.manage_search_outlined),
    ('Tool', Icons.build_outlined),
    ('Perubahan', Icons.edit_note_outlined),
    ('Review', Icons.rate_review_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AgentWorkingPalette.fromTheme(Theme.of(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            key: const ValueKey('agent-progress-timeline'),
            children: [
              for (var index = 0; index < _steps.length; index++)
                _buildCompactStep(context, palette, index),
            ],
          );
        }
        return Row(
          key: const ValueKey('agent-progress-timeline'),
          children: [
            for (var index = 0; index < _steps.length; index++) ...[
              Expanded(child: _buildStep(context, palette, index)),
              if (index < _steps.length - 1)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 20),
                    color: index < activeStep
                        ? palette.accent.withValues(alpha: 0.7)
                        : palette.border,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStep(
    BuildContext context,
    AgentWorkingPalette palette,
    int index,
  ) {
    final complete = index < activeStep;
    final current = index == activeStep;
    final color = complete || current ? palette.accent : palette.mutedText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: _fastMotion,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: current
                ? palette.accent.withValues(alpha: 0.16)
                : complete
                ? palette.accent.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(color: color.withValues(alpha: 0.7)),
          ),
          child: Icon(
            complete ? Icons.check : _steps[index].$2,
            size: 15,
            color: color,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _steps[index].$1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 9,
            fontWeight: current || complete ? FontWeight.w800 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactStep(
    BuildContext context,
    AgentWorkingPalette palette,
    int index,
  ) {
    final complete = index < activeStep;
    final current = index == activeStep;
    final color = complete || current ? palette.accent : palette.mutedText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            complete ? Icons.check : _steps[index].$2,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _steps[index].$1,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10,
                fontWeight: current || complete
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: color,
              ),
            ),
          ),
          Text(
            complete
                ? 'SELESAI'
                : current
                ? 'AKTIF'
                : 'MENUNGGU',
            style: TextStyle(fontFamily: 'Consolas', fontSize: 9, color: color),
          ),
        ],
      ),
    );
  }
}

class _AgentOrbitPainter extends CustomPainter {
  const _AgentOrbitPainter(
    this.progress, {
    required this.orbitColor,
    required this.dotColor,
  });

  final double progress;
  final Color orbitColor;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final orbit = Paint()
      ..color = orbitColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final dot = Paint()..color = dotColor;
    canvas.drawCircle(center, size.shortestSide * 0.34, orbit);
    final angle = progress * 6.283185307179586;
    final radius = size.shortestSide * 0.34;
    canvas.drawCircle(
      center + Offset(radius * math.cos(angle), radius * math.sin(angle)),
      3,
      dot,
    );
  }

  @override
  bool shouldRepaint(covariant _AgentOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.orbitColor != orbitColor ||
      oldDelegate.dotColor != dotColor;
}
