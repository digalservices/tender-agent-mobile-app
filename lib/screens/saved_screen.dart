import 'package:flutter/material.dart';

import '../models/saved_tender.dart';
import '../models/tender.dart';
import '../services/tender_files.dart';
import '../services/tenders_controller.dart';
import '../theme.dart';
import '../widgets/tender_agent_panel.dart';
import '../widgets/tender_card.dart';
import 'tender_detail_screen.dart';

Color statusColor(String s) => switch (s) {
  'Preparing bid' => Colors.orange.shade800,
  'Submitted' => Colors.deepPurple,
  'Won' => Colors.green.shade700,
  'Lost' => Colors.blueGrey,
  _ => AppColors.blue,
};

/// Tenders the company bookmarked: track each one from "Interested" to the result, with a note.
class SavedScreen extends StatefulWidget {
  const SavedScreen({
    super.key,
    required this.controller,
    required this.onBrowse,
    required this.onAsk,
  });
  final TendersController controller;
  final VoidCallback onBrowse;

  /// Sends a question to the AI Analysis chat (the website's "Analyze" and "Ask the AI agent").
  final void Function(String question) onAsk;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

const _sorts = [
  'Deadline (soonest)',
  'Recently saved',
  'Match (highest)',
  'Value (highest)',
];

class _SavedScreenState extends State<SavedScreen> {
  String _status = 'All';
  String _sort = _sorts.first;

  /// The website's four sort orders for Saved Tenders.
  int Function(SavedTender, SavedTender) _comparator(TendersController c) {
    Tender t(SavedTender s) => s.asTender(c.live(s.id));
    bool late(Tender x) => x.deadline == null || (x.daysLeft ?? 0) < 0;
    return switch (_sort) {
      'Recently saved' => (a, b) => (b.savedAt ?? DateTime(0)).compareTo(
        a.savedAt ?? DateTime(0),
      ),
      'Match (highest)' => (a, b) => t(b).match.compareTo(t(a).match),
      'Value (highest)' => (a, b) => (t(b).valueCr ?? 0).compareTo(
        t(a).valueCr ?? 0,
      ),
      _ => (a, b) {
        // Soonest deadline first; closed tenders and tenders without a deadline last.
        final ta = t(a), tb = t(b);
        if (late(ta) != late(tb)) return late(ta) ? 1 : -1;
        return (ta.deadline ?? '9999').compareTo(tb.deadline ?? '9999');
      },
    };
  }

  @override
  void initState() {
    super.initState();
    // The live feed gives fresh deadlines and scores for saved tenders that are still in it.
    if (widget.controller.feed == null) widget.controller.load();
  }

