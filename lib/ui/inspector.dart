part of '../main.dart';

// Inspector + conversation widgets: activity/plan/files panels, metrics,
// message cards, model bar, composer, suggestions, and status bar.

class _AgentActivity {
  const _AgentActivity({
    required this.id,
    required this.name,
    required this.detail,
    required this.state,
  });

  final String id;
  final String name;
  final String detail;
  final String state;

  String get label => switch (name) {
    'run_command' => 'Shell',
    'read_file' => 'Read',
    'write_file' => 'Write',
    'replace_text' => 'Edit',
    'list_files' => 'Glob',
    'search_text' => 'Grep',
    'multi_agent' => 'Agent',
    _ when name.startsWith('mcp_') => 'MCP',
    _ => name,
  };

  bool get running => state == 'berjalan';
  bool get completed => !running;
  bool get succeeded => state == 'selesai';
  bool get failed => state == 'gagal';
  bool get warning => state == 'ditolak' || state == 'dibatalkan';
}

// Retained for the detailed inspector flow and compatibility with saved UI state.
// ignore: unused_element
class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({
    required this.activities,
    required this.busy,
    required this.status,
    required this.onHide,
    required this.section,
    required this.onSectionChanged,
    required this.pendingChanges,
    required this.changeHistory,
    required this.onReviewChanges,
    required this.onRestoreCheckpoint,
    // ignore: unused_element_parameter
    this.onRevert,
  });

  final List<_AgentActivity> activities;
  final bool busy;
  final String status;
  final VoidCallback onHide;
  final _InspectorSection section;
  final ValueChanged<_InspectorSection> onSectionChanged;
  final WorkspaceTurnChanges? pendingChanges;
  final List<WorkspaceTurnChanges> changeHistory;
  final VoidCallback onReviewChanges;
  final ValueChanged<WorkspaceTurnChanges> onRestoreCheckpoint;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final last = activities.isEmpty ? null : activities.last;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 52,
            child: Stack(
              children: [
                Row(
                  children: [
                    _InspectorTab(
                      label: 'ACTIVITY',
                      active: section == _InspectorSection.activity,
                      onTap: () => onSectionChanged(_InspectorSection.activity),
                    ),
                    _InspectorTab(
                      label: 'PLAN',
                      active: section == _InspectorSection.plan,
                      onTap: () => onSectionChanged(_InspectorSection.plan),
                    ),
                    _InspectorTab(
                      label: pendingChanges == null
                          ? 'FILES'
                          : 'FILES ${pendingChanges!.files.length}',
                      active: section == _InspectorSection.files,
                      onTap: () => onSectionChanged(_InspectorSection.files),
                    ),
                  ],
                ),
                Positioned(
                  right: 2,
                  top: 13,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      key: const ValueKey('hide-activity-panel'),
                      onPressed: onHide,
                      tooltip: 'Hide tool activity',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_right, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: section == _InspectorSection.files
                ? _InspectorFiles(
                    changes: pendingChanges,
                    history: changeHistory,
                    onReview: onReviewChanges,
                    onRestoreCheckpoint: onRestoreCheckpoint,
                    onRevert: onRevert,
                  )
                : section == _InspectorSection.plan
                ? _InspectorPlan(activities: activities, busy: busy)
                : SilkyListView(
                    silkyConfig: _silkyScrollConfig,
                    padding: const EdgeInsets.all(18),
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: busy
                                  ? colors.primary
                                  : (Theme.of(context).brightness ==
                                            Brightness.light
                                        ? const Color(0xFF2F9E69)
                                        : const Color(0xFF57C08A)),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              busy
                                  ? 'AGENT: ${status.toUpperCase()}'
                                  : 'AGENT: IDLE',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Column(
                          children: [
                            _InspectorMetric(
                              label: 'Last tool:',
                              value: last?.label ?? 'none',
                              accent: true,
                            ),
                            const SizedBox(height: 12),
                            _InspectorMetric(
                              label: 'Status:',
                              value:
                                  last?.state ?? (busy ? 'Running' : 'Ready'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      const _InspectorHeading('SYSTEM LOAD'),
                      const SizedBox(height: 12),
                      _LoadBar(label: 'COMPUTE', value: busy ? 0.72 : 0.12),
                      const SizedBox(height: 14),
                      _LoadBar(
                        label: 'CONTEXT',
                        value: activities.isEmpty ? 0.04 : 0.28,
                        tertiary: true,
                      ),
                      const SizedBox(height: 28),
                      const _InspectorHeading('NOTIFICATIONS'),
                      const SizedBox(height: 12),
                      if (activities.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.06),
                            border: Border(
                              left: BorderSide(color: colors.primary),
                            ),
                          ),
                          child: Text(
                            'NO ACTIVITY DETECTED',
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        for (final activity in activities.reversed)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: colors.primary),
                              ),
                              color: colors.primary.withValues(alpha: 0.05),
                            ),
                            child: Text(
                              '${activity.label}\n${activity.detail}\n${activity.state.toUpperCase()}',
                              style: const TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 10,
                                height: 1.4,
                              ),
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

class _ClassicEnvironmentPanel extends StatelessWidget {
  const _ClassicEnvironmentPanel({
    required this.workspaceSelected,
    required this.workspaceTrusted,
    required this.providerConfigured,
    required this.gitStatus,
    required this.changes,
    required this.activities,
    required this.terminalBusy,
    required this.sources,
    required this.onChooseWorkspace,
    required this.onTrustWorkspace,
    required this.onConfigureProvider,
    required this.onAddSource,
    required this.onChanges,
    required this.onGit,
  });

  final bool workspaceSelected;
  final bool workspaceTrusted;
  final bool providerConfigured;
  final GitStatus gitStatus;
  final WorkspaceTurnChanges? changes;
  final List<_AgentActivity> activities;
  final bool terminalBusy;
  final List<String> sources;
  final VoidCallback onChooseWorkspace;
  final VoidCallback onTrustWorkspace;
  final VoidCallback onConfigureProvider;
  final VoidCallback onAddSource;
  final VoidCallback onChanges;
  final VoidCallback onGit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final files = changes?.files ?? const <WorkspaceFileChange>[];
    final running = activities.where((item) => item.running).toList();
    final processCount = running.length + (terminalBusy ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 0),
      child: Material(
        key: const ValueKey('classic-environment-panel'),
        color: Color.alphaBlend(
          colors.onSurface.withValues(alpha: 0.035),
          colors.surface,
        ),
        elevation: 14,
        shadowColor: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('environment-summary-card'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _EnvironmentDetailsDialog(
              gitStatus: gitStatus,
              changes: changes,
              activities: activities,
              terminalBusy: terminalBusy,
              sources: sources,
              onAddSource: onAddSource,
              onChanges: onChanges,
              onGit: onGit,
            ),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ENVIRONMENT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (workspaceSelected)
                      IconButton(
                        key: const ValueKey('environment-add-source'),
                        tooltip: 'Tambah source',
                        onPressed: onAddSource,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    const Icon(Icons.open_in_new, size: 15),
                  ],
                ),
                const SizedBox(height: 12),
                if (!workspaceSelected ||
                    !workspaceTrusted ||
                    !providerConfigured) ...[
                  _EnvironmentSetupBanner(
                    workspaceSelected: workspaceSelected,
                    workspaceTrusted: workspaceTrusted,
                    providerConfigured: providerConfigured,
                    onTrustWorkspace: onTrustWorkspace,
                    onConfigureProvider: onConfigureProvider,
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _EnvironmentMetric(
                        icon: Icons.difference_outlined,
                        label: 'Changes',
                        value: files.isEmpty ? '0' : '${files.length}',
                        onTap: files.isEmpty ? onGit : onChanges,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _EnvironmentMetric(
                        icon: Icons.terminal_outlined,
                        label: 'Processes',
                        value: '$processCount',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _EnvironmentMetric(
                        icon: Icons.attach_file,
                        label: 'Sources',
                        value: '${sources.length}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      gitStatus.dirty
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      size: 16,
                      color: gitStatus.dirty ? colors.tertiary : colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        !workspaceSelected
                            ? 'Workspace belum dipilih'
                            : !gitStatus.isRepository
                            ? 'Workspace belum memakai Git'
                            : gitStatus.branch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      !workspaceSelected
                          ? 'Setup'
                          : !gitStatus.isRepository
                          ? 'No Git'
                          : gitStatus.dirty
                          ? 'Modified'
                          : 'Clean',
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        color: gitStatus.dirty
                            ? colors.tertiary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  workspaceSelected
                      ? 'Klik untuk membuka detail workspace'
                      : 'Mulai dari memilih workspace proyek',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (workspaceSelected && (files.isNotEmpty || gitStatus.dirty))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('environment-review-changes'),
                        onPressed: files.isNotEmpty ? onChanges : onGit,
                        icon: Icon(
                          files.isNotEmpty
                              ? Icons.rate_review_outlined
                              : Icons.account_tree_outlined,
                          size: 16,
                        ),
                        label: Text(
                          files.isNotEmpty
                              ? 'REVIEW CHANGES'
                              : 'OPEN GIT CENTER',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnvironmentSetupBanner extends StatelessWidget {
  const _EnvironmentSetupBanner({
    required this.workspaceSelected,
    required this.workspaceTrusted,
    required this.providerConfigured,
    required this.onTrustWorkspace,
    required this.onConfigureProvider,
  });

  final bool workspaceSelected;
  final bool workspaceTrusted;
  final bool providerConfigured;
  final VoidCallback onTrustWorkspace;
  final VoidCallback onConfigureProvider;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, title, detail, action, onPressed) = !workspaceSelected
        ? (
            Icons.folder_open_outlined,
            'Workspace belum dipilih',
            'Gunakan tombol utama di tengah atau sidebar untuk membuka proyek.',
            null,
            null,
          )
        : !workspaceTrusted
        ? (
            Icons.shield_outlined,
            'Restricted Mode aktif',
            'Trust workspace untuk mengaktifkan edit, terminal, add-on, dan MCP.',
            'TRUST',
            onTrustWorkspace,
          )
        : (
            Icons.psychology_outlined,
            'Model belum dikonfigurasi',
            'Tambahkan provider dan model sebelum menjalankan tugas agent.',
            'SETUP',
            onConfigureProvider,
          );
    return Container(
      key: const ValueKey('environment-setup-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.075),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: colors.onSurfaceVariant,
            ),
          ),
          if (action != null && onPressed != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                key: const ValueKey('environment-setup-action'),
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(action),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EnvironmentMetric extends StatelessWidget {
  const _EnvironmentMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.onSurface.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 15, color: colors.primary),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvironmentDetailsDialog extends StatelessWidget {
  const _EnvironmentDetailsDialog({
    required this.gitStatus,
    required this.changes,
    required this.activities,
    required this.terminalBusy,
    required this.sources,
    required this.onAddSource,
    required this.onChanges,
    required this.onGit,
  });

  final GitStatus gitStatus;
  final WorkspaceTurnChanges? changes;
  final List<_AgentActivity> activities;
  final bool terminalBusy;
  final List<String> sources;
  final VoidCallback onAddSource;
  final VoidCallback onChanges;
  final VoidCallback onGit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final files = changes?.files ?? const <WorkspaceFileChange>[];
    var additions = 0;
    var deletions = 0;
    for (final file in files) {
      for (final hunk in file.hunks) {
        additions += hunk.lines.where((line) => line.startsWith('+')).length;
        deletions += hunk.lines.where((line) => line.startsWith('-')).length;
      }
    }
    final running = activities.where((item) => item.running).toList();
    final processCount = running.length + (terminalBusy ? 1 : 0);
    return Dialog(
      key: const ValueKey('environment-details-dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 660),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ENVIRONMENT',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('environment-dialog-add-source'),
                      tooltip: 'Tambah source',
                      onPressed: onAddSource,
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  children: [
                    _EnvironmentRow(
                      key: const ValueKey('environment-changes'),
                      icon: Icons.difference_outlined,
                      label: 'Changes',
                      trailing: files.isEmpty
                          ? '0'
                          : '${files.length}  +$additions  -$deletions',
                      onTap: files.isEmpty ? onGit : onChanges,
                    ),
                    _EnvironmentRow(
                      icon: Icons.computer_outlined,
                      label: 'Local',
                      trailing: gitStatus.dirty ? 'Modified' : 'Clean',
                    ),
                    _EnvironmentRow(
                      key: const ValueKey('environment-branch'),
                      icon: Icons.account_tree_outlined,
                      label: gitStatus.branch.isEmpty
                          ? 'No branch'
                          : gitStatus.branch,
                      trailing: gitStatus.mainBranch ? 'main' : null,
                      onTap: onGit,
                    ),
                    _EnvironmentRow(
                      key: const ValueKey('environment-commit-push'),
                      icon: Icons.commit_outlined,
                      label: 'Commit or push',
                      muted: !gitStatus.isRepository,
                      onTap: onGit,
                    ),
                    _EnvironmentRow(
                      key: const ValueKey('environment-compare-branch'),
                      icon: Icons.compare_arrows_outlined,
                      label: 'Compare branch',
                      onTap: onGit,
                    ),
                    const SizedBox(height: 12),
                    _EnvironmentSectionHeader(
                      label: 'BACKGROUND PROCESSES',
                      count: processCount,
                    ),
                    if (processCount == 0)
                      const _EnvironmentEmpty('Tidak ada proses aktif')
                    else ...[
                      for (final activity in running.take(4))
                        _EnvironmentRow(
                          icon: Icons.terminal_outlined,
                          label: activity.label,
                          trailing: 'Running',
                        ),
                      if (terminalBusy)
                        const _EnvironmentRow(
                          icon: Icons.terminal,
                          label: 'Terminal command',
                          trailing: 'Running',
                        ),
                    ],
                    const SizedBox(height: 12),
                    _EnvironmentSectionHeader(
                      label: 'SOURCES',
                      count: sources.length,
                    ),
                    if (sources.isEmpty)
                      const _EnvironmentEmpty('Belum ada source terlampir')
                    else
                      for (final source in sources)
                        _EnvironmentRow(
                          icon: Icons.insert_drive_file_outlined,
                          label: source.replaceAll('\\', '/').split('/').last,
                          trailing: 'Attached',
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvironmentSectionHeader extends StatelessWidget {
  const _EnvironmentSectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text('$count', style: const TextStyle(fontSize: 10)),
      ],
    ),
  );
}

class _EnvironmentEmpty extends StatelessWidget {
  const _EnvironmentEmpty(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _EnvironmentRow extends StatelessWidget {
  const _EnvironmentRow({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    this.muted = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      minTileHeight: 38,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, size: 17),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: muted ? colors.onSurfaceVariant : null,
        ),
      ),
      trailing: trailing == null
          ? null
          : Text(
              trailing!,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10,
                color: colors.onSurfaceVariant,
              ),
            ),
      onTap: onTap,
    );
  }
}

class _InspectorPlan extends StatelessWidget {
  const _InspectorPlan({required this.activities, required this.busy});

  final List<_AgentActivity> activities;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (activities.isEmpty) {
      return Center(
        child: Text(
          busy ? 'MENYIAPKAN RENCANA...' : 'BELUM ADA RENCANA',
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11,
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }
    return SilkyListView.separated(
      silkyConfig: _silkyScrollConfig,
      padding: const EdgeInsets.all(18),
      itemCount: activities.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final activity = activities[index];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}.',
                style: TextStyle(fontFamily: 'Consolas', color: colors.primary),
              ),
            ),
            Expanded(
              child: Text(
                '${activity.label}\n${activity.detail}',
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InspectorFiles extends StatelessWidget {
  const _InspectorFiles({
    required this.changes,
    required this.history,
    required this.onReview,
    required this.onRestoreCheckpoint,
    this.onRevert,
  });

  final WorkspaceTurnChanges? changes;
  final List<WorkspaceTurnChanges> history;
  final VoidCallback onReview;
  final ValueChanged<WorkspaceTurnChanges> onRestoreCheckpoint;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final files = changes?.files ?? const <WorkspaceFileChange>[];
    return SilkyListView(
      silkyConfig: _silkyScrollConfig,
      padding: const EdgeInsets.all(18),
      children: [
        if (files.isEmpty)
          Text(
            'TIDAK ADA PERUBAHAN TERTUNDA',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 11,
              color: colors.onSurfaceVariant,
            ),
          )
        else ...[
          for (final file in files)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(
                file.status,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
              title: Text(
                file.path,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
              ),
              subtitle: Text('${file.hunks.length} hunk'),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onReview,
            child: const Text('REVIEW CHANGES'),
          ),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            '${history.length} CHECKPOINT TERSIMPAN',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 10,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final turn in history)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                turn.prompt.isEmpty ? 'Agent turn' : turn.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              subtitle: Text(
                '${turn.files.length} file · '
                '${turn.createdAt.toLocal().toString().substring(0, 16)}',
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 10),
              ),
              trailing: IconButton(
                tooltip: 'Restore checkpoint',
                onPressed: () => onRestoreCheckpoint(turn),
                icon: const Icon(Icons.restore, size: 18),
              ),
            ),
        ],
        if (onRevert != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRevert,
            child: const Text('REVERT LAST TURN'),
          ),
        ],
      ],
    );
  }
}

class _ChangesReviewDialog extends StatefulWidget {
  const _ChangesReviewDialog({required this.changes});

  final WorkspaceTurnChanges changes;

  @override
  State<_ChangesReviewDialog> createState() => _ChangesReviewDialogState();
}

class _ChangesReviewDialogState extends State<_ChangesReviewDialog> {
  late final Set<String> _selected = {
    for (final file in widget.changes.files)
      for (final hunk in file.hunks) hunk.id,
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review agent changes'),
    content: SizedBox(
      width: 760,
      child: SilkyListView(
        silkyConfig: _silkyScrollConfig,
        shrinkWrap: true,
        children: [
          for (final file in widget.changes.files) ...[
            Text(
              '${file.status}  ${file.path}',
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final hunk in file.hunks)
              CheckboxListTile(
                value: _selected.contains(hunk.id),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (selected) => setState(() {
                  if (selected == true) {
                    _selected.add(hunk.id);
                  } else {
                    _selected.remove(hunk.id);
                  }
                }),
                title: Text(
                  hunk.unified,
                  maxLines: 12,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('CANCEL'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, <String>{}),
        child: const Text('REJECT ALL'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, Set<String>.of(_selected)),
        child: Text('APPLY ${_selected.length} HUNKS'),
      ),
    ],
  );
}

class _InspectorTab extends StatelessWidget {
  const _InspectorTab({
    required this.label,
    this.active = false,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: active
                ? Border(bottom: BorderSide(color: colors.primary, width: 2))
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: active ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectorMetric extends StatelessWidget {
  const _InspectorMetric({
    required this.label,
    required this.value,
    this.accent = false,
  });
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11,
            color: colors.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11,
            color: accent ? colors.primary : colors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _InspectorHeading extends StatelessWidget {
  const _InspectorHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontFamily: 'Consolas',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _LoadBar extends StatelessWidget {
  const _LoadBar({
    required this.label,
    required this.value,
    this.tertiary = false,
  });
  final String label;
  final double value;
  final bool tertiary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 9),
            ),
            const Spacer(),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 9),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: value,
          minHeight: 2,
          color: tertiary ? colors.tertiary : colors.primary,
          backgroundColor: colors.onSurface.withValues(alpha: 0.12),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.workspace,
    required this.workspaceSelected,
    required this.workspaceTrusted,
    required this.providerConfigured,
    required this.gitStatus,
    required this.pendingChanges,
    required this.lastChange,
    required this.qualityGateResult,
    required this.recentFiles,
    required this.recentWorkspaces,
    required this.onChooseWorkspace,
    required this.onOpenWorkspace,
    required this.onTrustWorkspace,
    required this.onConfigureProvider,
    required this.onOpenHistory,
    required this.onFocusComposer,
    required this.onSuggestion,
    required this.onOpenFile,
    required this.onOpenEditor,
    required this.onGit,
    required this.onReviewChanges,
  });

  final String workspace;
  final bool workspaceSelected;
  final bool workspaceTrusted;
  final bool providerConfigured;
  final GitStatus gitStatus;
  final WorkspaceTurnChanges? pendingChanges;
  final WorkspaceTurnChanges? lastChange;
  final QualityGateResult? qualityGateResult;
  final List<String> recentFiles;
  final List<String> recentWorkspaces;
  final VoidCallback onChooseWorkspace;
  final ValueChanged<String> onOpenWorkspace;
  final VoidCallback onTrustWorkspace;
  final VoidCallback onConfigureProvider;
  final VoidCallback onOpenHistory;
  final VoidCallback onFocusComposer;
  final ValueChanged<String> onSuggestion;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onOpenEditor;
  final VoidCallback onGit;
  final VoidCallback onReviewChanges;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 520;
        final compact = constraints.maxWidth < 620;
        final horizontalPadding = compact ? 20.0 : 32.0;
        final topPadding = short ? 8.0 : 28.0;
        final bottomPadding = short ? 24.0 : 44.0;
        return SilkySingleChildScrollView(
          silkyConfig: _silkyScrollConfig,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 720,
                minHeight: math.max(
                  0,
                  constraints.maxHeight - topPadding - bottomPadding,
                ),
              ),
              child: Column(
                mainAxisAlignment: short
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!short && !workspaceSelected) ...[
                    Opacity(
                      opacity: 0.18,
                      child: Container(
                        width: compact ? 88 : 112,
                        height: compact ? 88 : 112,
                        padding: const EdgeInsets.all(12),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        child: Image.asset(
                          'assets/younzcode_logo_new.png',
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 28),
                  ],
                  Text(
                    workspaceSelected
                        ? 'Workspace overview'
                        : 'What are we building?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: short
                          ? 26
                          : compact
                          ? 27
                          : 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  SizedBox(height: short ? 6 : 12),
                  Text(
                    workspaceSelected
                        ? 'Pantau kondisi proyek, buka file terakhir, atau lanjutkan '
                              'pekerjaan dari satu tempat.'
                        : 'Select a workspace or describe a task to begin. I can help '
                              'with architecture, debugging, or test automation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                      fontSize: short
                          ? 12
                          : compact
                          ? 13
                          : 15,
                    ),
                  ),
                  SizedBox(height: short ? 6 : 18),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: short ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          workspaceSelected
                              ? Icons.check_circle_outline
                              : Icons.folder_open_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          workspaceSelected
                              ? 'WORKSPACE READY'
                              : 'NO WORKSPACE SELECTED',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .6,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: short ? 6 : 10),
                  if (workspaceSelected)
                    _WorkspaceDashboard(
                      workspace: workspace,
                      gitStatus: gitStatus,
                      pendingChanges: pendingChanges,
                      lastChange: lastChange,
                      qualityGateResult: qualityGateResult,
                      recentFiles: recentFiles,
                      onOpenFile: onOpenFile,
                      onOpenEditor: onOpenEditor,
                      onGit: onGit,
                      onHistory: onOpenHistory,
                      onFocusComposer: onFocusComposer,
                      onReviewChanges: onReviewChanges,
                    ),
                  if (!workspaceSelected ||
                      !workspaceTrusted ||
                      !providerConfigured) ...[
                    if (workspaceSelected) SizedBox(height: short ? 6 : 12),
                    _WorkspaceSetupCard(
                      workspaceSelected: workspaceSelected,
                      workspaceTrusted: workspaceTrusted,
                      providerConfigured: providerConfigured,
                      onChooseWorkspace: onChooseWorkspace,
                      onTrustWorkspace: onTrustWorkspace,
                      onConfigureProvider: onConfigureProvider,
                      onFocusComposer: onFocusComposer,
                    ),
                  ],
                  if (!workspaceSelected && recentWorkspaces.isNotEmpty) ...[
                    SizedBox(height: short ? 6 : 24),
                    _RecentWorkspaceStrip(
                      workspaces: recentWorkspaces,
                      onOpen: onOpenWorkspace,
                      onChoose: onChooseWorkspace,
                    ),
                  ] else if (!workspaceSelected && !short) ...[
                    const SizedBox(height: 24),
                    _DashboardActionStrip(
                      onChooseWorkspace: onChooseWorkspace,
                      onHistory: onOpenHistory,
                      onFocusComposer: onFocusComposer,
                    ),
                  ],
                  if (short) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'QUICK START',
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(height: short ? 4 : 8),
                    Wrap(
                      key: const ValueKey('quick-start-compact'),
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _QuickStartChip(
                          icon: Icons.bolt_outlined,
                          label: 'FEATURE',
                          tooltip: 'Generate Feature · Bootstrap new module',
                          onTap: () => onSuggestion(
                            'Buat fitur baru dengan mengikuti pola kode yang sudah ada.',
                          ),
                        ),
                        _QuickStartChip(
                          icon: Icons.bug_report_outlined,
                          label: 'BUG',
                          tooltip: 'Fix Logic Bug · Trace and repair errors',
                          onTap: () => onSuggestion(
                            'Bantu saya menganalisis dan memperbaiki bug pada proyek ini.',
                          ),
                        ),
                        _QuickStartChip(
                          icon: Icons.checklist_rtl_outlined,
                          label: 'TEST',
                          tooltip:
                              'Write Test Suite · Unit & integration coverage',
                          onTap: () => onSuggestion(
                            'Jalankan semua test dan perbaiki kegagalan yang ditemukan.',
                          ),
                        ),
                        _QuickStartChip(
                          icon: Icons.menu_book_outlined,
                          label: 'EXPLAIN',
                          tooltip: 'Explain Codebase · Analyze relationships',
                          onTap: () => onSuggestion(
                            'Jelaskan arsitektur proyek ini dan modul-modul utamanya.',
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    SizedBox(height: compact ? 22 : 28),
                    Row(
                      children: [
                        Text(
                          'QUICK START',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'KLIK ATAU TEKAN ENTER',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 9,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: compact ? 1 : 2,
                      mainAxisExtent: compact ? 88 : 96,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _SuggestionCard(
                          icon: Icons.bolt_outlined,
                          title: 'Generate Feature',
                          subtitle: 'Bootstrap new module',
                          badge: 'RECOMMENDED',
                          shortcut: 'Ctrl+Enter',
                          onTap: () => onSuggestion(
                            'Buat fitur baru dengan mengikuti pola kode yang sudah ada.',
                          ),
                        ),
                        _SuggestionCard(
                          icon: Icons.bug_report_outlined,
                          title: 'Fix Logic Bug',
                          subtitle: 'Trace and repair errors',
                          shortcut: 'Ctrl+B',
                          onTap: () => onSuggestion(
                            'Bantu saya menganalisis dan memperbaiki bug pada proyek ini.',
                          ),
                        ),
                        _SuggestionCard(
                          icon: Icons.checklist_rtl_outlined,
                          title: 'Write Test Suite',
                          subtitle: 'Unit & integration coverage',
                          shortcut: 'Ctrl+T',
                          onTap: () => onSuggestion(
                            'Jalankan semua test dan perbaiki kegagalan yang ditemukan.',
                          ),
                        ),
                        _SuggestionCard(
                          icon: Icons.menu_book_outlined,
                          title: 'Explain Codebase',
                          subtitle: 'Analyze relationships',
                          shortcut: 'Ctrl+E',
                          onTap: () => onSuggestion(
                            'Jelaskan arsitektur proyek ini dan modul-modul utamanya.',
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: short ? 20 : 28),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceDashboard extends StatelessWidget {
  const _WorkspaceDashboard({
    required this.workspace,
    required this.gitStatus,
    required this.pendingChanges,
    required this.lastChange,
    required this.qualityGateResult,
    required this.recentFiles,
    required this.onOpenFile,
    required this.onOpenEditor,
    required this.onGit,
    required this.onHistory,
    required this.onFocusComposer,
    required this.onReviewChanges,
  });

  final String workspace;
  final GitStatus gitStatus;
  final WorkspaceTurnChanges? pendingChanges;
  final WorkspaceTurnChanges? lastChange;
  final QualityGateResult? qualityGateResult;
  final List<String> recentFiles;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onOpenEditor;
  final VoidCallback onGit;
  final VoidCallback onHistory;
  final VoidCallback onFocusComposer;
  final VoidCallback onReviewChanges;

  String _relativePath(String filePath) {
    final normalizedWorkspace = workspace.replaceAll('\\', '/');
    final normalizedFile = filePath.replaceAll('\\', '/');
    if (normalizedFile.startsWith('$normalizedWorkspace/')) {
      return normalizedFile.substring(normalizedWorkspace.length + 1);
    }
    return normalizedFile.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final folder = workspace.replaceAll('\\', '/').split('/').last;
    final changedFiles = gitStatus.entries.length;
    final quality = qualityGateResult == null
        ? (
            'Belum diuji',
            Icons.hourglass_empty_outlined,
            colors.onSurfaceVariant,
          )
        : qualityGateResult!.skipped
        ? (
            'Tidak ada check',
            Icons.remove_circle_outline,
            colors.onSurfaceVariant,
          )
        : qualityGateResult!.passed
        ? (
            '${qualityGateResult!.checks.length} lulus',
            Icons.check_circle_outline,
            colors.primary,
          )
        : (
            '${qualityGateResult!.checks.where((check) => !check.passed).length} gagal',
            Icons.error_outline,
            colors.error,
          );
    final latestChange = pendingChanges ?? lastChange;
    final latestChangeLabel = pendingChanges != null
        ? 'MENUNGGU REVIEW'
        : lastChange == null
        ? 'BELUM ADA PERUBAHAN AGENT'
        : 'TERAKHIR DITERAPKAN';

    return Container(
      key: const ValueKey('workspace-dashboard'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.055),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.folder_special_outlined,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.isEmpty ? 'Workspace aktif' : folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      workspace,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _WorkspaceStatusPill(
                label: gitStatus.isRepository
                    ? (gitStatus.branch.isEmpty ? 'DETACHED' : gitStatus.branch)
                    : 'NO GIT',
                icon: Icons.account_tree_outlined,
                color: gitStatus.isRepository
                    ? colors.primary
                    : colors.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 560 ? 1 : 3;
              final tileWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _WorkspaceMetric(
                      icon: Icons.difference_outlined,
                      label: 'PERUBAHAN GIT',
                      value: changedFiles == 0
                          ? 'Bersih'
                          : '$changedFiles file',
                      color: changedFiles == 0
                          ? colors.primary
                          : colors.tertiary,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _WorkspaceMetric(
                      icon: quality.$2,
                      label: 'QUALITY GATE',
                      value: quality.$1,
                      color: quality.$3,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _WorkspaceMetric(
                      icon: Icons.auto_awesome_outlined,
                      label: 'TASK AGENT',
                      value: latestChange == null
                          ? 'Belum ada'
                          : '${latestChange.files.length} file',
                      color: latestChange == null
                          ? colors.onSurfaceVariant
                          : colors.primary,
                    ),
                  ),
                ],
              );
            },
          ),
          if (latestChange != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.76),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Icon(
                    pendingChanges != null
                        ? Icons.rate_review_outlined
                        : Icons.history_toggle_off_outlined,
                    size: 17,
                    color: pendingChanges != null
                        ? colors.tertiary
                        : colors.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latestChangeLabel,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: pendingChanges != null
                                ? colors.tertiary
                                : colors.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          latestChange.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '+${latestChange.additions}  -${latestChange.deletions}  ·  ${latestChange.files.length} file',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 9,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pendingChanges != null)
                    IconButton(
                      key: const ValueKey('dashboard-review-changes'),
                      tooltip: 'Review changes',
                      onPressed: onReviewChanges,
                      icon: const Icon(Icons.chevron_right),
                    ),
                ],
              ),
            ),
          ],
          if (recentFiles.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'FILE TERBARU',
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onOpenEditor,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('OPEN EDITOR'),
                ),
              ],
            ),
            ...recentFiles
                .take(3)
                .map(
                  (file) => ListTile(
                    key: ValueKey('dashboard-recent-file-$file'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.description_outlined,
                      size: 17,
                      color: colors.primary,
                    ),
                    title: Text(
                      _relativePath(file),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                      ),
                    ),
                    onTap: () => onOpenFile(file),
                    trailing: const Icon(Icons.chevron_right, size: 17),
                  ),
                ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onFocusComposer,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('TULIS TASK'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('dashboard-open-git'),
                onPressed: onGit,
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                label: const Text('GIT CENTER'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              TextButton.icon(
                onPressed: onHistory,
                icon: const Icon(Icons.history, size: 16),
                label: const Text('HISTORY'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkspaceMetric extends StatelessWidget {
  const _WorkspaceMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _WorkspaceStatusPill extends StatelessWidget {
  const _WorkspaceStatusPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 140),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RecentWorkspaceStrip extends StatelessWidget {
  const _RecentWorkspaceStrip({
    required this.workspaces,
    required this.onOpen,
    required this.onChoose,
  });

  final List<String> workspaces;
  final ValueChanged<String> onOpen;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('recent-workspaces-strip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RECENT WORKSPACES',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: colors.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              key: const ValueKey('dashboard-choose-workspace'),
              onPressed: onChoose,
              icon: const Icon(Icons.add, size: 15),
              label: const Text('WORKSPACE BARU'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final workspace in workspaces.take(3))
              _RecentWorkspaceCard(
                workspace: workspace,
                onTap: () => onOpen(workspace),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecentWorkspaceCard extends StatelessWidget {
  const _RecentWorkspaceCard({required this.workspace, required this.onTap});

  final String workspace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final folder = path.basename(workspace);
    return SizedBox(
      width: 214,
      child: Material(
        color: colors.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: ValueKey('recent-workspace-${workspace.replaceAll('\\', '/')}'),
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 17,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.isEmpty ? workspace : folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        workspace,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 9,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardActionStrip extends StatelessWidget {
  const _DashboardActionStrip({
    required this.onChooseWorkspace,
    required this.onHistory,
    required this.onFocusComposer,
  });

  final VoidCallback onChooseWorkspace;
  final VoidCallback onHistory;
  final VoidCallback onFocusComposer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('dashboard-action-strip'),
      children: [
        Expanded(
          child: _DashboardAction(
            icon: Icons.folder_open_outlined,
            label: 'BUKA WORKSPACE',
            detail: 'Pilih folder proyek',
            onTap: onChooseWorkspace,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DashboardAction(
            icon: Icons.history,
            label: 'CHAT HISTORY',
            detail: 'Buka percakapan tersimpan',
            onTap: onHistory,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DashboardAction(
            icon: Icons.edit_outlined,
            label: 'MULAI MENULIS',
            detail: 'Fokus ke composer',
            onTap: onFocusComposer,
            accent: colors.primary,
          ),
        ),
      ],
    );
  }
}

class _DashboardAction extends StatelessWidget {
  const _DashboardAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = accent ?? colors.onSurfaceVariant;
    return Material(
      color: colors.onSurface.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSetupCard extends StatelessWidget {
  const _WorkspaceSetupCard({
    required this.workspaceSelected,
    required this.workspaceTrusted,
    required this.providerConfigured,
    required this.onChooseWorkspace,
    required this.onTrustWorkspace,
    required this.onConfigureProvider,
    required this.onFocusComposer,
  });

  final bool workspaceSelected;
  final bool workspaceTrusted;
  final bool providerConfigured;
  final VoidCallback onChooseWorkspace;
  final VoidCallback onTrustWorkspace;
  final VoidCallback onConfigureProvider;
  final VoidCallback onFocusComposer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = [
      workspaceSelected,
      workspaceSelected && workspaceTrusted,
      providerConfigured,
    ].where((value) => value).length;
    final ready = workspaceSelected && workspaceTrusted && providerConfigured;
    final actionLabel = !workspaceSelected
        ? 'PILIH WORKSPACE'
        : !workspaceTrusted
        ? 'TRUST WORKSPACE'
        : !providerConfigured
        ? 'ATUR MODEL'
        : 'MULAI MENULIS';
    final actionIcon = !workspaceSelected
        ? Icons.folder_open_outlined
        : !workspaceTrusted
        ? Icons.shield_outlined
        : !providerConfigured
        ? Icons.psychology_outlined
        : Icons.edit_outlined;
    final action = !workspaceSelected
        ? onChooseWorkspace
        : !workspaceTrusted
        ? onTrustWorkspace
        : !providerConfigured
        ? onConfigureProvider
        : onFocusComposer;
    return Container(
      key: const ValueKey('workspace-setup-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.035),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.09)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                ready ? 'SIAP MEMULAI' : 'SETUP WORKSPACE',
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              const Spacer(),
              Text(
                '$completed/3 SIAP',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 10,
                  color: ready ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _WorkspaceSetupStep(
            number: 1,
            title: 'Pilih workspace proyek',
            complete: workspaceSelected,
          ),
          _WorkspaceSetupStep(
            number: 2,
            title: 'Trust workspace',
            complete: workspaceSelected && workspaceTrusted,
            enabled: workspaceSelected,
          ),
          _WorkspaceSetupStep(
            number: 3,
            title: 'Konfigurasi provider dan model',
            complete: providerConfigured,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: ValueKey(
                !workspaceSelected
                    ? 'empty-choose-workspace'
                    : !workspaceTrusted
                    ? 'empty-trust-workspace'
                    : !providerConfigured
                    ? 'empty-configure-provider'
                    : 'empty-focus-composer',
              ),
              onPressed: action,
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSetupStep extends StatelessWidget {
  const _WorkspaceSetupStep({
    required this.number,
    required this.title,
    required this.complete,
    this.enabled = true,
  });

  final int number;
  final String title;
  final bool complete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = complete
        ? colors.primary
        : enabled
        ? colors.onSurfaceVariant
        : colors.onSurfaceVariant.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          AnimatedContainer(
            duration: _fastMotion,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: complete
                  ? colors.primary.withValues(alpha: 0.13)
                  : Colors.transparent,
              border: Border.all(color: color.withValues(alpha: 0.55)),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: complete
                ? Icon(Icons.check, size: 15, color: colors.primary)
                : Text(
                    '$number',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: complete ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            complete
                ? 'SELESAI'
                : enabled
                ? 'BERIKUTNYA'
                : 'TERKUNCI',
            style: TextStyle(fontFamily: 'Consolas', fontSize: 9, color: color),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({super.key, required this.entry});

  final ChatEntry entry;

  Future<void> _copyResponse(BuildContext context, String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Respons disalin.'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = entry.role == ChatRole.user;
    final error = entry.role == ChatRole.error;
    final progress = entry.role == ChatRole.tool;
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final displayedContent = user
        ? entry.content
        : formatAgentResponse(entry.content);
    return TweenAnimationBuilder<double>(
      duration: _mediumMotion,
      curve: _motionCurve,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset((user ? 12 : -12) * (1 - value), 6 * (1 - value)),
          child: child,
        ),
      ),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          key: ValueKey(user ? 'user-message-card' : 'agent-message-card'),
          constraints: const BoxConstraints(maxWidth: 760),
          margin: const EdgeInsets.only(bottom: 18),
          padding: EdgeInsets.all(progress ? 12 : 16),
          decoration: BoxDecoration(
            color: user
                ? theme.colorScheme.primary.withValues(
                    alpha: light ? 0.07 : 0.13,
                  )
                : progress
                ? theme.colorScheme.primary.withValues(alpha: 0.045)
                : theme.colorScheme.surface,
            border: Border.all(
              color: error
                  ? Theme.of(context).colorScheme.error
                  : progress
                  ? theme.colorScheme.primary.withValues(alpha: 0.24)
                  : theme.dividerColor,
            ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(user ? 12 : 3),
              bottomRight: Radius.circular(user ? 3 : 12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: user
                          ? theme.colorScheme.primary.withValues(alpha: 0.14)
                          : theme.colorScheme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      user ? Icons.person_outline : Icons.auto_awesome,
                      size: 13,
                      color: user
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    user
                        ? 'YOU'
                        : error
                        ? 'ERROR'
                        : progress
                        ? 'PROGRESS'
                        : 'AGENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: error
                          ? Theme.of(context).colorScheme.error
                          : user
                          ? theme.colorScheme.onSurfaceVariant
                          : progress
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                  ),
                  if (!user && !progress) ...[
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('copy-agent-response'),
                      tooltip: 'Salin respons',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () => _copyResponse(context, displayedContent),
                      icon: const Icon(Icons.copy_all_outlined),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              user
                  ? SelectableText(
                      displayedContent,
                      style: const TextStyle(height: 1.55, fontSize: 13.5),
                    )
                  : _AgentResponseContent(content: displayedContent),
              if (!user && !progress) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('copy-agent-response-bottom'),
                    onPressed: () => _copyResponse(context, displayedContent),
                    icon: const Icon(Icons.copy_all_outlined, size: 15),
                    label: const Text('COPY RESPONSE'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentResponseContent extends StatelessWidget {
  const _AgentResponseContent({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    final fence = RegExp(r'```([^\n]*)\n([\s\S]*?)```');
    var cursor = 0;
    for (final match in fence.allMatches(content)) {
      if (match.start > cursor) {
        parts.add(
          SelectableText(
            content.substring(cursor, match.start),
            style: const TextStyle(height: 1.65, fontSize: 14),
          ),
        );
      }
      parts.add(
        _ResponseCodeBlock(
          language: match.group(1)?.trim() ?? '',
          code: match.group(2) ?? '',
        ),
      );
      cursor = match.end;
    }
    if (cursor < content.length || parts.isEmpty) {
      parts.add(
        SelectableText(
          content.substring(cursor),
          style: const TextStyle(height: 1.65, fontSize: 14),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < parts.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          parts[index],
        ],
      ],
    );
  }
}

class _ResponseCodeBlock extends StatelessWidget {
  const _ResponseCodeBlock({required this.language, required this.code});

  final String language;
  final String code;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Kode disalin.'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('response-code-block'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.055),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: colors.onSurface.withValues(alpha: 0.06),
            child: Row(
              children: [
                Icon(Icons.code, size: 14, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    language.isEmpty ? 'CODE' : language.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('copy-response-code'),
                  tooltip: 'Salin kode',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_outlined, size: 14),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SelectableText(
              code.trimRight(),
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                height: 1.55,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationLane extends StatelessWidget {
  const _ConversationLane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1040),
      child: child,
    ),
  );
}

class _GoalBanner extends StatelessWidget {
  const _GoalBanner({
    required this.goal,
    required this.busy,
    required this.onResume,
    required this.onPause,
    required this.onClear,
  });

  final AgentGoal goal;
  final bool busy;
  final VoidCallback onResume;
  final VoidCallback onPause;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (goal.status) {
      AgentGoalStatus.active => colors.primary,
      AgentGoalStatus.completed => const Color(0xFF2F9E69),
      AgentGoalStatus.blocked => colors.error,
      AgentGoalStatus.paused => const Color(0xFFB7862A),
      AgentGoalStatus.stopped => colors.onSurfaceVariant,
    };
    return Container(
      key: const ValueKey('goal-banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(color: color.withValues(alpha: 0.22)),
          bottom: BorderSide(color: color.withValues(alpha: 0.22)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GOAL ${goal.status.name.toUpperCase()} · '
                  '${goal.turnCount} TURN',
                  key: const ValueKey('goal-status'),
                  style: TextStyle(
                    color: color,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  goal.objective,
                  key: const ValueKey('goal-objective'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (goal.status == AgentGoalStatus.active)
            TextButton(
              key: const ValueKey('goal-pause'),
              onPressed: onPause,
              child: Text(busy ? 'STOP' : 'PAUSE'),
            )
          else if (goal.canResume)
            TextButton(
              key: const ValueKey('goal-resume'),
              onPressed: busy ? null : onResume,
              child: const Text('RESUME'),
            ),
          IconButton(
            key: const ValueKey('goal-clear'),
            tooltip: 'Clear goal',
            onPressed: busy ? null : onClear,
            icon: const Icon(Icons.close, size: 17),
          ),
        ],
      ),
    );
  }
}

class _ModelBar extends StatelessWidget {
  const _ModelBar({
    required this.models,
    required this.selectedModel,
    required this.favoriteModel,
    required this.busy,
    required this.planMode,
    required this.onSelected,
    required this.onManage,
    required this.onPlanModeChanged,
  });

  final List<String> models;
  final String selectedModel;
  final String favoriteModel;
  final bool busy;
  final bool planMode;
  final ValueChanged<String> onSelected;
  final VoidCallback onManage;
  final ValueChanged<bool> onPlanModeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasFavoriteModel =
        favoriteModel.isNotEmpty && models.contains(favoriteModel);
    final orderedModels = [
      if (hasFavoriteModel) favoriteModel,
      for (final model in models)
        if (model != favoriteModel) model,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final modelControls = Row(
          children: [
            Expanded(
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.06),
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 15,
                      color: colors.onSurface,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const ValueKey('model-selector'),
                          value: selectedModel,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: colors.surface,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                            color: colors.onSurface,
                          ),
                          onChanged: busy
                              ? null
                              : (value) {
                                  if (value != null) onSelected(value);
                                },
                          items: [
                            for (final model in orderedModels)
                              DropdownMenuItem(
                                value: model,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        model,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (model == favoriteModel) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.star_rounded,
                                        key: const ValueKey(
                                          'favorite-model-indicator',
                                        ),
                                        size: 15,
                                        color: colors.primary,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (compact)
              SizedBox.square(
                dimension: 32,
                child: IconButton(
                  key: const ValueKey('manage-models-compact'),
                  tooltip: 'Manage models',
                  padding: EdgeInsets.zero,
                  onPressed: busy ? null : onManage,
                  icon: const Icon(Icons.description_outlined, size: 18),
                ),
              )
            else
              TextButton.icon(
                onPressed: busy ? null : onManage,
                icon: const Icon(Icons.description_outlined, size: 15),
                label: const Text('MANAGE MODELS'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        );
        final planControl = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              key: const ValueKey('agent-mode-selector'),
              value: planMode,
              onChanged: busy ? null : onPlanModeChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 6),
            Text(
              'Plan Mode',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        );
        return Container(
          height: compact ? 96 : 44,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
          decoration: BoxDecoration(color: colors.surface),
          child: compact
              ? Column(
                  children: [
                    SizedBox(width: double.infinity, child: modelControls),
                    const Spacer(),
                    Align(alignment: Alignment.centerRight, child: planControl),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: modelControls),
                    const SizedBox(width: 12),
                    planControl,
                  ],
                ),
        );
      },
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.density,
    required this.onDensityChanged,
    required this.workspaceSelected,
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.planMode,
    required this.onPlanModeChanged,
    required this.contextFiles,
    required this.fileSuggestions,
    required this.onAttachContext,
    required this.onRemoveContext,
    required this.onClearContext,
    required this.onPromptTemplates,
    required this.onPromptHistory,
    required this.onPasteCode,
    required this.onSelectFileSuggestion,
    required this.onDropFiles,
    required this.slashCommands,
    required this.onSlashCommand,
    required this.onOpenCommandPalette,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final _ComposerDensity density;
  final ValueChanged<_ComposerDensity> onDensityChanged;
  final bool workspaceSelected;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool planMode;
  final ValueChanged<bool> onPlanModeChanged;
  final List<String> contextFiles;
  final List<String> fileSuggestions;
  final VoidCallback onAttachContext;
  final ValueChanged<String> onRemoveContext;
  final VoidCallback onClearContext;
  final VoidCallback onPromptTemplates;
  final VoidCallback onPromptHistory;
  final VoidCallback onPasteCode;
  final ValueChanged<String> onSelectFileSuggestion;
  final ValueChanged<List<String>> onDropFiles;
  final List<_SlashCommand> slashCommands;
  final Future<void> Function(String command) onSlashCommand;
  final VoidCallback onOpenCommandPalette;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hasText = false;
  bool _focused = false;
  bool _dragging = false;
  List<_SlashCommand> _matchingCommands = const [];
  List<String> _matchingFiles = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncText);
    widget.focusNode.addListener(_syncFocus);
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncText);
      widget.controller.addListener(_syncText);
      _syncText();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_syncFocus);
      widget.focusNode.addListener(_syncFocus);
      _syncFocus();
    }
    if (oldWidget.fileSuggestions != widget.fileSuggestions) _syncText();
  }

  void _syncFocus() {
    if (mounted && _focused != widget.focusNode.hasFocus) {
      setState(() => _focused = widget.focusNode.hasFocus);
    }
  }

  void _syncText() {
    final text = widget.controller.text.trim();
    final hasText = text.isNotEmpty;
    final matchingCommands = text.startsWith('/') && !text.contains(' ')
        ? widget.slashCommands
              .where((item) => item.command.startsWith(text.toLowerCase()))
              .toList()
        : const <_SlashCommand>[];
    final cursor = widget.controller.selection.isValid
        ? widget.controller.selection.baseOffset
        : widget.controller.text.length;
    final prefix = widget.controller.text.substring(
      0,
      cursor.clamp(0, widget.controller.text.length),
    );
    final mention = RegExp(r'@([^\s]*)$').firstMatch(prefix);
    final mentionQuery = mention?.group(1)?.toLowerCase() ?? '';
    final matchingFiles = mention == null
        ? const <String>[]
        : widget.fileSuggestions
              .where(
                (file) => file
                    .replaceAll('\\', '/')
                    .toLowerCase()
                    .contains(mentionQuery),
              )
              .take(8)
              .toList();
    if (mounted) {
      setState(() {
        _hasText = hasText;
        _matchingCommands = matchingCommands;
        _matchingFiles = matchingFiles;
      });
    }
  }

  Future<void> _selectCommand(_SlashCommand command) async {
    widget.controller.clear();
    await widget.onSlashCommand(command.command);
  }

  void _prepareCommand(String command) {
    widget.controller.text = command;
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    widget.focusNode.requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncText);
    widget.focusNode.removeListener(_syncFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compactDensity = widget.density == _ComposerDensity.compact;
    final statusButtonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 24),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        widget.onDropFiles(detail.files.map((file) => file.path).toList());
      },
      child: AnimatedContainer(
        duration: _fastMotion,
        curve: _motionCurve,
        padding: EdgeInsets.fromLTRB(
          compactDensity ? 16 : 20,
          0,
          compactDensity ? 16 : 20,
          compactDensity ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          boxShadow: _focused || _dragging
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(
                      alpha: _dragging ? 0.18 : 0.10,
                    ),
                    blurRadius: _dragging ? 20 : 14,
                    spreadRadius: _dragging ? 1 : 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_dragging)
              Container(
                key: const ValueKey('composer-drop-banner'),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.13),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.workspaceSelected
                          ? Icons.file_download_outlined
                          : Icons.folder_open_outlined,
                      size: 24,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.workspaceSelected
                            ? 'LEPASKAN FILE UNTUK MENAMBAHKAN CONTEXT'
                            : 'PILIH WORKSPACE SEBELUM MENAMBAHKAN CONTEXT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_matchingCommands.isNotEmpty)
              Container(
                key: const ValueKey('slash-command-menu'),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height >= 700
                      ? 440
                      : 280,
                ),
                margin: const EdgeInsets.only(bottom: 6),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: SilkySingleChildScrollView(
                    silkyConfig: _silkyScrollConfig,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 480 ? 2 : 1;
                        final itemWidth = constraints.maxWidth / columns;
                        return Wrap(
                          children: [
                            for (final command in _matchingCommands)
                              SizedBox(
                                width: itemWidth,
                                child: ListTile(
                                  key: ValueKey(
                                    'slash-command-${command.command.substring(1)}',
                                  ),
                                  dense: true,
                                  minTileHeight: 52,
                                  visualDensity: VisualDensity.compact,
                                  leading: Icon(
                                    command.icon,
                                    size: 17,
                                    color: colors.primary,
                                  ),
                                  title: Text(
                                    command.command,
                                    style: const TextStyle(
                                      fontFamily: 'Consolas',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    command.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: widget.busy
                                      ? null
                                      : () => _selectCommand(command),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            if (_matchingFiles.isNotEmpty)
              Container(
                key: const ValueKey('composer-file-mention-menu'),
                constraints: const BoxConstraints(maxHeight: 240),
                margin: const EdgeInsets.only(bottom: 6),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: SilkyListView.builder(
                    silkyConfig: _silkyScrollConfig,
                    shrinkWrap: true,
                    itemCount: _matchingFiles.length,
                    itemBuilder: (context, index) {
                      final file = _matchingFiles[index];
                      return ListTile(
                        key: ValueKey('composer-file-suggestion-$index'),
                        dense: true,
                        leading: Icon(
                          Icons.insert_drive_file_outlined,
                          size: 17,
                          color: colors.primary,
                        ),
                        title: Text(
                          file.replaceAll('\\', '/').split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                          ),
                        ),
                        subtitle: Text(
                          file,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: widget.busy
                            ? null
                            : () => widget.onSelectFileSuggestion(file),
                      );
                    },
                  ),
                ),
              ),
            if (widget.contextFiles.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    '${widget.contextFiles.length} files · ~${_estimatedTokens()} tokens',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 10,
                      color: colors.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('clear-context'),
                    onPressed: widget.busy ? null : widget.onClearContext,
                    child: const Text('CLEAR CONTEXT'),
                  ),
                ],
              ),
              SizedBox(
                height: 34,
                child: SilkyListView.separated(
                  silkyConfig: _silkyHorizontalScrollConfig,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.contextFiles.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final file = widget.contextFiles[index];
                    return Tooltip(
                      message: file,
                      child: InputChip(
                        avatar: Icon(
                          Icons.insert_drive_file_outlined,
                          size: 14,
                          color: colors.primary,
                        ),
                        label: Text(
                          '${file.replaceAll('\\', '/').split('/').last} · '
                          '${_fileSizeLabel(file)}',
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                          ),
                        ),
                        backgroundColor: colors.primary.withValues(alpha: 0.06),
                        side: BorderSide(
                          color: colors.primary.withValues(alpha: 0.18),
                        ),
                        onDeleted: widget.busy
                            ? null
                            : () => widget.onRemoveContext(file),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
            ],
            Wrap(
              key: const ValueKey('composer-shortcuts'),
              spacing: 6,
              runSpacing: 4,
              children: [
                _ComposerShortcut(
                  key: const ValueKey('composer-templates'),
                  label: 'TEMPLATES',
                  tooltip: 'Pilih template prompt',
                  onTap: widget.busy ? null : widget.onPromptTemplates,
                ),
                _ComposerShortcut(
                  key: const ValueKey('composer-history'),
                  label: 'HISTORY',
                  tooltip: 'Gunakan kembali prompt sebelumnya',
                  onTap: widget.busy ? null : widget.onPromptHistory,
                ),
                _ComposerShortcut(
                  key: const ValueKey('composer-paste-code'),
                  label: 'PASTE CODE',
                  tooltip: 'Tempel clipboard sebagai code block',
                  onTap: widget.busy ? null : widget.onPasteCode,
                ),
                _ComposerShortcut(
                  label: 'Ctrl+K',
                  tooltip: 'Buka command palette',
                  onTap: widget.busy ? null : widget.onOpenCommandPalette,
                ),
                _ComposerShortcut(
                  label: '/review',
                  tooltip: 'Siapkan review Git diff',
                  onTap: widget.busy ? null : () => _prepareCommand('/review'),
                ),
                _ComposerShortcut(
                  label: '/retry',
                  tooltip: 'Siapkan prompt terakhir untuk ditinjau',
                  onTap: widget.busy ? null : () => _prepareCommand('/retry'),
                ),
                _ComposerShortcut(
                  label: '/continue',
                  tooltip: 'Siapkan lanjutan checkpoint',
                  onTap: widget.busy
                      ? null
                      : () => _prepareCommand('/continue'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (!widget.busy && _hasText) widget.onSend();
                    },
                  },
                  child: TextField(
                    key: const ValueKey('prompt-field'),
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    minLines: 1,
                    maxLines: compactDensity ? 3 : 5,
                    enabled: !widget.busy,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                    decoration: InputDecoration(
                      hintText: 'Describe a task or type / for commands...',
                      contentPadding: EdgeInsets.fromLTRB(
                        12,
                        compactDensity ? 4 : 7,
                        48,
                        compactDensity ? 6 : 10,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Tooltip(
                      message: widget.busy ? 'Hentikan agent' : 'Kirim prompt',
                      child: FilledButton(
                        key: ValueKey(
                          widget.busy ? 'stop-agent' : 'send-agent',
                        ),
                        onPressed: widget.busy
                            ? widget.onStop
                            : !_hasText
                            ? null
                            : widget.onSend,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: widget.busy
                              ? colors.error
                              : colors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Icon(
                          widget.busy ? Icons.stop_rounded : Icons.send_rounded,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('attach-context'),
                  onPressed: widget.busy ? null : widget.onAttachContext,
                  icon: const Icon(Icons.attach_file, size: 14),
                  label: Text('${widget.contextFiles.length} FILES'),
                  style: statusButtonStyle,
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const ValueKey('composer-density-toggle'),
                  onPressed: widget.busy
                      ? null
                      : () => widget.onDensityChanged(
                          widget.density == _ComposerDensity.compact
                              ? _ComposerDensity.comfortable
                              : _ComposerDensity.compact,
                        ),
                  icon: Icon(
                    compactDensity ? Icons.density_small : Icons.density_large,
                    size: 14,
                  ),
                  label: Text(compactDensity ? 'LEGA' : 'RINGKAS'),
                  style: statusButtonStyle,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.planMode
                        ? 'READ-ONLY · Enter kirim · Shift+Enter baris baru'
                        : 'Enter kirim · Shift+Enter baris baru · Drop file untuk context',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 9,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _estimatedTokens() {
    var bytes = 0;
    for (final file in widget.contextFiles) {
      try {
        bytes += File(file).lengthSync();
      } catch (_) {}
    }
    return (bytes / 4).ceil();
  }

  String _fileSizeLabel(String filePath) {
    try {
      final bytes = File(filePath).lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return 'FILE';
    }
  }
}

class _ComposerShortcut extends StatelessWidget {
  const _ComposerShortcut({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: ActionChip(
        label: Text(
          label,
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 9),
        ),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        side: BorderSide(color: colors.onSurface.withValues(alpha: 0.1)),
        backgroundColor: colors.onSurface.withValues(alpha: 0.035),
      ),
    );
  }
}

class _ComposerActionBar extends StatefulWidget {
  const _ComposerActionBar({
    required this.busy,
    required this.onAddContext,
    required this.onPlugins,
    required this.onSubagent,
  });

  final bool busy;
  final VoidCallback onAddContext;
  final VoidCallback onPlugins;
  final VoidCallback onSubagent;

  @override
  State<_ComposerActionBar> createState() => _ComposerActionBarState();
}

class _ComposerActionBarState extends State<_ComposerActionBar> {
  bool _expanded = false;

  void _runAction(String value) {
    if (value == 'add') widget.onAddContext();
    if (value == 'plugins') widget.onPlugins();
    if (value == 'subagent') widget.onSubagent();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final short = MediaQuery.sizeOf(context).height < 760;
    final expanded = short == false || _expanded;
    final actionStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final actions = Row(
      key: const ValueKey('composer-tools-expanded'),
      children: [
        TextButton.icon(
          key: const ValueKey('classic-add-context'),
          onPressed: widget.busy ? null : widget.onAddContext,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('ADD'),
          style: actionStyle,
        ),
        const SizedBox(width: 6),
        TextButton.icon(
          key: const ValueKey('classic-plugins'),
          onPressed: widget.busy ? null : widget.onPlugins,
          icon: const Icon(Icons.extension_outlined, size: 16),
          label: const Text('PLUGINS'),
          style: actionStyle,
        ),
        const SizedBox(width: 6),
        TextButton.icon(
          key: const ValueKey('classic-subagent'),
          onPressed: widget.busy ? null : widget.onSubagent,
          icon: const Icon(Icons.account_tree_outlined, size: 16),
          label: const Text('SUBAGENT'),
          style: actionStyle,
        ),
      ],
    );
    if (short == false) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
        child: actions,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 15, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'TOOLS',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('composer-tools-toggle'),
                onPressed: () => setState(() => _expanded = expanded == false),
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                ),
                label: Text(expanded ? 'SEMBUNYIKAN' : 'TAMPILKAN'),
                style: actionStyle,
              ),
              PopupMenuButton<String>(
                key: const ValueKey('composer-tools-menu'),
                tooltip: 'Aksi composer',
                enabled: widget.busy == false,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: _runAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('ADD CONTEXT')),
                  PopupMenuItem(value: 'plugins', child: Text('PLUGINS')),
                  PopupMenuItem(value: 'subagent', child: Text('SUBAGENT')),
                ],
              ),
            ],
          ),
          AnimatedSize(
            duration: _fastMotion,
            curve: _motionCurve,
            child: expanded
                ? Align(alignment: Alignment.centerLeft, child: actions)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _QuickStartChip extends StatelessWidget {
  const _QuickStartChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: ActionChip(
        avatar: Icon(icon, size: 14, color: colors.primary),
        label: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.22)),
        backgroundColor: colors.primary.withValues(alpha: 0.06),
      ),
    );
  }
}

class _SuggestionCard extends StatefulWidget {
  const _SuggestionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.shortcut,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final String? shortcut;
  final VoidCallback onTap;

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final light = theme.brightness == Brightness.light;
    return Semantics(
      button: true,
      label: widget.title,
      hint: widget.subtitle,
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: AnimatedScale(
            duration: _fastMotion,
            curve: _motionCurve,
            scale: _pressed ? 0.975 : 1,
            child: AnimatedContainer(
              duration: _fastMotion,
              curve: _motionCurve,
              transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
              decoration: BoxDecoration(
                color: _pressed
                    ? colors.primary.withValues(alpha: light ? 0.10 : 0.16)
                    : _hovered
                    ? colors.primary.withValues(alpha: light ? 0.06 : 0.10)
                    : colors.surface,
                border: Border.all(
                  color: _hovered || _focused
                      ? colors.primary
                      : theme.dividerColor,
                  width: _focused ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: (_hovered || _focused) && !_pressed
                    ? const [
                        BoxShadow(
                          color: Color(0x24000000),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: widget.onTap,
                  focusColor: colors.primary.withValues(alpha: 0.09),
                  hoverColor: Colors.transparent,
                  onHighlightChanged: (pressed) =>
                      setState(() => _pressed = pressed),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: _fastMotion,
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _hovered || _focused
                                ? colors.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Icon(
                            widget.icon,
                            size: 19,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ),
                                  if (widget.badge != null) ...[
                                    const SizedBox(width: 6),
                                    _SuggestionBadge(label: widget.badge!),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 9,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.shortcut != null) ...[
                          const SizedBox(width: 8),
                          _SuggestionShortcut(label: widget.shortcut!),
                        ],
                        AnimatedSlide(
                          duration: _fastMotion,
                          offset: _hovered || _focused
                              ? Offset.zero
                              : const Offset(-0.25, 0),
                          child: AnimatedOpacity(
                            duration: _fastMotion,
                            opacity: _hovered || _focused ? 1 : 0.35,
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 17,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionBadge extends StatelessWidget {
  const _SuggestionBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _SuggestionShortcut extends StatelessWidget {
  const _SuggestionShortcut({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 8,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.connected,
    required this.configured,
    required this.busy,
    required this.status,
    required this.gitStatus,
    required this.onGit,
    required this.onStatus,
    required this.workspaceTrusted,
    required this.onTrustWorkspace,
  });

  final bool connected;
  final bool configured;
  final bool busy;
  final String status;
  final GitStatus gitStatus;
  final VoidCallback onGit;
  final VoidCallback onStatus;
  final bool workspaceTrusted;
  final VoidCallback onTrustWorkspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final light = theme.brightness == Brightness.light;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final state = busy
        ? status.toUpperCase()
        : connected
        ? 'API CONNECTED'
        : configured
        ? 'API CONFIGURED · NOT VERIFIED'
        : 'OFFLINE';
    final color = connected
        ? colors.primary
        : configured
        ? (light ? const Color(0xFFB7862A) : const Color(0xFFD7A544))
        : colors.onSurfaceVariant;
    return Container(
      key: const ValueKey('status-bar'),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: colors.surface),
      child: Row(
        children: [
          const Spacer(),
          if (gitStatus.isRepository) ...[
            const SizedBox(width: 16),
            InkWell(
              onTap: onGit,
              child: Text(
                compact
                    ? '${gitStatus.branch.split('/').last}${gitStatus.dirty ? ' *' : ''}'
                    : '${gitStatus.branch}${gitStatus.dirty ? ' *' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 10,
                  color: gitStatus.dirty
                      ? (light
                            ? const Color(0xFFB7862A)
                            : const Color(0xFFD7A544))
                      : colors.primary,
                ),
              ),
            ),
          ],
          if (!workspaceTrusted) ...[
            const SizedBox(width: 16),
            InkWell(
              key: const ValueKey('restricted-mode-action'),
              onTap: onTrustWorkspace,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: compact
                    ? Tooltip(
                        message: 'Trust workspace',
                        child: Icon(
                          Icons.lock_outline,
                          size: 15,
                          color: light
                              ? const Color(0xFFB7862A)
                              : const Color(0xFFD7A544),
                        ),
                      )
                    : Text(
                        'RESTRICTED MODE · TRUST WORKSPACE',
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: light
                              ? const Color(0xFFB7862A)
                              : const Color(0xFFD7A544),
                        ),
                      ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Material(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              key: const ValueKey('status-summary-chip'),
              onTap: onStatus,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      compact
                          ? (connected ? 'SYNCED' : state.split(' · ').first)
                          : (connected ? 'SYNCED' : state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 9,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 13, color: color),
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

class _WorkspaceStatusDialog extends StatelessWidget {
  const _WorkspaceStatusDialog({
    required this.workspace,
    required this.connected,
    required this.configured,
    required this.busy,
    required this.workspaceTrusted,
    required this.onChooseWorkspace,
    required this.onTrustWorkspace,
    required this.onConfigureProvider,
  });

  final String workspace;
  final bool connected;
  final bool configured;
  final bool busy;
  final bool workspaceTrusted;
  final Future<void> Function() onChooseWorkspace;
  final VoidCallback onTrustWorkspace;
  final Future<void> Function() onConfigureProvider;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final providerTitle = connected
        ? 'Provider terhubung'
        : configured
        ? 'Provider belum diverifikasi'
        : 'Provider belum dikonfigurasi';
    final providerDetail = connected
        ? 'YOUNZCODE siap mengirim tugas ke model yang dipilih.'
        : configured
        ? 'API key tersimpan di memori aplikasi, tetapi koneksi terakhir belum berhasil diverifikasi.'
        : 'Tambahkan Base URL, API key, dan model dari Model Settings untuk mulai menggunakan agent.';
    final providerColor = connected
        ? colors.primary
        : configured
        ? colors.tertiary
        : colors.onSurfaceVariant;
    return AlertDialog(
      key: const ValueKey('workspace-status-dialog'),
      title: const Text('Workspace status'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusDetailRow(
              icon: Icons.folder_open_outlined,
              title: 'Workspace',
              value: workspace.isEmpty ? 'Belum dipilih' : workspace,
              color: workspace.isEmpty ? colors.tertiary : colors.primary,
            ),
            const SizedBox(height: 10),
            _StatusDetailRow(
              icon: Icons.shield_outlined,
              title: 'Permission',
              value: workspace.isEmpty
                  ? 'Pilih workspace terlebih dahulu'
                  : workspaceTrusted
                  ? 'Trusted — edit dan tool aktif'
                  : 'Restricted — hanya baca',
              color: workspaceTrusted ? colors.primary : colors.tertiary,
            ),
            const SizedBox(height: 10),
            _StatusDetailRow(
              icon: connected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              title: providerTitle,
              value: providerDetail,
              color: providerColor,
            ),
            const SizedBox(height: 14),
            Text(
              'TINDAKAN BERIKUTNYA',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (workspace.isEmpty)
              _StatusAction(
                key: const ValueKey('status-choose-workspace'),
                icon: Icons.folder_open_outlined,
                title: 'Pilih workspace proyek',
                subtitle: 'Hubungkan folder sebelum menjalankan tugas.',
                onTap: busy ? null : onChooseWorkspace,
              )
            else if (!workspaceTrusted)
              _StatusAction(
                key: const ValueKey('status-trust-workspace'),
                icon: Icons.shield_outlined,
                title: 'Trust workspace',
                subtitle: 'Aktifkan edit file, terminal, add-on, dan MCP.',
                onTap: busy ? null : onTrustWorkspace,
              ),
            if (!configured || !connected)
              _StatusAction(
                key: const ValueKey('status-configure-provider'),
                icon: Icons.settings_outlined,
                title: connected
                    ? 'Atur provider/model'
                    : 'Buka Model Settings',
                subtitle: connected
                    ? 'Ganti endpoint atau model yang digunakan agent.'
                    : 'Periksa Base URL, API key, lalu verifikasi koneksi.',
                onTap: busy ? null : onConfigureProvider,
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
}

class _StatusDetailRow extends StatelessWidget {
  const _StatusDetailRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 6),
      elevation: 0,
      color: colors.onSurface.withValues(alpha: 0.045),
      child: ListTile(
        enabled: onTap != null,
        leading: Icon(icon, color: colors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
