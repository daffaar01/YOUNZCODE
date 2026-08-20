part of '../main.dart';

// Window chrome: resize handle, command rail, workspace bar/tabs, project
// panel, and the file tree.

class _PanelResizeHandle extends StatefulWidget {
  const _PanelResizeHandle({super.key, required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_PanelResizeHandle> createState() => _PanelResizeHandleState();
}

class _PanelResizeHandleState extends State<_PanelResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: _fastMotion,
              width: _hovered ? 3 : 1,
              color: _hovered ? colors.primary : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandRail extends StatelessWidget {
  const _CommandRail({
    required this.onNewChat,
    required this.onChat,
    required this.onFiles,
    required this.onSearch,
    required this.onImages,
    required this.onBrowser,
    required this.onHistory,
    required this.onAddons,
    required this.onTerminal,
    required this.onSettings,
    required this.imageGenerationMode,
    required this.browserMode,
    required this.chatSelected,
  });

  final VoidCallback onNewChat;
  final VoidCallback onChat;
  final VoidCallback onFiles;
  final VoidCallback onSearch;
  final VoidCallback onImages;
  final VoidCallback onBrowser;
  final VoidCallback onHistory;
  final VoidCallback onAddons;
  final VoidCallback onTerminal;
  final VoidCallback onSettings;
  final bool imageGenerationMode;
  final bool browserMode;
  final bool chatSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).height < 560;
    return Container(
      key: const ValueKey('command-rail'),
      width: 72,
      decoration: BoxDecoration(color: colors.surface),
      child: Column(
        children: [
          SizedBox(height: compact ? 6 : 16),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(2)),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/younzcode_logo_new.png',
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'v$_appVersion',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          SizedBox(height: compact ? 5 : 22),
          Expanded(
            child: SilkySingleChildScrollView(
              silkyConfig: _silkyScrollConfig,
              child: Column(
                children: [
                  _RailAction(
                    icon: Icons.add_comment_outlined,
                    label: 'NEW CHAT',
                    onTap: onNewChat,
                  ),
                  _RailAction(
                    icon: Icons.chat_bubble_outline,
                    label: 'CHAT',
                    selected: chatSelected,
                    onTap: onChat,
                  ),
                  _RailAction(
                    icon: Icons.image_outlined,
                    label: 'IMAGES',
                    selected: imageGenerationMode,
                    onTap: onImages,
                  ),
                  _RailAction(
                    icon: Icons.travel_explore,
                    label: 'BROWSER',
                    selected: browserMode,
                    onTap: onBrowser,
                  ),
                  _RailAction(
                    icon: Icons.folder_outlined,
                    label: 'FILES',
                    onTap: onFiles,
                  ),
                  _RailAction(
                    icon: Icons.search,
                    label: 'SEARCH',
                    onTap: onSearch,
                  ),
                  _RailAction(
                    icon: Icons.history,
                    label: 'HISTORY',
                    onTap: onHistory,
                  ),
                  _RailAction(
                    icon: Icons.extension_outlined,
                    label: 'ADD-ONS',
                    onTap: onAddons,
                  ),
                ],
              ),
            ),
          ),
          _RailAction(
            icon: Icons.terminal,
            label: 'TERMINAL',
            onTap: onTerminal,
          ),
          _RailAction(
            icon: Icons.settings_outlined,
            label: 'SETTINGS',
            onTap: onSettings,
          ),
          SizedBox(height: compact ? 4 : 14),
        ],
      ),
    );
  }
}

class _ClassicSidebar extends StatefulWidget {
  const _ClassicSidebar({
    required this.workspace,
    required this.sessions,
    required this.activeChatId,
    required this.onNewChat,
    required this.onOpenSession,
    required this.onPullRequests,
    required this.onScheduled,
    required this.onPlugins,
    required this.onBrowser,
    required this.onImages,
    required this.onTerminal,
    required this.onHistory,
    required this.onAddons,
    required this.onChooseWorkspace,
    required this.onLayoutChanged,
    required this.workspaceLayout,
    required this.onAbout,
    required this.browserMode,
    required this.imageGenerationMode,
    required this.terminalVisible,
    required this.changeCount,
  });

