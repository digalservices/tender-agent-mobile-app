import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// The single saved files of a company, stored exactly like the web app does:
///   companies/{uid}/{kind}/current            name, size, chunks, uploaded_at (+ person_name, designation)
///   companies/{uid}/{kind}/current/chunks/0000 {n, data}   (a Firestore document holds at most 1 MiB)
enum AssetKind {
  letterhead('letterhead'),
  signature('signature'), // the proprietor's
  authorisedSignature('authorised_signature'),
  seal('seal');

  const AssetKind(this.collection);
  final String collection;
}

const maxAssetBytes = 10 * 1024 * 1024; // same limit as the web app
const _chunkBytes = 700000;
const _chunksPerBatch = 4;

class AssetInfo {
  AssetInfo({
    required this.name,
    required this.size,
    required this.chunks,
    this.personName = '',
    this.uploadedAt,
  });
  final String name;
  final int size;
  final int chunks;
  final String personName;
  final DateTime? uploadedAt;
}

class AssetService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid, AssetKind kind) =>
      _db
          .collection('companies')
          .doc(uid)
          .collection(kind.collection)
          .doc('current');

  Future<AssetInfo?> info(String uid, AssetKind kind) async {
    final snap = await _ref(uid, kind).get();
    final d = snap.data();
    if (d == null) return null;
    return AssetInfo(
      name: '${d['name'] ?? ''}',
      size: (d['size'] as num?)?.toInt() ?? 0,
      chunks: (d['chunks'] as num?)?.toInt() ?? 0,
      personName: '${d['person_name'] ?? ''}',
      uploadedAt: (d['uploaded_at'] as Timestamp?)?.toDate(),
    );
  }

  /// The file bytes, or null when it is missing or only partly uploaded.
  Future<Uint8List?> bytes(String uid, AssetKind kind, AssetInfo info) async {
    final chunks = await _ref(
      uid,
      kind,
    ).collection('chunks').orderBy('n').get();
    if (chunks.docs.length != info.chunks) return null;
    final out = BytesBuilder(copy: false);
    for (final c in chunks.docs) {
      out.add((c.data()['data'] as Blob).bytes);
    }
    return out.takeBytes();
  }

  /// Replaces the saved file. The metadata is removed first and written last, so a half-replaced
  /// file never looks complete.
  Future<void> save(
    String uid,
    AssetKind kind,
    String name,
    Uint8List data, {
    Map<String, dynamic> extra = const {},
  }) async {
    if (data.isEmpty) throw StateError('$name is empty.');
    if (data.length > maxAssetBytes) {
      throw StateError(
        '$name is larger than ${maxAssetBytes ~/ (1024 * 1024)} MB.',
      );
    }
    final ref = _ref(uid, kind);
    await ref.delete();
    await _clearChunks(ref);
    final pieces = <Uint8List>[
      for (var i = 0; i < data.length; i += _chunkBytes)
        Uint8List.sublistView(
          data,
          i,
          i + _chunkBytes > data.length ? data.length : i + _chunkBytes,
        ),
    ];
    for (var start = 0; start < pieces.length; start += _chunksPerBatch) {
      final batch = _db.batch();
      for (
        var n = start;
        n < start + _chunksPerBatch && n < pieces.length;
        n++
      ) {
        batch.set(ref.collection('chunks').doc(n.toString().padLeft(4, '0')), {
          'n': n,
          'data': Blob(pieces[n]),
        });
      }
      await batch.commit();
    }
    await ref.set({
      'name': name,
      'size': data.length,
      'chunks': pieces.length,
      'uploaded_at': FieldValue.serverTimestamp(),
      ...extra,
    });
  }

  Future<void> setPersonName(String uid, AssetKind kind, String name) =>
      _ref(uid, kind).update({'person_name': name});

  Future<void> delete(String uid, AssetKind kind) async {
    final ref = _ref(uid, kind);
    await ref.delete();
    await _clearChunks(ref);
  }

  Future<void> _clearChunks(DocumentReference<Map<String, dynamic>> ref) async {
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
  }
}
