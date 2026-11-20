import 'tender.dart';

/// The bid statuses the web app uses on Saved Tenders.
const bidStatuses = ['Interested', 'Preparing bid', 'Submitted', 'Won', 'Lost'];

/// A bookmarked tender: the snapshot saved with it, plus the company's own bid status and note.
class SavedTender {
  SavedTender({
    required this.id,
    required this.status,
    required this.note,
    required this.snapshot,
    this.savedAt,
  });

  final String id;
  final String status;
  final String note;
  final Map<String, dynamic> snapshot;
  final DateTime? savedAt;

  factory SavedTender.fromData(
    String id,
    Map<String, dynamic> d,
    DateTime? savedAt,
  ) => SavedTender(
    id: id,
    status: bidStatuses.contains(d['status'])
        ? d['status'] as String
        : 'Interested',
    note: '${d['note'] ?? ''}',
    snapshot: d,
    savedAt: savedAt,
  );

  /// A tender to show, using the live feed's fresh details when it is still in the feed, else the
  /// snapshot taken when it was saved (a tender can leave the feed after its deadline).
  Tender asTender(Tender? live) =>
      live ?? Tender.fromJson({...snapshot, 'id': id});

  bool get hasDeadlinePassed {
    final d = DateTime.tryParse('${snapshot['deadline'] ?? ''}');
    return d != null &&
        d.isBefore(
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        );
  }
}
