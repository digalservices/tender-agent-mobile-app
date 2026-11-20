import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/asset_service.dart';

mixin _Say<T extends StatefulWidget> on State<T> {
  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }
}

/// A .docx is a zip holding word/document.xml. (The website opens it with python-docx; this is the
/// same check without needing a server.)
bool looksLikeDocx(Uint8List data) {
  if (data.length < 4 || data[0] != 0x50 || data[1] != 0x4B)
    return false; // "PK"
  return String.fromCharCodes(data).contains('word/document.xml');
}

String _kb(int bytes) => '${(bytes / 1024).ceil().clamp(1, 1 << 30)} KB';

/// True when the bytes decode as a picture (the web app checks the same before saving).
Future<bool> isValidImage(Uint8List data) async {
  try {
    final codec = await ui.instantiateImageCodec(data);
    codec.dispose();
    return true;
  } catch (_) {
    return false;
  }
}

Widget _spinner() => const SizedBox(
  height: 18,
  width: 18,
  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
);

// ---------------------------------------------------------------- letterhead

/// The company letterhead (.docx, or a PDF that is converted on the server). Every drafted bid
/// document is exported onto it.
class LetterheadCard extends StatefulWidget {
  const LetterheadCard({super.key, required this.uid});
  final String uid;

  @override
  State<LetterheadCard> createState() => _LetterheadCardState();
}

class _LetterheadCardState extends State<LetterheadCard>
    with _Say<LetterheadCard> {
  final _assets = AssetService();
  final _api = ApiClient();
  late Future<AssetInfo?> _info = _assets.info(
    widget.uid,
    AssetKind.letterhead,
  );
  bool _busy = false;

  Future<void> _upload() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['docx', 'pdf'],
      );
    } catch (e) {
      _say('Could not open the file picker: $e', error: true);
      return;
    }
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final data = await file.readAsBytes();
      if (data.length > maxAssetBytes)
        throw ApiException('${file.name} is larger than 10 MB.');
      if (file.name.toLowerCase().endsWith('.pdf')) {
        // Only a PDF needs the server: turning its first page into a Word header/footer takes Python.
        await _api.saveLetterhead(file.name, data);
      } else {
        // A Word file goes straight into the database, like the website stores it.
        if (!looksLikeDocx(data)) {
          throw "${file.name} isn't a Word file that can be opened. Save it as .docx and try again.";
        }
        await _assets.save(widget.uid, AssetKind.letterhead, file.name, data);
      }
      if (!mounted) return;
      setState(() => _info = _assets.info(widget.uid, AssetKind.letterhead));
      _say('Letterhead saved to your company profile.');
    } catch (e) {
      _say('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await _assets.delete(widget.uid, AssetKind.letterhead);
      if (!mounted) return;
      setState(() => _info = Future.value(null));
      _say('Letterhead removed.');
    } catch (e) {
      _say('Could not remove the letterhead: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<AssetInfo?>(
          future: _info,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snap.hasError)
              return Text('Could not load the letterhead.\n${snap.error}');
            final info = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (info != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade700,
                    ),
                    title: Text(info.name),
                    subtitle: Text(
                      '${_kb(info.size)} · Saved to your company profile. Every drafted bid document is exported onto it.',
                    ),
                  )
                else
                  const Text(
                    "Upload a Word or PDF file with your letterhead design. A PDF's first page is split into a "
                    'header band and a footer band automatically. Every drafted bid document is exported onto it.',
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: _busy ? _spinner() : const Icon(Icons.upload_file),
                  label: Text(
                    info != null
                        ? 'Replace letterhead'
                        : 'Upload letterhead (.docx or .pdf)',
                  ),
                ),
                if (info != null)
                  TextButton.icon(
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- signatures and seal

/// The proprietor's signature, the authorised signatory's signature and the company seal.
class SignatureSealCard extends StatelessWidget {
  const SignatureSealCard({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            "Upload the proprietor's signature, the authorised signatory's signature and the company seal as "
            'images (PNG, JPG or JPEG, ideally on a transparent or white background). On the Word file the '
            "authorised signatory's signature, name and the seal go at the bottom of every drafted page; the "
            "proprietor's go only on the pages where your company documents are attached.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ImageAssetBox(
          uid: uid,
          kind: AssetKind.signature,
          title: "Proprietor's signature",
          label: 'proprietor signature',
          nameLabel: 'Proprietor name',
        ),
        const SizedBox(height: 8),
        ImageAssetBox(
          uid: uid,
          kind: AssetKind.authorisedSignature,
          title: "Authorised signatory's signature",
          label: 'authorised signature',
          nameLabel: 'Authorised signatory name',
        ),
        const SizedBox(height: 8),
        ImageAssetBox(
          uid: uid,
          kind: AssetKind.seal,
          title: 'Company seal / stamp',
          label: 'seal',
        ),
      ],
    );
  }
}

