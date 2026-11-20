import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

import '../models/chat.dart';
import 'api_client.dart';

/// The AI Analysis conversation. The AI runs on the server; this sends requests and polls for the steps
/// and the answer, so a long job survives the phone sleeping or the tab changing.
class ChatController extends ChangeNotifier {
  final _api = ApiClient();

  List<ChatMessage> messages = [];
  List<ChatSuggestion> suggestions = [];
  bool loaded = false;
  bool running = false;
  bool aiReady = true;
  String label = '';
  List<String> steps = [];
  int queued = 0;
  String? error;

  /// Ticked tender refs per message index.
  final Map<int, Set<String>> selected = {};

  int _epoch = 0;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;

  /// First load (and a refresh when the tab opens again).
  Future<void> refresh() => _poll();

  Future<void> _poll() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final snap = await _api.chat(have: messages.length, epoch: _epoch);
      if (snap.replace) {
        messages = [...snap.messages];
        selected.clear();
      } else {
        messages = [...messages, ...snap.messages];
      }
      _epoch = snap.epoch;
      running = snap.running;
      label = snap.label;
      steps = snap.steps;
      queued = snap.queued;
      aiReady = snap.aiReady;
      suggestions = snap.suggestions;
      loaded = true;
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not load the chat: $e';
    } finally {
      _polling = false;
    }
    _schedule();
    if (!_disposed) notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    // Poll only while the AI is working (or after a request that may not have started yet).
    if (running && !_disposed) {
      _timer = Timer(const Duration(seconds: 2), _poll);
    }
  }

  Future<String?> _act(Future<void> Function() action) async {
    try {
      await action();
      running = true; // optimistic, until the next poll says otherwise
      label = label.isEmpty ? 'Working...' : label;
      notifyListeners();
      await _poll();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> ask(String text) => _act(() => _api.chatAsk(text: text));

  Future<String?> findBest() => _act(() => _api.chatAsk(best: true));

  Future<String?> bid(String job, int index) {
    final refs = (selected[index] ?? {}).toList();
    // The ticks stay after a job starts (the user unticks them, or taps the X on the selection bar).
    return _act(() => _api.chatBid(job, index, refs));
  }

  /// The message count when "Cancel" was tapped on a warning, so its buttons stay hidden.
  int dismissedAt = -1;

  /// Whether the newest message is a warning that still waits for "Run anyway" / "Cancel".
  bool get awaitingConfirm =>
      !running &&
      messages.isNotEmpty &&
      messages.last.confirm != null &&
      dismissedAt != messages.length;

  void cancelConfirm() {
    dismissedAt = messages.length;
    notifyListeners();
  }

  /// "Run anyway" after a warning: runs the held job without the check.
  Future<String?> runAnyway(ChatMessage held) {
    final c = held.confirm;
    if (c == null || c['index'] is! int) {
      return Future.value('That warning is too old - pick the tender again.');
    }
    return _act(
      () => _api.chatBid('${c['job']}', c['index'] as int, [
        '${c['ref']}',
      ], force: true),
    );
  }

  Future<String?> stopQueue() async {
    try {
      await _api.chatStop();
      await _poll();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> clear() async {
    try {
      await _api.chatClear();
      messages = [];
      selected.clear();
      await _poll();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Unticks every tender (the close button on the "N tenders selected" bar).
  void clearSelection() {
    selected.clear();
    notifyListeners();
  }

  void toggle(int index, String ref, bool on) {
    final set = selected.putIfAbsent(index, () => {});
    on ? set.add(ref) : set.remove(ref);
    notifyListeners();
  }

  /// Builds the Word / Excel file on the server, saves it and opens it. Returns (error, note about enclosures).
  Future<(String?, String?)> download(int index) async {
    try {
      final file = await _api.chatExport(index);
      final path =
          '${Directory.systemTemp.path}/${file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      final result = await OpenFilex.open(path);
      final notes = [
        if (file.attached.isNotEmpty) 'Attached: ${file.attached.join(', ')}.',
        if (file.missing.isNotEmpty)
          'Not in your saved documents - attach before submitting: ${file.missing.join(', ')}.',
      ].join('\n');
      if (result.type != ResultType.done) {
        return (
          'Saved as ${file.name}, but no app was found to open it. (${result.message})',
          notes,
        );
      }
      return (null, notes.isEmpty ? null : notes);
    } on ApiException catch (e) {
      return (e.message, null);
    } catch (e) {
      return ('Could not open the file: $e', null);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
