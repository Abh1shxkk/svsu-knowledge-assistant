/// A document's text drawn as pages of paper, with the cited passage highlighted.
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../util.dart';

class Highlight {
  const Highlight(this.page, this.block, [this.quote = '']);
  final int page;
  final String block;
  final String quote;
}

class Pages extends StatelessWidget {
  const Pages({super.key, required this.doc, this.hl, this.onBookmark, this.zoom = 1, this.only, this.hlKey, this.pageKeys});
  final Doc doc;
  final Highlight? hl;
  /// Long-press a paragraph to bookmark it.
  final void Function(int page, String block)? onBookmark;
  final double zoom;
  final int? only;
  /// Attached to the highlighted paragraph, so the viewer can scroll to it.
  final GlobalKey? hlKey;
  /// One key per page, so the viewer can jump to a page.
  final List<GlobalKey>? pageKeys;

  @override
  Widget build(BuildContext context) {
    if (!doc.hasPages) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final pages = doc.pages;
    if (pages.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: Text('No text was read from this document.', style: TextStyle(color: context.pal.fg3)));
    return Column(children: [
      for (var pi = 0; pi < pages.length; pi++)
        if (only == null || only == pi)
          Container(key: pageKeys != null && pi < pageKeys!.length ? pageKeys![pi] : null, child: _Sheet(doc: doc, page: pages[pi], pi: pi, total: pages.length, parent: this)),
    ]);
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.doc, required this.page, required this.pi, required this.total, required this.parent});
  final Doc doc;
  final List<TextBlock> page;
  final int pi;
  final int total;
  final Pages parent;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final z = parent.zoom;
    final scan = doc.fileType == 'scan';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.fromLTRB(18 * z, 18 * z, 18 * z, 12 * z),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.paperLine),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (scan)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: p.amberSoft, borderRadius: BorderRadius.circular(99)),
              child: Text('Scanned · OCR text ${doc.ocr ?? '?'}% confidence', style: TextStyle(fontSize: 10.5, color: p.amber)),
            ),
          ),
        if (pi == 0 && doc.sample) _Letterhead(doc: doc, zoom: z),
        if (doc.fileType == 'xlsx') _SheetTable(page: page, hl: parent.hl, zoom: z, hlKey: parent.hlKey) else
          for (final b in page) _BlockP(b: b, page: pi + 1, parent: parent),
        if (doc.sample && pi == total - 1 && doc.fileType != 'xlsx')
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('sd/-', style: TextStyle(fontFamily: docFont, fontStyle: FontStyle.italic, fontSize: 16 * z, color: p.paperDim)),
              Text(doc.authority, style: TextStyle(fontFamily: docFont, fontWeight: FontWeight.w600, fontSize: 13 * z, color: p.paperFg)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(children: [
            Expanded(child: Text(doc.ref, style: TextStyle(fontFamily: monoFont, fontSize: 10.5, color: p.paperDim), overflow: TextOverflow.ellipsis)),
            Text('Page ${pi + 1} of $total', style: TextStyle(fontSize: 10.5, color: p.paperDim)),
          ]),
        ),
      ]),
    );
  }
}

class _Letterhead extends StatelessWidget {
  const _Letterhead({required this.doc, required this.zoom});
  final Doc doc;
  final double zoom;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final hi = doc.lang == 'hi';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.paperLine, width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Image.asset('assets/logo.png', width: 40 * zoom, height: 40 * zoom),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hi ? 'स्वामी विवेकानन्द सुभारती विश्वविद्यालय' : 'Swami Vivekanand Subharti University',
                  style: TextStyle(fontFamily: docFont, fontWeight: FontWeight.w700, fontSize: 14 * zoom, color: p.paperFg)),
              Text('Subhartipuram, NH-58, Delhi–Haridwar Bypass Road, Meerut (U.P.)', style: TextStyle(fontSize: 9.5 * zoom, color: p.paperDim)),
              Text('${hi ? 'कार्यालय: ' : 'Office of the '}${doc.authority}', style: TextStyle(fontSize: 10.5 * zoom, color: p.paperFg)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('${hi ? 'पत्रांक' : 'No.'} ${doc.ref}', style: TextStyle(fontSize: 11 * zoom, color: p.paperFg))),
          Text('${hi ? 'दिनांक' : 'Date'}: ${fmtD(doc.date)}', style: TextStyle(fontSize: 11 * zoom, color: p.paperFg)),
        ]),
      ]),
    );
  }
}

