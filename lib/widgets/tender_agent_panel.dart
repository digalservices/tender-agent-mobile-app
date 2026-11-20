import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/tender.dart';
import '../services/tender_files.dart';
import '../theme.dart';
import 'tender_card.dart';

/// The website's quick actions. Each becomes a question for the AI Analysis chat.
const quickActions = <String, String>{
  'Analyze Eligibility': 'Check our eligibility for the tender "{title}" (ID {id}) against our company profile and documents, criterion by criterion.',
  'Find Risks':
      'List the risks and gaps for us in bidding on "{title}" (ID {id}).',
  'Summarize': 'Summarise the tender "{title}" (ID {id}) in plain language: scope, value, deadlines, eligibility.',
  'List Documents': 'List every document we need to prepare to bid on "{title}" (ID {id}), and which ones we already have.',
  'Compare Tenders': 'Compare "{title}" (ID {id}) with other active tenders that suit our company.',
  'Calculate Bid Cost': 'Estimate our bid cost for "{title}" (ID {id}): EMD, document fee, statutory costs and a suggested margin.',
};

String quickQuestion(String template, Tender t) =>
    template.replaceAll('{title}', t.title).replaceAll('{id}', t.id);

String aboutQuestion(Tender t, String asked) =>
    'About the tender "${t.title}" (ID ${t.id}, ${t.department}): $asked';

/// "Tender Agent": how the selected tender matches the company profile, with quick actions for the AI.
class TenderAgentPanel extends StatefulWidget {
  const TenderAgentPanel({
    super.key,
    required this.tender,
    required this.saved,
    required this.onSave,
    required this.onRefresh,
    required this.onAsk,
  });
  final Tender tender;
  final bool saved;
  final VoidCallback onSave;
  final Future<void> Function() onRefresh;
  final void Function(String question) onAsk;

  @override
  State<TenderAgentPanel> createState() => _TenderAgentPanelState();
}

class _TenderAgentPanelState extends State<TenderAgentPanel> {
  final _ask = TextEditingController();

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  void _send() {
    final q = _ask.text.trim();
    if (q.isEmpty) return;
    widget.onAsk(aboutQuestion(widget.tender, q));
    _ask.clear();
  }

  Widget _box(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: Colors.black12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );

  Widget _stat(IconData icon, Color color, String value, String label) =>
      Expanded(
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.tender;
    final text = Theme.of(context).textTheme;
    final barColors = [
      Colors.green.shade600,
      AppColors.blue,
      Colors.amber.shade700,
    ];
    final remaining = t.daysLeft == null ? '—' : '${t.daysLeft} Days';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy, color: AppColors.blue),
              const SizedBox(width: 8),
              // The title shrinks (with "...") before the row can overflow on a narrow phone.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Tender Agent',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(30),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '● Online',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: widget.saved ? 'Remove from saved' : 'Save tender',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  widget.saved
                      ? Icons.bookmark_added
                      : Icons.bookmark_add_outlined,
                ),
                onPressed: widget.onSave,
              ),
              IconButton(
                tooltip: 'Refresh tenders',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh),
                onPressed: widget.onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEDEBFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "Here's how this tender matches your company profile. Use the actions below for a full AI check "
              'against the tender documents.',
              style: TextStyle(color: Color(0xFF3B2F8F)),
            ),
          ),
          _box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        t.title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                    if (t.link.isNotEmpty)
                      IconButton(
                        tooltip: isBidAssistLink(t.link)
                            ? 'Tender documents'
                            : 'Copy tender documents link',
                        icon: const Icon(
                          Icons.open_in_new,
                          color: AppColors.blue,
                        ),
                        onPressed: () => openTenderDocuments(context, t.link),
                      ),
                  ],
                ),
                Text(
                  '${t.department} • Tender ID: ${t.id}',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stat(
                      Icons.payments,
                      Colors.green.shade700,
                      formatValueCr(t.valueCr),
                      'Estimated Value',
                    ),
                    _stat(
                      Icons.calendar_month,
                      AppColors.blue,
                      t.deadline ?? 'Not stated',
                      'Bid Deadline',
                    ),
                    _stat(
                      Icons.schedule,
                      t.closingSoon ? Colors.red.shade700 : AppColors.ink,
                      remaining,
                      'Remaining',
                    ),
                  ],
                ),
              ],
            ),
          ),
          _box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile Match',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 104,
                      height: 104,
                      child: CustomPaint(
                        painter: _DonutPainter(t.match, Colors.green.shade600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          for (final (i, e) in t.analysis.entries.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 74,
                                    child: Text(e.key, style: text.bodySmall),
                                  ),
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: e.value / 100,
                                      minHeight: 8,
                                      borderRadius: BorderRadius.circular(4),
                                      color: barColors[i % 3],
                                      backgroundColor: Colors.black12,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 42,
                                    child: Text(
                                      '${e.value}%',
                                      textAlign: TextAlign.right,
                                      style: text.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Flexible(
                                child: SizedBox(
                                  width: 74,
                                  child: Text(
                                    'Risk Level',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.circle,
                                size: 12,
                                color: riskColor(t.risk),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.risk,
                                style: TextStyle(
                                  color: riskColor(t.risk),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          // The cause goes on its own line: beside "High" there is no room for it on a phone.
                          if (t.riskReason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 92, top: 2),
                              child: Text(t.riskReason, style: text.bodySmall),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (t.summary.isNotEmpty)
            _box(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.assignment, color: AppColors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Executive Summary',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.summary,
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (t.requirements.isNotEmpty)
            _box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Key Requirements',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final r in t.requirements)
                    _Requirement(r.label, r.status),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.description, size: 20, color: AppColors.blue),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Documents Required',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in t.documents)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          d.have
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: d.have ? AppColors.blue : Colors.black38,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(d.label)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Documents most tenders ask for · ticked = in your company profile',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          TextField(
            controller: _ask,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Ask anything about this tender...',
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_upward),
                onPressed: _send,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in quickActions.entries)
                ActionChip(
                  label: Text(e.key),
                  avatar: e.key == 'Summarize'
                      ? const Icon(Icons.article_outlined, size: 18)
                      : null,
                  onPressed: () => widget.onAsk(quickQuestion(e.value, t)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement(this.label, this.status);
  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final (icon, color, word) = switch (status) {
      'met' => (Icons.check_circle, Colors.green.shade700, 'Met'),
      'verify' => (Icons.error, Colors.orange.shade700, 'Need Verification'),
      _ => (Icons.info, AppColors.blue, 'Note'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Text(
            word,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.percent, this.color);
  final int percent;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = color.withAlpha(35);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * percent.clamp(0, 100) / 100,
      false,
      arc,
    );
    void label(String s, double fontSize, FontWeight w, Color c, double dy) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontSize: fontSize, fontWeight: w, color: c),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + dy));
    }

    label('$percent%', 24, FontWeight.w800, AppColors.ink, -20);
    label('MATCH SCORE', 8, FontWeight.w600, Colors.black54, 8);
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.percent != percent || old.color != color;
}
