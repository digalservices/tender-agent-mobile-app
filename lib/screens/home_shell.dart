import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/chat_controller.dart';
import '../services/tenders_controller.dart';
import 'ai_analysis_screen.dart';
import 'activity_screen.dart';
import 'comparisons_screen.dart';
import 'dashboard_screen.dart';
import 'reports_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'tenders_screen.dart';

/// The signed-in app: bottom navigation mirroring the web app's sidebar.
/// Each tab is a placeholder until its screen is built.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.user, required this.auth});
  final User user;
  final AuthService auth;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final TendersController _tenders = TendersController(widget.user.uid);

  final _chat = ChatController();

  @override
  void dispose() {
    _chat.dispose();
    _tenders.dispose();
    super.dispose();
  }

  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'Dashboard'),
    (Icons.list_alt_outlined, Icons.list_alt, 'Tenders'),
    (Icons.psychology_outlined, Icons.psychology, 'AI Analysis'),
    (Icons.bookmark_border, Icons.bookmark, 'Saved'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  /// A Tender Agent quick action / question: queued for the AI Analysis chat, which opens.
  void _ask(String question) => setState(() {
    _tenders.pendingQuestion = question;
    _index = 2;
  });

  void _openTenders(TenderFilter filter) => setState(() {
    _tenders.requestedFilter = filter;
    _index = 1;
  });

  /// Leaves a pushed screen (Comparisons, Agent Activity, Reports) and runs `then` on the tab bar.
  void _backToTabs(BuildContext context, VoidCallback then) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    then();
  }

  void _open(BuildContext context, String screen) {
    final page = switch (screen) {
      'comparisons' => ComparisonsScreen(
        controller: _tenders,
        onAsk: (q) => _backToTabs(context, () => _ask(q)),
        onBrowse: () =>
            _backToTabs(context, () => _openTenders(TenderFilter.all)),
      ),
      'activity' => ActivityScreen(
        onAsk: (q) => _backToTabs(context, () => _ask(q)),
      ),
      _ => ReportsScreen(controller: _tenders),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _body(String title) => switch (_index) {
    0 => DashboardScreen(
      user: widget.user,
      controller: _tenders,
      onOpenTenders: _openTenders,
      onOpenSaved: () => setState(() => _index = 3),
      onAsk: _ask,
    ),
    1 => TendersScreen(controller: _tenders),
    2 => AiAnalysisScreen(
      key: const ValueKey('ai'),
      user: widget.user,
      auth: widget.auth,
      chat: _chat,
      tenders: _tenders,
    ),
    3 => SavedScreen(
      controller: _tenders,
      onBrowse: () => _openTenders(TenderFilter.all),
      onAsk: _ask,
    ),
    4 => SettingsScreen(user: widget.user, auth: widget.auth),
    _ => Center(child: Text('$title screen - coming next.')),
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _chat,
    builder: (context, _) => _scaffold(context),
  );

  Widget _scaffold(BuildContext context) {
    final title = _tabs[_index].$3;
    // While the AI answers on the AI Analysis tab, the other tabs and menus are switched off, as on the website.
    final locked = _index == 2 && _chat.running;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !locked,
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => _open(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'comparisons',
                child: ListTile(
                  leading: Icon(Icons.compare_arrows),
                  title: Text('Comparisons'),
                ),
              ),
              PopupMenuItem(
                value: 'activity',
                child: ListTile(
                  leading: Icon(Icons.monitor_heart_outlined),
                  title: Text('Agent & Tender Activity'),
                ),
              ),
              PopupMenuItem(
                value: 'reports',
                child: ListTile(
                  leading: Icon(Icons.bar_chart),
                  title: Text('Reports'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: locked ? null : widget.auth.signOut,
          ),
        ],
      ),
      body: _body(title),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              enabled: !locked,
              icon: Icon(t.$1),
              selectedIcon: Icon(t.$2),
              label: t.$3,
            ),
        ],
      ),
    );
  }
}
