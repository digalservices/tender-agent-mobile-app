import 'package:flutter/material.dart';

import '../models/tender.dart';
import '../theme.dart';

Color riskColor(String risk) => switch (risk) {
  'Low' => Colors.green.shade700,
  'High' => Colors.red.shade700,
  _ => Colors.orange.shade800,
};

Color matchColor(int m) => m >= 80
    ? Colors.green.shade700
    : (m >= 60 ? Colors.orange.shade800 : Colors.red.shade700);

class Pill extends StatelessWidget {
  const Pill(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

String dueText(Tender t) {
  final left = t.daysLeft;
  if (t.deadline == null) return 'Due date not stated';
  if (left == null) return 'Due ${t.deadline}';
  if (left == 0) return 'Due today';
  if (left == 1) return 'Due tomorrow';
  return 'Due ${t.deadline} · $left days left';
}

/// One row of the tenders list: BID NO first, then title, authority, location, value, due date.
class TenderCard extends StatelessWidget {
  const TenderCard({
    super.key,
    required this.tender,
    required this.saved,
    required this.onTap,
    required this.onSave,
    this.selected = false,
    this.compared = false,
    this.onCompare,
  });
  final Tender tender;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onSave;

  /// Whether it is in the comparison, and the button that adds / removes it (hidden when null).
  final bool compared;
  final VoidCallback? onCompare;

  /// Highlights the tender currently shown in the Tender Agent panel.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = tender;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? const BorderSide(color: AppColors.blue, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
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
                  if (t.isNew) const Pill('New', Colors.blue),
                  const Spacer(),
                  if (onCompare != null)
                    IconButton(
                      tooltip: compared
                          ? 'Remove from comparison'
                          : 'Add to comparison',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.compare_arrows,
                        color: compared ? AppColors.blue : null,
                      ),
                      onPressed: onCompare,
                    ),
                  IconButton(
                    tooltip: saved ? 'Remove from saved' : 'Save',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      saved ? Icons.bookmark : Icons.bookmark_border,
                      color: saved ? AppColors.blue : null,
                    ),
                    onPressed: onSave,
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
              Text(
                t.subDepartment.isEmpty ? t.location : t.subDepartment,
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
                      dueText(t),
                      style: text.bodySmall?.copyWith(
                        color: t.closingSoon ? Colors.red.shade700 : null,
                      ),
                    ),
                    Pill('${t.match}% match', matchColor(t.match)),
                    Pill('${t.risk} risk', riskColor(t.risk)),
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
