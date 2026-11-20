import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat.dart';
import '../models/signup.dart';
import '../models/tender.dart';
import '../services/auth_service.dart';
import '../services/chat_controller.dart';
import '../services/document_service.dart';
import '../models/md_table.dart';
import '../services/tender_files.dart';
import '../widgets/table_cards.dart';
import '../services/tenders_controller.dart';
import '../theme.dart';

/// The website's AI Analysis page: a hero card with the company's key facts and "Find best tenders for me",
/// starter questions, and the conversation with the Tender Agent (tender tables with bid-work buttons).
class AiAnalysisScreen extends StatefulWidget {
  const AiAnalysisScreen({
    super.key,
    required this.user,
    required this.auth,
    required this.chat,
    required this.tenders,
  });
  final User user;
  final AuthService auth;
  final ChatController chat;
  final TendersController tenders;

  @override
  State<AiAnalysisScreen> createState() => _AiAnalysisScreenState();
}

class _AiAnalysisScreenState extends State<AiAnalysisScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic>? _company;
  int? _docCount;
  int _lastCount = 0;
  bool _lastRunning = false;

  ChatController get _chat => widget.chat;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_changed);
    _chat.refresh().then((_) => _takePending());
    widget.auth.company(widget.user.uid).then((c) {
      if (mounted) setState(() => _company = c);
    });
    DocumentService().watch(widget.user.uid).first.then((d) {
      if (mounted) setState(() => _docCount = d.length);
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_changed);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final grew = _chat.messages.length != _lastCount;
    if (grew || _chat.running != _lastRunning) {
      _lastCount = _chat.messages.length;
      _lastRunning = _chat.running;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// A question queued from the Dashboard / Tender Agent quick actions.
  void _takePending() {
    final q = widget.tenders.pendingQuestion;
    if (q == null || !mounted) return;
    widget.tenders.pendingQuestion = null;
    _send(q);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
        duration: Duration(seconds: error ? 6 : 4),
      ),
    );
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _chat.running) return;
    _input.clear();
    final err = await _chat.ask(t);
    if (err != null) _toast(err, error: true);
  }

  Future<void> _findBest() async {
    final err = await _chat.findBest();
    if (err != null) _toast(err, error: true);
  }

  Future<void> _bid(String job, int index) async {
    final err = await _chat.bid(job, index);
    if (err != null) _toast(err, error: true);
  }

  /// The ticked tenders of one answer, as table rows.
  List<ChatTender> _picked(int index) {
    final ticked = _chat.selected[index] ?? {};
    return [
      for (final t in _chat.messages[index].tenders)
        if (ticked.contains(t.ref)) t,
    ];
  }

  bool _allSaved(int index) {
    final rows = _picked(index);
    return rows.isNotEmpty &&
        rows.every((r) => widget.tenders.savedIds.contains(r.ref));
  }

  Future<void> _saveTicked(int index) async {
    final rows = _picked(index);
    final removing = _allSaved(index);
    final err = await widget.tenders.toggleSavedRows(rows);
    if (!mounted) return;
    _toast(
      err ??
          (removing
              ? 'Removed from Saved Tenders.'
              : 'Saved to Saved Tenders.'),
      error: err != null,
    );
  }

  Future<void> _download(int index) async {
    _toast('Preparing your file...');
    final (err, note) = await _chat.download(index);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (err != null) _toast(err, error: true);
    if (note != null) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Enclosures'),
          content: Text(note),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _newChat({bool confirm = false}) async {
    if (_chat.running) {
      _toast('Wait for the AI to finish first.', error: true);
      return;
    }
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Delete chat history'),
          content: const Text(
            'This clears the conversation and removes it from your account. This can\'t be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final err = await _chat.clear();
    if (err != null) _toast(err, error: true);
  }

  // ------------------------------------------------------------------ pieces

  Widget _hero() {
    final c = _company ?? const <String, dynamic>{};
    final turnover = rupeesFromCrore(c['annual_turnover_cr']);
    final name = '${c['company_name'] ?? 'your company'}';
    final contact = '${c['contact_person'] ?? ''}'.trim();
    final first = contact.isEmpty ? '' : ' ${contact.split(' ').first}';
    final docs = _docCount;
    final stats = [
      (Icons.description_outlined, 'Documents', docs == null ? '—' : '$docs'),
      (Icons.apartment, 'Business type', '${c['business_type'] ?? '—'}'),
      (
        Icons.payments_outlined,
        'Annual turnover',
        turnover.isEmpty ? '—' : '₹${_commas(turnover)}',
      ),
      (Icons.location_on_outlined, 'Location', '${c['city'] ?? '—'}'),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text(
                'AI TENDER AGENT',
                style: TextStyle(
                  color: Colors.white70,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Hi$first, let's find your next win",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "I read $name's profile and ${docs ?? 'your'} saved document(s), search live tenders and rank the ones you can actually win - with reasons, risks and the documents to prepare.",
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.blue,
            ),
            onPressed: _chat.running || !_chat.aiReady ? null : _findBest,
            icon: const Icon(Icons.travel_explore),
            label: const Text('Find best tenders for me'),
          ),
          const SizedBox(height: 14),
          // Tiles size themselves to their text, so a larger phone font never overflows.
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in stats)
                  Container(
                    width: (box.maxWidth - 8) / 2,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(s.$1, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                s.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.$3,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _commas(String digits) =>
      digits.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  Widget _suggestions() {
    final items = _chat.suggestions;
    if (items.isEmpty) return const SizedBox.shrink();
    const icons = [
      Icons.summarize,
      Icons.travel_explore,
      Icons.fact_check,
      Icons.description,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('TRY ASKING', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, s) in items.indexed)
              ActionChip(
                avatar: Icon(icons[i % icons.length], size: 18),
                label: Text(s.label),
                onPressed: _chat.running ? null : () => _send(s.prompt),
              ),
          ],
        ),
      ],
    );
  }

  MarkdownStyleSheet get _mdStyle =>
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 14.5, height: 1.4),
        tableBorder: TableBorder.all(color: Colors.black12),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.all(6),
        tableHead: const TextStyle(fontWeight: FontWeight.w700),
        tableBody: const TextStyle(fontSize: 13),
      );

  void _onLink(String text, String? href, String title) {
    if (href == null) return;
    if (isBidAssistLink(href)) {
      // A BidAssist tender's files: the server fetches them (the address itself needs a token) and the phone opens them.
      openTenderDocuments(context, href);
      return;
    }
    Clipboard.setData(ClipboardData(text: href));
    _toast('Link copied - paste it into your browser.');
  }

  Widget _answerBody(String text) {
    final parts = splitTables(shortLinksInTables(text));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (isTable, chunk) in parts)
          if (chunk.trim().isNotEmpty)
            isTable && (parseMdTable(chunk)?.isTenderTable ?? false)
                ? TableCards(
                    table: parseMdTable(chunk)!,
                    style: _mdStyle,
                    onTapLink: _onLink,
                  )
                : isTable
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: MarkdownBody(
                      data: chunk,
                      styleSheet: _mdStyle,
                      onTapLink: _onLink,
                      fitContent: true,
                    ),
                  )
                : MarkdownBody(
                    data: chunk,
                    styleSheet: _mdStyle,
                    onTapLink: _onLink,
                    selectable: true,
                  ),
      ],
    );
  }

  /// The ticked tenders' details and documents, in a sheet from the bottom.
  void _showDetails(List<ChatTender> tenders) {
    String cr(double? rupees) =>
        formatValueCr(rupees == null || rupees == 0 ? null : rupees / 1e7);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            for (final t in tenders) ...[
              Text(
                t.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final (label, value) in [
                ('BID NO', t.ref),
                ('Authority', t.authority),
                ('Location', t.location),
                ('Sector', t.sector ?? ''),
                ('Tender value', cr(t.value)),
                ('EMD', cr(t.emd)),
                ('Document cost', cr(t.docCost)),
                ('Bid deadline', t.dueDate ?? 'Not stated'),
              ])
                if (value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 112,
                          child: Text(
                            label,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                        Expanded(child: Text(value)),
                      ],
                    ),
                  ),
              if (t.link.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => openTenderDocuments(context, t.link),
                    icon: Icon(
                      isBidAssistLink(t.link) ? Icons.folder_zip : Icons.link,
                    ),
                    label: Text(
                      isBidAssistLink(t.link)
                          ? 'Tender documents'
                          : 'Copy tender documents link',
                    ),
                  ),
                ),
              if (t != tenders.last) const Divider(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tenderList(int index, ChatMessage m) {
    if (m.tenders.isEmpty) return const SizedBox.shrink();
    final picked = _chat.selected[index] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(
          'Tick the tenders to prepare bids for',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        for (final t in m.tenders)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: CheckboxListTile(
              dense: true,
              value: picked.contains(t.ref),
              // no ticking while the AI works (as on the website): the ticks stay as they are until it has finished
              onChanged: _chat.running
                  ? null
                  : (on) => _chat.toggle(index, t.ref, on == true),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  'BID NO ${t.ref}',
                  if (t.authority.isNotEmpty) t.authority,
                  if (t.location.isNotEmpty) t.location,
                  'Value ${formatValueCr(t.value == null ? null : t.value! / 1e7)}',
                  if (t.dueDate != null) 'Due ${t.dueDate}',
                ].join(' · '),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: picked.isEmpty
                  ? null
                  : () => _showDetails([
                      for (final t in m.tenders)
                        if (picked.contains(t.ref)) t,
                    ]),
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('Tender details'),
            ),
            for (final (job, text) in bidJobs)
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: picked.isEmpty || _chat.running
                    ? null
                    : () => _bid(job, index),
                child: Text(text),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: picked.isEmpty || _chat.running
                  ? null
                  : () => _saveTicked(index),
              icon: Icon(
                _allSaved(index) ? Icons.bookmark_remove : Icons.bookmark_add,
                size: 18,
              ),
              label: Text(
                _allSaved(index) ? 'Remove from saved' : 'Save tender',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _exportButton(int index, ChatMessage m) {
    if (m.export.isEmpty) return const SizedBox.shrink();
    final word = m.export == 'docx';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => _download(index),
            icon: const Icon(Icons.download),
            label: Text(word ? 'Download as Word' : 'Download as Excel'),
          ),
          if (word)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Uses the letterhead, signature and seal saved in Settings.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bubble(int index, ChatMessage m) {
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 40),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            m.text.replaceAll('*', ''),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 12, right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.smart_toy, size: 18, color: AppColors.blue),
              SizedBox(width: 6),
              Text(
                'Tender Agent',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _answerBody(m.text),
          _exportButton(index, m),
          _tenderList(index, m),
          _confirmButtons(index, m),
        ],
      ),
    );
  }

  /// "Run anyway" / "Cancel" under a warning that held a bid job back (only on the newest message).
  Widget _confirmButtons(int index, ChatMessage m) {
    if (m.confirm == null ||
        index != _chat.messages.length - 1 ||
        !_chat.awaitingConfirm) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
              onPressed: _chat.cancelConfirm,
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
              onPressed: () async {
                final err = await _chat.runAnyway(m);
                if (err != null) _toast(err, error: true);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run anyway'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _status() {
    final steps = _chat.steps.reversed.take(6).toList().reversed.toList();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _chat.label.isEmpty ? 'Working...' : _chat.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(s, style: const TextStyle(fontSize: 12.5)),
            ),
          if (_chat.queued > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_chat.queued} more tender(s) waiting - each is handled on its own.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final err = await _chat.stopQueue();
                    if (err != null) _toast(err, error: true);
                  },
                  child: const Text('Stop the rest'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          const Text(
            'This can take a few minutes. You can switch tabs - the answer will be here.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  /// Stays above the message box while tenders are ticked, so the three bid buttons are always in reach
  /// however far down the tender list the person has scrolled.
  Widget _selectionBar() {
    final picks = _chat.selected.entries.where((e) => e.value.isNotEmpty);
    if (picks.isEmpty) return const SizedBox.shrink();
    final index = picks.last.key;
    final count = picks.last.value.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$count tender${count == 1 ? '' : 's'} selected',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Close - untick all',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: _chat.clearSelection,
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () => _showDetails([
                  for (final t in _chat.messages[index].tenders)
                    if ((_chat.selected[index] ?? {}).contains(t.ref)) t,
                ]),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('Tender details'),
              ),
              for (final (job, text) in bidJobs)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: _chat.running ? null : () => _bid(job, index),
                  child: Text(text),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _chat.running ? null : () => _saveTicked(index),
                icon: Icon(
                  _allSaved(index) ? Icons.bookmark_remove : Icons.bookmark_add,
                  size: 18,
                ),
                label: Text(
                  _allSaved(index) ? 'Remove from saved' : 'Save tender',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      TextButton.icon(
        onPressed: _chat.running ? null : () => _newChat(),
        icon: const Icon(Icons.add_comment_outlined, size: 18),
        label: const Text('New chat'),
      ),
      TextButton.icon(
        onPressed: _chat.messages.isEmpty || _chat.running
            ? null
            : () => _newChat(confirm: true),
        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
        label: const Text('Delete history'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final messages = _chat.messages;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              Text(
                'AI Analysis',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Text(
                'Ask about your company, or find the tenders that suit it best',
              ),
              _actions(),
              _hero(),
              if (!_chat.aiReady)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'The AI service is not set up yet. Please contact the administrator.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              if (_chat.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _chat.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _chat.refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              if (!_chat.loaded && _chat.error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_chat.loaded && messages.isEmpty) _suggestions(),
              for (final (i, m) in messages.indexed) _bubble(i, m),
              if (_chat.running) _status(),
            ],
          ),
        ),
        _selectionBar(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    enabled: !_chat.running,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: _chat.running
                          ? 'The AI is working...'
                          : 'e.g. Which tenders are best for my company?',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _chat.running ? null : () => _send(_input.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
