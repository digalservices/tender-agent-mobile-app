import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/saved_tender.dart';
import '../models/tender.dart';
import '../services/api_client.dart';
import '../services/file_open.dart';
import '../services/tenders_controller.dart';
import '../theme.dart';
import '../widgets/bars.dart';
import '../widgets/tender_card.dart';

enum _Report { market, pipeline, usage }

const _labels = {
  _Report.market: 'Market',
  _Report.pipeline: 'Bid pipeline',
  _Report.usage: 'Agent usage',
};

const _kinds = {
  _Report.market: 'market',
  _Report.pipeline: 'pipeline',
  _Report.usage: 'usage',
};

/// The website's Reports page: the tender market, your bid pipeline and agent usage, each with an Excel download.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.controller});
  final TendersController controller;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _api = ApiClient();
  _Report _tab = _Report.market;
  List<AgentRun>? _runs;
  String? _usageError;
  bool _downloading = false;

  TendersController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_c.feed == null) _c.load();
  }

  Future<void> _loadUsage() async {
    setState(() => _usageError = null);
    try {
      final runs = await _api.activity();
      if (mounted) setState(() => _runs = runs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _usageError = e.message);
    } catch (e) {
      if (mounted) setState(() => _usageError = 'Could not load the runs: $e');
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final file = await _api.reportFile(_kinds[_tab]!);
      final err = await saveAndOpen(file.name, file.bytes);
      if (err != null) _toast(err, error: true);
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('Could not download the report: $e', error: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'The tender market, your bid pipeline and agent usage - with Excel downloads',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final r in _Report.values)
                  ChoiceChip(
                    label: Text(_labels[r]!),
                    selected: _tab == r,
                    onSelected: (_) {
                      setState(() => _tab = r);
                      if (r == _Report.usage && _runs == null) _loadUsage();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ...switch (_tab) {
              _Report.market => _market(),
              _Report.pipeline => _pipeline(),
              _Report.usage => _usage(),
            },
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _downloading ? null : _download,
              icon: _downloading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download),
              label: Text('Download ${_labels[_tab]!.toLowerCase()} report'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String subtitle, Widget child) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(subtitle, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );

  List<(String, num)> _top(Iterable<String> values, [int n = 6]) {
    final counts = <String, int>{};
    for (final v in values) {
      final key = v.trim().isEmpty ? 'Not stated' : v.trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final list = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list.take(n)) (e.key, e.value)];
  }

  // ------------------------------------------------------------------ Market

  List<Widget> _market() {
    final feed = _c.feed;
    if (feed == null) {
      return [
        if (_c.error != null)
          Text(_c.error!)
        else
          const LinearProgressIndicator(),
      ];
    }
    final rows = feed.tenders;
    if (rows.isEmpty) {
      return [Text('The ${feed.source} feed has no active tenders right now.')];
    }
    final valued = rows.map((t) => t.valueCr).whereType<double>();
    final total = valued.fold<double>(0, (a, b) => a + b);
    final strong = rows.where((t) => t.match >= 70).length;
    final avg = rows.fold<int>(0, (a, t) => a + t.match) / rows.length;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final horizon = [for (var n = 0; n < 30; n++) start.add(Duration(days: n))];
    final due = <String, int>{};
    for (final t in rows) {
      final d = t.deadlineDate;
      if (d != null) {
        final key = '${d.year}-${d.month}-${d.day}';
        due[key] = (due[key] ?? 0) + 1;
      }
    }
    final closing = [
      for (final (i, d) in horizon.indexed)
        (
          i % 5 == 0 ? '${d.day}' : '',
          <num>[due['${d.year}-${d.month}-${d.day}'] ?? 0],
        ),
    ];
    final buckets = <(String, num)>[
      ('Strong (85-100%)', rows.where((t) => t.match >= 85).length),
      (
        'Good (70-84%)',
        rows.where((t) => t.match >= 70 && t.match < 85).length,
      ),
      (
        'Fair (50-69%)',
        rows.where((t) => t.match >= 50 && t.match < 70).length,
      ),
      ('Weak (0-49%)', rows.where((t) => t.match < 50).length),
    ];
    final top = [...rows]
      ..sort((a, b) {
        final byMatch = b.match.compareTo(a.match);
        return byMatch != 0
            ? byMatch
            : (a.daysLeft ?? 9999).compareTo(b.daysLeft ?? 9999);
      });
    return [
      KpiGrid(
        tiles: [
          KpiTile(
            label: 'Active tenders',
            value: '${rows.length}',
            icon: Icons.grid_view,
            color: const Color(0xFF2563EB),
          ),
          KpiTile(
            label: 'Combined value',
            value: valued.isEmpty ? '—' : formatValueCr(total),
            icon: Icons.currency_rupee,
            color: const Color(0xFF16A34A),
          ),
          KpiTile(
            label: 'Good matches (70%+)',
            value: '$strong',
            icon: Icons.thumb_up,
            color: const Color(0xFF7C3AED),
          ),
          KpiTile(
            label: 'Average match',
            value: '${avg.round()}%',
            icon: Icons.percent,
            color: const Color(0xFFF59E0B),
          ),
          KpiTile(
            label: 'Closing in 7 days',
            value: '${rows.where((t) => t.closingSoon).length}',
            icon: Icons.schedule,
            color: const Color(0xFFDC2626),
          ),
        ],
      ),
      _section(
        'Top sectors',
        'Active tenders by sector',
        HBarList(items: _top(rows.map((t) => t.category))),
      ),
      _section(
        'Top states',
        'Where the active tenders are',
        HBarList(items: _top(rows.map((t) => t.location))),
      ),
      _section(
        'Deadlines ahead',
        'Tenders closing each day, next 30 days',
        DayBars(days: closing, colors: const [AppColors.blue]),
      ),
      _section(
        'How well they fit you',
        'Tenders by profile match score',
        HBarList(items: buckets),
      ),
      _section(
        'Top 10 matches',
        'Best profile match first',
        Column(
          children: [
            for (final t in top.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${t.department} · ${formatValueCr(t.valueCr)} · ${dueText(t)}',
                ),
                trailing: Pill('${t.match}%', matchColor(t.match)),
              ),
          ],
        ),
      ),
    ];
  }

  // ------------------------------------------------------------------ Bid pipeline

  List<Widget> _pipeline() {
    if (_c.savedError != null) return [Text(_c.savedError!)];
    if (!_c.savedLoaded) return [const LinearProgressIndicator()];
    final saved = _c.saved;
    if (saved.isEmpty) {
      return [
        const Text(
          'No saved tenders yet - save tenders from the Tenders tab to build your bid pipeline.',
        ),
      ];
    }
    final items = [for (final s in saved) (s, s.asTender(_c.live(s.id)))];
    const open = ['Interested', 'Preparing bid', 'Submitted'];
    final openItems = [
      for (final i in items)
        if (open.contains(i.$1.status)) i,
    ];
    final openValue = openItems.fold<double>(
      0,
      (a, i) => a + (i.$2.valueCr ?? 0),
    );
    final won = items.where((i) => i.$1.status == 'Won').length;
    final lost = items.where((i) => i.$1.status == 'Lost').length;
    final stage = <(String, num)>[
      for (final s in bidStatuses)
        (s, items.where((i) => i.$1.status == s).length),
    ];
    final stageValue = <(String, num)>[
      for (final s in bidStatuses)
        (
          s,
          double.parse(
            items
                .where((i) => i.$1.status == s)
                .fold<double>(0, (a, i) => a + (i.$2.valueCr ?? 0))
                .toStringAsFixed(2),
          ),
        ),
    ];
    final upcoming = [
      for (final i in openItems)
        if ((i.$2.daysLeft ?? -1) >= 0) i,
    ]..sort((a, b) => a.$2.daysLeft!.compareTo(b.$2.daysLeft!));
    return [
      KpiGrid(
        tiles: [
          KpiTile(
            label: 'Saved tenders',
            value: '${items.length}',
            icon: Icons.bookmark,
            color: const Color(0xFF2563EB),
          ),
          KpiTile(
            label: 'Open pipeline value',
            value: openValue == 0 ? '—' : formatValueCr(openValue),
            icon: Icons.currency_rupee,
            color: const Color(0xFF7C3AED),
          ),
          KpiTile(
            label: 'Submitted',
            value: '${items.where((i) => i.$1.status == 'Submitted').length}',
            icon: Icons.send,
            color: const Color(0xFF0891B2),
          ),
          KpiTile(
            label: 'Won',
            value: '$won',
            icon: Icons.emoji_events,
            color: const Color(0xFF16A34A),
          ),
          KpiTile(
            label: 'Win rate',
            value: won + lost == 0
                ? '—'
                : '${(100 * won / (won + lost)).round()}%',
            icon: Icons.percent,
            color: const Color(0xFFF59E0B),
          ),
        ],
      ),
      _section(
        'Tenders by stage',
        'From first interest to result',
        HBarList(items: stage),
      ),
      _section(
        'Value by stage',
        'Combined stated tender value, ₹ crore',
        HBarList(items: stageValue, color: const Color(0xFF7C3AED)),
      ),
      _section(
        'Upcoming deadlines in your pipeline',
        'Open bids, soonest first',
        upcoming.isEmpty
            ? const Text('No open bids with an upcoming deadline.')
            : Column(
                children: [
                  for (final i in upcoming)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        i.$2.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${i.$1.status} · ${formatValueCr(i.$2.valueCr)}'
                        '${i.$1.note.isEmpty ? '' : ' · ${i.$1.note}'}',
                      ),
                      trailing: Text('${i.$2.daysLeft} days'),
                    ),
                ],
              ),
      ),
    ];
  }

  // ------------------------------------------------------------------ Agent usage

  List<Widget> _usage() {
    if (_usageError != null) {
      return [
        Text(_usageError!),
        TextButton(onPressed: _loadUsage, child: const Text('Try again')),
      ];
    }
    final all = _runs;
    if (all == null) {
      return [const LinearProgressIndicator()]; // the chip tap starts the load
    }
    final runs = [
      for (final r in all)
        if (r.startedAt != null) r,
    ];
    if (runs.isEmpty) {
      return [
        const Text(
          'No agent runs yet - ask the AI agent something and it will show up here.',
        ),
      ];
    }
    final ok = runs.where((r) => r.ok).length;
    final byKind = _top(runs.map((r) => r.kind), 8);
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final oldest = runs
        .map((r) => r.startedAt!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final span =
        (start
                    .difference(DateTime(oldest.year, oldest.month, oldest.day))
                    .inDays +
                1)
            .clamp(1, 30);
    final perDay = [
      for (var n = span - 1; n >= 0; n--)
        (
          span <= 10 || n % 5 == 0
              ? '${start.subtract(Duration(days: n)).day}'
              : '',
          <num>[
            runs
                .where((r) {
                  final d = start.subtract(Duration(days: n));
                  return r.startedAt!.year == d.year &&
                      r.startedAt!.month == d.month &&
                      r.startedAt!.day == d.day;
                })
                .fold<int>(0, (a, r) => a + r.tokens),
          ],
        ),
    ];
    return [
      KpiGrid(
        tiles: [
          KpiTile(
            label: 'Agent runs',
            value: '${runs.length}',
            icon: Icons.smart_toy,
            color: const Color(0xFF2563EB),
          ),
          KpiTile(
            label: 'Success rate',
            value: '${(100 * ok / runs.length).round()}%',
            icon: Icons.task_alt,
            color: const Color(0xFF16A34A),
          ),
          KpiTile(
            label: 'Tenders found',
            value: '${runs.fold<int>(0, (a, r) => a + r.tendersFound)}',
            icon: Icons.search,
            color: const Color(0xFF7C3AED),
          ),
          KpiTile(
            label: 'Total run time',
            value: formatDuration(
              runs.fold<double>(0, (a, r) => a + r.durationS),
            ),
            icon: Icons.timer,
            color: const Color(0xFFF59E0B),
          ),
          KpiTile(
            label: 'AI tokens',
            value: formatTokens(runs.fold<int>(0, (a, r) => a + r.tokens)),
            icon: Icons.token,
            color: const Color(0xFF0891B2),
          ),
          KpiTile(
            label: 'Est. AI cost (US\$)',
            value: formatCost(runs.fold<double>(0, (a, r) => a + r.costUsd)),
            icon: Icons.payments,
            color: const Color(0xFFDC2626),
          ),
        ],
      ),
      _section(
        'What the agent was used for',
        'Runs by type',
        HBarList(items: byKind),
      ),
      _section(
        'AI tokens per day',
        'Last $span days',
        DayBars(days: perDay, colors: const [AppColors.blue]),
      ),
    ];
  }
}
