import 'package:flutter/material.dart';

import '../models/tender.dart';
import '../services/tender_files.dart';
import '../services/tenders_controller.dart';
import '../widgets/tender_card.dart';

class TenderDetailScreen extends StatelessWidget {
  const TenderDetailScreen({
    super.key,
    required this.tender,
    required this.controller,
  });
  final Tender tender;
  final TendersController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = tender;
        final saved = controller.savedIds.contains(t.id);
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text('BID NO ${t.id}'),
            actions: [
              IconButton(
                tooltip: controller.compareIds.contains(t.id)
                    ? 'Remove from comparison'
                    : 'Add to comparison',
                icon: Icon(
                  Icons.compare_arrows,
                  color: controller.compareIds.contains(t.id)
                      ? Colors.lightBlueAccent
                      : null,
                ),
                onPressed: () {
                  final msg = controller.toggleCompare(t);
                  if (msg != null) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  }
                },
              ),
              IconButton(
                tooltip: saved ? 'Remove from saved' : 'Save',
                icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () async {
                  final error = await controller.toggleSaved(t);
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(error)));
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t.title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Pill('${t.match}% match', matchColor(t.match)),
                  Pill('${t.risk} risk', riskColor(t.risk)),
                  if (t.isNew) const Pill('New', Colors.blue),
                  if (t.highValue) const Pill('High value', Colors.purple),
                  if (t.closingSoon) Pill('Closing soon', Colors.red.shade700),
                ],
              ),
              const SizedBox(height: 16),
              _facts(context, [
                ('BID NO', t.id),
                if (t.tenderNo.isNotEmpty) ('Tender no.', t.tenderNo),
                ('Authority', t.department),
                (
                  'Location',
                  t.subDepartment.isEmpty ? t.location : t.subDepartment,
                ),
                ('Category', t.category),
                ('Type', t.type),
                ('Tender value', formatValueCr(t.valueCr)),
                ('EMD', formatValueCr(t.emdCr)),
                ('Published', t.published ?? 'Not stated'),
                ('Due', dueText(t)),
              ]),
              if (t.summary.isNotEmpty && t.summary != t.title) ...[
                const SizedBox(height: 16),
                Text(
                  'Summary',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(t.summary),
              ],
              const SizedBox(height: 16),
              Text(
                'How well it fits your company',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final e in t.analysis.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(e.key, style: text.bodySmall),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: e.value / 100,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                          color: matchColor(e.value),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text('  ${e.value}%', style: text.bodySmall),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              for (final r in t.requirements)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    r.status == 'met'
                        ? Icons.check_circle
                        : (r.status == 'verify'
                              ? Icons.help_outline
                              : Icons.info_outline),
                    color: r.status == 'met'
                        ? Colors.green.shade700
                        : (r.status == 'verify'
                              ? Colors.orange.shade800
                              : null),
                  ),
                  title: Text(r.label),
                ),
              const SizedBox(height: 8),
              Text(
                'Common documents',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              for (final d in t.documents)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    d.have ? Icons.check_box : Icons.check_box_outline_blank,
                    color: d.have ? Colors.green.shade700 : null,
                  ),
                  title: Text(d.label),
                ),
              if (t.link.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: Icon(isBidAssistLink(t.link) ? Icons.folder_zip : Icons.link),
                  label: Text(
                    isBidAssistLink(t.link)
                        ? 'Tender documents'
                        : 'Copy tender documents link',
                  ),
                  onPressed: () => openTenderDocuments(context, t.link),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Match and risk are quick screening figures from your profile, not an eligibility check. '
                'Bid documents, price bid and checklist come with the AI Analysis screen.',
                style: text.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _facts(BuildContext context, List<(String, String)> rows) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      r.$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: Text(r.$2)),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
