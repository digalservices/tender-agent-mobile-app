import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/md_table.dart';
import '../theme.dart';

bool _blank(String v) {
  final t = v.replaceAll('*', '').trim();
  return t.isEmpty || t == '-' || t == '—' || t == '–';
}

/// A tender table as one card per tender, instead of a grid that has to be scrolled sideways. A card shows the rank,
/// the tender's name and its BID NO; tapping "Details" opens the rest: short facts (value, deadline, risk ...) side by
/// side, long ones (why, risks) as paragraphs.
class TableCards extends StatelessWidget {
  const TableCards({
    super.key,
    required this.table,
    required this.style,
    required this.onTapLink,
  });
  final MdTable table;
  final MarkdownStyleSheet style;
  final MarkdownTapLinkCallback onTapLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in table.rows)
          _TenderCard(
            table: table,
            row: row,
            style: style,
            onTapLink: onTapLink,
          ),
      ],
    );
  }
}

class _TenderCard extends StatefulWidget {
  const _TenderCard({
    required this.table,
    required this.row,
    required this.style,
    required this.onTapLink,
  });
  final MdTable table;
  final List<String> row;
  final MarkdownStyleSheet style;
  final MarkdownTapLinkCallback onTapLink;

  @override
  State<_TenderCard> createState() => _TenderCardState();
}

class _TenderCardState extends State<_TenderCard> {
  bool _open = false;

  Widget _md(String text) => MarkdownBody(
    data: text,
    styleSheet: widget.style,
    onTapLink: widget.onTapLink,
    shrinkWrap: true,
  );

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final row = widget.row;
    final rank = table.rankIndex;
    final bid = table.bidIndex;
    final title = table.titleIndex;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.black54);

    final shortFacts = <Widget>[];
    final longFacts = <Widget>[];
    for (var c = 0; c < table.header.length; c++) {
      if (c == rank || c == bid || c == title || _blank(row[c])) continue;
      final value = row[c];
      if (value.length <= 26 && !value.contains('](')) {
        shortFacts.add(
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${table.header[c]}: ', style: muted),
                TextSpan(
                  text: value.replaceAll('**', ''),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      } else {
        longFacts.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(table.header[c], style: muted), _md(value)],
            ),
          ),
        );
      }
    }
    final hasDetails = shortFacts.isNotEmpty || longFacts.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: hasDetails ? () => setState(() => _open = !_open) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rank >= 0 && !_blank(row[rank]))
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 10),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    row[rank].replaceAll('*', ''),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title >= 0 && !_blank(row[title]))
                      DefaultTextStyle.merge(
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        child: _md(row[title]),
                      ),
                    if (bid >= 0 && !_blank(row[bid]))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'BID NO ${row[bid].replaceAll('*', '')}',
                          style: muted,
                        ),
                      ),
                    if (hasDetails)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _open ? 'Hide details' : 'Details',
                              style: const TextStyle(
                                color: AppColors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(
                              _open ? Icons.expand_less : Icons.expand_more,
                              color: AppColors.blue,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    if (_open) ...[
                      if (shortFacts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 14,
                            runSpacing: 2,
                            children: shortFacts,
                          ),
                        ),
                      ...longFacts,
                    ],
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
