class WorkspaceSearchGuard {
  const WorkspaceSearchGuard({required this.workspace, required this.service});

  final String workspace;
  final Object service;

  bool isCurrent({required String workspace, required Object? service}) =>
      this.workspace == workspace && identical(this.service, service);
}
