import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silky_scroll/silky_scroll.dart';

import 'models/chat_entry.dart';
import 'models/chat_session.dart';
import 'models/addon.dart';
import 'models/agent_goal.dart';
import 'models/task_graph.dart';
import 'models/workspace_change.dart';
import 'agent_working_palette.dart';
import 'editor_support.dart';
import 'lottie_support.dart';
import 'services/agent_service.dart';
import 'services/agent_completion_client.dart';
import 'services/addon_service.dart';
import 'services/approval_mode.dart';
import 'services/browser_agent_service.dart';
import 'services/provider_catalog.dart';
import 'services/provider_routing_service.dart';
import 'services/provider_usage_store.dart';
import 'services/prompt_budget.dart';
import 'services/chat_session_store.dart';
import 'services/code_intelligence_service.dart';
import 'services/context_engine.dart';
import 'services/context_request_guard.dart';
import 'services/debug_adapter_service.dart';
import 'services/document_extraction_service.dart';
import 'services/extension_contribution_service.dart';
import 'services/settings_store.dart';
import 'services/mcp_client.dart';
import 'services/media_download_service.dart';
import 'services/secret_scanner.dart';
import 'services/tool_permission_store.dart';
import 'services/git_service.dart';
import 'services/goal_coordinator.dart';
import 'services/image_generation_service.dart';
import 'services/interaction_flow_policy.dart';
import 'services/multi_agent_service.dart';
import 'services/workspace_trust_service.dart';
import 'services/workspace_search_guard.dart';
import 'services/persistent_terminal_service.dart';
import 'services/quality_gate_service.dart';
import 'services/review_service.dart';
import 'services/update_ping_service.dart';
import 'services/update_service.dart';
import 'services/workspace_checkpoint_store.dart';
import 'services/workspace_tools.dart';
import 'ui/browser_panel.dart';

part 'app/agent_configuration.dart';
part 'app/agent_turn_workflow.dart';
part 'app/browser_workflow.dart';
part 'app/command_workflow.dart';
part 'app/goal_workflow.dart';
part 'app/media_document_workflow.dart';
part 'app/session_workspace_workflow.dart';
part 'app/update_diagnostics.dart';
part 'app/update_workflow.dart';
part 'app/workspace_lifecycle.dart';
part 'ui/chrome.dart';
part 'ui/editor.dart';
part 'ui/inspector.dart';
part 'ui/task_graph_banner.dart';
part 'ui/image_studio.dart';
part 'ui/provider_presets.dart';
part 'ui/dialogs.dart';
part 'ui/overlays.dart';

const _fastMotion = Duration(milliseconds: 140);
const _mediumMotion = Duration(milliseconds: 240);
const _motionCurve = Curves.easeOutCubic;
const _appVersion = '2.0.0';
const _silkyScrollConfig = SilkyScrollConfig(
  silkyScrollDuration: Duration(milliseconds: 700),
  animationCurve: Curves.easeOutCubic,
  enableStretchEffect: false,
);
const _silkyHorizontalScrollConfig = SilkyScrollConfig(
  silkyScrollDuration: Duration(milliseconds: 700),
  animationCurve: Curves.easeOutCubic,
  direction: Axis.horizontal,
  enableStretchEffect: false,
);

enum _AgentTurnState {
  idle,
  running,
  success,
  failed,
  cancelled,
  timedOut,
  paused,
}

enum _WorkspaceLayout { classic, focus }

enum _InspectorSection { activity, plan, files }

class _SlashCommand {
  const _SlashCommand(this.command, this.description, this.icon);

  final String command;
  final String description;
  final IconData icon;
}

