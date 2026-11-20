import 'package:flutter/material.dart';

import '../models/tender.dart';
import '../models/tender_filters.dart';
import '../services/tenders_controller.dart';
import '../widgets/live_tenders.dart';
import '../widgets/tender_card.dart';
import 'tender_detail_screen.dart';

const _filterLabels = {
  TenderFilter.all: 'All',
  TenderFilter.newOnes: 'New',
  TenderFilter.closing: 'Closing soon',
  TenderFilter.highValue: 'High value',
  TenderFilter.highRisk: 'High risk',
};

bool _passes(Tender t, TenderFilter f) => switch (f) {
  TenderFilter.all => true,
  TenderFilter.newOnes => t.isNew,
  TenderFilter.closing => t.closingSoon,
  TenderFilter.highValue => t.highValue,
  TenderFilter.highRisk => t.risk == 'High',
};

/// Search over the BID NO, title, authority and place - the same fields a bid manager looks up by. "manpower, civil"
/// is two words: a tender with any of them stays (the ones with all of them are listed first, see bestMatchesFirst).
bool matchesQuery(Tender t, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final text = [
    t.id,
    t.tenderNo,
    t.title,
    t.department,
    t.subDepartment,
    t.location,
    t.category,
  ].join(' ').toLowerCase();
  return text.contains(q) || searchWords(q).any(text.contains);
}

class TendersScreen extends StatefulWidget {
  const TendersScreen({super.key, required this.controller});
  final TendersController controller;

  @override
  State<TendersScreen> createState() => _TendersScreenState();
}

class _TendersScreenState extends State<TendersScreen> {
  // A Dashboard tile (New, Closing soon, High risk ...) opens the list of YOUR matched tenders with that filter, even when
  // the Tenders tab otherwise searches all of India live - the tile's number counts those matched tenders.
  late final TenderFilter? _requested = widget.controller.takeRequestedFilter();
  late TenderFilter _filter = _requested ?? TenderFilter.all;
  late bool _matchedList = _requested != null;
  String _query = '';
  int _shown =
      30; // grows as the list is scrolled, so 500 cards are never built at once

  @override
  void initState() {
    super.initState();
    if (widget.controller.feed == null) widget.controller.load();
  }

  Future<void> _toggle(Tender t) async {
    final error = await widget.controller.toggleSaved(t);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
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

        // The server searches BidAssist live: every active tender in India, ten at a time.
        if (feed.live && !_matchedList) return LiveTendersView(controller: c);

        final rows = bestMatchesFirst([
          for (final t in feed.tenders)
            if (_passes(t, _filter) && matchesQuery(t, _query)) t,
        ], _query);
        final visible = rows.take(_shown).toList();
        return Column(
          children: [
            if (feed.live)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _matchedList = false),
                    icon: const Icon(Icons.travel_explore, size: 18),
                    label: const Text('Search all tenders in India'),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search BID NO, title, authority, place',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() {
                  _query = v;
                  _shown = 30;
                }),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in TenderFilter.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: ChoiceChip(
                        label: Text(_filterLabels[f]!),
                        selected: _filter == f,
                        onSelected: (_) => setState(() {
                          _filter = f;
                          _shown = 30;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            if (feed.notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  feed.notice,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${rows.length} of ${feed.tenders.length} tenders · best match first · ${feed.source}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.load,
                child: rows.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('No tenders match.')),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount:
                            visible.length +
                            (visible.length < rows.length ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          if (i == visible.length) {
                            return TextButton(
                              onPressed: () => setState(() => _shown += 30),
                              child: Text(
                                'Show more (${rows.length - visible.length} left)',
                              ),
                            );
                          }
                          final t = visible[i];
                          return TenderCard(
                            tender: t,
                            saved: c.savedIds.contains(t.id),
                            onSave: () => _toggle(t),
                            compared: c.compareIds.contains(t.id),
                            onCompare: () {
                              final msg = c.toggleCompare(t);
                              if (msg != null) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text(msg)));
                              }
                            },
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TenderDetailScreen(
                                  tender: t,
                                  controller: c,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
