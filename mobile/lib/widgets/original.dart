/// The original uploaded file: PDF pages drawn as pictures by the server, photos as they are, and
/// Word or Excel files opened in another app. Files need the sign-in token, so they are fetched here.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'ui.dart';

final _cache = <String, Future<Uint8List>>{};

Future<Uint8List> _load(String key, Future<Uint8List> Function() fetch) {
  final f = _cache[key] ??= fetch();
  f.catchError((_) {
    _cache.remove(key);
    return Uint8List(0);
  });
  return f;
}

class OriginalFile extends StatelessWidget {
  const OriginalFile({super.key, required this.doc, this.page = 1});
  final Doc doc;
  final int page;

  @override
  Widget build(BuildContext context) {
    final fileKey = '${doc.file?['key']}';
    if (doc.isPdf) {
      return _Picture(k: '${doc.id}:$fileKey:$page', fetch: () => api.originalPage(doc.id, page));
    }
    if (doc.isImage) return _Picture(k: '${doc.id}:$fileKey', fetch: () => api.originalFile(doc.id));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Text("Word and Excel files can't be shown here. Open the original in another app, or use the Text view.",
            textAlign: TextAlign.center, style: muted(context)),
        const SizedBox(height: 12),
        DownloadOriginal(doc: doc),
      ]),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.k, required this.fetch});
  final String k;
  final Future<Uint8List> Function() fetch;
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _load(k, fetch),
        builder: (context, snap) {
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}', style: muted(context)));
          if (!snap.hasData) return const SizedBox(height: 320, child: Center(child: Spinner(size: 24)));
          if (snap.data!.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Text("Couldn't load this page.", style: muted(context)));
          return Container(
            decoration: BoxDecoration(border: Border.all(color: context.pal.line), color: Colors.white),
            child: Image.memory(snap.data!, fit: BoxFit.fitWidth, width: double.infinity, gaplessPlayback: true),
          );
        },
      );
}

/// Every page of the original, one under the other.
class OriginalPages extends StatelessWidget {
  const OriginalPages({super.key, required this.doc});
  final Doc doc;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 1; i <= doc.originalPages; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: OriginalFile(doc: doc, page: i)),
      ]);
}

/// Writes bytes to a file the phone can open or share.
Future<File> _write(Uint8List bytes, String name) async {
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
  final f = File('${dir.path}/$safe');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

/// Opens a file in another app (PDF reader, Word…); offers to share it if none can open it.
Future<void> openBytes(Uint8List bytes, String name, {String? mime}) async {
  final f = await _write(bytes, name);
  final r = await OpenFilex.open(f.path, type: mime);
  if (r.type != ResultType.done) await shareFile(f.path, name, mime: mime);
}

Future<void> shareFile(String path, String name, {String? mime}) =>
    SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: mime, name: name)], subject: name));

Future<void> shareBytes(Uint8List bytes, String name, {String? mime}) async {
  final f = await _write(bytes, name);
  await shareFile(f.path, name, mime: mime);
}

Future<void> shareText(String text, {String? subject}) => SharePlus.instance.share(ShareParams(text: text, subject: subject));

class DownloadOriginal extends StatefulWidget {
  const DownloadOriginal({super.key, required this.doc});
  final Doc doc;
  @override
  State<DownloadOriginal> createState() => _DownloadOriginalState();
}

class _DownloadOriginalState extends State<DownloadOriginal> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    if (d.file == null) return const SizedBox.shrink();
    return btn('Open original', busy ? null : () async {
      setState(() => busy = true);
      try {
        await openBytes(await api.originalFile(d.id), '${d.file?['name'] ?? 'document'}', mime: d.mime);
      } catch (e) {
        store.toast('$e');
      }
      if (mounted) setState(() => busy = false);
    }, icon: Icons.open_in_new, busy: busy);
  }
}
