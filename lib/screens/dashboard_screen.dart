import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/tender.dart';
import '../models/tender_filters.dart';
import '../services/company_service.dart';
import '../services/tenders_controller.dart';
import '../widgets/filter_card.dart';
import '../widgets/tender_agent_panel.dart';
import '../widgets/tender_card.dart';

const _pageSize = 5; // same as the website

/// Overview: greeting, the counts, search & filter, the tenders list with pages, and the Tender Agent panel.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    required this.controller,
    required this.onOpenTenders,
    required this.onOpenSaved,
    required this.onAsk,
  });
  final User user;
  final TendersController controller;

  /// Open the Tenders tab, filtered.
  final void Function(TenderFilter filter) onOpenTenders;

  /// Open the Saved tab (the Saved tile).
  final VoidCallback onOpenSaved;

  /// Send a question to the AI Analysis chat.
  final void Function(String question) onAsk;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final Future<Map<String, dynamic>> _company = CompanyService()
      .load(widget.user.uid)
      .catchError((_) => <String, dynamic>{});
  final _panelKey = GlobalKey();
  final _tableKey = GlobalKey();

  TenderFilters _filters = const TenderFilters();
  TenderTab _tab = TenderTab.all;
  TenderSort _sort = TenderSort.deadlineEarliest;
  int _page = 1;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    if (widget.controller.feed == null) widget.controller.load();
  }

  String _firstName(Map<String, dynamic> company) {
    final person = '${company['contact_person'] ?? ''}'.trim();
    final name = person.isNotEmpty
        ? person
        : (widget.user.email ?? '').split('@').first;
    final first = name.split(RegExp(r'\s+')).first;
    return first.isEmpty
        ? ''
        : first[0].toUpperCase() + first.substring(1).toLowerCase();
  }

  String _part() {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Morning'
        : h < 17
        ? 'Afternoon'
        : 'Evening';
  }

  void _scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null)
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
    });
  }

  void _setTab(TenderTab tab) {
    setState(() {
      _tab = tab;
      _page = 1;
    });
    _scrollTo(_tableKey);
  }

  Future<void> _toggleSaved(Tender t) async {
    final error = await widget.controller.toggleSaved(t);
    if (error != null && mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final feed = c.feed;
        if (feed == null) {
          if (c.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: c.load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }

        final all = feed.tenders;
        final text = Theme.of(context).textTheme;
        final rows = bestMatchesFirst(
          sortTenders(_filters.apply(all).where((t) => inTab(t, _tab)), _sort),
          _filters.query,
        );
        final pages = rows.isEmpty ? 1 : (rows.length / _pageSize).ceil();
        final page = _page.clamp(1, pages);
        final start = (page - 1) * _pageSize;
        final pageRows = rows.skip(start).take(_pageSize).toList();

        // Until a card is tapped, the panel shows the best match, like the website.
        final selected =
            (_selectedId == null ? null : c.live(_selectedId!)) ??
            (all.isEmpty
                ? null
                : all.reduce((a, b) => b.match > a.match ? b : a));

        Widget tile(
          String label,
          int? value,
          IconData icon,
          Color color,
          VoidCallback? onTap,
        ) => Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withAlpha(30),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value?.toString() ?? '-',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          label,
                          style: text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return RefreshIndicator(
          onRefresh: c.load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FutureBuilder<Map<String, dynamic>>(
                  future: _company,
                  builder: (context, snap) {
                    final name = snap.hasData ? _firstName(snap.data!) : '';
                    return Text(
                      'Good ${_part()}${name.isEmpty ? '' : ', $name'}! 👋',
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    );
                  },
                ),
                Text(
                  "Here's your tender intelligence overview",
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.1,
                  children: [
                    tile(
                      'Total tenders',
                      feed.kpis['total'],
                      Icons.grid_view,
                      Colors.blue,
                      () => _setTab(TenderTab.all),
                    ),
                    tile(
                      'New tenders',
                      feed.kpis['new'],
                      Icons.fiber_new,
                      Colors.green,
                      () => _setTab(TenderTab.newOnes),
                    ),
                    tile(
                      'Closing soon',
                      feed.kpis['closing'],
                      Icons.schedule,
                      Colors.orange,
                      () => _setTab(TenderTab.closing),
                    ),
                    tile(
                      'High value',
                      feed.kpis['high_value'],
                      Icons.currency_rupee,
                      Colors.purple,
                      () => _setTab(TenderTab.highValue),
                    ),
                    tile(
                      'High risk',
                      feed.kpis['high_risk'],
                      Icons.warning_amber,
                      Colors.red,
                      () => widget.onOpenTenders(TenderFilter.highRisk),
                    ),
                    tile(
                      'Saved',
                      c.savedLoaded ? c.saved.length : null,
                      Icons.bookmark,
                      Colors.teal,
                      widget.onOpenSaved,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilterCard(
                  tenders: all,
                  filters: _filters,
                  onChanged: (f) => setState(() {
                    _filters = f;
                    _page = 1;
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  key: _tableKey,
                  children: [
                    Expanded(
                      child: Text(
                        'Latest Tenders',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text('Sort by ', style: text.bodySmall),
                    DropdownButton<TenderSort>(
                      value: _sort,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final s in TenderSort.values)
                          DropdownMenuItem(
                            value: s,
                            child: Text(sortLabels[s]!),
                          ),
                      ],
                      onChanged: (s) => setState(() {
                        _sort = s ?? _sort;
                        _page = 1;
                      }),
                    ),
                  ],
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final tab in TenderTab.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${tab == TenderTab.all ? 'All' : tabLabels[tab]} (${switch (tab) {
                                    TenderTab.all => feed.kpis['total'],
                                    TenderTab.newOnes => feed.kpis['new'],
                                    TenderTab.closing => feed.kpis['closing'],
                                    TenderTab.highValue => feed.kpis['high_value'],
                                  } ?? 0})',
                            ),
                            selected: _tab == tab,
                            onSelected: (_) => setState(() {
                              _tab = tab;
                              _page = 1;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                if (pageRows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No tenders match these filters.'),
                    ),
                  ),
                for (final t in pageRows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TenderCard(
                      tender: t,
                      selected: selected?.id == t.id,
                      saved: c.savedIds.contains(t.id),
                      onSave: () => _toggleSaved(t),
                      onTap: () {
                        setState(() => _selectedId = t.id);
                        _scrollTo(
                          _panelKey,
                        ); // Analyze: show it in the Tender Agent panel below
                      },
                    ),
                  ),
                Text(
                  rows.isEmpty
                      ? 'Showing 0 of 0 tenders'
                      : 'Showing ${start + 1} to ${start + pageRows.length} of ${rows.length} tenders',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 8),
                _Pager(
                  page: page,
                  pages: pages,
                  onPage: (p) {
                    setState(() => _page = p);
                    _scrollTo(_tableKey);
                  },
                ),
                const SizedBox(height: 16),
                if (selected != null)
                  KeyedSubtree(
                    key: _panelKey,
                    child: TenderAgentPanel(
                      tender: selected,
                      saved: c.savedIds.contains(selected.id),
                      onSave: () => _toggleSaved(selected),
                      onRefresh: c.load,
                      onAsk: widget.onAsk,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Live from ${feed.source}. Match and risk are quick screening figures from your profile.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Page buttons like  ‹ 1 2 3 4 5 … 100 ›.
class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.pages, required this.onPage});
  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    Widget button(Widget child, VoidCallback? onTap, {bool active = false}) =>
        SizedBox(
          width: 40,
          height: 40,
          child: active
              ? FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: onTap,
                  child: child,
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: onTap,
                  child: child,
                ),
        );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        button(
          const Icon(Icons.chevron_left),
          page > 1 ? () => onPage(page - 1) : null,
        ),
        for (final p in pageWindow(page, pages))
          p == null
              ? button(const Text('…'), null)
              : button(Text('$p'), () => onPage(p), active: p == page),
        button(
          const Icon(Icons.chevron_right),
          page < pages ? () => onPage(page + 1) : null,
        ),
      ],
    );
  }
}
