import 'package:flutter/material.dart';

import '../models/compare.dart';
import '../models/tender.dart';
import '../services/tenders_controller.dart';
import '../theme.dart';
import '../widgets/tender_agent_panel.dart';
import '../widgets/tender_card.dart';
import 'tender_detail_screen.dart';
import 'tenders_screen.dart' show matchesQuery;

/// The website's Comparisons page: up to four tenders side by side, the best value in each row marked,
/// a recommendation, and a button to ask the AI for a detailed comparison.
class ComparisonsScreen extends StatefulWidget {
  const ComparisonsScreen({
    super.key,
    required this.controller,
    required this.onAsk,
    required this.onBrowse,
  });
  final TendersController controller;

  /// Sends a question to the AI Analysis chat (and leaves this screen).
  final void Function(String question) onAsk;

  /// Opens the Tenders tab (and leaves this screen).
  final VoidCallback onBrowse;

  @override
  State<ComparisonsScreen> createState() => _ComparisonsScreenState();
}

class _ComparisonsScreenState extends State<ComparisonsScreen> {
  TendersController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_c.feed == null) _c.load();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pick() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _Picker(controller: _c, onMessage: _toast),
    );
  }

  Future<void> _toggleSaved(Tender t) async {
    final err = await _c.toggleSaved(t);
    if (err != null && mounted) _toast(err);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comparisons')),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final feed = _c.feed;
          if (feed == null) {
            return Center(
              child: _c.error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_c.error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _c.load,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(),
            );
          }
          final byId = {..._c.known, for (final t in feed.tenders) t.id: t};
          // Drop any that have left the feed since they were added.
          final items = [
            for (final id in _c.compareIds)
              if (byId[id] != null) byId[id]!,
          ];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Put up to four tenders side by side and pick the one to bid on',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.add),
                label: Text('Choose tenders (${items.length}/$maxCompare)'),
              ),
              const SizedBox(height: 4),
              Text(
                'Tip: the compare icon on a tender card or tender page adds it here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (items.length < 2)
                _empty(items.length)
              else
                ..._compare(items),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(int count) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.compare_arrows, size: 44, color: AppColors.blue),
          const SizedBox(height: 8),
          Text(
            count == 0 ? 'Nothing to compare yet' : 'Add one more tender',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Pick at least two tenders to see value, deadline, risk and how well each fits your company, side by side.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.onBrowse,
            child: const Text('Browse tenders'),
          ),
        ],
      ),
    ),
  );

  List<Widget> _compare(List<Tender> items) {
    final best = <String, Set<int>>{
      'match': bestIndexes([for (final t in items) t.match]),
      'risk': bestIndexes([
        for (final t in items) riskRank(t.risk),
      ], higher: false),
      'value': bestIndexes([for (final t in items) t.valueCr]),
      'emd': bestIndexes([for (final t in items) t.emdCr], higher: false),
      'doc': bestIndexes([for (final t in items) t.docCostCr], higher: false),
      'time': bestIndexes([for (final t in items) t.daysLeft]),
      'met': bestIndexes([for (final t in items) requirementsMet(t).$1]),
      for (final name in items.first.analysis.keys)
        name: bestIndexes([for (final t in items) t.analysis[name]]),
    };
    final pick = recommended(items);
    final reasons = [
      best['match']!.contains(items.indexOf(pick))
          ? 'highest profile match (${pick.match}%)'
          : '${pick.match}% profile match',
      '${pick.risk.toLowerCase()} risk',
      if (pick.daysLeft != null) '${pick.daysLeft} days to prepare',
    ];
    final listing = [
      for (final (n, t) in items.indexed)
        '${n + 1}. "${t.title}" (ID ${t.id}, ${t.department})',
    ].join('\n');
    return [
      Card(
        color: const Color(0xFFEEF4FF),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.workspace_premium, color: AppColors.blue),
                  SizedBox(width: 6),
                  Text(
                    'RECOMMENDED',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                pick.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${reasons.join(', ')}.'.replaceFirstMapped(
                  RegExp(r'^.'),
                  (m) => m[0]!.toUpperCase(),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => widget.onAsk(
                  'Compare these tenders for our company, criterion by criterion (eligibility, turnover and '
                  'experience criteria, EMD, scope fit, deadline, risks), and recommend which one to bid on '
                  'and why. Open each tender\'s details first.\n$listing',
                ),
                icon: const Icon(Icons.psychology),
                label: const Text('Ask AI for a detailed comparison'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 700,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (i, t) in items.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 300,
                  child: _card(t, i, best, identical(t, pick)),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Swipe sideways to see every tender. Match and risk are quick screening figures, not an eligibility check.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  Widget _row(
    String label,
    Widget value, {
    bool best = false,
    String bestLabel = 'Best',
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
    margin: const EdgeInsets.only(bottom: 2),
    decoration: BoxDecoration(
      color: best ? Colors.green.withAlpha(24) : null,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: const TextStyle(fontSize: 12.5)),
        ),
        Expanded(child: value),
        if (best) Pill(bestLabel, Colors.green.shade700),
      ],
    ),
  );

  Widget _bar(int v) => Row(
    children: [
      SizedBox(width: 38, child: Text('$v%')),
      Expanded(
        child: LinearProgressIndicator(
          value: v / 100,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          color: matchColor(v),
        ),
      ),
    ],
  );

  Widget _card(Tender t, int i, Map<String, Set<int>> best, bool isPick) {
    final (met, total) = requirementsMet(t);
    final due = t.deadline == null
        ? 'Not stated'
        : '${t.deadline} · ${t.daysLeft == null ? '' : '${t.daysLeft} days left'}';
    final saved = _c.savedIds.contains(t.id);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isPick
            ? const BorderSide(color: AppColors.blue, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPick)
              const Pill('Best fit', AppColors.blue)
            else
              const SizedBox(height: 22),
            const SizedBox(height: 4),
            Text(
              t.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${t.department} · ID ${t.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${t.match}%',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: matchColor(t.match),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('profile match'),
                if (best['match']!.contains(i)) ...[
                  const SizedBox(width: 6),
                  Pill('Best', Colors.green.shade700),
                ],
              ],
            ),
            LinearProgressIndicator(
              value: t.match / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: matchColor(t.match),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  _row(
                    'Risk',
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Pill(t.risk, riskColor(t.risk)),
                    ),
                    best: best['risk']!.contains(i),
                    bestLabel: 'Lowest',
                  ),
                  _row(
                    'Estimated value',
                    Text(formatValueCr(t.valueCr)),
                    best: best['value']!.contains(i),
                    bestLabel: 'Highest',
                  ),
                  _row(
                    'EMD',
                    Text(formatValueCr(t.emdCr)),
                    best: best['emd']!.contains(i),
                    bestLabel: 'Lowest',
                  ),
                  _row(
                    'Document fee',
                    Text(formatValueCr(t.docCostCr)),
                    best: best['doc']!.contains(i),
                    bestLabel: 'Lowest',
                  ),
                  _row(
                    'Bid deadline',
                    Text(due),
                    best: best['time']!.contains(i),
                    bestLabel: 'Most time',
                  ),
                  for (final e in t.analysis.entries)
                    _row(
                      e.key,
                      _bar(e.value),
                      best: best[e.key]?.contains(i) ?? false,
                    ),
                  _row(
                    'Requirements met',
                    Text('$met of $total'),
                    best: best['met']!.contains(i),
                  ),
                  _row(
                    'Location',
                    Text(
                      t.subDepartment.isEmpty ? t.location : t.subDepartment,
                    ),
                  ),
                  _row('Category', Text(t.category)),
                  _row('Tender type', Text(t.type)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                    ),
                    onPressed: () => widget.onAsk(
                      quickQuestion(quickActions['Analyze Eligibility']!, t),
                    ),
                    child: const Text('Analyze'),
                  ),
                ),
                IconButton(
                  tooltip: 'Details',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TenderDetailScreen(tender: t, controller: _c),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: saved ? 'Remove from saved' : 'Save',
                  icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: () => _toggleSaved(t),
                ),
                IconButton(
                  tooltip: 'Remove from comparison',
                  icon: const Icon(Icons.close),
                  onPressed: () => _c.removeCompare(t.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The bottom sheet for choosing which tenders to compare.
class _Picker extends StatefulWidget {
  const _Picker({required this.controller, required this.onMessage});
  final TendersController controller;
  final void Function(String) onMessage;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final tenders = [
      for (final t in c.feed?.tenders ?? const <Tender>[])
        if (matchesQuery(t, _query)) t,
    ];
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by title or BID NO',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tenders.length > 60 ? 60 : tenders.length,
              itemBuilder: (context, i) {
                final t = tenders[i];
                return CheckboxListTile(
                  dense: true,
                  value: c.compareIds.contains(t.id),
                  title: Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('BID NO ${t.id} · ${t.match}% match'),
                  onChanged: (_) {
                    final msg = c.toggleCompare(t);
                    if (msg != null) widget.onMessage(msg);
                    setState(() {});
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Done (${c.compareIds.length}/$maxCompare)'),
            ),
          ),
        ],
      ),
    );
  }
}
