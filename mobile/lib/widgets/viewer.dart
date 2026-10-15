/// The document viewer: opens a document at a cited passage, highlighted, and steps through an
/// answer's citations. Shows the original file or the text read from it.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'original.dart';
import 'paper.dart';
import 'ui.dart';

class ViewerArgs {
  const ViewerArgs({required this.doc, this.page = 1, this.block, this.quote, this.cites = const [], this.idx = 0});
  final String doc;
  final int page;
  final String? block;
  final String? quote;
  final List<Cite> cites;
  final int idx;
}

void openViewer(BuildContext context, ViewerArgs a) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ViewerPage(args: a)));

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.args});
  final ViewerArgs args;
  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late ViewerArgs v = widget.args;
  double zoom = 1;
  String view = 'original'; // the real file, or the text read from it
  final hlKey = GlobalKey();
  List<GlobalKey> pageKeys = [];
  final scroll = ScrollController();
  String? _scrolledFor;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    // Citations point at a passage: the text view shows it highlighted.
    if (v.block != null) view = 'text';
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _scrollToHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = hlKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .3, duration: const Duration(milliseconds: 350));
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = store.fullDoc(v.doc);
    final listed = store.getDoc(v.doc);
    final p = context.pal;
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: Text(listed?.title ?? 'Document')),
        body: listed == null ? const EmptyBox("This document isn't available to you.") : const Loading(),
      );
    }
    final showOriginal = view == 'original' && doc.previewable;
    final cites = v.cites;
    final cur = v.idx < cites.length ? cites[v.idx] : null;
    final hl = v.block != null ? Highlight(v.page, v.block!, v.quote ?? '') : null;
    final pageCount = showOriginal ? doc.originalPages : (doc.pages.isEmpty ? 1 : doc.pages.length);
    if (pageKeys.length != doc.pages.length) pageKeys = List.generate(doc.pages.length, (_) => GlobalKey());
    final newer = doc.supersededBy != null ? store.getDoc(doc.supersededBy) : null;
    final target = '${v.doc}|${v.block}|${v.idx}|$showOriginal';
    if (!showOriginal && hl != null && target != _scrolledFor) {
      _scrolledFor = target;
      _scrollToHighlight();
    }

    void step(int d) {
      final i = v.idx + d;
      if (i < 0 || i >= cites.length) return;
      final c = cites[i];
      setState(() => v = ViewerArgs(doc: c.doc, page: c.page, block: c.block, quote: c.quote, cites: cites, idx: i));
    }

    void goPage(int d) {
      final page = (v.page + d).clamp(1, pageCount);
      setState(() => v = ViewerArgs(doc: v.doc, page: page, block: v.block, quote: v.quote, cites: v.cites, idx: v.idx));
      if (!showOriginal && page - 1 < pageKeys.length) {
        final ctx = pageKeys[page - 1].currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      }
    }

    Future<void> bookmark() async {
      if (v.block == null) return;
      final ok = await store.save('bm_passages', {
        'id': nid('bp'), 'doc': v.doc, 'page': v.page, 'block': v.block, 'quote': v.quote ?? '', 'note': '', 'when': todayIso(),
      });
      if (ok) store.toast('Passage bookmarked. Find it in Saved Chats & Bookmarks.');
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${doc.ref} · ${doc.authority} · ${fmtD(doc.date)}', style: xs(context), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (k) {
              if (k == 'details') {
                Navigator.pop(context);
                context.push('/library/${doc.id}');
              } else if (k == 'bm') {
                bookmark();
              }
            },
            itemBuilder: (_) => [
              if (hl != null) const PopupMenuItem(value: 'bm', child: ListTile(leading: Icon(Icons.bookmark_add_outlined), title: Text('Bookmark passage'))),
              const PopupMenuItem(value: 'details', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Document details'))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: p.surface,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Pill(doc.status), const Spacer(), if (doc.file != null) DownloadOriginal(doc: doc)]),
            if (doc.status == 'Superseded' && newer != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Note(kind: 'warn', child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('Superseded by ', style: TextStyle(fontSize: 13)),
                  InkWell(
                    onTap: () => setState(() => v = ViewerArgs(doc: newer.id)),
                    child: Text(newer.ref, style: TextStyle(fontSize: 13, color: p.accent, decoration: TextDecoration.underline)),
                  ),
                  const Text('. Shown because it was cited as a historical or comparison source.', style: TextStyle(fontSize: 13)),
                ])),
              ),
            if (doc.status == 'Withdrawn')
              const Padding(padding: EdgeInsets.only(top: 8), child: Note(kind: 'bad', text: 'This document has been withdrawn.')),
            if (cur != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
                child: Row(children: [
                  IconButton(onPressed: v.idx == 0 ? null : () => step(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous citation'),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Citation ${v.idx + 1} of ${cites.length} · page ${cur.page}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text(cur.quote, maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: docFont, fontStyle: FontStyle.italic, fontSize: 12.5, color: p.fg2)),
                    ]),
                  ),
                  IconButton(onPressed: v.idx >= cites.length - 1 ? null : () => step(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next citation'),
                ]),
              ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                if (doc.previewable) ...[
                  Seg<String>(
                    options: const [('original', 'Original', null), ('text', 'Text', null)],
                    value: showOriginal ? 'original' : 'text',
                    onChanged: (x) => setState(() => view = x),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(onPressed: v.page <= 1 ? null : () => goPage(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous page'),
                Text('Page ${v.page.clamp(1, pageCount)} / $pageCount', style: sm(context)),
                IconButton(onPressed: v.page >= pageCount ? null : () => goPage(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next page'),
                if (!showOriginal) ...[
                  IconButton(onPressed: () => setState(() => zoom = (zoom - .1).clamp(.6, 1.6)), icon: const Icon(Icons.zoom_out), tooltip: 'Zoom out'),
                  Text('${(zoom * 100).round()}%', style: sm(context)),
                  IconButton(onPressed: () => setState(() => zoom = (zoom + .1).clamp(.6, 1.6)), icon: const Icon(Icons.zoom_in), tooltip: 'Zoom in'),
                ],
              ]),
            ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: showOriginal
              ? InteractiveViewer(
                  maxScale: 4,
                  child: ListView(padding: const EdgeInsets.all(12), children: [OriginalFile(doc: doc, page: v.page.clamp(1, pageCount))]),
                )
              : SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.all(12),
                  child: Pages(
                    doc: doc,
                    hl: hl,
                    zoom: zoom,
                    hlKey: hlKey,
                    pageKeys: pageKeys,
                    onBookmark: (page, block) async {
                      final b = doc.pages[page - 1].where((x) => x.id == block).firstOrNull;
                      final quote = b == null || b.isRow ? '' : b.plain.replaceFirst(RegExp(r'^\d+\.\s*'), '');
                      if (await store.save('bm_passages', {
                        'id': nid('bp'), 'doc': doc.id, 'page': page, 'block': block, 'quote': quote, 'note': '', 'when': todayIso(),
                      })) {
                        store.toast('Passage bookmarked');
                      }
                    },
                  ),
                ),
        ),
        Container(
          width: double.infinity,
          color: p.surface,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: SafeArea(
            top: false,
            child: Text(
              showOriginal
                  ? 'The original file as uploaded${hl != null ? ', at page ${v.page}. Use Text to see the cited passage highlighted.' : '.'}'
                  : hl != null
                      ? 'Highlighted text is the exact passage cited. Page ${v.page}. Long-press a paragraph to bookmark it.'
                      : 'The text read from the document${doc.fileType == 'scan' ? ' by OCR — check figures against the original' : ''}. Long-press a paragraph to bookmark it.',
              style: xs(context),
            ),
          ),
        ),
      ]),
    );
  }
}