  void _toast(String? error) {
    if (error != null && mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _editNote(SavedTender s) async {
    final field = TextEditingController(text: s.note);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: field,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'e.g. Need OEM letter, site visit on 10 Oct',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    final text = field.text.trim();
    field.dispose();
    if (saved == true)
      _toast(await widget.controller.updateSaved(s.id, {'note': text}));
  }

  Future<void> _remove(SavedTender s) async {
    final title = '${s.snapshot['title'] ?? s.id}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from saved?'),
        content: Text(
          '$title\n\nYour status and note for this tender will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) _toast(await widget.controller.removeSaved(s.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.savedError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load saved tenders.\n${c.savedError}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(160, 46),
                    ),
                    onPressed: c.retrySaved,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!c.savedLoaded)
          return const Center(child: CircularProgressIndicator());
        final all = [...c.saved];
        if (all.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bookmarks_outlined, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'No saved tenders yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap the bookmark on any tender to save it here and track your bid.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(180, 48),
                    ),
                    onPressed: widget.onBrowse,
                    child: const Text('Browse tenders'),
                  ),
                ],
              ),
            ),
          );
        }

        int count(String s) => all.where((x) => x.status == s).length;
        final closing = all.where((s) {
          final t = s.asTender(c.live(s.id));
          return t.closingSoon && (t.daysLeft ?? 0) >= 0;
        }).length;
        final shown = [
          for (final s in all)
            if (_status == 'All' || s.status == _status) s,
        ]..sort(_comparator(c));
        final text = Theme.of(context).textTheme;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Count('Saved', all.length, Colors.blue),
                _Count('Closing in 7 days', closing, Colors.orange),
                _Count(
                  'Preparing bid',
                  count('Preparing bid'),
                  Colors.deepPurple,
                ),
                _Count('Submitted', count('Submitted'), Colors.teal),
                _Count('Won', count('Won'), Colors.green),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in ['All', ...bidStatuses])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '$s (${s == 'All' ? all.length : count(s)})',
                        ),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                const Text('Sort by'),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final s in _sorts)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? _sort),
                ),
              ],
            ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('No tenders marked $_status.')),
              ),
            for (final s in shown) ...[
              _SavedCard(
                saved: s,
                live: c.live(s.id),
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TenderDetailScreen(
                      tender: s.asTender(c.live(s.id)),
                      controller: c,
                    ),
                  ),
                ),
                compared: c.compareIds.contains(s.id),
                onAnalyze: c.live(s.id) == null
                    ? null
                    : () => widget.onAsk(
                        quickQuestion(
                          quickActions['Analyze Eligibility']!,
                          s.asTender(c.live(s.id)),
                        ),
                      ),
                onAsk: () => widget.onAsk(
                  quickQuestion(
                    quickActions['Summarize']!,
                    s.asTender(c.live(s.id)),
                  ),
                ),
                onCompare: () {
                  final live = c.live(s.id);
                  if (live != null) _toast(c.toggleCompare(live));
                },
                onStatus: (v) async =>
                    _toast(await c.updateSaved(s.id, {'status': v})),
                onNote: () => _editNote(s),
                onRemove: () => _remove(s),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Saved in your account - the same list as on the website.',
              style: text.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.saved,
    required this.live,
    required this.onOpen,
    required this.onStatus,
    required this.onNote,
    required this.onRemove,
    required this.onAsk,
    required this.onCompare,
    required this.compared,
    this.onAnalyze,
  });
  final SavedTender saved;
  final Tender? live;
  final VoidCallback onOpen;
  final VoidCallback onAsk;
  final VoidCallback onCompare;
  final bool compared;

  /// "Analyze" - null (disabled) when the tender is no longer in the live feed.
  final VoidCallback? onAnalyze;
  final ValueChanged<String> onStatus;
  final VoidCallback onNote;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = saved.asTender(live);
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'BID NO ${t.id}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(saved.status, statusColor(saved.status)),
                  if (live == null) ...[
                    const SizedBox(width: 6),
                    const Pill('Not in live feed', Colors.blueGrey),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Saved - tap to remove',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.bookmark, color: AppColors.blue),
                    onPressed: onRemove,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) {
                      switch (v) {
                        case 'ask':
                          onAsk();
                        case 'compare':
                          onCompare();
                        case 'note':
                          onNote();
                        case 'link':
                          openTenderDocuments(context, t.link);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'ask',
                        child: Text('Ask the AI agent'),
                      ),
                      if (live != null)
                        PopupMenuItem(
                          value: 'compare',
                          child: Text(
                            compared
                                ? 'Remove from comparison'
                                : 'Add to compare',
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'note',
                        child: Text('Add / edit note'),
                      ),
                      if (t.link.isNotEmpty)
                        PopupMenuItem(
                          value: 'link',
                          child: Text(
                            isBidAssistLink(t.link)
                                ? 'Tender documents'
                                : 'Copy documents link',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  t.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.department,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatValueCr(t.valueCr),
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      saved.hasDeadlinePassed && live == null
                          ? 'Closed ${t.deadline}'
                          : dueText(t),
                      style: text.bodySmall?.copyWith(
                        color: t.closingSoon ? Colors.red.shade700 : null,
                      ),
                    ),
                    Pill('${t.match}% match', matchColor(t.match)),
                    Pill('${t.risk} risk', riskColor(t.risk)),
                    if (t.category.isNotEmpty)
                      Pill(t.category, Colors.blueGrey),
                  ],
                ),
              ),
              if (saved.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2_outlined, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(saved.note, style: text.bodySmall)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: saved.status,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Bid status',
                          isDense: true,
                        ),
                        items: [
                          for (final s in bidStatuses)
                            DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) {
                          if (v != null && v != saved.status) onStatus(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: onAnalyze,
                      child: const Text('Analyze'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
