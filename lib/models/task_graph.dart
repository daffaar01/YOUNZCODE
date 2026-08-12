enum TaskNodeStatus {
  pending,
  running,
  paused,
  blocked,
  failed,
  completed,
  cancelled,
}

class TaskArtifact {
  const TaskArtifact({
    required this.kind,
    required this.label,
    required this.value,
  });

  factory TaskArtifact.fromJson(Map<String, dynamic> json) => TaskArtifact(
    kind: (json['kind'] as String? ?? '').trim(),
    label: (json['label'] as String? ?? '').trim(),
    value: (json['value'] as String? ?? '').trim(),
  );

  final String kind;
  final String label;
  final String value;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'label': label,
    'value': value,
  };
}

class TaskNode {
  const TaskNode({
    required this.id,
    required this.title,
    this.dependencies = const [],
    this.status = TaskNodeStatus.pending,
    this.detail = '',
    this.agentId = '',
    this.worktree = '',
    this.attempt = 1,
    this.artifacts = const [],
  });

  factory TaskNode.fromJson(
    Map<String, dynamic> json, {
    bool safeRestore = false,
  }) {
    final rawStatus = json['status'] as String? ?? '';
    final matches = TaskNodeStatus.values.where(
      (candidate) => candidate.name == rawStatus,
    );
    if (matches.length != 1) {
      throw const FormatException('Status task node tidak valid.');
    }
    var status = matches.single;
    var detail = json['detail'] as String? ?? '';
    if (safeRestore && status == TaskNodeStatus.running) {
      status = TaskNodeStatus.paused;
      detail = 'Task dipulihkan dalam keadaan dijeda untuk keamanan.';
    }
    return TaskNode(
      id: (json['id'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? '').trim(),
      dependencies: (json['dependencies'] as List? ?? const [])
          .map((value) => '$value')
          .toList(growable: false),
      status: status,
      detail: detail,
      agentId: json['agentId'] as String? ?? '',
      worktree: json['worktree'] as String? ?? '',
      attempt: (json['attempt'] as num?)?.toInt() ?? 1,
      artifacts: (json['artifacts'] as List? ?? const [])
          .map(
            (value) =>
                TaskArtifact.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String title;
  final List<String> dependencies;
  final TaskNodeStatus status;
  final String detail;
  final String agentId;
  final String worktree;
  final int attempt;
  final List<TaskArtifact> artifacts;

  TaskNode copyWith({
    TaskNodeStatus? status,
    String? detail,
    String? agentId,
    String? worktree,
    int? attempt,
    List<TaskArtifact>? artifacts,
  }) => TaskNode(
    id: id,
    title: title,
    dependencies: dependencies,
    status: status ?? this.status,
    detail: detail ?? this.detail,
    agentId: agentId ?? this.agentId,
    worktree: worktree ?? this.worktree,
    attempt: attempt ?? this.attempt,
    artifacts: artifacts ?? this.artifacts,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'dependencies': dependencies,
    'status': status.name,
    if (detail.isNotEmpty) 'detail': detail,
    if (agentId.isNotEmpty) 'agentId': agentId,
    if (worktree.isNotEmpty) 'worktree': worktree,
    'attempt': attempt,
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
  };
}

class TaskGraph {
  TaskGraph({
    required this.id,
    required this.objective,
    required List<TaskNode> nodes,
  }) : nodes = List.unmodifiable(nodes.map(_snapshotNode)) {
    _validate();
  }

  static TaskNode _snapshotNode(TaskNode node) => TaskNode(
    id: node.id,
    title: node.title,
    dependencies: List.unmodifiable(node.dependencies),
    status: node.status,
    detail: node.detail,
    agentId: node.agentId,
    worktree: node.worktree,
    attempt: node.attempt,
    artifacts: List.unmodifiable(node.artifacts),
  );

  factory TaskGraph.fromJson(
    Map<String, dynamic> json, {
    bool safeRestore = false,
  }) => TaskGraph(
    id: (json['id'] as String? ?? '').trim(),
    objective: (json['objective'] as String? ?? '').trim(),
    nodes: (json['nodes'] as List? ?? const [])
        .map(
          (value) => TaskNode.fromJson(
            Map<String, dynamic>.from(value as Map),
            safeRestore: safeRestore,
          ),
        )
        .toList(growable: false),
  );

  final String id;
  final String objective;
  final List<TaskNode> nodes;

  TaskNode node(String id) => nodes.firstWhere(
    (candidate) => candidate.id == id,
    orElse: () => throw StateError('Task node tidak ditemukan: $id'),
  );

  List<TaskNode> get runnable => nodes
      .where(
        (candidate) =>
            candidate.status == TaskNodeStatus.pending &&
            candidate.dependencies.every(
              (dependency) =>
                  node(dependency).status == TaskNodeStatus.completed,
            ),
      )
      .toList(growable: false);

  TaskGraph transition(
    String nodeId,
    TaskNodeStatus next, {
    String detail = '',
    String? agentId,
    String? worktree,
    List<TaskArtifact>? artifacts,
  }) {
    final current = node(nodeId);
    if (!_allowed[current.status]!.contains(next)) {
      throw StateError(
        'Transisi ${current.status.name} -> ${next.name} tidak diizinkan.',
      );
    }
    if (next == TaskNodeStatus.running &&
        !current.dependencies.every(
          (dependency) => node(dependency).status == TaskNodeStatus.completed,
        )) {
      throw StateError('Dependency task $nodeId belum selesai.');
    }
    final updated = _replace(
      current.copyWith(
        status: next,
        detail: detail,
        agentId: agentId,
        worktree: worktree,
        artifacts: artifacts,
      ),
    );
    return next == TaskNodeStatus.failed || next == TaskNodeStatus.cancelled
        ? updated._propagateBlocked()
        : updated;
  }

  TaskGraph retry(String nodeId) {
    final current = node(nodeId);
    if (current.status != TaskNodeStatus.failed &&
        current.status != TaskNodeStatus.blocked &&
        current.status != TaskNodeStatus.cancelled) {
      throw StateError(
        'Hanya task gagal, blocked, atau cancelled yang dapat retry.',
      );
    }
    return _replace(
      current.copyWith(
        status: TaskNodeStatus.pending,
        detail: '',
        attempt: current.attempt + 1,
      ),
    );
  }

  TaskGraph _propagateBlocked() {
    var current = this;
    var changed = true;
    while (changed) {
      changed = false;
      for (final candidate in current.nodes) {
        if (candidate.status != TaskNodeStatus.pending &&
            candidate.status != TaskNodeStatus.paused) {
          continue;
        }
        final dependencyFailed = candidate.dependencies.any((dependency) {
          final status = current.node(dependency).status;
          return status == TaskNodeStatus.failed ||
              status == TaskNodeStatus.cancelled ||
              status == TaskNodeStatus.blocked;
        });
        if (!dependencyFailed) continue;
        current = current._replace(
          candidate.copyWith(
            status: TaskNodeStatus.blocked,
            detail: 'Dependency gagal atau dibatalkan.',
          ),
        );
        changed = true;
      }
    }
    return current;
  }

  TaskGraph _replace(TaskNode replacement) => TaskGraph(
    id: id,
    objective: objective,
    nodes: [
      for (final candidate in nodes)
        if (candidate.id == replacement.id) replacement else candidate,
    ],
  );

  void _validate() {
    final safeId = RegExp(r'^[A-Za-z0-9._:-]+$');
    if (id.isEmpty ||
        id.length > 512 ||
        !safeId.hasMatch(id) ||
        objective.isEmpty ||
        objective.length > 12000 ||
        nodes.isEmpty ||
        nodes.length > 64) {
      throw const FormatException(
        'Task graph id, objective, atau jumlah nodes tidak valid.',
      );
    }
    final ids = <String>{};
    for (final node in nodes) {
      if (node.id.isEmpty ||
          node.id.length > 512 ||
          !safeId.hasMatch(node.id) ||
          node.title.isEmpty ||
          node.title.length > 12000 ||
          node.detail.length > 12000 ||
          node.agentId.length > 512 ||
          node.worktree.length > 12000 ||
          node.artifacts.length > 32 ||
          !ids.add(node.id)) {
        throw const FormatException(
          'Task node field invalid, terlalu besar, atau duplikat.',
        );
      }
      if (node.attempt < 1 ||
          node.artifacts.any(
            (artifact) =>
                artifact.kind.isEmpty ||
                artifact.kind.length > 512 ||
                artifact.label.length > 512 ||
                artifact.value.length > 256 * 1024,
          )) {
        throw const FormatException('Task node attempt/artifact tidak valid.');
      }
    }
    for (final node in nodes) {
      if (node.dependencies.toSet().length != node.dependencies.length ||
          node.dependencies.contains(node.id) ||
          node.dependencies.any((dependency) => !ids.contains(dependency))) {
        throw FormatException('Dependency invalid pada ${node.id}.');
      }
    }
    for (final candidate in nodes) {
      if ((candidate.status == TaskNodeStatus.running ||
              candidate.status == TaskNodeStatus.paused ||
              candidate.status == TaskNodeStatus.completed) &&
          candidate.dependencies.any(
            (dependency) => node(dependency).status != TaskNodeStatus.completed,
          )) {
        throw FormatException(
          'Status ${candidate.status.name} tidak valid untuk ${candidate.id}.',
        );
      }
    }
    final visiting = <String>{};
    final visited = <String>{};
    void visit(String nodeId) {
      if (visiting.contains(nodeId)) {
        throw const FormatException('Task graph mengandung cycle.');
      }
      if (!visited.add(nodeId)) return;
      visiting.add(nodeId);
      for (final dependency in node(nodeId).dependencies) {
        visit(dependency);
      }
      visiting.remove(nodeId);
    }

    for (final node in nodes) {
      visit(node.id);
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'objective': objective,
    'nodes': nodes.map((node) => node.toJson()).toList(),
  };

  static const Map<TaskNodeStatus, Set<TaskNodeStatus>> _allowed = {
    TaskNodeStatus.pending: {TaskNodeStatus.running, TaskNodeStatus.cancelled},
    TaskNodeStatus.running: {
      TaskNodeStatus.paused,
      TaskNodeStatus.blocked,
      TaskNodeStatus.failed,
      TaskNodeStatus.completed,
      TaskNodeStatus.cancelled,
    },
    TaskNodeStatus.paused: {TaskNodeStatus.running, TaskNodeStatus.cancelled},
    TaskNodeStatus.blocked: {TaskNodeStatus.cancelled},
    TaskNodeStatus.failed: {TaskNodeStatus.cancelled},
    TaskNodeStatus.completed: {},
    TaskNodeStatus.cancelled: {},
  };
}
