import 'dart:typed_data';

/// One AI agent run from the Agent Activity log (`GET /api/activity`).
class AgentRun {
  AgentRun({
    required this.id,
    required this.kind,
    required this.question,
    required this.startedAt,
    required this.durationS,
    required this.status,
    required this.error,
    required this.steps,
    required this.tendersFound,
    required this.tokens,
    this.costUsd = 0,
  });

  final String id;
  final String kind;
  final String question;
  final DateTime? startedAt; // local time
  final double durationS;
  final String status;
  final String error;
  final List<String> steps;
  final int tendersFound;
  final int
  tokens; // the answering model's tokens plus the cheap reading model's

  /// Estimated cost in US dollars (an upper estimate: cached input counts at the full rate).
  final double costUsd;

  bool get ok => status == 'success';

  factory AgentRun.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return AgentRun(
      id: '${j['id'] ?? ''}',
      kind: '${j['kind'] ?? ''}',
      question: '${j['question'] ?? ''}',
      startedAt: DateTime.tryParse('${j['started_at'] ?? ''}')?.toLocal(),
      durationS: (j['duration_s'] as num?)?.toDouble() ?? 0,
      status: '${j['status'] ?? ''}',
      error: '${j['error'] ?? ''}',
      steps: [for (final s in (j['steps'] as List? ?? const [])) '$s'],
      tendersFound: n('tenders_found'),
      costUsd: (j['cost_usd'] as num?)?.toDouble() ?? 0,
      tokens:
          n('input_tokens') +
          n('output_tokens') +
          n('read_input_tokens') +
          n('read_output_tokens'),
    );
  }
}

/// "$0.0123" / "$0.293" / "$2.33", or "<$0.001" for a tiny amount.
String formatCost(double usd) {
  if (usd <= 0) return '\$0.00';
  if (usd < 0.001) return '<\$0.001';
  if (usd < 0.1) return '\$${usd.toStringAsFixed(4)}';
  if (usd < 1) return '\$${usd.toStringAsFixed(3)}';
  return '\$${usd.toStringAsFixed(2)}';
}

/// "45s" / "3m 12s".
String formatDuration(double sec) {
  final s = sec.round();
  return s < 60 ? '${s}s' : '${s ~/ 60}m ${s % 60}s';
}

/// "950" / "12.3k" / "1.4M".
String formatTokens(int n) => n >= 1000000
    ? '${(n / 1e6).toStringAsFixed(1)}M'
    : (n >= 1000 ? '${(n / 1e3).toStringAsFixed(1)}k' : '$n');

/// "Today" / "Yesterday" / "Mon, 12 Oct 2026".
String dayLabel(DateTime d, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(today.year, today.month, today.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
}

/// A report workbook built by the server (`GET /api/reports/{kind}`).
class ReportFile {
  ReportFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// BidAssist token state, for administrators (`GET /api/tender-status` -> admin.token).
class TokenHealth {
  TokenHealth({
    required this.ok,
    required this.message,
    required this.planEnd,
    required this.daysLeft,
    required this.tokenFrom,
  });
  final bool ok;
  final String message;
  final String? planEnd; // yyyy-mm-dd
  final int? daysLeft;
  final String tokenFrom; // 'saved in the app' | '.env' | ''

  factory TokenHealth.fromJson(Map<String, dynamic> j) => TokenHealth(
    ok: j['ok'] == true,
    message: '${j['message'] ?? ''}',
    planEnd: j['plan_end'] as String?,
    daysLeft: (j['days_left'] as num?)?.toInt(),
    tokenFrom: '${j['token_from'] ?? ''}',
  );
}

/// Where the tenders come from, plus - for administrators - the controls' state (`GET /api/tender-status`).
class TenderStatus {
  TenderStatus({
    required this.source,
    required this.live,
    required this.notice,
    required this.isAdmin,
    required this.canSwitch,
    required this.choice,
    required this.haveTenderDetailKey,
    required this.token,
  });
  final String source;
  final bool live;
  final String notice;
  final bool isAdmin;
  final bool canSwitch;
  final String choice; // 'bidassist_api' | 'tenderdetail'
  final bool haveTenderDetailKey;
  final TokenHealth? token;

  factory TenderStatus.fromJson(Map<String, dynamic> j) {
    final a = j['admin'] is Map ? Map<String, dynamic>.from(j['admin'] as Map) : <String, dynamic>{};
    return TenderStatus(
      source: '${j['source'] ?? ''}',
      live: j['live'] == true,
      notice: '${j['notice'] ?? ''}',
      isAdmin: j['is_admin'] == true,
      canSwitch: a['can_switch'] == true,
      choice: '${a['choice'] ?? ''}',
      haveTenderDetailKey: a['have_tenderdetail_key'] == true,
      token: a['token'] is Map
          ? TokenHealth.fromJson(Map<String, dynamic>.from(a['token'] as Map))
          : null,
    );
  }
}
