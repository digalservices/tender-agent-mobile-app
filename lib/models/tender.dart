/// One scored tender from the backend (`GET /api/tenders`). The BID NO is the feed's reference number.
class Tender {
  Tender({
    required this.id,
    required this.tenderNo,
    required this.title,
    required this.department,
    required this.subDepartment,
    required this.location,
    required this.category,
    required this.type,
    required this.valueCr,
    required this.emdCr,
    this.docCostCr,
    required this.published,
    required this.deadline,
    required this.daysLeft,
    required this.closingSoon,
    required this.match,
    required this.risk,
    this.riskReason = '',
    required this.analysis,
    required this.requirements,
    required this.isNew,
    required this.highValue,
    required this.summary,
    required this.documents,
    required this.link,
  });

  final String id;
  final String tenderNo;
  final String title;
  final String department;
  final String subDepartment;
  final String location;
  final String category;
  final String type;
  final double? valueCr;
  final double? emdCr;
  final double? docCostCr; // the tender document fee
  final String? published;
  final String? deadline;
  final int? daysLeft;
  final bool closingSoon;
  final int match;
  final String risk;

  /// Why the risk is what it is, in a few words (e.g. 'closes in 2 days').
  final String riskReason;
  final Map<String, int> analysis;
  final List<({String label, String status})> requirements;
  final bool isNew;
  final bool highValue;
  final String summary;
  final List<({String label, bool have})> documents;
  final String link;

  DateTime? get deadlineDate => DateTime.tryParse(deadline ?? '');
  DateTime? get publishedDate => DateTime.tryParse(published ?? '');

  factory Tender.fromJson(Map<String, dynamic> j) {
    // A saved snapshot has no days_left: work it out from the deadline.
    final deadline = j['deadline'] as String?;
    int? daysLeft = (j['days_left'] as num?)?.toInt();
    if (daysLeft == null && deadline != null) {
      final d = DateTime.tryParse(deadline);
      final now = DateTime.now();
      if (d != null)
        daysLeft = DateTime(
          d.year,
          d.month,
          d.day,
        ).difference(DateTime(now.year, now.month, now.day)).inDays;
    }
    return Tender(
      id: '${j['id']}',
      tenderNo: '${j['tender_no'] ?? ''}',
      title: '${j['title'] ?? ''}',
      department: '${j['department'] ?? ''}',
      subDepartment: '${j['sub_department'] ?? ''}',
      location: '${j['location'] ?? ''}',
      category: '${j['category'] ?? ''}',
      type: '${j['type'] ?? ''}',
      valueCr: (j['value_cr'] as num?)?.toDouble(),
      emdCr: (j['emd_cr'] as num?)?.toDouble(),
      docCostCr: (j['doc_cost_cr'] as num?)?.toDouble(),
      published: j['published'] as String?,
      deadline: j['deadline'] as String?,
      daysLeft: daysLeft,
      closingSoon:
          j['closing_soon'] == true ||
          (j['closing_soon'] == null &&
              daysLeft != null &&
              daysLeft >= 0 &&
              daysLeft <= 7),
      match: (j['match'] as num?)?.toInt() ?? 0,
      risk: '${j['risk'] ?? 'Medium'}',
      riskReason: '${j['risk_reason'] ?? ''}',
      analysis: {
        for (final e in (j['analysis'] as Map? ?? {}).entries)
          '${e.key}': (e.value as num).toInt(),
      },
      requirements: [
        for (final r in (j['requirements'] as List? ?? []))
          (label: '${r['label']}', status: '${r['status']}'),
      ],
      isNew: j['is_new'] == true,
      highValue: j['high_value'] == true,
      summary: '${j['summary'] ?? ''}',
      documents: [
        for (final d in (j['documents'] as List? ?? []))
          (label: '${d['label']}', have: d['have'] == true),
      ],
      link: '${j['link'] ?? ''}',
    );
  }

  /// Same snapshot the web app saves under `saved_tenders/{id}`, so a bookmark shows in both apps.
  Map<String, dynamic> toSavedSnapshot() => {
    'title': title,
    'tender_no': tenderNo,
    'department': department,
    'sub_department': subDepartment,
    'location': location,
    'category': category,
    'type': type,
    'value_cr': valueCr,
    'match': match,
    'risk': risk,
    'risk_reason': riskReason,
    'link': link,
    'deadline': deadline,
    'published': published,
  };
}

/// One page of the live search (`GET /api/tenders/live`): the tenders on it, how many match in all, and how many
/// pages can be opened.
class LivePage {
  LivePage({
    required this.tenders,
    required this.total,
    required this.pages,
    required this.page,
  });
  final List<Tender> tenders;
  final int total;
  final int pages;
  final int page; // counted from 1

  /// BidAssist stops counting at 50,000.
  String get totalText => total >= 50000 ? '50,000+' : '$total';

  factory LivePage.fromJson(Map<String, dynamic> j) => LivePage(
    tenders: [
      for (final t in (j['tenders'] as List? ?? []))
        Tender.fromJson(Map<String, dynamic>.from(t as Map)),
    ],
    total: (j['total'] as num?)?.toInt() ?? 0,
    pages: (j['pages'] as num?)?.toInt() ?? 1,
    page: (j['page'] as num?)?.toInt() ?? 1,
  );
}

class TenderFeed {
  TenderFeed({
    required this.source,
    required this.kpis,
    required this.tenders,
    this.live = false,
    this.notice = '',
  });
  final String source;

  /// When true the Tenders tab searches live, one page at a time, instead of listing [tenders].
  final bool live;

  /// Set when the tenders are not from the source that was asked for (BidAssist was down, TenderDetail stood in).
  final String notice;
  final Map<String, int> kpis; // total, new, closing, high_value, high_risk
  final List<Tender> tenders;

  factory TenderFeed.fromJson(Map<String, dynamic> j) => TenderFeed(
    source: '${j['source'] ?? ''}',
    live: j['live'] == true,
    notice: '${j['notice'] ?? ''}',
    kpis: {
      for (final k in (j['kpis'] as List? ?? []))
        '${k['key']}': (k['value'] as num).toInt(),
    },
    tenders: [
      for (final t in (j['tenders'] as List? ?? []))
        Tender.fromJson(t as Map<String, dynamic>),
    ],
  );
}

String _trim(double v) =>
    double.parse(v.toStringAsFixed(2))
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '');

/// "₹2.07 Crore" / "₹29,400" - the same wording as the web app.
String formatValueCr(double? cr) {
  if (cr == null) return 'Not stated';
  if (cr >= 1) return '₹${_trim(cr)} Crore';
  if (cr >= 0.01) return '₹${_trim(cr * 100)} Lakhs';
  final rupees = (cr * 1e7).round().toString();
  return '₹${rupees.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';
}
