/// The free Bid Check as the server (bid_check_api.py) reports it: the files added so far, the check's progress, and
/// its report once it is done. The report is the same one the website's Analyze Tender page shows.
library;

/// A requirement can get the bid rejected when it is this heavy and the bid is wrong or missing it.
const riskWeight = 3;

class BidStep {
  BidStep({
    required this.id,
    required this.group,
    required this.title,
    required this.detail,
    required this.ref,
    required this.weight,
    required this.status,
    required this.foundIn,
    required this.cause,
    required this.fix,
  });

  final String id, group, title, detail, ref, status, foundIn, cause, fix;
  final int weight;

  factory BidStep.fromJson(Map<String, dynamic> j) => BidStep(
    id: '${j['id'] ?? ''}',
    group: '${j['group'] ?? ''}',
    title: '${j['title'] ?? ''}',
    detail: '${j['detail'] ?? ''}',
    ref: '${j['ref'] ?? ''}',
    weight: (j['weight'] as num?)?.toInt() ?? 1,
    status: '${j['status'] ?? 'unclear'}',
    foundIn: '${j['found_in'] ?? ''}',
    cause: '${j['cause'] ?? ''}',
    fix: '${j['fix'] ?? ''}',
  );

  /// Wrong or missing, and heavy enough to get the bid rejected.
  bool get risky =>
      weight >= riskWeight && (status == 'wrong' || status == 'missing');
}

class BidGroup {
  BidGroup(this.name, this.total, this.done, this.score);
  final String name;
  final int total, done;
  final int? score;
}

class BidReport {
  BidReport({
    required this.title,
    required this.authority,
    required this.closing,
    required this.score,
    required this.total,
    required this.done,
    required this.wrong,
    required this.missing,
    required this.unclear,
    required this.riskCount,
    required this.groups,
    required this.steps,
    required this.warnings,
  });

  final String title, authority, closing;
  final int? score;
  final int total, done, wrong, missing, unclear, riskCount;
  final List<BidGroup> groups;
  final List<BidStep> steps;
  final List<String> warnings;

  int get problems => wrong + missing;

  /// "red" (a lot to do), "amber" (nearly there) or "green" (ready) - the website's thresholds.
  String get level => score == null || score! < 60
      ? 'red'
      : score! < 85
      ? 'amber'
      : 'green';

  String get levelWord => switch (level) {
    'red' => 'Needs a lot of work',
    'amber' => 'Nearly there',
    _ => 'Ready to submit',
  };

  String get message {
    var text = '$done of $total steps are done.';
    if (problems > 0) {
      text += ' $problems need fixing';
      text += riskCount > 0
          ? ', $riskCount of them can get the bid rejected.'
          : '.';
    }
    return text;
  }

  factory BidReport.fromJson(Map<String, dynamic> j) {
    final tender = Map<String, dynamic>.from(j['tender'] as Map? ?? {});
    final s = Map<String, dynamic>.from(j['summary'] as Map? ?? {});
    int n(String key) => (s[key] as num?)?.toInt() ?? 0;
    final groups = <BidGroup>[];
    (s['groups'] as Map? ?? {}).forEach((name, g) {
      final m = Map<String, dynamic>.from(g as Map);
      groups.add(
        BidGroup(
          '$name',
          (m['total'] as num?)?.toInt() ?? 0,
          (m['done'] as num?)?.toInt() ?? 0,
          (m['score'] as num?)?.toInt(),
        ),
      );
    });
    return BidReport(
      title: '${tender['title'] ?? ''}',
      authority: '${tender['authority'] ?? ''}',
      closing: '${tender['closing_date'] ?? ''}',
      score: (s['score'] as num?)?.toInt(),
      total: n('total'),
      done: n('done'),
      wrong: n('wrong'),
      missing: n('missing'),
      unclear: n('unclear'),
      riskCount: n('risk_count'),
      groups: groups,
      steps: [
        for (final x in (j['steps'] as List? ?? []))
          BidStep.fromJson(Map<String, dynamic>.from(x as Map)),
      ],
      warnings: [for (final w in (j['warnings'] as List? ?? [])) '$w'],
    );
  }
}

class BidCheckStatus {
  BidCheckStatus({
    required this.tenderFiles,
    required this.bidFiles,
    required this.running,
    required this.stage,
    required this.elapsed,
    required this.steps,
    required this.error,
    required this.report,
  });

  final List<String> tenderFiles, bidFiles, steps;
  final bool running;
  final int stage;
  final double elapsed;
  final String error;
  final BidReport? report;

  factory BidCheckStatus.fromJson(Map<String, dynamic> j) {
    final files = Map<String, dynamic>.from(j['files'] as Map? ?? {});
    List<String> names(Object? v) => [for (final x in (v as List? ?? [])) '$x'];
    final report = j['report'];
    return BidCheckStatus(
      tenderFiles: names(files['tender']),
      bidFiles: names(files['bid']),
      running: j['running'] == true,
      stage: (j['stage'] as num?)?.toInt() ?? 1,
      elapsed: (j['elapsed'] as num?)?.toDouble() ?? 0,
      steps: names(j['steps']),
      error: '${j['error'] ?? ''}',
      report: report is Map
          ? BidReport.fromJson(Map<String, dynamic>.from(report))
          : null,
    );
  }

  static const stageWords = {
    1: 'reading your files',
    2: 'finding what the tender requires',
    3: 'checking your bid against the requirements',
  };

  String get stageWord => stageWords[stage] ?? stageWords[1]!;
}
