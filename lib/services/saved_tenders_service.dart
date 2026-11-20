import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/saved_tender.dart';
import '../models/tender.dart';

/// `companies/{uid}/saved_tenders/{tender_id}` - the web app's bookmarks, with the same fields.
class SavedTendersService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('companies').doc(uid).collection('saved_tenders');

  /// The ids of the saved tenders, live.
  Stream<Set<String>> watchIds(String uid) =>
      _col(uid).snapshots().map((q) => {for (final d in q.docs) d.id});

  /// Every saved tender with its status and note, live.
  Stream<List<SavedTender>> watchAll(String uid) => _col(uid).snapshots().map(
    (q) => [
      for (final d in q.docs)
        SavedTender.fromData(
          d.id,
          d.data(),
          (d.data()['saved_at'] as Timestamp?)?.toDate(),
        ),
    ],
  );

  Future<void> save(String uid, Tender t) => _col(uid).doc(t.id).set({
    ...t.toSavedSnapshot(),
    'status': 'Interested',
    'note': '',
    'saved_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> update(String uid, String id, Map<String, dynamic> fields) =>
      _col(uid)
          .doc(id)
          .update({...fields, 'updated_at': FieldValue.serverTimestamp()});

  Future<void> remove(String uid, String id) => _col(uid).doc(id).delete();
}
