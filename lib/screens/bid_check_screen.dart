import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import '../models/bid_check.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/bid_report_view.dart';
import 'landing_screen.dart';

/// Kinds of file a tender or a bid can come in (the same list the website accepts).
const bidFileTypes = [
  'zip', 'rar', '7z', 'pdf', 'docx', 'xlsx', 'xls', 'xlsm', 'txt', 'csv', 'html', 'htm',
];

/// What an account made with a mobile OTP sees: no menu, just the free Bid Check - add the tender, add your bid, check it,
/// then the progress and the report. The check itself runs on the server (the same one the website's Analyze Tender page
/// uses); the files wait there until "Check my bid".
class BidCheckScreen extends StatefulWidget {
  const BidCheckScreen({super.key, required this.onSignOut, this.api});
  final VoidCallback onSignOut;

  /// The server client; tests pass their own.
  final ApiClient? api;

  @override
  State<BidCheckScreen> createState() => _BidCheckScreenState();
}

class _BidCheckScreenState extends State<BidCheckScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  BidCheckStatus? _status;
  int _step = 1;
  String? _busy; // "Uploading nit.pdf..."
  String? _error;
  String? _loadError;
  Timer? _timer;
  String _portal = 'Odisha e-procurement';
  final _tenderId = TextEditingController();

  static const _portals = ['GeM', 'CPPP', 'Odisha e-procurement', 'Another portal'];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tenderId.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await _api.bidCheck();
      if (!mounted) return;
      setState(() {
        _status = s;
        _loadError = null;
      });
      _timer?.cancel();
      if (s.running) {
        _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _pick(String kind) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: bidFileTypes,
      );
    } catch (e) {
      setState(() => _error = 'Could not open the file picker: $e');
      return;
    }
    if (picked.isEmpty) return;
    setState(() => _error = null);
    try {
      for (final f in picked) {
        setState(() => _busy = 'Uploading ${f.name}...');
        await _api.addBidCheckFile(kind, f.name, await f.readAsBytes());
      }
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _clearFiles(String kind) async {
    try {
      await _api.clearBidCheckFiles(kind);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _next() {
    final s = _status;
    if (s == null || s.tenderFiles.isEmpty) {
      setState(
        () => _error = _tenderId.text.trim().isNotEmpty
            ? 'Fetching a tender by its ID is coming soon. Please upload the tender PDF for now.'
            : 'Upload the tender PDF (NIT, ATC and corrigenda) first.',
      );
      return;
    }
    setState(() {
      _step = 2;
      _error = null;
    });
  }

  Future<void> _check() async {
    final s = _status;
    if (s == null || s.bidFiles.isEmpty) {
      setState(() => _error = 'Upload your bid files first.');
      return;
    }
    setState(() {
      _busy = 'Starting the check...';
      _error = null;
    });
    try {
      await _api.startBidCheck();
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _again() async {
    try {
      await _api.clearBidCheck();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    _timer?.cancel();
    setState(() {
      _step = 1;
      _error = null;
    });
    await _refresh();
  }

  // ------------------------------------------------------------------ pieces

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: BidColors.navy,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),
  );

  Widget _fileList(List<String> names, String kind) => names.isEmpty
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: BidColors.field,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BidColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  names.join('\n'),
                  key: ValueKey('$kind-files'),
                  style: const TextStyle(fontSize: 13, color: BidColors.navy),
                ),
              ),
              IconButton(
                tooltip: 'Remove these files',
                visualDensity: VisualDensity.compact,
                onPressed: _busy == null ? () => _clearFiles(kind) : null,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        );

  Widget _uploadButton(String kind, String label) => OutlinedButton.icon(
    key: ValueKey('pick-$kind'),
    onPressed: _busy == null ? () => _pick(kind) : null,
    icon: const Icon(Icons.upload_file),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: BidColors.navy,
      minimumSize: Size.fromHeight(52 * _k),
      side: const BorderSide(color: BidColors.navy, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  Widget _stepHeader(int step, String heading, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (step == 2)
            TextButton.icon(
              key: const ValueKey('step-back'),
              onPressed: () => setState(() {
                _step = 1;
                _error = null;
              }),
              icon: const Icon(Icons.arrow_back, size: 18, color: BidColors.brown),
              label: const Text('Back', style: TextStyle(color: BidColors.brown)),
            ),
          const Spacer(),
          Text('Step $step of 2', style: const TextStyle(color: BidColors.muted)),
        ],
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: step / 2,
          minHeight: 6,
          color: BidColors.brown,
          backgroundColor: const Color(0xFFE3DCCB),
        ),
      ),
      SizedBox(height: 14 * _k),
      Text(
        heading,
        style: const TextStyle(
          color: BidColors.navy,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
      SizedBox(height: 6 * _k),
      Text(sub, style: const TextStyle(color: BidColors.muted, fontSize: 15)),
    ],
  );

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _error!,
            key: const ValueKey('bid-error'),
            style: const TextStyle(
              color: Color(0xFFB3261E),
              fontWeight: FontWeight.w600,
            ),
          ),
        );

  Widget _stepOne(BidCheckStatus s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _stepHeader(1, 'Add the tender', 'From GeM, CPPP, Odisha e-procurement or any tender site.'),
      SizedBox(height: 14 * _k),
      Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14 * _k),
        decoration: BoxDecoration(
          color: BidColors.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BidColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Option A · Enter tender ID',
              style: TextStyle(fontWeight: FontWeight.w700, color: BidColors.navy),
            ),
            SizedBox(height: 10 * _k),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _portal,
              decoration: const InputDecoration(labelText: 'Portal', isDense: true),
              items: [
                for (final p in _portals) DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _portal = v ?? _portal),
            ),
            SizedBox(height: 10 * _k),
            TextField(
              key: const ValueKey('tender-id'),
              controller: _tenderId,
              decoration: const InputDecoration(labelText: 'Tender ID', isDense: true),
            ),
            SizedBox(height: 8 * _k),
            const Text(
              'We fetch the NIT and every corrigendum.',
              style: TextStyle(color: BidColors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: Text('or', style: TextStyle(color: BidColors.muted))),
      ),
      const Text(
        'Option B · Upload tender PDF',
        style: TextStyle(fontWeight: FontWeight.w700, color: BidColors.navy),
      ),
      SizedBox(height: 8 * _k),
      _uploadButton('tender', 'Upload tender files'),
      SizedBox(height: 4 * _k),
      const Text('NIT, ATC and corrigenda', style: TextStyle(color: BidColors.muted, fontSize: 12.5)),
      _fileList(s.tenderFiles, 'tender'),
      _errorText(),
      SizedBox(height: 16 * _k),
      FilledButton(
        key: const ValueKey('next'),
        style: FilledButton.styleFrom(
          backgroundColor: BidColors.navy,
          minimumSize: Size.fromHeight(52 * _k),
        ),
        onPressed: _busy == null ? _next : null,
        child: const Text('Next: upload my bid', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    ],
  );

  Widget _stepTwo(BidCheckStatus s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _stepHeader(2, 'Upload your technical bid', 'The documents you plan to submit, as they are now.'),
      SizedBox(height: 14 * _k),
      Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12 * _k),
        decoration: BoxDecoration(
          color: BidColors.field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BidColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.check, color: Color(0xFF15803D)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tender added', style: TextStyle(fontWeight: FontWeight.w700, color: BidColors.navy)),
                  Text(
                    '${s.tenderFiles.length} file(s) · ${s.tenderFiles.take(2).join(', ')}${s.tenderFiles.length > 2 ? ' + ${s.tenderFiles.length - 2} more' : ''}',
                    style: const TextStyle(color: BidColors.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _title('Upload bid files'),
      _uploadButton('bid', 'Upload bid files'),
      SizedBox(height: 4 * _k),
      const Text('PDF, scanned copies are fine', style: TextStyle(color: BidColors.muted, fontSize: 12.5)),
      _fileList(s.bidFiles, 'bid'),
      SizedBox(height: 14 * _k),
      Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14 * _k),
        decoration: BoxDecoration(
          color: BidColors.navy,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: BidColors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Your documents stay private', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              'Technical bid only. Never upload your price bid. Files are deleted after the check.',
              style: TextStyle(color: BidColors.soft, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      ),
      _errorText(),
      SizedBox(height: 16 * _k),
      FilledButton(
        key: const ValueKey('check'),
        style: FilledButton.styleFrom(
          backgroundColor: BidColors.orange,
          foregroundColor: BidColors.navy,
          minimumSize: Size.fromHeight(52 * _k),
        ),
        onPressed: _busy == null ? _check : null,
        child: const Text('Check my bid', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    ],
  );

  Widget _progress(BidCheckStatus s) {
    final secs = s.elapsed.floor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Analysing your bid...',
          style: const TextStyle(color: BidColors.navy, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8 * _k),
        Text(
          'Step ${s.stage} of 3 · ${s.stageWord} · ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
          key: const ValueKey('progress-line'),
          style: const TextStyle(color: BidColors.muted, fontSize: 15),
        ),
        SizedBox(height: 12 * _k),
        LinearProgressIndicator(
          value: (s.stage / 3) - 0.1,
          minHeight: 8,
          color: BidColors.brown,
          backgroundColor: const Color(0xFFE3DCCB),
        ),
        SizedBox(height: 14 * _k),
        for (final line in s.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: const TextStyle(color: BidColors.muted, fontSize: 13)),
          ),
        SizedBox(height: 10 * _k),
        const Text(
          'This takes a couple of minutes. You can close the app - the check keeps running and the result will be here when you come back.',
          style: TextStyle(color: BidColors.muted, fontSize: 13),
        ),
      ],
    );
  }

  Widget _card(Widget child) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(16, 4, 16, 24 * _k),
    child: Container(
      padding: EdgeInsets.fromLTRB(18, 14 * _k, 18, 20 * _k),
      decoration: BoxDecoration(
        color: BidColors.cream,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    ),
  );

  Widget _body() {
    final s = _status;
    if (s == null) {
      if (_loadError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                SizedBox(height: 12 * _k),
                FilledButton(
                  onPressed: _refresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (s.running) return _card(_progress(s));
    if (s.report != null) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.page,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: BidReportView(report: s.report!, onAgain: _again),
      );
    }
    if (s.error.isNotEmpty) {
      return _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'The check could not finish',
              style: TextStyle(color: BidColors.navy, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 10 * _k),
            Text(s.error, key: const ValueKey('check-error'), style: const TextStyle(color: Color(0xFFB3261E))),
            SizedBox(height: 16 * _k),
            FilledButton(
              key: const ValueKey('try-again'),
              style: FilledButton.styleFrom(backgroundColor: BidColors.navy),
              onPressed: _again,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    return _card(_step == 1 ? _stepOne(s) : _stepTwo(s));
  }

  /// How much smaller than normal the page is drawn so it fits a short phone (see build).
  double _k = 1.0;

  @override
  Widget build(BuildContext context) {
    // On a short phone the whole page is drawn smaller (text and gaps), so it fits without scrolling.
    final media = MediaQuery.of(context);
    final room = media.size.height - media.padding.top - media.padding.bottom;
    _k = math.pow(room / 760.0, 1.4).toDouble().clamp(0.55, 1.0);
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(media.textScaler.scale(1) * _k),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          visualDensity: _k < 0.9 ? VisualDensity.compact : null,
        ),
        child: Scaffold(
      backgroundColor: BidColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  const Flexible(
                    child: Text(
                      'Tender Agent',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('sign-out'),
                    onPressed: widget.onSignOut,
                    child: const Text('Sign out', style: TextStyle(color: BidColors.orange)),
                  ),
                ],
              ),
            ),
            if (_busy != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: BidColors.orange),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _busy!,
                        key: const ValueKey('busy'),
                        style: const TextStyle(color: BidColors.soft),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _body()),
          ],
        ),
      ),
    ),
    ),
    );
  }
}
