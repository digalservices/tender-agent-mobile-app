import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../models/compare.dart';
import '../models/saved_tender.dart';
import '../models/tender.dart';
import 'api_client.dart';
import 'saved_tenders_service.dart';

/// Which subset of tenders to show. Lives here so the Dashboard tiles can open the Tenders tab filtered.
enum TenderFilter { all, newOnes, closing, highValue, highRisk }

/// Holds the scored tender feed and the saved tenders, shared by the Dashboard, Tenders and Saved
/// screens so the feed is fetched once, not once per tab.
class TendersController extends ChangeNotifier {
  TendersController(this.uid) {
    _listenSaved();
  }

  /// (Re)starts the live view of the saved tenders. Also used by "Try again" after an error.
  void _listenSaved() {
    _savedSub?.cancel();
    _savedSub = _service
        .watchAll(uid)
        .listen(
          (list) {
            saved = list;
            savedIds = {for (final s in list) s.id};
            savedLoaded = true;
            notifyListeners();
          },
          onError: (Object e) {
            savedError = '$e';
            notifyListeners();
          },
        );
  }

  final String uid;

  /// "Try again" on the Saved screen after the list could not be loaded.
  void retrySaved() {
    savedError = null;
    savedLoaded = false;
    notifyListeners();
    _listenSaved();
  }

  final _api = ApiClient();
  final _service = SavedTendersService();
  StreamSubscription<List<SavedTender>>? _savedSub;

  TenderFeed? feed;
  String? error;
  bool loading = false;

  List<SavedTender> saved = [];
  Set<String> savedIds = {};
  bool savedLoaded = false;
  String? savedError;

  /// A question for the AI Analysis chat, queued by a Tender Agent quick action (read when that tab opens).
  String? pendingQuestion;

  /// Tenders put side by side on the Comparisons screen (up to [maxCompare]), by BID NO.
  final List<String> compareIds = [];

  /// Adds or removes a tender from the comparison. Returns a message when it cannot be added.
  String? toggleCompare(Tender t) {
    if (compareIds.remove(t.id)) {
      notifyListeners();
      return null;
    }
    if (compareIds.length >= maxCompare) {
      return 'You can compare up to $maxCompare tenders - remove one first.';
    }
    compareIds.add(t.id);
    notifyListeners();
    return null;
  }

  void removeCompare(String id) {
    if (compareIds.remove(id)) notifyListeners();
  }

  /// Set by a Dashboard tile; the Tenders tab reads and clears it when it opens.
  TenderFilter? requestedFilter;

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      feed = await _api.tenders();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not load tenders: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  TenderFilter? takeRequestedFilter() {
    final f = requestedFilter;
    requestedFilter = null;
    return f;
  }

  /// Tenders shown by the live search so far, by BID NO - so Compare finds a tender that is not in the feed.
  final Map<String, Tender> known = {};

  void remember(Iterable<Tender> tenders) {
    for (final t in tenders) {
      known[t.id] = t;
    }
  }

  /// The live feed's version of a tender, if it is still in the feed (or was shown by the live search).
  Tender? live(String id) {
    for (final t in feed?.tenders ?? const <Tender>[]) {
      if (t.id == id) return t;
    }
    return known[id];
  }

  /// Returns an error message, or null when it worked.
  Future<String?> toggleSaved(Tender t) => _run(
    () => savedIds.contains(t.id)
        ? _service.remove(uid, t.id)
        : _service.save(uid, t),
  );

  /// The AI Analysis "Save tender" button: saves the ticked tenders (the live feed's fresh version when it has
  /// them), or removes them again when every one is already saved. Returns an error message, or null.
  Future<String?> toggleSavedRows(List<ChatTender> rows) async {
    if (rows.isEmpty) return null;
    final allSaved = rows.every((r) => savedIds.contains(r.ref));
    return _run(() async {
      for (final r in rows) {
        if (allSaved) {
          await _service.remove(uid, r.ref);
        } else if (!savedIds.contains(r.ref)) {
          await _service.save(uid, live(r.ref) ?? r.asTender());
        }
      }
    });
  }

  Future<String?> updateSaved(String id, Map<String, dynamic> fields) =>
      _run(() => _service.update(uid, id, fields));

  Future<String?> removeSaved(String id) =>
      _run(() => _service.remove(uid, id));

  Future<String?> _run(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (e) {
      return 'Could not update saved tenders: $e';
    }
  }

  @override
  void dispose() {
    _savedSub?.cancel();
    super.dispose();
  }
}