const _slashCommands = <_SlashCommand>[
  _SlashCommand(
    '/download',
    'Download media from a public URL',
    Icons.download,
  ),
  _SlashCommand('/graphify', 'Update workspace knowledge graph', Icons.hub),
  _SlashCommand('/agents', 'Run isolated parallel agents', Icons.groups_2),
  _SlashCommand('/mcp', 'Manage MCP servers', Icons.device_hub),
  _SlashCommand('/review', 'Review pending or Git changes', Icons.rate_review),
  _SlashCommand('/retry', 'Prepare the last prompt for review', Icons.replay),
  _SlashCommand(
    '/continue',
    'Prepare checkpoint continuation for review',
    Icons.play_arrow_outlined,
  ),

  _SlashCommand('/fork', 'Fork the current chat', Icons.call_split),
  _SlashCommand('/model', 'Open model settings', Icons.psychology_outlined),
  _SlashCommand('/usage', 'Open provider usage dashboard', Icons.query_stats),
  _SlashCommand('/share', 'Copy the current chat transcript', Icons.share),
  _SlashCommand('/open', 'Open a workspace file', Icons.file_open_outlined),
  _SlashCommand('/skill', 'Manage installed skills', Icons.auto_awesome),
  _SlashCommand('/help', 'Show available commands', Icons.help_outline),
  _SlashCommand('/new', 'Start a new chat', Icons.add_comment_outlined),
  _SlashCommand(
    '/clear',
    'Clear prompt, context, and activity',
    Icons.clear_all,
  ),
  _SlashCommand('/terminal', 'Toggle integrated terminal', Icons.terminal),
  _SlashCommand('/explorer', 'Toggle Explorer panel', Icons.folder_outlined),
  _SlashCommand('/editor', 'Open the last editor or file picker', Icons.code),
  _SlashCommand('/settings', 'Open project settings', Icons.tune),
  _SlashCommand('/models', 'Open model settings', Icons.psychology_outlined),
  _SlashCommand('/history', 'Open chat history', Icons.history),
  _SlashCommand('/addons', 'Open Add-on Manager', Icons.extension_outlined),
  _SlashCommand('/search', 'Search the workspace', Icons.manage_search),
  _SlashCommand('/symbol', 'Find symbol references', Icons.data_object),
  _SlashCommand('/images', 'Open Image Generation', Icons.image_outlined),
  _SlashCommand(
    '/browser',
    'Open the Agent Browser or navigate to a URL',
    Icons.travel_explore,
  ),
  _SlashCommand(
    '/notifications',
    'Open notifications',
    Icons.notifications_none,
  ),
  _SlashCommand(
    '/goal',
    'Run and persist a task until complete or blocked',
    Icons.flag_outlined,
  ),
  _SlashCommand('/plan', 'Enable Plan Mode', Icons.account_tree_outlined),
  _SlashCommand('/build', 'Enable Build Mode', Icons.build_outlined),
  _SlashCommand(
    '/update',
    'Check for application updates',
    Icons.system_update_alt,
  ),
  _SlashCommand(
    '/update-status',
    'Show update & signing diagnostics',
    Icons.verified_outlined,
  ),
];

bool _isEnvironmentFileName(String name) =>
    name == '.env' || name.startsWith('.env.');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KodeAgentApp());
}

class KodeAgentApp extends StatefulWidget {
  const KodeAgentApp({super.key});

  @override
  State<KodeAgentApp> createState() => _KodeAgentAppState();
}

class _KodeAgentAppState extends State<KodeAgentApp> {
  bool _lightMode = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((preferences) {
      if (mounted) {
        setState(() => _lightMode = preferences.getBool('light_mode') ?? false);
      }
    });
  }

  Future<void> _toggleTheme() async {
    final lightMode = !_lightMode;
    setState(() => _lightMode = lightMode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('light_mode', lightMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YOUNZCODE',
      theme: _buildTheme(light: true),
      darkTheme: _buildTheme(light: false),
      themeMode: _lightMode ? ThemeMode.light : ThemeMode.dark,
      home: AgentHomePage(lightMode: _lightMode, onToggleTheme: _toggleTheme),
    );
  }

  ThemeData _buildTheme({required bool light}) {
    // Calm dev-tool palette: slate ground + a single blue accent. Semantic
    // colours (success/warning/error) live outside the accent and are applied
    // per-widget, so the accent never competes with a second decorative hue.
    final scheme = light
        ? const ColorScheme.light(
            primary: Color(0xFF2F6FE0),
            onPrimary: Color(0xFFFFFFFF),
            secondary: Color(0xFF55627A),
            tertiary: Color(0xFF2F6FE0),
            surface: Color(0xFFFFFFFF),
            onSurface: Color(0xFF1A222E),
            onSurfaceVariant: Color(0xFF55627A),
            outline: Color(0xFFDDE3EC),
            error: Color(0xFFD64A34),
          )
        : const ColorScheme.dark(
            primary: Color(0xFF5B9DFF),
            onPrimary: Color(0xFFFFFFFF),
            secondary: Color(0xFF9AA7B8),
            tertiary: Color(0xFF8AB4F0),
            surface: Color(0xFF10151D),
            onSurface: Color(0xFFE7ECF3),
            onSurfaceVariant: Color(0xFF9AA7B8),
            outline: Color(0xFF232C39),
            error: Color(0xFFEC6A55),
          );
    final border = light ? const Color(0xFFDDE3EC) : const Color(0xFF232C39);
    final input = light ? const Color(0xFFFFFFFF) : const Color(0xFF0D1117);
    return ThemeData(
      brightness: light ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: scheme.surface,
      colorScheme: scheme,
      fontFamily: 'Inter',
      dividerColor: Colors.transparent,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 13.5, height: 1.5),
        bodySmall: TextStyle(fontSize: 12, height: 1.42),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          elevation: 0,
          animationDuration: _fastMotion,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          animationDuration: _fastMotion,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? scheme.secondary.withValues(alpha: 0.2)
                : null,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          animationDuration: _fastMotion,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? scheme.secondary.withValues(alpha: 0.2)
                : null,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          animationDuration: _fastMotion,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? scheme.secondary.withValues(alpha: 0.25)
                : null,
          ),
        ),
      ),
      hoverColor: scheme.secondary.withValues(alpha: 0.08),
      splashFactory: InkRipple.splashFactory,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: light ? const Color(0xFF322F35) : const Color(0xFF36343B),
          border: Border.all(color: border),
        ),
        textStyle: const TextStyle(fontSize: 11, color: Color(0xFFE7ECF3)),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}

