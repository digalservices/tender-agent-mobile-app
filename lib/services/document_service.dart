import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// File types the web app accepts (documents.SUPPORTED_TYPES) and its size limit.
const supportedExtensions = ['pdf', 'docx', 'txt', 'md'];
const maxFileBytes = 10 * 1024 * 1024;

// Same layout as the web app, so documents added in either app show up in both:
//   companies/{uid}/documents/{id}          name, size, chunks, uploaded_at
//   companies/{uid}/documents/{id}/chunks/{0000}   {n, data}  (a Firestore document holds at most 1 MiB)
//   companies/{uid}/passages/{id}_{0000}     the searchable text, written by the AI backend when it analyses a file
const _chunkBytes = 700000;
const _chunksPerBatch = 4;
const _passagesPerBatch = 400;

class CompanyDocument {
  CompanyDocument({
    required this.id,
    required this.name,
    required this.size,
    this.uploadedAt,
  });
  final String id;
  final String name;
  final int size;
  final DateTime? uploadedAt;
}

class DocumentService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _company(String uid) =>
      _db.collection('companies').doc(uid);
  CollectionReference<Map<String, dynamic>> _docs(String uid) =>
      _company(uid).collection('documents');

  /// Newest first. A file that is still uploading has no metadata yet, so it never appears half-done.
  Stream<List<CompanyDocument>> watch(String uid) =>
      _docs(uid)
          .orderBy('uploaded_at', descending: true)
          .snapshots()
          .map(
            (q) => [
              for (final s in q.docs)
                CompanyDocument(
                  id: s.id,
                  name: '${s.data()['name'] ?? s.id}',
                  size: (s.data()['size'] as num?)?.toInt() ?? 0,
                  uploadedAt: (s.data()['uploaded_at'] as Timestamp?)?.toDate(),
                ),
            ],
          );

  /// Splits the file into chunks, then writes the metadata last (like the web app).
  Future<void> upload(String uid, String filename, Uint8List data) async {
    if (data.isEmpty) throw DocumentException('$filename is empty.');
    if (data.length > maxFileBytes) {
      throw DocumentException(
        '$filename is larger than ${maxFileBytes ~/ (1024 * 1024)} MB.',
      );
    }
    final ref = _docs(uid).doc();
    final pieces = <Uint8List>[
      for (var i = 0; i < data.length; i += _chunkBytes)
        Uint8List.sublistView(
          data,
          i,
          i + _chunkBytes > data.length ? data.length : i + _chunkBytes,
        ),
    ];
    try {
      for (var start = 0; start < pieces.length; start += _chunksPerBatch) {
        final batch = _db.batch();
        for (
          var n = start;
          n < start + _chunksPerBatch && n < pieces.length;
          n++
        ) {
          batch.set(
            ref.collection('chunks').doc(n.toString().padLeft(4, '0')),
            {'n': n, 'data': Blob(pieces[n])},
          );
        }
        await batch.commit();
      }
      await ref.set({
        'name': filename,
        'size': data.length,
        'chunks': pieces.length,
        'uploaded_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      await _deleteChunks(
        ref,
      ); // best effort: don't leave orphaned pieces behind
      throw DocumentException('Could not upload $filename: $e');
    }
  }

  Future<Uint8List> read(String uid, String docId) async {
    final chunks = await _docs(uid)
        .doc(docId)
        .collection('chunks')
        .orderBy('n')
        .get();
    final out = BytesBuilder(copy: false);
    for (final c in chunks.docs) {
      out.add((c.data()['data'] as Blob).bytes);
    }
    return out.takeBytes();
  }

  /// Removes the file, its pieces and any searchable passages the AI made from it.
  Future<void> delete(String uid, String docId) async {
    final passages = _company(uid).collection('passages');
    while (true) {
      final group = await passages
          .where('doc_id', isEqualTo: docId)
          .limit(_passagesPerBatch)
          .get();
      if (group.docs.isEmpty) break;
      final batch = _db.batch();
      for (final s in group.docs) {
        batch.delete(s.reference);
      }
      await batch.commit();
    }
    final ref = _docs(uid).doc(docId);
    await _deleteChunks(ref);
    await ref.delete();
  }

  Future<void> _deleteChunks(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      while (true) {
        final group = await ref
            .collection('chunks')
            .limit(_chunksPerBatch * 2)
            .get();
        if (group.docs.isEmpty) break;
        final batch = _db.batch();
        for (final c in group.docs) {
          batch.delete(c.reference);
        }
        await batch.commit();
      }
    } catch (_) {}
  }
}

class DocumentException implements Exception {
  DocumentException(this.message);
  final String message;
  @override
  String toString() => message;
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
