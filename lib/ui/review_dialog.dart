part of '../main.dart';

class _ReviewDialog extends StatelessWidget {
  const _ReviewDialog({required this.result, required this.applicableFindings});

  final ReviewResult result;
  final Set<int> applicableFindings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 680,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: const Text('GIT DIFF REVIEW'),
              subtitle: Text(result.summary),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: result.findings.isEmpty
                  ? const Center(
                      child: Text(
                        'Tidak ditemukan masalah yang dapat ditindaklanjuti.',
                      ),
                    )
                  : SilkyListView.separated(
                      silkyConfig: _silkyScrollConfig,
                      padding: const EdgeInsets.all(16),
                      itemCount: result.findings.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final finding = result.findings[index];
                        final applicable = applicableFindings.contains(index);
                        return Material(
                          color: colors.onSurface.withValues(alpha: 0.04),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _ReviewSeverityBadge(
                                      severity: finding.severity,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        finding.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${finding.path}:${finding.line}',
                                      style: const TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(finding.description),
                                const SizedBox(height: 8),
                                Text(
                                  finding.category.toUpperCase(),
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (finding.suggestedPatch.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: Text(
                                      applicable
                                          ? 'SUGGESTED PATCH'
                                          : 'PATCH INVALID OR STALE',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    children: [
                                      SelectableText(
                                        finding.suggestedPatch,
                                        style: const TextStyle(
                                          fontFamily: 'Consolas',
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed: applicable
                                          ? () => Navigator.pop(context, index)
                                          : null,
                                      icon: const Icon(
                                        Icons.build_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('APPLY PATCH'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
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
}

class _ReviewSeverityBadge extends StatelessWidget {
  const _ReviewSeverityBadge({required this.severity});

  final ReviewSeverity severity;

  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      ReviewSeverity.critical => const Color(0xFFB42318),
      ReviewSeverity.high => const Color(0xFFD64A34),
      ReviewSeverity.medium => const Color(0xFFF59F00),
      ReviewSeverity.low => const Color(0xFF2F6FE0),
      ReviewSeverity.info => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        severity.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ReviewQualityDialog extends StatelessWidget {
  const _ReviewQualityDialog({required this.result});

  final QualityGateResult result;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
    title: const Text('Patch applied, quality gate failed'),
    content: SizedBox(
      width: 720,
      child: SelectableText(
        result.checks
            .map(
              (check) =>
                  '${check.check.label}: '
                  '${check.passed ? 'PASS' : 'FAIL'}\n${check.output}',
            )
            .join('\n\n'),
        style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('KEEP PATCH'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('REVERT PATCH'),
      ),
    ],
  );
}