class AgentHomePage extends StatefulWidget {
  const AgentHomePage({
    super.key,
    required this.lightMode,
    required this.onToggleTheme,
  });

  final bool lightMode;
  final VoidCallback onToggleTheme;

  @override
  State<AgentHomePage> createState() => _AgentHomePageState();
}

class _AgentHomePageState extends State<AgentHomePage> {
  final _promptController = TextEditingController();
  final _searchController = TextEditingController();
  final _environment = <String, String>{};
  final _apiHeaders = <String, String>{};
  final _scrollController = ScrollController();
  final _promptFocusNode = FocusNode();
  final _settingsStore = SettingsStore();
  final _chatSessionStore = ChatSessionStore();
  final _addonService = AddonService();
  final _extensionContributions = const ExtensionContributionService();
  final _gitService = const GitService();
  final _trustService = WorkspaceTrustService();
  final _toolPermissionStore = ToolPermissionStore();
  final _providerRouter = ProviderRoutingService();
  final _providerUsageStore = ProviderUsageStore();
  final _qualityGateService = QualityGateService();
  final _updateService = const UpdateService();
  final _updatePingService = UpdatePingService();
  bool _updatePingEnabled = true;
  String _installId = '';
  // Update diagnostics (surfaced via /update-status and Model Settings):
  // which key verified the last update check and when it ran.
  DateTime? _lastUpdateCheckAt;
  String? _lastUpdateCheckResult;
  String? _lastVerifiedSigningKey;
  int? _lastUpdateCheckMs;
  final _checkpointStore = WorkspaceCheckpointStore();
  final _documentExtractionService = DocumentExtractionService();
  final _mediaDownloadService = MediaDownloadService();
  final _browserService = BrowserAgentService();
  final _browserTurnNavigation = BrowserTurnNavigationPolicy();
  final _goalCoordinator = GoalCoordinator();
  final _mainBranchWarningPolicy = MainBranchWarningPolicy();
  final _entries = <ChatEntry>[];
  final _chatSessions = <ChatSession>[];
  final _addons = <Addon>[];
  final _activities = <_AgentActivity>[];
  final _agentCheckpoint = <Map<String, dynamic>>[];
  String? _preparedCheckpointPrompt;
  final _models = <String>['gpt-4.1-mini'];
  final _documents = <_OpenDocument>[];
  final _terminalController = TextEditingController();
  final _terminalScrollController = ScrollController();
  final _terminalOutput = <String>[];
  final _contextFiles = <String>[];
  final _changeHistory = <WorkspaceTurnChanges>[];
  final _notifications = <_AppNotification>[];
  final _toolPermissionPolicies = <String, ToolPermissionPolicy>{};
  // Bumped whenever _notifications changes so an open notifications dialog
  // rebuilds to show additions made while it is on screen.
  final _notificationRevision = ValueNotifier<int>(0);
  // Cumulative provider token spend for the active chat session.
  int _sessionTokens = 0;
  late final PersistentTerminalService _terminalService =
      PersistentTerminalService(
        onOutput: (output) {
          if (mounted) setState(() => _terminalOutput.add(output));
        },
      );

