import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads and writes `companies/{uid}` - the same document the web app uses.
/// Writes merge into the existing document and never touch `status`, so an edit can't undo an
/// administrator's approval.
class CompanyService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('companies').doc(uid);

  Future<Map<String, dynamic>> load(String uid) async {
    final snap = await _ref(uid).get();
    return snap.data() ?? {};
  }

  Future<void> saveDetails(String uid, Map<String, dynamic> details) =>
      _merge(uid, details);

  Future<void> saveChecklist(
    String uid, {
    required bool? registered,
    required List<String> documents,
  }) => _merge(uid, {
    'registered_company': registered,
    'tender_documents': documents,
  });

  Future<void> _merge(String uid, Map<String, dynamic> fields) => _ref(uid).set(
    {...fields, 'updated_at': FieldValue.serverTimestamp()},
    SetOptions(merge: true),
  );
}