  final String workspace;
  final List<ChatSession> sessions;
  final String activeChatId;
  final VoidCallback onNewChat;
  final ValueChanged<ChatSession> onOpenSession;
  final VoidCallback onPullRequests;
  final VoidCallback onScheduled;
  final VoidCallback onPlugins;
  final VoidCallback onBrowser;
  final VoidCallback onImages;
  final VoidCallback onTerminal;
  final VoidCallback onHistory;
  final VoidCallback onAddons;
  final VoidCallback onChooseWorkspace;
  final ValueChanged<_WorkspaceLayout> onLayoutChanged;
  final _WorkspaceLayout workspaceLayout;
  final VoidCallback onAbout;
  final bool browserMode;
  final bool imageGenerationMode;
  final bool terminalVisible;
  final int changeCount;

  @override
  State<_ClassicSidebar> createState() => _ClassicSidebarState();
}

class _ClassicSidebarState extends State<_ClassicSidebar> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final folder = widget.workspace.isEmpty
        ? 'Pilih workspace'
        : widget.workspace.replaceAll('\\', '/').split('/').last;
    final recent = widget.sessions.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return AnimatedContainer(
      key: const ValueKey('classic-sidebar'),
      duration: _mediumMotion,
      curve: _motionCurve,
      width: _collapsed ? 72 : 266,
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 220;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 18, 14, 12),
                child: compact
                    ? Column(
                        children: [
                          Image.asset(
                            'assets/younzcode_logo_new.png',
                            width: 28,
                            height: 28,
                          ),
                          const SizedBox(height: 6),
                          IconButton(
                            key: const ValueKey('classic-sidebar-toggle'),
                            tooltip: 'Expand sidebar',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _collapsed = false),
                            icon: const Icon(
                              Icons.keyboard_double_arrow_right,
                              size: 18,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Image.asset(
                            'assets/younzcode_logo_new.png',
                            width: 28,
                            height: 28,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'YOUNZCODE',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.45,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('classic-about-button'),
                            tooltip: 'About YOUNZCODE',
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.onAbout,
                            icon: const Icon(Icons.info_outline, size: 18),
                          ),
                          PopupMenuButton<_WorkspaceLayout>(
                            key: const ValueKey('workspace-layout-picker'),
                            tooltip: 'Pilih tampilan workspace',
                            initialValue: widget.workspaceLayout,
                            onSelected: widget.onLayoutChanged,
                            icon: Icon(
                              widget.workspaceLayout == _WorkspaceLayout.classic
                                  ? Icons.view_quilt_outlined
                                  : Icons.vertical_split_outlined,
                              size: 18,
                            ),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: _WorkspaceLayout.classic,
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.view_quilt_outlined,
                                    size: 19,
                                  ),
                                  title: Text('Classic'),
                                  subtitle: Text('Sidebar dan workspace utama'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _WorkspaceLayout.focus,
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.vertical_split_outlined,
                                    size: 19,
                                  ),
                                  title: Text('Focus'),
                                  subtitle: Text(
                                    'Explorer dan Agent berdampingan',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            key: const ValueKey('classic-sidebar-toggle'),
                            tooltip: 'Collapse sidebar',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _collapsed = true),
                            icon: const Icon(
                              Icons.keyboard_double_arrow_left,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
              ),
              _ClassicNavItem(
                icon: Icons.add_comment_outlined,
                label: 'New Chat',
                onTap: widget.onNewChat,
                compact: compact,
              ),
              _ClassicNavItem(
                icon: Icons.account_tree_outlined,
                label: 'Pull Requests',
                onTap: widget.onPullRequests,
                compact: compact,
                badgeCount: widget.changeCount,
              ),
              _ClassicNavItem(
                icon: Icons.schedule_outlined,
                label: 'Scheduled',
                onTap: widget.onScheduled,
                compact: compact,
              ),
              _ClassicNavItem(
                icon: Icons.extension_outlined,
                label: 'Plugins',
                onTap: widget.onPlugins,
                compact: compact,
              ),
              _ClassicNavItem(
                icon: Icons.travel_explore,
                label: 'Browser',
                onTap: widget.onBrowser,
                compact: compact,
                selected: widget.browserMode,
              ),
              _ClassicNavItem(
                icon: Icons.image_outlined,
                label: 'Images',
                onTap: widget.onImages,
                compact: compact,
                selected: widget.imageGenerationMode,
              ),
              _ClassicNavItem(
                icon: Icons.terminal,
                label: 'Terminal',
                onTap: widget.onTerminal,
                compact: compact,
                selected: widget.terminalVisible,
              ),
              _ClassicNavItem(
                icon: Icons.history,
                label: 'History',
                onTap: widget.onHistory,
                compact: compact,
              ),
              _ClassicNavItem(
                icon: Icons.widgets_outlined,
                label: 'Add-ons',
                onTap: widget.onAddons,
                compact: compact,
              ),
              if (!compact) ...[
                const SizedBox(height: 12),
                _ClassicSectionLabel('PROJECT'),
                _ClassicNavItem(
                  key: const ValueKey('classic-project'),
                  icon: Icons.folder_outlined,
                  label: folder,
                  onTap: widget.onChooseWorkspace,
                ),
                const SizedBox(height: 8),
                _ClassicSectionLabel('RECENTS'),
                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Belum ada chat sebelumnya',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          key: const ValueKey('classic-first-chat'),
                          onPressed: widget.onNewChat,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(
                            Icons.add_comment_outlined,
                            size: 15,
                          ),
                          label: const Text('Mulai chat pertama'),
                        ),
                      ],
                    ),
                  )
                else
                  ...recent
                      .take(12)
                      .map(
                        (session) => _ClassicNavItem(
                          icon: Icons.chat_bubble_outline,
                          label: session.title,
                          selected: session.id == widget.activeChatId,
                          onTap: () => widget.onOpenSession(session),
                        ),
                      ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ClassicSectionLabel extends StatelessWidget {
  const _ClassicSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ClassicNavItem extends StatelessWidget {
  const _ClassicNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.compact = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool compact;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconWidget = Badge(
      isLabelVisible: badgeCount > 0,
      label: Text('${badgeCount.clamp(0, 99)}'),
      child: Icon(icon, size: 18),
    );
    final item = Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: compact
              ? Stack(
                  children: [
                    if (selected)
                      Positioned(
                        left: 0,
                        top: 9,
                        bottom: 9,
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    Center(child: iconWidget),
                  ],
                )
              : Row(
                  children: [
                    const SizedBox(width: 4),
                    if (selected)
                      Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )
                    else
                      const SizedBox(width: 3),
                    const SizedBox(width: 10),
                    iconWidget,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: compact ? Tooltip(message: label, child: item) : item,
    );
  }
}

class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).height < 560;
    return Tooltip(
      message: label,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 0 : 2),
        child: Material(
          color: selected
              ? colors.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              key: ValueKey('rail-${label.toLowerCase().replaceAll(' ', '-')}'),
              width: 48,
              height: compact ? 36 : 42,
              decoration: const BoxDecoration(),
              child: Icon(
                icon,
                size: 21,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopWorkspaceBar extends StatelessWidget {
  const _TopWorkspaceBar({
    required this.activeFile,
    required this.searchMode,
    required this.imageGenerationMode,
    required this.browserMode,
    required this.terminalVisible,
    required this.inspectorVisible,
    required this.lightMode,
    required this.onExplorer,
    required this.onEditor,
    required this.onTerminal,
    required this.onImages,
    required this.onBrowser,
    required this.onInspector,
    required this.onToggleTheme,
    required this.onNotifications,
    required this.notificationCount,
    required this.workspaceLayout,
    required this.onLayoutChanged,
  });

  final String? activeFile;
  final bool searchMode;
  final bool imageGenerationMode;
  final bool browserMode;
  final bool terminalVisible;
  final bool inspectorVisible;
  final bool lightMode;
  final VoidCallback onExplorer;
  final VoidCallback? onEditor;
  final VoidCallback onTerminal;
  final VoidCallback onImages;
  final VoidCallback onBrowser;
  final VoidCallback onInspector;
  final VoidCallback onToggleTheme;
  final VoidCallback onNotifications;
  final int notificationCount;
  final _WorkspaceLayout workspaceLayout;
  final ValueChanged<_WorkspaceLayout> onLayoutChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('top-workspace-bar'),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: colors.surface),
      child: Row(
        children: [
          Text(
            'YOUNZCODE',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SilkySingleChildScrollView(
                silkyConfig: _silkyHorizontalScrollConfig,
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WorkspaceTab(
                        label: 'Explorer',
                        active:
                            activeFile == null &&
                            !searchMode &&
                            !imageGenerationMode &&
                            !browserMode &&
                            !terminalVisible,
                        onTap: onExplorer,
                      ),
                      _WorkspaceTab(
                        label: 'Editor',
                        active: activeFile != null,
                        onTap: onEditor,
                      ),
                      _WorkspaceTab(
                        label: 'Images',
                        active: imageGenerationMode,
                        onTap: onImages,
                      ),
                      _WorkspaceTab(
                        label: 'Browser',
                        active: browserMode,
                        onTap: onBrowser,
                      ),
                      _WorkspaceTab(
                        label: 'Terminal',
                        active: terminalVisible,
                        onTap: onTerminal,
                      ),
                      _WorkspaceTab(
                        key: const ValueKey('show-activity-panel'),
                        label: 'Inspector',
                        active: inspectorVisible,
                        onTap: onInspector,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('theme-toggle'),
            tooltip: lightMode ? 'Gunakan mode gelap' : 'Gunakan mode terang',
            onPressed: onToggleTheme,
            icon: Icon(
              lightMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 20,
            ),
          ),
          PopupMenuButton<_WorkspaceLayout>(
            key: const ValueKey('workspace-layout-picker'),
            tooltip: 'Pilih tampilan workspace',
            initialValue: workspaceLayout,
            onSelected: onLayoutChanged,
            icon: Icon(
              workspaceLayout == _WorkspaceLayout.classic
                  ? Icons.view_quilt_outlined
                  : Icons.vertical_split_outlined,
              size: 20,
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _WorkspaceLayout.classic,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.view_quilt_outlined, size: 19),
                  title: Text('Classic'),
                  subtitle: Text('Tampilan YOUNZCODE saat ini'),
                ),
              ),
              PopupMenuItem(
                value: _WorkspaceLayout.focus,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.vertical_split_outlined, size: 19),
                  title: Text('Focus'),
                  subtitle: Text('Explorer, workspace, dan Agent'),
                ),
              ),
            ],
          ),
          if (MediaQuery.sizeOf(context).width >= 1000)
            IconButton(
              tooltip: 'Project settings',
              onPressed: onInspector,
              icon: const Icon(Icons.account_tree_outlined, size: 20),
            ),
          IconButton(
            key: const ValueKey('notifications-button'),
            tooltip: 'Notifications',
            onPressed: onNotifications,
            icon: Badge(
              isLabelVisible: notificationCount > 0,
              label: Text('${notificationCount.clamp(0, 99)}'),
              child: const Icon(Icons.notifications_none, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    // A segment inside the top-bar's unified view switcher: the active one
    // carries the accent-subtle fill, matching the command rail's active state.
    return Material(
      color: active
          ? colors.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: !enabled
                  ? colors.onSurfaceVariant.withValues(alpha: 0.4)
                  : active
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectPanel extends StatefulWidget {
  const _ProjectPanel({
    required this.workspace,
    required this.activeFile,
    required this.dirtyFiles,
    required this.recentWorkspaces,
    required this.onOpenFile,
    required this.onOpenRecent,
    required this.onChoose,
    required this.onNewChat,
    required this.onChat,
    required this.onTerminal,
    required this.onHistory,
    required this.onAddons,
    required this.onSettings,
    required this.onSearch,
    required this.onHide,
  });

  final String workspace;
  final String? activeFile;
  final Set<String> dirtyFiles;
  final List<String> recentWorkspaces;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onOpenRecent;
  final VoidCallback onChoose;
  final VoidCallback onNewChat;
  final VoidCallback onChat;
  final VoidCallback onTerminal;
  final VoidCallback onSettings;
  final VoidCallback onSearch;
  final VoidCallback onHistory;
  final VoidCallback onAddons;
  final VoidCallback onHide;

  @override
  State<_ProjectPanel> createState() => _ProjectPanelState();
}

class _ProjectPanelState extends State<_ProjectPanel> {
  int _treeRevision = 0;
  bool _treeExpanded = true;
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ProjectPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) _treeRevision++;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final folderName = widget.workspace.isEmpty
        ? 'Belum dipilih'
        : widget.workspace.replaceAll('\\', '/').split('/').last;
    final activeRelativePath = widget.activeFile == null
        ? null
        : widget.workspace.isEmpty
        ? widget.activeFile!
        : path.relative(widget.activeFile!, from: widget.workspace);
    final activeFileDirty =
        widget.activeFile != null &&
        widget.dirtyFiles.contains(widget.activeFile);
    final recent = widget.recentWorkspaces
        .where((workspace) => workspace != widget.workspace)
        .take(3)
        .toList();
    return Container(
      key: const ValueKey('workspace-explorer'),
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'WORKSPACE',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onChoose,
                  tooltip: 'Choose workspace',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_horiz, size: 18),
                ),
                IconButton(
                  key: const ValueKey('hide-explorer-panel'),
                  onPressed: widget.onHide,
                  tooltip: 'Hide Explorer',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              onTap: widget.onChoose,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                color: colors.primary.withValues(alpha: 0.12),
                child: Text(
                  widget.workspace.isEmpty
                      ? '/select/a/project'
                      : widget.workspace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
          ),
          if (activeRelativePath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Container(
                key: const ValueKey('explorer-active-file'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 14,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        activeRelativePath.replaceAll('\\', ' / '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 10,
                        ),
                      ),
                    ),
                    if (activeFileDirty)
                      Tooltip(
                        message: 'Perubahan belum disimpan',
                        child: Container(
                          key: const ValueKey('explorer-unsaved-indicator'),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.tertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: SizedBox(
              height: 38,
              child: TextField(
                key: const ValueKey('file-filter'),
                controller: _filterController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Filter files...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          if (widget.workspace.isNotEmpty) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('workspace-tree-root-toggle'),
                onTap: () => setState(() => _treeExpanded = !_treeExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _treeExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 17,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: colors.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          folderName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _treeRevision++),
                        tooltip: 'Refresh file tree',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh, size: 15),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_treeExpanded)
              Expanded(
                child: _WorkspaceTree(
                  key: ValueKey('${widget.workspace}:$_treeRevision'),
                  root: widget.workspace,
                  filter: _filterController.text,
                  onOpenFile: widget.onOpenFile,
                ),
              )
            else
              const Spacer(),
          ] else
            Expanded(
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: widget.onChoose,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('SELECT WORKSPACE'),
                ),
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            decoration: const BoxDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RECENT',
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (recent.isEmpty)
                  Text(
                    'No workspace history',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  )
                else
                  for (final workspace in recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey(
                            'explorer-recent-${workspace.replaceAll('\\', '/')}',
                          ),
                          borderRadius: BorderRadius.circular(7),
                          onTap: () => widget.onOpenRecent(workspace),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 14,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    path.basename(workspace),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Consolas',
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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

class _WorkspaceTree extends StatefulWidget {
  const _WorkspaceTree({
    super.key,
    required this.root,
    this.filter = '',
    required this.onOpenFile,
  });

  final String root;
  final String filter;
  final ValueChanged<String> onOpenFile;

  @override
  State<_WorkspaceTree> createState() => _WorkspaceTreeState();
}

class _WorkspaceTreeState extends State<_WorkspaceTree> {
  late Future<List<FileSystemEntity>> _entries = _readDirectory(widget.root);

  static Future<List<FileSystemEntity>> _readDirectory(String directory) async {
    final entries = await Directory(
      directory,
    ).list(followLinks: false).toList();
    entries.sort((left, right) {
      final leftDirectory = left is Directory;
      final rightDirectory = right is Directory;
      if (leftDirectory != rightDirectory) return leftDirectory ? -1 : 1;
      return _entityName(
        left,
      ).toLowerCase().compareTo(_entityName(right).toLowerCase());
    });
    return entries;
  }

  static String _entityName(FileSystemEntity entity) =>
      entity.path.replaceAll('\\', '/').split('/').last;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FileSystemEntity>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          );
        }
        if (snapshot.hasError) {
          return _TreeMessage(
            icon: Icons.error_outline,
            message: 'Gagal membaca folder',
            onRetry: () =>
                setState(() => _entries = _readDirectory(widget.root)),
          );
        }
        final query = widget.filter.trim().toLowerCase();
        final entries = query.isEmpty
            ? snapshot.data!
            : snapshot.data!
                  .where(
                    (entry) => _entityName(entry).toLowerCase().contains(query),
                  )
                  .toList();
        if (entries.isEmpty) {
          return const _TreeMessage(
            icon: Icons.folder_off_outlined,
            message: 'Folder kosong',
          );
        }
        return SilkyListView.builder(
          silkyConfig: _silkyScrollConfig,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          itemCount: entries.length,
          itemBuilder: (context, index) => _FileTreeEntry(
            key: ValueKey(entries[index].path),
            entity: entries[index],
            depth: 0,
            onOpenFile: widget.onOpenFile,
          ),
        );
      },
    );
  }
}

class _FileTreeEntry extends StatefulWidget {
  const _FileTreeEntry({
    super.key,
    required this.entity,
    required this.depth,
    required this.onOpenFile,
  });

  final FileSystemEntity entity;
  final int depth;
  final ValueChanged<String> onOpenFile;

  @override
  State<_FileTreeEntry> createState() => _FileTreeEntryState();
}

class _FileTreeEntryState extends State<_FileTreeEntry> {
  bool _expanded = false;
  Future<List<FileSystemEntity>>? _children;

  bool get _isDirectory => widget.entity is Directory;

  void _toggle() {
    if (!_isDirectory) return;
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _children ??= _WorkspaceTreeState._readDirectory(widget.entity.path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = _WorkspaceTreeState._entityName(widget.entity);
    final icon = _isDirectory
        ? (_expanded ? Icons.folder_open : Icons.folder)
        : _fileIcon(name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: widget.entity.path,
          waitDuration: const Duration(milliseconds: 650),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.hardEdge,
            child: InkWell(
              onTap: _isDirectory
                  ? _toggle
                  : () => widget.onOpenFile(widget.entity.path),
              highlightColor: colors.primary.withValues(alpha: 0.10),
              splashColor: colors.primary.withValues(alpha: 0.16),
              child: SizedBox(
                height: 28,
                child: Padding(
                  padding: EdgeInsets.only(left: widget.depth * 14.0 + 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        child: _isDirectory
                            ? Icon(
                                _expanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_right,
                                size: 15,
                                color: colors.onSurfaceVariant,
                              )
                            : null,
                      ),
                      Icon(
                        icon,
                        size: 15,
                        color: _isDirectory
                            ? colors.secondary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                            height: 1,
                            fontWeight: FontWeight.w500,
                            color: _isDirectory
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
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
        if (_expanded && _children != null)
          FutureBuilder<List<FileSystemEntity>>(
            future: _children,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: EdgeInsets.only(left: widget.depth * 14.0 + 34),
                  child: const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.2),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: EdgeInsets.only(left: widget.depth * 14.0 + 34),
                  child: Text(
                    'Tidak dapat dibaca',
                    style: TextStyle(fontSize: 9, color: colors.error),
                  ),
                );
              }
              final children = snapshot.data!;
              if (children.isEmpty) {
                return Padding(
                  padding: EdgeInsets.only(left: widget.depth * 14.0 + 34),
                  child: Text(
                    'Folder kosong',
                    style: TextStyle(
                      fontSize: 9,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final child in children)
                    _FileTreeEntry(
                      key: ValueKey(child.path),
                      entity: child,
                      depth: widget.depth + 1,
                      onOpenFile: widget.onOpenFile,
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  IconData _fileIcon(String name) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    return switch (extension) {
      'dart' => Icons.flutter_dash,
      'json' || 'yaml' || 'yml' || 'toml' => Icons.data_object,
      'md' || 'txt' => Icons.description_outlined,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'ico' => Icons.image_outlined,
      'exe' || 'dll' => Icons.memory,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

class _TreeMessage extends StatelessWidget {
  const _TreeMessage({required this.icon, required this.message, this.onRetry});

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onRetry,
        icon: Icon(icon, size: 16),
        label: Text(message, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}