  String _baseUrl = 'https://api.openai.com/v1';
  List<String> _fallbackBaseUrls = const ['http://127.0.0.1:20128/v1'];
  double _inputCostPerMillion = 0;
  double _outputCostPerMillion = 0;
  int _monthlyTokenBudget = 0;
  bool _qualityGateEnabled = true;
  String _activeChatId = DateTime.now().microsecondsSinceEpoch.toString();
  String _model = 'gpt-4.1-mini';
  String _apiKey = '';
  String _workspace = '';
  bool _busy = false;
  bool _loading = true;
  bool _searchMode = false;
  bool _imageGenerationMode = false;
  bool _browserMode = false;
  bool _searchBusy = false;
  bool _allowWrite = true;
  bool _allowTerminal = true;
  ApprovalMode _approvalMode = ApprovalMode.askForApproval;
  bool _providerVerified = false;
  bool _activityPanelVisible = true;
  bool _executionSummaryVisible = false;
  bool _explorerPanelVisible = true;
  bool _terminalVisible = false;
  bool _terminalBusy = false;
  bool _planMode = false;
  _WorkspaceLayout _workspaceLayout = _WorkspaceLayout.classic;
  AgentGoal? _goal;
  TaskGraph? _taskGraph;
  String? _activeFile;
  String? _browserInitialUrl;
  String _agentStatus = 'Siap menerima tugas';
  int _timeoutMs = 120000;
  int _dapTimeoutMs = 30000;
  List<String> _searchResults = [];
  AgentService? _agent;
  CodeIntelligenceService? _codeIntelligence;
  ContextEngine? _contextEngine;
  _AgentTurnState _turnState = _AgentTurnState.idle;
  // Retained for restoring sessions created with the detailed inspector.
  // ignore: unused_field
  _InspectorSection _inspectorSection = _InspectorSection.activity;
  WorkspaceTurnChanges? _pendingChanges;
  WorkspaceTurnChanges? _lastAppliedTurn;

  DateTime? _turnStartedAt;
  Duration _lastTurnDuration = Duration.zero;
  GitStatus _gitStatus = const GitStatus(isRepository: false);
  bool _workspaceTrusted = false;
  bool _budgetWarningShown = false;
  bool _onboardingShown = false;
  bool _updateChecking = false;
  double _explorerWidth = 260;
  double _inspectorWidth = 260;
  Future<void> _persistenceQueue = Future.value();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _updateState(VoidCallback update) => setState(update);

