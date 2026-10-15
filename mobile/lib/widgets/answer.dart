/// One answer: its body with **bold** and {n} citation chips, the sources list and follow-up questions.
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'ui.dart';

const kindInfo = {
  'One source': 'info', 'Multiple sources': 'info', 'Revised policy': 'info',
  'Historical record': 'warn', 'Conflicting instructions': 'bad', 'Insufficient evidence': 'mute2',
  'Needs clarification': 'mute2', 'Outside your scope': 'warn',
};

final _partRe = RegExp(r'(\*\*[^*]+\*\*|\{\d+\})');

/// Text with **bold** and {n} citation markers as tappable numbers.
List<InlineSpan> inlineSpans(BuildContext context, dynamic text, void Function(int) onCite) {
  final s = txt(text);
  final out = <InlineSpan>[];
  var last = 0;
  for (final m in _partRe.allMatches(s)) {
    if (m.start > last) out.add(TextSpan(text: s.substring(last, m.start)));
    final part = m.group(0)!;
    if (part.startsWith('**')) {
      out.add(TextSpan(text: part.substring(2, part.length - 2), style: const TextStyle(fontWeight: FontWeight.w700)));
    } else {
      final n = int.parse(part.substring(1, part.length - 1));
      out.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: CiteChip(n: n, onTap: () => onCite(n - 1))));
    }
    last = m.end;
  }
  if (last < s.length) out.add(TextSpan(text: s.substring(last)));
  return out;
}

class CiteChip extends StatelessWidget {
  const CiteChip({super.key, required this.n, required this.onTap});
  final int n;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minWidth: 20),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: context.pal.accentSoft, borderRadius: BorderRadius.circular(6)),
            child: Text('$n', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.pal.accent)),
          ),
        ),
      );
}

class AnswerView extends StatelessWidget {
  const AnswerView({super.key, required this.answer, required this.onCite, required this.onAsk});
  final Answer answer;
  final void Function(int) onCite;
  final void Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final base = TextStyle(fontSize: 14.5, height: 1.5, color: p.fg);
    final banner = answer.banner;
    final kids = <Widget>[];
    if (banner != null) {
      final kind = str(banner['kind']);
      kids.add(Note(kind: kind == 'conflict' ? 'bad' : kind == 'insuff' ? 'mute2' : 'warn', text: txt(banner['text'])));
    }
    for (final part in answer.body) {
      if (part['p'] != null) {
        kids.add(Text.rich(TextSpan(children: inlineSpans(context, part['p'], onCite)), style: base));
      } else if (part['sub'] != null) {
        kids.add(Text.rich(TextSpan(children: inlineSpans(context, part['sub'], onCite)),
            style: base.copyWith(fontWeight: FontWeight.w600, fontSize: 14)));
      } else if (part['ul'] is List) {
        kids.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final x in part['ul'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('•  ', style: base),
                Expanded(child: Text.rich(TextSpan(children: inlineSpans(context, x, onCite)), style: base)),
              ]),
            ),
        ]));
      } else if (part['opts'] is List) {
        kids.add(Wrap(spacing: 6, runSpacing: 6, children: [
          for (final q in (part['opts'] as List).map(txt)) ActionChip(label: Text(q), onPressed: () => onAsk(q)),
        ]));
      } else if (part['table'] is Map) {
        final t = part['table'] as Map;
        final head = (t['head'] as List? ?? const []).map(txt).toList();
        final rows = (t['rows'] as List? ?? const []).map((r) => (r as List).toList()).toList();
        kids.add(SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: p.line, borderRadius: BorderRadius.circular(8)),
            children: [
              TableRow(decoration: BoxDecoration(color: p.surface2), children: [
                for (final h in head) Padding(padding: const EdgeInsets.all(8), child: Text(h, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ]),
              for (final r in rows)
                TableRow(children: [
                  for (var i = 0; i < head.length; i++)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text.rich(TextSpan(children: inlineSpans(context, i < r.length ? r[i] : '', onCite)), style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                ]),
            ],
          ),
        ));
      }
    }
    final cites = answer.cites;
    if (cites.isNotEmpty) {
      kids.add(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text('SOURCES', style: TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w600, color: p.fg3)),
        ),
        for (var i = 0; i < cites.length; i++) _SourceRow(i: i, c: cites[i], onTap: () => onCite(i)),
      ]));
    }
    final follow = answer.follow;
    if (follow.isNotEmpty) {
      kids.add(Wrap(spacing: 6, runSpacing: 6, children: [
        for (final q in follow)
          ActionChip(
            label: Text(q, style: const TextStyle(fontSize: 13)),
            avatar: Icon(Icons.subdirectory_arrow_right, size: 15, color: p.accent),
            onPressed: () => onAsk(q),
          ),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap(kids, 10));
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.i, required this.c, required this.onTap});
  final int i;
  final Cite c;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final d = store.getDoc(c.doc);
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: p.line), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          CiteChip(n: i + 1, onTap: onTap),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: d?.title ?? c.doc, style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: ' · ${d?.ref ?? ''} · page ${c.page}', style: TextStyle(color: p.fg3)),
              ]),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (d != null && d.status != 'Active') Padding(padding: const EdgeInsets.only(left: 6), child: Pill(d.status)),
        ]),
      ),
    );
  }
}

/// Plain-text version of an answer, for copy and export.
String answerText(Answer a) {
  String clean(String x) => x.replaceAll('**', '').replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) => '[${m[1]}]');
  final lines = <String>[];
  if (a.banner != null) lines.add('Note: ${txt(a.banner!['text'])}');
  for (final p in a.body) {
    if (p['p'] != null) lines.add(clean(txt(p['p'])));
    if (p['sub'] != null) lines.add(clean(txt(p['sub'])));
    if (p['ul'] is List) lines.addAll((p['ul'] as List).map((x) => '• ${clean(txt(x))}'));
    if (p['opts'] is List) lines.addAll((p['opts'] as List).map((x) => '• ${txt(x)}'));
    if (p['table'] is Map) {
      final t = p['table'] as Map;
      lines.add((t['head'] as List? ?? const []).map(txt).join(' | '));
      for (final r in t['rows'] as List? ?? const []) {
        lines.add((r as List).map((c) => clean(txt(c))).join(' | '));
      }
    }
  }
  return lines.join('\n');
}

bool hindiText(String s) => isHindi(s);
