import 'dart:typed_data';

import 'tender.dart';

/// A tender row shown under an AI answer (the website's selectable table). Values are in rupees.
class ChatTender {
  ChatTender({
    required this.ref,
    required this.title,
    required this.authority,
    required this.location,
    this.value,
    this.emd,
    this.docCost,
    this.dueDate,
    this.sector,
    this.link = '',
  });

  final String ref; // the BID NO
  final String title;
  final String authority;
  final String location;
  final double? value;
  final double? emd;
  final double? docCost;
  final String? dueDate;
  final String? sector;

  /// The tender documents link, when the answer's table has one.
  final String link;

  factory ChatTender.fromJson(Map<String, dynamic> j) => ChatTender(
    ref: '${j['ref'] ?? ''}',
    title: '${j['title'] ?? '(no title)'}',
    authority: '${j['authority'] ?? ''}',
    location: '${j['location'] ?? ''}',
    value: (j['value'] as num?)?.toDouble(),
    emd: (j['emd'] as num?)?.toDouble(),
    docCost: (j['doc_cost'] as num?)?.toDouble(),
    dueDate: j['due_date'] as String?,
    sector: j['sector'] as String?,
    link: '${j['documents'] ?? ''}'.startsWith('http')
        ? '${j['documents']}'
        : '',
  );

  /// This row as a [Tender], to save it (value and EMD here are rupees, a tender holds crore).
  Tender asTender() => Tender.fromJson({
    'id': ref,
    'tender_no': ref,
    'title': title,
    'department': authority,
    'location': location,
    'category': sector ?? '',
    'value_cr': value == null ? null : value! / 1e7,
    'emd_cr': emd == null ? null : emd! / 1e7,
    'deadline': dueDate,
    'link': link,
  });
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    required this.tenders,
    required this.export,
    required this.ref,
    this.confirm,
  });

  final String role; // 'user' | 'assistant'
  final String text;
  final List<ChatTender> tenders;
  final String export; // '' | 'docx' | 'xlsx'
  final String ref;

  /// Set when a bid job was held back with a warning: {job, ref, index}. The app offers "Run anyway" / "Cancel".
  final Map<String, dynamic>? confirm;

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    role: '${j['role'] ?? 'assistant'}',
    text: '${j['text'] ?? ''}',
    tenders: [
      for (final t in (j['tenders'] as List? ?? const []))
        ChatTender.fromJson(Map<String, dynamic>.from(t as Map)),
    ],
    export: '${j['export'] ?? ''}',
    ref: '${j['ref'] ?? ''}',
    confirm: j['confirm'] is Map
        ? Map<String, dynamic>.from(j['confirm'] as Map)
        : null,
  );
}

class ChatSuggestion {
  ChatSuggestion(this.label, this.prompt);
  final String label;
  final String prompt;
}

/// One poll of `GET /api/chat`.
class ChatSnapshot {
  ChatSnapshot({
    required this.epoch,
    required this.replace,
    required this.total,
    required this.messages,
    required this.running,
    required this.label,
    required this.steps,
    required this.queued,
    required this.aiReady,
    required this.suggestions,
  });

  final int epoch;
  final bool replace; // true: `messages` is the whole conversation; false: only the new ones
  final int total;
  final List<ChatMessage> messages;
  final bool running;
  final String label;
  final List<String> steps;
  final int queued;
  final bool aiReady;
  final List<ChatSuggestion> suggestions;

  factory ChatSnapshot.fromJson(Map<String, dynamic> j) => ChatSnapshot(
    epoch: (j['epoch'] as num?)?.toInt() ?? 0,
    replace: j['replace'] == true,
    total: (j['total'] as num?)?.toInt() ?? 0,
    messages: [
      for (final m in (j['messages'] as List? ?? const []))
        ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)),
    ],
    running: j['running'] == true,
    label: '${j['label'] ?? ''}',
    steps: [for (final s in (j['steps'] as List? ?? const [])) '$s'],
    queued: (j['queued'] as num?)?.toInt() ?? 0,
    aiReady: j['ai_ready'] != false,
    suggestions: [
      for (final s in (j['suggestions'] as List? ?? const []))
        ChatSuggestion('${(s as Map)['label']}', '${s['prompt']}'),
    ],
  );
}

class ChatDownload {
  ChatDownload(this.name, this.bytes, this.attached, this.missing);
  final String name;
  final Uint8List bytes;
  final List<String> attached;
  final List<String> missing; // enclosures not found in the saved documents
}

/// The AI's bid-work buttons under a tender table (same three as the website).
const bidJobs = [
  ('tech', 'Create technical bid checklist'),
  ('price', 'Create price bid'),
  ('docs', 'Create bid documents'),
];

/// Splits an answer into plain text and Markdown tables, so a wide table can scroll sideways on a phone.
List<(bool isTable, String text)> splitTables(String text) {
  final parts = <(bool, String)>[];
  final buf = <String>[];
  var inTable = false;
  void flush() {
    if (buf.isNotEmpty) parts.add((inTable, buf.join('\n')));
    buf.clear();
  }

  for (final line in text.split('\n')) {
    final isRow = line.trimLeft().startsWith('|');
    if (isRow != inTable) {
      flush();
      inTable = isRow;
    }
    buf.add(line);
  }
  flush();
  return parts;
}

final _bareUrl = RegExp(r'''(?<![\]\(\[<"'])(https?://[^\s|<>)\]]+)''');

/// BidAssist's own document address needs a token that only the server holds, so opening it directly answers
/// "Unauthorized". It is shown as a "Docs" link; tapping it makes the server fetch the files and the phone opens them
/// (see openTenderDocuments), instead of opening the address.
final _bidAssistLink = RegExp(
  r'\[[^\]]*\]\(\s*(https://api\.bidassist\.com/[^)\s]*)\s*\)|(https://api\.bidassist\.com/[^\s|<>)\]]+)',
);

String docsLinksForBidAssist(String line) => line.replaceAllMapped(
  _bidAssistLink,
  (m) => '[Docs](${m.group(1) ?? m.group(2)})',
);

/// Inside table rows a bare web address becomes a short "Documents" link (as on the website); a BidAssist document
/// address becomes "Docs", which downloads the tender's files.
String shortLinksInTables(String text) => text
    .split('\n')
    .map(
      (line) => line.trimLeft().startsWith('|')
          ? docsLinksForBidAssist(line).replaceAllMapped(_bareUrl, (m) {
              final url = m.group(1)!.replaceAll(RegExp(r'[.,;]+$'), '');
              return '[Documents]($url)${m.group(1)!.substring(url.length)}';
            })
          : line,
    )
    .join('\n');