  Future<void> _setWorkspaceLayout(_WorkspaceLayout layout) async {
    setState(() {
      _workspaceLayout = layout;
      if (layout == _WorkspaceLayout.focus) _explorerPanelVisible = true;
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('workspace_layout', layout.name);
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => const _YounzcodeAboutDialog(),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _promptFocusNode.dispose();
    _terminalController.dispose();
    _terminalScrollController.dispose();
    _notificationRevision.dispose();
    unawaited(_terminalService.dispose());
    unawaited(_mediaDownloadService.dispose());
    unawaited(_browserService.shutdown());
    unawaited(_agent?.dispose());
    for (final document in _documents) {
      document.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): _openCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            _openFileSearch,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): _openSearch,
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showRail = constraints.maxWidth >= 760;
              final explorerAvailable = constraints.maxWidth >= 900;
              final showExplorer =
                  explorerAvailable &&
                  _explorerPanelVisible &&
                  _workspaceLayout == _WorkspaceLayout.focus;
              final showInspector = constraints.maxWidth >= 1150;
              final railWidth = showRail
                  ? _workspaceLayout == _WorkspaceLayout.classic
                        ? 266.0
                        : 72.0
                  : 0.0;
              final availableWidth = constraints.maxWidth - railWidth;
              final inspectorWidth = _inspectorWidth
                  .clamp(220.0, math.max(220.0, availableWidth - 580))
                  .toDouble();
              final explorerWidth = _explorerWidth
                  .clamp(
                    220.0,
                    math.max(
                      220.0,
                      availableWidth -
                          (showInspector && _activityPanelVisible
                              ? inspectorWidth + 6
                              : 0) -
                          360,
                    ),
                  )
                  .toDouble();
              return Row(
                children: [
                  if (showRail && _workspaceLayout == _WorkspaceLayout.focus)
                    _CommandRail(
                      onNewChat: _clearChat,
                      onChat: _showChat,
                      onFiles: _chooseWorkspace,
                      onSearch: _openSearch,
                      onImages: _openImageGeneration,
                      onBrowser: _openBrowser,
                      onHistory: _openChatHistory,
                      onAddons: _openAddonManager,
                      onTerminal: _toggleTerminal,
                      onSettings: _openProjectSettings,
                      imageGenerationMode: _imageGenerationMode,
                      browserMode: _browserMode,
                      chatSelected:
                          !_imageGenerationMode &&
                          !_browserMode &&
                          !_searchMode &&
                          _activeFile == null,
                    ),
                  if (showRail && _workspaceLayout == _WorkspaceLayout.classic)
                    _ClassicSidebar(
                      workspace: _workspace,
                      sessions: _chatSessions
                          .where((session) => session.workspace == _workspace)
                          .toList(),
                      activeChatId: _activeChatId,
                      onNewChat: _clearChat,
                      onOpenSession: _restoreChatSession,
                      onPullRequests: _showGitDetails,
                      onScheduled: () => _showMessage(
                        'Scheduled tasks akan hadir pada pembaruan berikutnya.',
                      ),
                      onPlugins: _openAddonManager,
                      onBrowser: _openBrowser,
                      onImages: _openImageGeneration,
                      onTerminal: _toggleTerminal,
                      onHistory: _openChatHistory,
                      onAddons: _openAddonManager,
                      onChooseWorkspace: _chooseWorkspace,
                      onLayoutChanged: (layout) =>
                          unawaited(_setWorkspaceLayout(layout)),
                      workspaceLayout: _workspaceLayout,
                      onAbout: _showAbout,
                      browserMode: _browserMode,
                      imageGenerationMode: _imageGenerationMode,
                      terminalVisible: _terminalVisible,
                      changeCount: _pendingChanges?.files.length ?? 0,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (_workspaceLayout == _WorkspaceLayout.focus)
                          _TopWorkspaceBar(
                            activeFile: _activeFile,
                            searchMode: _searchMode,
                            imageGenerationMode: _imageGenerationMode,
                            browserMode: _browserMode,
                            terminalVisible: _terminalVisible,
                            inspectorVisible:
                                showInspector && _activityPanelVisible,
                            lightMode: widget.lightMode,
                            onExplorer: () => setState(() {
                              _explorerPanelVisible = true;
                              _activeFile = null;
                              _searchMode = false;
                              _imageGenerationMode = false;
                              _browserMode = false;
                            }),
                            onEditor: _workspace.isEmpty ? null : _showEditor,
                            onImages: _openImageGeneration,
                            onBrowser: _openBrowser,
                            onTerminal: _toggleTerminal,
                            onInspector: () => setState(
                              () => _activityPanelVisible =
                                  !_activityPanelVisible,
                            ),
                            onToggleTheme: widget.onToggleTheme,
                            onNotifications: _showNotifications,
                            notificationCount: _notifications.length,
                            workspaceLayout: _workspaceLayout,
                            onLayoutChanged: (layout) =>
                                unawaited(_setWorkspaceLayout(layout)),
                          ),
                        Expanded(
                          child:
                              _workspaceLayout == _WorkspaceLayout.focus &&
                                  constraints.maxWidth >= 900
                              ? _buildFocusWorkspace(
                                  explorerWidth: explorerWidth,
                                  explorerVisible: showExplorer,
                                  showInspector: showInspector,
                                  inspectorWidth: inspectorWidth,
                                )
                              : Row(
                                  key: const ValueKey(
                                    'classic-codex-workspace-layout',
                                  ),
                                  children: [
                                    if (showExplorer)
                                      SizedBox(
                                        width: explorerWidth,
                                        child: _ProjectPanel(
                                          workspace: _workspace,
                                          onOpenFile: _openFile,
                                          onChoose: _chooseWorkspace,
                                          onNewChat: _clearChat,
                                          onChat: _showChat,
                                          onTerminal: _toggleTerminal,
                                          onSettings: _openProjectSettings,
                                          onSearch: _openSearch,
                                          onHistory: _openChatHistory,
                                          onAddons: _openAddonManager,
                                          onHide: () => setState(
                                            () => _explorerPanelVisible = false,
                                          ),
                                        ),
                                      ),
                                    if (showExplorer)
                                      _PanelResizeHandle(
                                        key: const ValueKey(
                                          'explorer-resize-handle',
                                        ),
                                        onDrag: (delta) => setState(
                                          () => _explorerWidth =
                                              (_explorerWidth + delta).clamp(
                                                220.0,
                                                480.0,
                                              ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: AnimatedSwitcher(
                                              duration: _mediumMotion,
                                              child: _browserMode
                                                  ? AgentBrowserPanel(
                                                      key: const ValueKey(
                                                        'agent-browser',
                                                      ),
                                                      service: _browserService,
                                                      workspace: _workspace,
                                                      initialUrl:
                                                          _browserInitialUrl,
                                                      onClose: _showChat,
                                                      onMessage: _showMessage,
                                                    )
                                                  : _imageGenerationMode
                                                  ? _ImageGenerationView(
                                                      key: const ValueKey(
                                                        'image-generation',
                                                      ),
                                                      baseUrl: _baseUrl,
                                                      apiKey: _apiKey,
                                                      models: _models,
                                                      selectedModel: _model,
                                                      headers: _apiHeaders,
                                                      timeoutMs: _timeoutMs,
                                                      onManageModels:
                                                          _openSettings,
                                                    )
                                                  : _searchMode
                                                  ? _SearchView(
                                                      key: const ValueKey(
                                                        'search',
                                                      ),
                                                      controller:
                                                          _searchController,
                                                      results: _searchResults,
                                                      busy: _searchBusy,
                                                      onSearch:
                                                          _searchWorkspace,
                                                      onClose: () => setState(
                                                        () =>
                                                            _searchMode = false,
                                                      ),
                                                      onOpenResult: (path, _) =>
                                                          _openFile(
                                                            '$_workspace${Platform.pathSeparator}$path',
                                                          ),
                                                    )
                                                  : _activeFile != null
                                                  ? _WorkspaceEditor(
                                                      key: const ValueKey(
                                                        'editor',
                                                      ),
                                                      documents: _documents,
                                                      activePath: _activeFile!,
                                                      onSelect: (path) =>
                                                          setState(
                                                            () => _activeFile =
                                                                path,
                                                          ),
                                                      onClose: _closeDocument,
                                                      onSave: _saveDocument,
                                                      onShowChat: _showChat,
                                                      workspace: _workspace,
                                                      trusted:
                                                          _workspaceTrusted,
                                                      dapTimeoutMs:
                                                          _dapTimeoutMs,
                                                    )
                                                  : KeyedSubtree(
                                                      key: const ValueKey(
                                                        'conversation',
                                                      ),
                                                      child: _buildConversation(
                                                        !showExplorer,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          if (_terminalVisible)
                                            SizedBox(
                                              height: 230,
                                              child: _IntegratedTerminal(
                                                controller: _terminalController,
                                                scrollController:
                                                    _terminalScrollController,
                                                output: _terminalOutput,
                                                busy: _terminalBusy,
                                                workspace: _workspace,
                                                onRun: _runTerminalCommand,
                                                onClose: _toggleTerminal,
                                                onClear: () => setState(
                                                  () => _terminalOutput.clear(),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (showInspector &&
                                        _activityPanelVisible) ...[
                                      _PanelResizeHandle(
                                        key: const ValueKey(
                                          'inspector-resize-handle',
                                        ),
                                        onDrag: (delta) => setState(
                                          () => _inspectorWidth =
                                              (_inspectorWidth - delta).clamp(
                                                220.0,
                                                480.0,
                                              ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: inspectorWidth,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: _ClassicEnvironmentPanel(
                                            gitStatus: _gitStatus,
                                            changes: _pendingChanges,
                                            activities: _activities,
                                            terminalBusy: _terminalBusy,
                                            sources: _contextFiles,
                                            onAddSource: _attachContext,
                                            onChanges: _reviewChanges,
                                            onGit: _showGitDetails,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                        _StatusBar(
                          connected: _providerVerified,
                          configured: _apiKey.isNotEmpty,
                          busy: _busy,
                          status: _agentStatus,
                          gitStatus: _gitStatus,
                          onGit: _showGitDetails,
                          workspaceTrusted: _workspaceTrusted,
                          onTrustWorkspace: _trustCurrentWorkspace,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFocusWorkspace({
    required double explorerWidth,
    required bool explorerVisible,
    required bool showInspector,
    required double inspectorWidth,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('focus-workspace-layout'),
      children: [
        if (explorerVisible)
          SizedBox(
            width: explorerWidth,
            child: _ProjectPanel(
              workspace: _workspace,
              onOpenFile: _openFile,
              onChoose: _chooseWorkspace,
              onNewChat: _clearChat,
              onChat: _showChat,
              onTerminal: _toggleTerminal,
              onSettings: _openProjectSettings,
              onSearch: _openSearch,
              onHistory: _openChatHistory,
              onAddons: _openAddonManager,
              onHide: () => setState(() => _explorerPanelVisible = false),
            ),
          ),
        if (explorerVisible)
          _PanelResizeHandle(
            key: const ValueKey('focus-explorer-resize-handle'),
            onDrag: (delta) => setState(
              () =>
                  _explorerWidth = (_explorerWidth + delta).clamp(220.0, 480.0),
            ),
          ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _browserMode
                    ? AgentBrowserPanel(
                        key: const ValueKey('agent-browser'),
                        service: _browserService,
                        workspace: _workspace,
                        initialUrl: _browserInitialUrl,
                        onClose: _showChat,
                        onMessage: _showMessage,
                      )
                    : _imageGenerationMode
                    ? _ImageGenerationView(
                        key: const ValueKey('image-generation'),
                        baseUrl: _baseUrl,
                        apiKey: _apiKey,
                        models: _models,
                        selectedModel: _model,
                        headers: _apiHeaders,
                        timeoutMs: _timeoutMs,
                        onManageModels: _openSettings,
                      )
                    : _searchMode
                    ? _SearchView(
                        key: const ValueKey('search'),
                        controller: _searchController,
                        results: _searchResults,
                        busy: _searchBusy,
                        onSearch: _searchWorkspace,
                        onClose: () => setState(() => _searchMode = false),
                        onOpenResult: (path, _) => _openFile(
                          '$_workspace${Platform.pathSeparator}$path',
                        ),
                      )
                    : _activeFile != null
                    ? _WorkspaceEditor(
                        key: const ValueKey('editor'),
                        documents: _documents,
                        activePath: _activeFile!,
                        onSelect: (path) => setState(() => _activeFile = path),
                        onClose: _closeDocument,
                        onSave: _saveDocument,
                        onShowChat: _showChat,
                        workspace: _workspace,
                        trusted: _workspaceTrusted,
                        dapTimeoutMs: _dapTimeoutMs,
                      )
                    : Container(
                        key: const ValueKey('focus-workspace-empty'),
                        color: colors.surfaceContainerLowest,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/younzcode_logo_new.png',
                              width: 64,
                              height: 64,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'YOUNZCODE',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Pilih file di Explorer atau mulai tugas di Agent',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_terminalVisible)
                SizedBox(
                  height: 230,
                  child: _IntegratedTerminal(
                    controller: _terminalController,
                    scrollController: _terminalScrollController,
                    output: _terminalOutput,
                    busy: _terminalBusy,
                    workspace: _workspace,
                    onRun: _runTerminalCommand,
                    onClose: _toggleTerminal,
                    onClear: () => setState(() => _terminalOutput.clear()),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox.shrink(),
        SizedBox(
          width: math.max(500, showInspector ? inspectorWidth + 140 : 500),
          child: Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: colors.surface),
                child: const Text(
                  'AGENT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: const ValueKey('focus-agent-panel'),
                  child: _buildConversation(false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConversation(bool compact) {
    final colors = Theme.of(context).colorScheme;
    final actionStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    return Column(
      children: [
        if (compact)
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(
                _workspace.isEmpty ? 'Pilih workspace' : _workspace,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _chooseWorkspace,
              trailing: PopupMenuButton<String>(
                tooltip: 'Menu workspace',
                onSelected: (value) {
                  if (value == 'search') _openSearch();
                  if (value == 'settings') _openProjectSettings();
                  if (value == 'new') _clearChat();
                  if (value == 'history') _openChatHistory();
                  if (value == 'addons') _openAddonManager();
                  if (value == 'terminal') _toggleTerminal();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'search',
                    child: Text('Search workspace'),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Text('Project settings'),
                  ),
                  PopupMenuItem(value: 'new', child: Text('New chat')),
                  PopupMenuItem(value: 'history', child: Text('Chat history')),
                  PopupMenuItem(value: 'addons', child: Text('Add-ons')),
                  PopupMenuItem(value: 'terminal', child: Text('Terminal')),
                ],
              ),
            ),
          ),
        Expanded(
          child: _entries.isEmpty && !_busy
              ? _EmptyState(
                  workspaceSelected: _workspace.isNotEmpty,
                  onChooseWorkspace: _chooseWorkspace,
                  onSuggestion: _useSuggestion,
                )
              : SilkyScroll.fromConfig(
                  config: _silkyScrollConfig,
                  controller: _scrollController,
                  builder: (context, controller, physics, _) =>
                      ListView.builder(
                        key: const ValueKey('conversation-list'),
                        controller: controller,
                        physics: physics,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                        itemCount:
                            _entries.length +
                            (_busy ||
                                    _activities.isNotEmpty ||
                                    _turnState != _AgentTurnState.idle
                                ? 1
                                : 0),
                        itemBuilder: (context, index) {
                          final showExecution =
                              _busy ||
                              _activities.isNotEmpty ||
                              _turnState != _AgentTurnState.idle;
                          if (showExecution && index == 0) {
                            return _ConversationLane(
                              child: _busy
                                  ? _AgentWorkingCard(
                                      status: _agentStatus,
                                      activities: _activities,
                                    )
                                  : _executionSummaryVisible
                                  ? _ExecutionSummary(
                                      activities: _activities,
                                      turnState: _turnState,
                                      onRetry: _hasRetryablePrompt
                                          ? _prepareRetryLastPrompt
                                          : null,
                                      onContinue: _agentCheckpoint.isEmpty
                                          ? null
                                          : _prepareCheckpointContinuation,
                                      duration: _lastTurnDuration,
                                      pendingChanges: _pendingChanges,
                                      canRevert: _lastAppliedTurn != null,
                                      onReviewChanges: _pendingChanges == null
                                          ? null
                                          : _reviewChanges,
                                      onRevert: _lastAppliedTurn == null
                                          ? null
                                          : _revertTurn,
                                      onHide: () => setState(
                                        () => _executionSummaryVisible = false,
                                      ),
                                    )
                                  : _ExecutionSummaryToggle(
                                      turnState: _turnState,
                                      duration: _lastTurnDuration,
                                      onShow: () => setState(
                                        () => _executionSummaryVisible = true,
                                      ),
                                    ),
                            );
                          }
                          final entryIndex =
                              _entries.length -
                              1 -
                              index +
                              (showExecution ? 1 : 0);
                          return _ConversationLane(
                            child: _MessageCard(
                              key: ValueKey(_entries[entryIndex]),
                              entry: _entries[entryIndex],
                            ),
                          );
                        },
                      ),
                ),
        ),
        if (_goal != null)
          _GoalBanner(
            goal: _goal!,
            busy: _busy,
            onResume: () => unawaited(_resumeGoal()),
            onPause: () => unawaited(_pauseGoal()),
            onClear: () => unawaited(_clearGoal()),
          ),
        if (_taskGraph != null) TaskGraphBanner(graph: _taskGraph!),
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Container(
              key: const ValueKey('composer-shell'),
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (_workspaceLayout == _WorkspaceLayout.classic)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                      child: Row(
                        children: [
                          TextButton.icon(
                            key: const ValueKey('classic-add-context'),
                            onPressed: _busy ? null : _attachContext,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('ADD'),
                            style: actionStyle,
                          ),
                          const SizedBox(width: 6),
                          TextButton.icon(
                            key: const ValueKey('classic-plugins'),
                            onPressed: _busy ? null : _openAddonManager,
                            icon: const Icon(
                              Icons.extension_outlined,
                              size: 16,
                            ),
                            label: const Text('PLUGINS'),
                            style: actionStyle,
                          ),
                          const SizedBox(width: 6),
                          TextButton.icon(
                            key: const ValueKey('classic-subagent'),
                            onPressed: _busy
                                ? null
                                : () {
                                    _promptController.text = '/agents ';
                                    _promptController.selection =
                                        TextSelection.collapsed(
                                          offset: _promptController.text.length,
                                        );
                                    _promptFocusNode.requestFocus();
                                  },
                            icon: const Icon(
                              Icons.account_tree_outlined,
                              size: 16,
                            ),
                            label: const Text('SUBAGENT'),
                            style: actionStyle,
                          ),
                        ],
                      ),
                    ),
                  _ModelBar(
                    models: _models,
                    selectedModel: _model,
                    busy: _busy,
                    planMode: _planMode,
                    onSelected: _selectModel,
                    onManage: _openSettings,
                    onPlanModeChanged: _setPlanMode,
                  ),
                  _Composer(
                    controller: _promptController,
                    focusNode: _promptFocusNode,
                    busy: _busy,
                    onSend: _send,
                    onStop: () => unawaited(_cancelAgent()),
                    planMode: _planMode,
                    onPlanModeChanged: _setPlanMode,
                    contextFiles: _contextFiles,
                    onAttachContext: _attachContext,
                    onRemoveContext: (file) =>
                        setState(() => _contextFiles.remove(file)),
                    onClearContext: () => setState(() => _contextFiles.clear()),
                    onDropFiles: (files) {
                      if (_workspace.isEmpty) {
                        _showMessage(
                          'Pilih workspace sebelum menambahkan context.',
                        );
                        return;
                      }
                      setState(() {
                        for (final file in files) {
                          if (!_contextFiles.contains(file)) {
                            _contextFiles.add(file);
                          }
                        }
                      });
                    },
                    slashCommands: _slashCommands,
                    onSlashCommand: _runSlashCommand,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
