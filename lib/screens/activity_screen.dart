import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../services/api_client.dart';
import '../widgets/bars.dart';
import '../widgets/tender_activity_view.dart';
import '../widgets/tender_card.dart';

const _kindStyle = <String, (IconData, Color)>{
  'Tender search': (Icons.travel_explore, Color(0xFF2563EB)),
  'Question': (Icons.forum, Color(0xFF7C3AED)),
  'Eligibility check': (Icons.checklist, Color(0xFF16A34A)),
  'Bid documents': (Icons.edit_document, Color(0xFFF59E0B)),
  'Price bid': (Icons.request_quote, Color(0xFF0891B2)),
  'Pre-check': (Icons.fact_check, Color(0xFF64748B)),
};

const _periods = <String, int?>{'7 days': 7, '30 days': 30, 'All time': null};

/// The website's Agent Activity page: every run of the AI agent - what it searched, read and found.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.onAsk, this.api});

  /// For tests: a stand-in for the server.
  final ApiClient? api;

  /// Sends a question to the AI Analysis chat again (and leaves this screen).
  final void Function(String question) onAsk;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  List<AgentRun>? _runs;
  String? _error;
  String _period = '30 days';
  String _kind = 'All';
  bool _errorsOnly = false;
  bool _tenders = false; // Agent (the default) | Tenders
  int _limit = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final runs = await _api.activity();
      if (mounted) setState(() => _runs = runs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load the activity: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent & Tender Activity'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.smart_toy),
                    label: Text('Agent'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.travel_explore),
                    label: Text('Tenders'),
                  ),
                ],
                selected: {_tenders},
                onSelectionChanged: (v) => setState(() => _tenders = v.first),
              ),
            ),
          ),
          Expanded(
            child: _tenders
                ? TenderActivityView(runs: _runs ?? const [], api: widget.api)
                : _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final all = _runs;
    if (all == null) return const Center(child: CircularProgressIndicator());
    if (all.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No activity yet. Each time you ask the AI agent something, the run shows up here with every step it took.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final days = _periods[_period];
    final now = DateTime.now();
    final runs = [
      for (final r in all)
        if (r.startedAt != null &&
            (days == null || now.difference(r.startedAt!).inDays < days))
          r,
    ];
    final ok = runs.where((r) => r.ok).length;
    final searches = runs.fold<int>(
      0,
      (n, r) =>
          n +
          r.steps
              .where((s) => s.startsWith('🔎') || s.startsWith('🌐 Web search'))
              .length,
    );
    final reads = runs.fold<int>(
      0,
      (n, r) =>
          n +
          r.steps
              .where(
                (s) =>
                    s.startsWith('📄') ||
                    s.startsWith('📥') ||
                    s.startsWith('📚') ||
                    s.startsWith('🌐 Reading'),
              )
              .length,
    );
    final tokens = runs.fold<int>(0, (n, r) => n + r.tokens);
    final cost = runs.fold<double>(0, (n, r) => n + r.costUsd);
    final avg = runs.isEmpty
        ? 0.0
        : runs.fold<double>(0, (n, r) => n + r.durationS) / runs.length;
    final kinds = [
      'All',
      ...{for (final r in runs) r.kind},
    ];
    final shown = [
      for (final r in runs)
        if ((_kind == 'All' || r.kind == _kind) && (!_errorsOnly || !r.ok)) r,
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Every question the AI agent worked on - what it searched, read and found',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final p in _periods.keys)
                ChoiceChip(
                  label: Text(p),
                  selected: _period == p,
                  onSelected: (_) => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: 12),
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
                value: runs.isEmpty
                    ? '—'
                    : '${(100 * ok / runs.length).round()}%',
                icon: Icons.task_alt,
                color: const Color(0xFF16A34A),
              ),
              KpiTile(
                label: 'Avg run time',
                value: runs.isEmpty ? '—' : formatDuration(avg),
                icon: Icons.timer,
                color: const Color(0xFFF59E0B),
              ),
              KpiTile(
                label: 'Searches made',
                value: '$searches',
                icon: Icons.search,
                color: const Color(0xFF7C3AED),
              ),
              KpiTile(
                label: 'Pages & docs read',
                value: '$reads',
                icon: Icons.menu_book,
                color: const Color(0xFF0891B2),
              ),
              KpiTile(
                label: 'AI tokens',
                value: formatTokens(tokens),
                icon: Icons.token,
                color: const Color(0xFF64748B),
              ),
              KpiTile(
                label: 'Est. AI cost (US\$)',
                value: formatCost(cost),
                icon: Icons.payments,
                color: const Color(0xFFDC2626),
              ),
            ],
          ),
          if (runs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('No agent runs in the last $_period.')),
            )
          else ...[
            const SizedBox(height: 16),
            _chart(runs, days, now),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final k in kinds)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(k),
                        selected: _kind == k,
                        onSelected: (_) => setState(() {
                          _kind = k;
                          _limit = 20;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Errors only'),
              value: _errorsOnly,
              onChanged: (v) => setState(() {
                _errorsOnly = v;
                _limit = 20;
              }),
            ),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No runs match these filters.'),
              ),
            ..._list(shown.take(_limit).toList()),
            if (shown.length > _limit)
              TextButton(
                onPressed: () => setState(() => _limit += 20),
                child: Text('Show more (${shown.length - _limit} older)'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chart(List<AgentRun> runs, int? days, DateTime now) {
    final oldest = runs
        .map((r) => r.startedAt!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final span = days ?? (now.difference(oldest).inDays + 1).clamp(1, 30);
    final today = DateTime(now.year, now.month, now.day);
    final bars = <(String, List<num>)>[];
    for (var n = span - 1; n >= 0; n--) {
      final day = today.subtract(Duration(days: n));
      final of = runs.where(
        (r) =>
            r.startedAt!.year == day.year &&
            r.startedAt!.month == day.month &&
            r.startedAt!.day == day.day,
      );
      bars.add((
        span <= 10 || n % 5 == 0 ? '${day.day}' : '',
        [of.where((r) => r.ok).length, of.where((r) => !r.ok).length],
      ));
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Runs per day',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${runs.length} runs, last $span days · green = success, red = error',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            DayBars(
              days: bars,
              colors: [Colors.green.shade600, Colors.red.shade600],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _list(List<AgentRun> runs) {
    final out = <Widget>[];
    DateTime? lastDay;
    for (final r in runs) {
      final when = r.startedAt!;
      final day = DateTime(when.year, when.month, when.day);
      if (lastDay != day) {
        lastDay = day;
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              dayLabel(when).toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      out.add(_runCard(r, when));
    }
    return out;
  }

  Widget _runCard(AgentRun r, DateTime when) {
    final style =
        _kindStyle[r.kind] ?? (Icons.smart_toy, const Color(0xFF2563EB));
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final time =
        '$hour:${when.minute.toString().padLeft(2, '0')} ${when.hour < 12 ? 'AM' : 'PM'}';
    final meta = [
      time,
      formatDuration(r.durationS),
      '${r.steps.length} step${r.steps.length == 1 ? '' : 's'}',
      if (r.tendersFound > 0) '${r.tendersFound} tenders found',
      if (r.tokens > 0)
        '${formatTokens(r.tokens)} tokens · ≈${formatCost(r.costUsd)}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.$1, color: style.$2, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.kind,
                    style: TextStyle(
                      color: style.$2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Pill(
                  r.ok ? 'Success' : 'Error',
                  r.ok ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(r.question, maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(meta, style: const TextStyle(fontSize: 12)),
            if (r.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  r.error,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
                ),
              ),
            if (r.steps.isNotEmpty)
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'What the agent did (${r.steps.length} steps)',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  children: [
                    for (final s in r.steps)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            s,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Answered directly, without searching.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            if (r.question.isNotEmpty && r.kind != 'Pre-check')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => widget.onAsk(r.question),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Run again'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
