import 'package:flutter/material.dart';

import '../models/tender.dart';
import '../models/tender_filters.dart';

/// "Search & Filter Tenders": a search box always on show, the rest under "Advanced filters".
class FilterCard extends StatefulWidget {
  const FilterCard({
    super.key,
    required this.tenders,
    required this.filters,
    required this.onChanged,
  });
  final List<Tender> tenders;
  final TenderFilters filters;
  final ValueChanged<TenderFilters> onChanged;

  @override
  State<FilterCard> createState() => _FilterCardState();
}

class _FilterCardState extends State<FilterCard> {
  final _query = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  bool _open = false;

  List<String> _options(String Function(Tender) pick) {
    final values = {for (final t in widget.tenders) pick(t)}
      ..removeWhere((v) => v.isEmpty);
    return values.toList()..sort();
  }

  void _set(TenderFilters f) => widget.onChanged(f);

  Future<void> _pickRange(
    DateTimeRange? current,
    ValueChanged<DateTimeRange?> done,
  ) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      initialDateRange: current,
    );
    if (picked != null) done(picked);
  }

  String _range(DateTimeRange r) {
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
    return '${d(r.start)} - ${d(r.end)}';
  }

  void _reset() {
    _query.clear();
    _min.clear();
    _max.clear();
    _set(const TenderFilters());
  }

  @override
  void dispose() {
    _query.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  /// A field that opens a list of ticks - several can be chosen; none chosen means all.
  Widget _multi(
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
          if (picked != null) onChanged(picked);
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
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nothing to choose from yet.'),
                  )
                : ListView(
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

  Widget _rangeButton(
    String label,
    DateTimeRange? value,
    ValueChanged<DateTimeRange?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _pickRange(value, onChanged),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            suffixIcon: value == null
                ? const Icon(Icons.calendar_month)
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => onChanged(null),
                  ),
          ),
          child: Text(value == null ? 'Any date' : _range(value)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filters;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Search & Filter Tenders',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _query,
              decoration: const InputDecoration(
                hintText: 'Search by keyword, tender ID...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => _set(f.copyWith(query: v)),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _open = !_open),
                  icon: Icon(_open ? Icons.expand_less : Icons.filter_list),
                  label: Text(
                    f.advancedCount > 0
                        ? 'Advanced filters (${f.advancedCount})'
                        : 'Advanced filters',
                  ),
                ),
                const Spacer(),
                if (f.isActive)
                  TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
            if (_open) ...[
              _multi(
                'Location',
                'All locations',
                _options((t) => t.location),
                f.location,
                (v) => _set(f.copyWith(location: v)),
              ),
              _multi(
                'Department',
                'All departments',
                _options((t) => t.department),
                f.department,
                (v) => _set(f.copyWith(department: v)),
              ),
              _multi(
                'Category',
                'All categories',
                _options((t) => t.category),
                f.category,
                (v) => _set(f.copyWith(category: v)),
              ),
              _multi(
                'Type',
                'All types',
                _options((t) => t.type),
                f.type,
                (v) => _set(f.copyWith(type: v)),
              ),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _min,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Min (₹ Cr)',
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            _set(f.copyWith(minCr: double.tryParse(v.trim()))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _max,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Max (₹ Cr)',
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            _set(f.copyWith(maxCr: double.tryParse(v.trim()))),
                      ),
                    ),
                  ),
                ],
              ),
              _rangeButton(
                'Bid deadline',
                f.deadline,
                (r) => _set(f.copyWith(deadline: r)),
              ),
              _rangeButton(
                'Published date',
                f.published,
                (r) => _set(f.copyWith(published: r)),
              ),
              Text(
                'Minimum match score: ${f.minMatch}%',
                style: text.bodyMedium,
              ),
              Slider(
                value: f.minMatch.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '${f.minMatch}%',
                onChanged: (v) => _set(f.copyWith(minMatch: v.round())),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
