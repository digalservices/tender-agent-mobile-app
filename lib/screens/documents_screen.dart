import 'dart:io' show Directory, File;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/document_service.dart';

/// The company's saved documents - the same files the web app shows under Documents.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, required this.user, this.inline = false});
  final User user;

  /// True when shown inside another scrolling page (Settings) instead of as a page of its own.
  final bool inline;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _service = DocumentService();
  late final Stream<List<CompanyDocument>> _docs = _service.watch(
    widget.user.uid,
  );
  final Set<String> _busy = {}; // ids being downloaded or deleted
  String? _uploading; // "file 2 of 3: name.pdf"

  void _toast(String message, {bool error = false}) {
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

  Future<void> _add() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedExtensions,
      );
    } catch (e) {
      _toast('Could not open the file picker: $e', error: true);
      return;
    }
    if (picked.isEmpty) return;

    final problems = <String>[];
    var done = 0;
    for (var i = 0; i < picked.length; i++) {
      final file = picked[i];
      setState(
        () =>
            _uploading = 'Uploading ${i + 1} of ${picked.length}: ${file.name}',
      );
      try {
        await _service.upload(
          widget.user.uid,
          file.name,
          await file.readAsBytes(),
        );
        done++;
      } catch (e) {
        problems.add('$e');
      }
    }
    if (!mounted) return;
    setState(() => _uploading = null);
    if (problems.isEmpty) {
      _toast('Saved $done document${done == 1 ? '' : 's'}.');
    } else {
      _toast(problems.join('\n'), error: true);
    }
  }

  Future<void> _open(CompanyDocument d) async {
    if (kIsWeb) {
      _toast(
        'Opening files works in the phone app (Android / iOS).',
        error: true,
      );
      return;
    }
    setState(() => _busy.add(d.id));
    try {
      final bytes = await _service.read(widget.user.uid, d.id);
      final dir =
          Directory.systemTemp; // the app's own cache folder on Android and iOS
      final path =
          '${dir.path}/${d.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}';
      await File(path).writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done)
        _toast(
          'No app found to open ${d.name}. (${result.message})',
          error: true,
        );
    } catch (e) {
      _toast('Could not open ${d.name}: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(d.id));
    }
  }

  Future<void> _delete(CompanyDocument d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          '${d.name} will be removed from your company documents. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(d.id));
    try {
      await _service.delete(widget.user.uid, d.id);
      _toast('Deleted ${d.name}.');
    } catch (e) {
      _toast('Could not delete ${d.name}: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(d.id));
    }
  }

  String _date(DateTime? t) {
    if (t == null) return '';
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
    return ' · uploaded ${t.day.toString().padLeft(2, '0')} ${months[t.month - 1]} ${t.year}';
  }

  Widget _wrap(Widget list) => widget.inline ? list : Expanded(child: list);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.inline ? 0 : 16,
            widget.inline ? 0 : 16,
            widget.inline ? 0 : 16,
            8,
          ),
          child: FilledButton.icon(
            onPressed: _uploading == null ? _add : null,
            icon: const Icon(Icons.upload_file),
            label: const Text('Add documents (PDF, DOCX, TXT, MD)'),
          ),
        ),
        if (_uploading != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.inline ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text(_uploading!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        _wrap(
          StreamBuilder<List<CompanyDocument>>(
            stream: _docs,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load your documents.\n${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snap.data!;
              if (docs.isEmpty) {
                return const Center(child: Text('No documents saved yet.'));
              }
              return ListView.separated(
                shrinkWrap: widget.inline,
                physics: widget.inline
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: widget.inline
                    ? const EdgeInsets.only(top: 8)
                    : const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final busy = _busy.contains(d.id);
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(
                        d.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${formatSize(d.size)}${_date(d.uploadedAt)}',
                      ),
                      onTap: busy ? null : () => _open(d),
                      trailing: busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(d),
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
