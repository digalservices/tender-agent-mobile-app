import 'package:flutter/material.dart';

import '../models/company_details.dart';
import '../models/tender.dart';
import '../screens/tender_detail_screen.dart';
import '../services/api_client.dart';
import '../services/tenders_controller.dart';
import 'tender_card.dart';

const _pageSize = 10;
const _anyTime = 'Any time';
const _dayOptions = {
  _anyTime: 1825,
  'Next 7 days': 7,
  'Next 30 days': 30,
  'Next 90 days': 90,
  'Next 6 months': 180,
};
const _sorts = ['Closing soonest', 'Most relevant', 'Newest', 'Highest value'];
const _kinds = {
  'Works': 'WORKS',
  'Services': 'SERVICES',
  'Goods': 'GOODS',
  'Auction': 'AUCTION',
};

/// The Tenders tab when the server searches BidAssist live: every active tender in India, ten at a time. The search
/// box and the filters search ALL of them; the arrows below open the next page.
class LiveTendersView extends StatefulWidget {
  const LiveTendersView({super.key, required this.controller});
  final TendersController controller;

  @override
  State<LiveTendersView> createState() => _LiveTendersViewState();
}

class _LiveTendersViewState extends State<LiveTendersView> {
  final _api = ApiClient();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  List<String> _states = []; // none chosen = all India
  Set<String> _kindNames = {}; // none chosen = every kind
  DateTimeRange? _due; // bid deadline range; none = "Closing within"
  DateTimeRange? _posted; // posting date range
  String _days = _anyTime;
  String _sort = _sorts.first;
  bool _open = false; // Advanced filters
  int _page = 1;
  LivePage? _result;
  String? _error;
  bool _loading = false;
  int _request =
      0; // a slow answer to an older search must not replace a newer one

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final mine = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.liveTenders(
        q: _query,
        states: _states,
        kinds: [for (final k in _kindNames) _kinds[k]!],
        dueFrom: _due == null ? '' : _iso(_due!.start),
        dueTo: _due == null ? '' : _iso(_due!.end),
        postedFrom: _posted == null ? '' : _iso(_posted!.start),
        postedTo: _posted == null ? '' : _iso(_posted!.end),
        days: _dayOptions[_days]!,
        sort: _sort,
        page: _page,
        size: _pageSize,
      );
      if (!mounted || mine != _request) return;
      widget.controller.remember(result.tenders);
      setState(() {
        _result = result;
        _loading = false;
        if (_page > result.pages) _page = result.pages;
      });
      if (_scroll.hasClients && !_open) _scroll.jumpTo(0);
    } on ApiException catch (e) {
      if (mounted && mine == _request) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
        // The server may have switched to its stand-in source: reload the feed, and the Tenders tab then shows that.
        if (_result == null) widget.controller.load();
      }
    } catch (e) {
      if (mounted && mine == _request) {
        setState(() {
          _error = 'Could not load tenders: $e';
          _loading = false;
        });
      }
    }
  }

  void _searchNow() {
    FocusScope.of(context).unfocus();
    _query = _search.text.trim();
    _page = 1;
    _load();
  }

  void _goto(int page) {
    _page = page;
    _load();
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// One line saying which closing dates the search covers (so a changed "Closing within" is visible).
  String get _windowText {
    if (_due != null) {
      return 'Bid deadline from ${_dmy(_due!.start)} to ${_dmy(_due!.end)}';
    }
    final days = _dayOptions[_days]!;
    if (_days == _anyTime || days >= 1000) return 'Closing: any date from today';
    final today = DateTime.now();
    final last = today.add(Duration(days: days));
    return 'Closing between ${_dmy(today)} and ${_dmy(last)}';
  }

  /// How many filters differ from the defaults (the number on "Advanced filters").
  int get _activeCount => [
    _states.isNotEmpty,
    _kindNames.isNotEmpty,
    _due != null,
    _posted != null,
    _due == null && _days != _anyTime,
    _sort != _sorts.first,
  ].where((x) => x).length;

  void _reset() {
    _search.clear();
    setState(() {
      _query = '';
      _states = [];
      _kindNames = {};
      _due = null;
      _posted = null;
      _days = _anyTime;
      _sort = _sorts.first;
      _page = 1;
    });
    _load();
  }

  /// A list of ticks in a dialog - several can be chosen; none chosen means all.
  Future<Set<String>?> _pickMany(
    String title,
    List<String> items,
    Set<String> current,
  ) {
    final chosen = {...current};
    return showDialog<Set<String>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final i in items)
                  CheckboxListTile(
                    dense: true,
                    value: chosen.contains(i),
                    title: Text(i),
                    onChanged: (on) => setLocal(
                      () => on == true ? chosen.add(i) : chosen.remove(i),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setLocal(chosen.clear),
              child: const Text('Clear'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, chosen),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tickField(
    String label,
    String all,
    List<String> items,
    Set<String> value,
    ValueChanged<Set<String>> onChanged,
  ) {
    final summary = value.isEmpty
        ? all
        : value.length <= 2
        ? value.join(', ')
        : '${value.length} selected';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final picked = await _pickMany(label, items, value);
          if (picked == null || !mounted) return;
          onChanged(picked);
          _page = 1;
          _load();
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: value.isEmpty
                ? TextStyle(color: Theme.of(context).hintColor)
                : null,
          ),
        ),
      ),
    );
  }

  Widget _rangeField(
    String label,
    DateTimeRange? value,
    ValueChanged<DateTimeRange?> onChanged,
    DateTime first,
    DateTime last,
  ) {
    Future<void> pick() async {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: first,
        lastDate: last,
        initialDateRange: value,
      );
      if (picked == null || !mounted) return;
      onChanged(picked);
      _page = 1;
      _load();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: pick,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            suffixIcon: value == null
                ? const Icon(Icons.calendar_month)
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      onChanged(null);
                      _page = 1;
                      _load();
                    },
                  ),
          ),
          child: Text(
            value == null
                ? 'Any date'
                : '${_dmy(value.start)} - ${_dmy(value.end)}',
          ),
        ),
      ),
    );
  }

  Widget _menuField(
    String label,
    List<String> items,
    String value,
    ValueChanged<String> onChanged, {
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label|$value|$enabled'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final i in items)
          DropdownMenuItem(
            value: i,
            child: Text(i, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled
          ? (v) {
              if (v == null || v == value) return;
              onChanged(v);
              _page = 1;
              _load();
            }
          : null,
    ),
  );

  List<Widget> _advanced() {
    final now = DateTime.now();
    return [
      _tickField(
        'Location',
        'All India',
        indianStates,
        {..._states},
        (v) => setState(() => _states = [
          for (final s in indianStates)
            if (v.contains(s)) s,
        ]),
      ),
      _tickField(
        'Type',
        'All types',
        _kinds.keys.toList(),
        _kindNames,
        (v) => setState(() => _kindNames = v),
      ),
      _rangeField(
        'Bid deadline',
        _due,
        (r) => setState(() => _due = r),
        DateTime(now.year, now.month, now.day),
        DateTime(now.year + 3),
      ),
      _menuField(
        _due == null ? 'Closing within' : 'Closing within (not used - a date range is set)',
        _dayOptions.keys.toList(),
        _days,
        (v) => setState(() => _days = v),
        enabled: _due == null,
      ),
      _rangeField(
        'Published date',
        _posted,
        (r) => setState(() => _posted = r),
        DateTime(now.year - 2),
        DateTime(now.year, now.month, now.day),
      ),
      _menuField('Sort by', _sorts, _sort, (v) => setState(() => _sort = v)),
      Text(
        'Department, category and value filters work on your matched tenders, on the Dashboard.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  final _resultsKey = GlobalKey();

  /// The whole page is ONE scrolling list: the search box and the filters on top, the results under them. Scrolling
  /// (dragging) up pushes the filters off the screen, so the results can fill it; the X closes the filters.
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final r = _result;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchNow(),
              decoration: InputDecoration(
                hintText: 'Search all tenders, e.g. road construction',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _searchNow,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _open = !_open),
                  icon: Icon(_open ? Icons.expand_less : Icons.filter_list),
                  label: Text(
                    _activeCount > 0
                        ? 'Advanced filters ($_activeCount)'
                        : 'Advanced filters',
                  ),
                ),
                const Spacer(),
                if (_activeCount > 0 || _query.isNotEmpty)
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                if (_open)
                  IconButton(
                    tooltip: 'Close filters',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _open = false),
                  ),
              ],
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._advanced(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _open = false),
                      icon: const Icon(Icons.check),
                      label: const Text('Show results'),
                    ),
                  ),
                ],
              ),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          Padding(
            key: _resultsKey,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              r == null
                  ? 'Searching tenders...'
                  : r.tenders.isEmpty
                  ? '0 tenders'
                  : 'Showing ${(r.page - 1) * _pageSize + 1} to ${(r.page - 1) * _pageSize + r.tenders.length} of ${r.totalText} tenders'
                        '${r.total >= 50000 ? ' (BidAssist counts up to 50,000)' : ''}'
                        '\n$_windowText',
              style: text.bodySmall,
            ),
          ),
          ..._results(c, r),
        ],
      ),
    );
  }

  List<Widget> _results(TendersController c, LivePage? r) {
    if (_error != null && r == null) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      ];
    }
    if (r == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    return [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      if (r.tenders.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No tenders match this search. Try a shorter keyword, another state, or a longer closing window.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      for (final t in r.tenders)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TenderCard(
            tender: t,
            saved: c.savedIds.contains(t.id),
            compared: c.compareIds.contains(t.id),
            onSave: () async {
              final msg = await c.toggleSaved(t);
              if (msg != null && mounted) _toast(msg);
            },
            onCompare: () {
              final msg = c.toggleCompare(t);
              if (msg != null) _toast(msg);
            },
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TenderDetailScreen(tender: t, controller: c),
              ),
            ),
          ),
        ),
      _pager(r),
    ];
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _pager(LivePage r) {
    if (r.pages <= 1 && r.page <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.outlined(
          tooltip: 'Previous page',
          onPressed: _loading || r.page <= 1 ? null : () => _goto(r.page - 1),
          icon: const Icon(Icons.chevron_left),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Page ${r.page} of ${r.pages}'),
        ),
        IconButton.outlined(
          tooltip: 'Next page',
          onPressed: _loading || r.page >= r.pages
              ? null
              : () => _goto(r.page + 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