class ImageAssetBox extends StatefulWidget {
  const ImageAssetBox({
    super.key,
    required this.uid,
    required this.kind,
    required this.title,
    required this.label,
    this.nameLabel,
  });
  final String uid;
  final AssetKind kind;
  final String title;
  final String label;

  /// Set for the two signatures: the name printed under the signature on the bid documents.
  final String? nameLabel;

  @override
  State<ImageAssetBox> createState() => _ImageAssetBoxState();
}

class _Loaded {
  _Loaded(this.info, this.bytes);
  final AssetInfo info;
  final Uint8List? bytes;
}

class _ImageAssetBoxState extends State<ImageAssetBox>
    with _Say<ImageAssetBox> {
  final _assets = AssetService();
  final _api = ApiClient();
  final _name = TextEditingController();
  late Future<_Loaded?> _loaded = _load();
  bool _busy = false;

  bool get _hasName => widget.nameLabel != null;

  Future<_Loaded?> _load() async {
    final info = await _assets.info(widget.uid, widget.kind);
    if (info == null) return null;
    final bytes = await _assets.bytes(widget.uid, widget.kind, info);
    _name.text = info.personName;
    return _Loaded(info, bytes);
  }

  void _reload() => setState(() => _loaded = _load());

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _say('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
      );
    } catch (e) {
      _say('Could not open the file picker: $e', error: true);
      return;
    }
    if (file == null) return;
    final picked = file;
    await _run(() async {
      final data = await picked.readAsBytes();
      if (!await isValidImage(data)) {
        throw "${picked.name} isn't an image that can be opened. Use a PNG, JPG or JPEG and try again.";
      }
      // Like the website, read the signatory's name from the picture (best effort - it can be corrected).
      var name = '';
      if (_hasName) {
        try {
          name = await _api.readSignatureName(data);
        } catch (_) {}
      }
      await _assets.save(
        widget.uid,
        widget.kind,
        picked.name,
        data,
        extra: _hasName ? {'person_name': name} : const {},
      );
      if (!mounted) return;
      _reload();
      _say('${_cap(widget.label)} saved to your company profile.');
    });
  }

  Future<void> _readAgain(_Loaded l) => _run(() async {
    if (l.bytes == null) return;
    final name = await _api.readSignatureName(l.bytes!);
    if (name.isEmpty) throw 'No name could be read from this signature. Type it in the box and tap Save name.';
    _name.text = name;
    await _assets.setPersonName(widget.uid, widget.kind, name);
    if (mounted) _reload();
  });

  Future<void> _saveName() => _run(() async {
    await _assets.setPersonName(widget.uid, widget.kind, _name.text.trim());
    if (!mounted) return;
    _reload();
    _say('Name saved.');
  });

  Future<void> _remove() => _run(() async {
    await _assets.delete(widget.uid, widget.kind);
    _name.clear();
    if (!mounted) return;
    _reload();
    _say('${_cap(widget.label)} removed.');
  });

  String _cap(String s) => s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<_Loaded?>(
          future: _loaded,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snap.hasError)
              return Text('Could not load the ${widget.label}.\n${snap.error}');
            final l = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (l == null)
                  Text(
                    'No ${widget.label} uploaded yet.',
                    style: text.bodySmall,
                  )
                else ...[
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${l.info.name} · ${_kb(l.info.size)}',
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (l.bytes != null)
                    Container(
                      height: 110,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Image.memory(l.bytes!, fit: BoxFit.contain),
                    )
                  else
                    Text(
                      'This file was not fully uploaded - upload it again.',
                      style: text.bodySmall,
                    ),
                  if (_hasName) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: widget.nameLabel,
                        helperText: _name.text.trim().isEmpty
                            ? 'No name read yet - type the full name as it should print.'
                            : 'Printed under the signature on the bid documents.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => _readAgain(l),
                            child: const Text('Read from picture'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _saveName,
                            child: const Text('Save name'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: _busy ? _spinner() : const Icon(Icons.upload_file),
                  label: Text(
                    l != null
                        ? 'Replace ${widget.label}'
                        : 'Upload ${widget.label} (PNG, JPG)',
                  ),
                ),
                if (l != null)
                  TextButton.icon(
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
