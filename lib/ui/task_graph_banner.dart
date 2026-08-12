part of '../main.dart';

class TaskGraphBanner extends StatelessWidget {
  const TaskGraphBanner({super.key, required this.graph});

  final TaskGraph graph;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('task-graph-banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 17,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  graph.objective,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                '${graph.nodes.where((node) => node.status == TaskNodeStatus.completed).length}/${graph.nodes.length}',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontFamily: 'Consolas',
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (graph.nodes.any((node) => node.dependencies.isNotEmpty)) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final target in graph.nodes)
                    for (final source in target.dependencies)
                      Container(
                        key: ValueKey('task-edge-$source-${target.id}'),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.outlineVariant),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$source → ${target.id}',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontFamily: 'Consolas',
                            fontSize: 9,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 7),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final node in graph.nodes) ...[
                  _TaskGraphNodeCard(node: node),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskGraphNodeCard extends StatelessWidget {
  const _TaskGraphNodeCard({required this.node});

  final TaskNode node;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (node.status) {
      TaskNodeStatus.completed => const Color(0xFF2F9E69),
      TaskNodeStatus.running => colors.primary,
      TaskNodeStatus.failed || TaskNodeStatus.blocked => colors.error,
      TaskNodeStatus.paused => const Color(0xFFB7862A),
      TaskNodeStatus.cancelled => colors.outline,
      TaskNodeStatus.pending => colors.onSurfaceVariant,
    };
    return Tooltip(
      message: [
        node.title,
        'Status: ${node.status.name}',
        if (node.dependencies.isNotEmpty)
          'Depends on: ${node.dependencies.join(', ')}',
        if (node.agentId.isNotEmpty) 'Agent: ${node.agentId}',
        if (node.worktree.isNotEmpty) 'Worktree: ${node.worktree}',
        if (node.detail.isNotEmpty) node.detail,
        if (node.artifacts.isNotEmpty)
          'Artifacts: ${node.artifacts.map((item) => item.label).join(', ')}',
      ].join('\n'),
      child: Container(
        key: ValueKey('task-node-${node.id}'),
        width: 154,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${node.status.name.toUpperCase()} · TRY ${node.attempt}',
                    style: TextStyle(
                      color: color,
                      fontFamily: 'Consolas',
                      fontSize: 9,
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