class _BlockP extends StatelessWidget {
  const _BlockP({required this.b, required this.page, required this.parent});
  final TextBlock b;
  final int page;
  final Pages parent;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final z = parent.zoom;
    final hl = parent.hl;
    final on = hl != null && hl.page == page && hl.block == b.id;
    final text = b.plain;
    final style = TextStyle(
      fontFamily: docFont,
      fontSize: (b.kind == 'subj' ? 14.5 : 14) * z,
      height: 1.55,
      fontWeight: b.kind == 'subj' || b.kind == 'hdr' ? FontWeight.w700 : FontWeight.w400,
      color: p.paperFg,
    );
    final hlStyle = TextStyle(backgroundColor: p.hl);
    InlineSpan span;
    if (on) {
      final q = hl.quote;
      final i = q.isNotEmpty ? text.indexOf(q) : -1;
      span = i >= 0
          ? TextSpan(children: [
              TextSpan(text: text.substring(0, i)),
              TextSpan(text: q, style: hlStyle),
              TextSpan(text: text.substring(i + q.length)),
            ])
          : TextSpan(text: text, style: hlStyle);
    } else {
      span = TextSpan(text: text);
    }
    final body = Container(
      key: on ? parent.hlKey : null,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: on ? const EdgeInsets.only(left: 8) : EdgeInsets.zero,
      decoration: on ? BoxDecoration(border: Border(left: BorderSide(color: p.hlRing, width: 3))) : null,
      child: Text.rich(span, style: style, textAlign: b.kind == 'subj' ? TextAlign.center : TextAlign.start),
    );
    if (parent.onBookmark == null || b.kind == 'subj') return body;
    return GestureDetector(onLongPress: () => parent.onBookmark!(page, b.id), child: body);
  }
}

class _SheetTable extends StatelessWidget {
  const _SheetTable({required this.page, required this.hl, required this.zoom, this.hlKey});
  final List<TextBlock> page;
  final Highlight? hl;
  final double zoom;
  final GlobalKey? hlKey;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cols = page.fold<int>(0, (m, b) => b.cells.length > m ? b.cells.length : m);
    Widget cell(String t, {bool head = false, bool num = false}) => Container(
          constraints: BoxConstraints(minWidth: num ? 30 : 90, maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(t, style: TextStyle(fontSize: 12.5 * zoom, fontWeight: head ? FontWeight.w600 : FontWeight.w400, color: num ? p.paperDim : p.paperFg)),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: p.paperLine),
        children: [
          TableRow(decoration: BoxDecoration(color: p.surface3), children: [
            cell('', num: true),
            for (var i = 0; i < cols; i++) cell(String.fromCharCode(65 + i % 26), head: true),
          ]),
          for (var i = 0; i < page.length; i++)
            TableRow(
              decoration: BoxDecoration(color: hl != null && hl!.block == page[i].id ? p.hl : (page[i].kind == 'hdr' ? p.surface2 : null)),
              children: [
                cell('${i + 1}', num: true),
                for (var c = 0; c < cols; c++) cell(c < page[i].cells.length ? page[i].cells[c] : '', head: page[i].kind == 'hdr'),
              ],
            ),
        ],
      ),
    );
  }
}

/// A document's text as plain text, for copying.
String docText(Doc d) => [
      for (var i = 0; i < d.pages.length; i++)
        '— Page ${i + 1} —\n${d.pages[i].map((b) => b.isRow ? b.cells.join('\t') : b.plain).join('\n\n')}',
    ].join('\n\n');
