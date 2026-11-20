import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../services/api_client.dart';
import 'bars.dart';

/// The agent steps that are about tenders: (what the step starts with, what to call it).
const _tenderSteps = <(String, String)>[
  ('🔎 Searching', 'Searched'),
  ('📄 Opening', 'Opened'),
  ('📥 Downloading', 'Downloaded documents'),
  ('📦 Using the saved tender pack', 'Tender pack'),
  ('📦 Reading the tender documents', 'Tender pack'),
];

String? _kindOf(String step) {
  for (final (prefix, name) in _tenderSteps) {
    if (step.startsWith(prefix)) return name;
  }
  return null;
}

/// "Agent & Tender Activity" -> Tenders: where the tenders come from, what the agent did with tenders (from the same
/// run log) and, for administrators, the tender source / BidAssist token / connection controls.
class TenderActivityView extends StatefulWidget {
  const TenderActivityView({super.key, required this.runs, this.api});
  final List<AgentRun> runs;

  /// For tests: a stand-in for the server.
  final ApiClient? api;

  @override
  State<TenderActivityView> createState() => _TenderActivityViewState();
}

class _TenderActivityViewState extends State<TenderActivityView> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _token = TextEditingController();
  TenderStatus? _status;
  String? _error;
  bool _busy = false;
  String? _message; // result of the last admin action
  bool _messageOk = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await _api.tenderStatus();
      if (mounted) setState(() => _status = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load: $e');
    }
  }

  void _say(String text, bool ok) => setState(() {
    _message = text;
    _messageOk = ok;
  });

  /// Runs an administrator action, shows its result, and refreshes the state.
  Future<void> _act(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final text = await action();
      if (mounted) _say(text, true);
      await _load();
    } on ApiException catch (e) {
      if (mounted) _say(e.message, false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (_error != null && s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (s == null) return const Center(child: CircularProgressIndicator());

    final events = <(DateTime, String, String)>[
      for (final r in widget.runs)
        if (r.startedAt != null)
          for (final step in r.steps)
            if (_kindOf(step) != null) (r.startedAt!, step, r.question),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    int count(String name) => events.where((e) => _kindOf(e.$2) == name).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Tender source',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'In use now: ${s.source}${s.live ? ' - every active tender in India, searched live.' : '.'}',
          ),
          if (s.notice.isNotEmpty) _banner(s.notice, Colors.orange.shade800),
          const SizedBox(height: 12),
          KpiGrid(
            tiles: [
              KpiTile(
                label: 'Tender searches',
                value: '${count('Searched')}',
                icon: Icons.search,
                color: const Color(0xFF7C3AED),
              ),
              KpiTile(
                label: 'Tenders opened',
                value: '${count('Opened')}',
                icon: Icons.article,
                color: const Color(0xFF2563EB),
              ),
              KpiTile(
                label: 'Document downloads',
                value: '${count('Downloaded documents')}',
                icon: Icons.folder_zip,
                color: const Color(0xFF0891B2),
              ),
              KpiTile(
                label: 'Tender packs',
                value: '${count('Tender pack')}',
                icon: Icons.inventory_2,
                color: const Color(0xFF16A34A),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Latest tender activity',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No tender activity yet - it shows here after the agent searches or opens tenders.',
              ),
            ),
          for (final (at, step, question) in events.take(30))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(step, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${_when(at)}${question.isEmpty ? '' : ' · $question'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (s.isAdmin) ..._admin(s),
        ],
      ),
    );
  }

  String _when(DateTime d) {
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
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day} ${months[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _banner(String text, Color color) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: TextStyle(color: color)),
  );

  void _pickSource(TenderStatus s, String? v) {
    if (v == null || _busy || v == s.choice) return;
    if (v == 'tenderdetail' && !s.haveTenderDetailKey) {
      _say('TenderDetail has no key on the server yet, so it cannot be used.', false);
      return;
    }
    _act(() async {
      await _api.setTenderSource(v);
      return 'Tender source saved - it applies to everyone within a minute.';
    });
  }

  void _saveToken() {
    final text = _token.text.trim();
    if (text.isEmpty) {
      _say('Paste the token first.', false);
      return;
    }
    _act(() async {
      final done = await _api.saveBidAssistToken(text);
      _token.clear();
      return done;
    });
  }

  List<Widget> _admin(TenderStatus s) {
    final t = s.token;
    return [
      const Divider(height: 32),
      const Text(
        'Tender source and connection (administrator)',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
      const SizedBox(height: 8),
      if (!s.canSwitch)
        const Text(
          'The browser source (BIDASSIST=true on the server) cannot be switched here.',
        )
      else ...[
        const Text('Source for everyone'),
        RadioGroup<String>(
          groupValue: s.choice,
          onChanged: (v) => _pickSource(s, v),
          child: const Column(
            children: [
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: 'bidassist_api',
                title: Text(
                  'BidAssist - every active tender in India, 10 per page',
                ),
              ),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: 'tenderdetail',
                title: Text('TenderDetail - the feed of about 500 tenders'),
              ),
            ],
          ),
        ),
        if (!s.haveTenderDetailKey)
          const Text(
            'Add TENDERDETAIL_API_KEY on the server to let TenderDetail stand in when BidAssist is down.',
            style: TextStyle(fontSize: 12.5),
          ),
        const Divider(height: 28),
        const Text(
          'BidAssist token - needed to download tender documents',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        if (t != null) ...[
          _banner(
            '${t.ok ? 'The token works.' : 'The token needs attention.'} ${t.message}'
            '${t.planEnd == null ? '' : ' Plan ends on ${t.planEnd}.'}'
            '${t.tokenFrom.isEmpty ? '' : ' (token ${t.tokenFrom})'}',
            t.ok ? Colors.green.shade700 : Colors.red.shade700,
          ),
          if (t.ok && t.daysLeft != null && t.daysLeft! <= 30)
            _banner(
              'The BidAssist plan ends in ${t.daysLeft! < 0 ? 0 : t.daysLeft} days. Renew it, then paste the new token here.',
              Colors.orange.shade800,
            ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _token,
          obscureText: true,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'New token',
            hintText: 'Paste the X-OFB-TOKEN value',
            helperText:
                'It is checked first and kept encrypted. It is never shown again.',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton(
              onPressed: _busy ? null : _saveToken,
              child: const Text('Save token'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _act(() async {
                      await _api.checkBidAssistToken();
                      return 'Checked just now.';
                    }),
              child: const Text('Check now'),
            ),
            if (t?.tokenFrom == 'saved in the app')
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _act(() async {
                        await _api.removeBidAssistToken();
                        return 'The saved token was removed.';
                      }),
                child: const Text('Remove saved token'),
              ),
          ],
        ),
      ],
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: LinearProgressIndicator(minHeight: 3),
        ),
      if (_message != null)
        _banner(
          _message!,
          _messageOk ? Colors.green.shade700 : Colors.red.shade700,
        ),
    ];
  }
}
