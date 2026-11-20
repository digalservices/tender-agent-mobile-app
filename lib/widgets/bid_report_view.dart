import 'package:flutter/material.dart';

import '../models/bid_check.dart';
import '../screens/landing_screen.dart';

/// The Bid Check report on a phone: the numbers, the groups, and each step with what is wrong and how to fix it
/// (the same content as the website's Analyze Tender report). [onAgain] starts a new check.
class BidReportView extends StatefulWidget {
  const BidReportView({super.key, required this.report, required this.onAgain});
  final BidReport report;
  final VoidCallback onAgain;

  @override
  State<BidReportView> createState() => _BidReportViewState();
}

class _BidReportViewState extends State<BidReportView> {
  bool _all = false;

  static const _status = {
    'done': ('Done', Color(0xFFE8F8EE), Color(0xFF15803D)),
    'wrong': ('Wrong', Color(0xFFFFF1DB), Color(0xFFC2410C)),
    'missing': ('Missing', Color(0xFFFDE8E8), Color(0xFFDC2626)),
    'unclear': ('Not sure', Color(0xFFF1F4F9), Color(0xFF475569)),
  };

  Color _levelColor(String level) => switch (level) {
    'red' => const Color(0xFFDC2626),
    'amber' => const Color(0xFFC2410C),
    _ => const Color(0xFF15803D),
  };

  Widget _tile(String label, String value, Color color) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BidColors.line),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: BidColors.muted),
          ),
        ],
      ),
    ),
  );

  Widget _row(String label, String text) => text.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: BidColors.muted),
                ),
              ),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
            ],
          ),
        );

  Widget _stepCard(BidStep s) {
    final (label, bg, fg) = _status[s.status] ?? _status['unclear']!;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BidColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (s.risky)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDE8E8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'Can get the bid rejected',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            _row('The tender asks', s.ref.isEmpty ? s.detail : '${s.detail} (${s.ref})'),
            _row('Found in your bid', s.foundIn.isEmpty && s.status != 'done' ? '-' : s.foundIn),
            if (s.status != 'done') _row('What is wrong', s.cause),
            if (s.status != 'done') _row('How to fix it', s.fix),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final shown = [
      for (final s in r.steps)
        if (_all || s.status != 'done') s,
    ]..sort((a, b) {
        const order = {'missing': 0, 'wrong': 1, 'unclear': 2, 'done': 3};
        if (a.risky != b.risky) return a.risky ? -1 : 1;
        return (order[a.status] ?? 2).compareTo(order[b.status] ?? 2);
      });
    final color = _levelColor(r.level);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (r.title.isNotEmpty)
          Text(
            [r.title, if (r.authority.isNotEmpty) r.authority, if (r.closing.isNotEmpty) 'closes ${r.closing}'].join(' · '),
            style: const TextStyle(color: BidColors.muted, fontSize: 13),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            _tile('Readiness', r.score == null ? '-' : '${r.score}%', color),
            _tile('Steps done', '${r.done} of ${r.total}', const Color(0xFF15803D)),
            _tile('Need fixing', '${r.problems}', const Color(0xFFC2410C)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _tile('Rejection risks', '${r.riskCount}', const Color(0xFFDC2626)),
            _tile('Not sure', '${r.unclear}', const Color(0xFF7C3AED)),
          ],
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${r.levelWord}. ',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              TextSpan(text: r.message),
            ],
          ),
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 4),
        const Text(
          '"Rejection risks" are problems with a mandatory requirement - a bid with one of them can be rejected.',
          style: TextStyle(color: BidColors.muted, fontSize: 12),
        ),
        for (final w in r.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('⚠ $w', style: const TextStyle(color: Color(0xFFC2410C), fontSize: 13)),
          ),
        const SizedBox(height: 14),
        for (final g in r.groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${g.name} · ${g.score ?? '-'}% (${g.done} of ${g.total} done)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (g.score ?? 0) / 100,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE3E8F2),
                    color: (g.score ?? 0) < 60
                        ? const Color(0xFFDC2626)
                        : (g.score ?? 0) < 85
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Problems')),
            ButtonSegment(value: true, label: Text('All steps')),
          ],
          selected: {_all},
          onSelectionChanged: (v) => setState(() => _all = v.first),
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Every step is done. Nothing to fix.'),
          ),
        for (final s in shown) _stepCard(s),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Checked from the text of your files, so it cannot tell whether a signature or stamp is genuine. It is a guide, not a guarantee.',
            style: TextStyle(color: BidColors.muted, fontSize: 12),
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          key: const ValueKey('check-another'),
          onPressed: widget.onAgain,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Check another bid'),
        ),
      ],
    );
  }
}
