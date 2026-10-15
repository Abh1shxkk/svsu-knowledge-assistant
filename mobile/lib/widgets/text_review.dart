/// The text the assistant will search, with words OCR wasn't sure of underlined, and a way to correct it.
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'ui.dart';

/// A document's text as plain text: pages marked "=== Page n ===", paragraphs separated by a blank line.
String pagesToText(List<List<TextBlock>> pages) =>
    [for (var i = 0; i < pages.length; i++) '=== Page ${i + 1} ===\n${pages[i].map((b) => b.plain).join('\n\n')}'].join('\n\n');

/// The reverse: corrected text back into pages of paragraphs (every paragraph gets a fresh id).
List<List<TextBlock>> textToPages(String text) {
  var n = 0;
  return text
      .split(RegExp(r'^=+ *Page \d+ *=+ *$', multiLine: true))
      .map((page) => page
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map((p) => TextBlock({'id': 'b${++n}', 'text': p, 'kind': 'p'}))
          .toList())
      .where((page) => page.isNotEmpty)
      .toList();
}

class TextReview extends StatefulWidget {
  const TextReview({super.key, required this.pages, this.unsure = const [], required this.editable, required this.onSave});
  final List<List<TextBlock>> pages;
  final List<String> unsure;
  final bool editable;
  final Future<void> Function(List<List<TextBlock>> pages) onSave;
  @override
  State<TextReview> createState() => _TextReviewState();
}

class _TextReviewState extends State<TextReview> {
  TextEditingController? draft;

  List<InlineSpan> _marked(String text) {
    if (widget.unsure.isEmpty) return [TextSpan(text: text)];
    final words = [...widget.unsure]..sort((a, b) => b.length - a.length);
    final re = RegExp(words.map(RegExp.escape).join('|'));
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) out.add(TextSpan(text: text.substring(last, m.start)));
      out.add(TextSpan(
        text: m.group(0),
        style: TextStyle(decoration: TextDecoration.underline, decorationColor: context.pal.red, decorationThickness: 2, backgroundColor: context.pal.redSoft),
      ));
      last = m.end;
    }
    if (last < text.length) out.add(TextSpan(text: text.substring(last)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sheet = widget.pages.any((pg) => pg.any((b) => b.isRow)); // spreadsheet rows aren't edited as text
    final text = pagesToText(widget.pages);
    final n = widget.unsure.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (n > 0 && draft == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Note(
            kind: 'warn',
            title: '$n word${n > 1 ? 's were' : ' was'} read with low confidence',
            text: '(underlined in red). Compare them with the original and correct any mistakes, especially dates, numbers and codes.',
          ),
        ),
      if (draft == null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
          child: SelectableText.rich(TextSpan(children: _marked(text)), style: TextStyle(fontFamily: docFont, fontSize: 13.5, height: 1.5, color: p.fg)),
        )
      else ...[
        Text('Keep the “=== Page n ===” lines. A blank line separates paragraphs; keep each table row on its own line.', style: xs(context)),
        const SizedBox(height: 6),
        TextField(
          controller: draft,
          maxLines: null,
          minLines: 12,
          style: const TextStyle(fontFamily: monoFont, fontSize: 13, height: 1.45),
          autocorrect: false,
          enableSuggestions: false,
        ),
      ],
      if (widget.editable && !sheet)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (draft == null)
              btn('Edit text', () => setState(() => draft = TextEditingController(text: text)), icon: Icons.edit_outlined)
            else ...[
              btn('Cancel', () => setState(() => draft = null)),
              const SizedBox(width: 8),
              btn('Save text', () async {
                final next = textToPages(draft!.text);
                if (next.isEmpty) return;
                await widget.onSave(next);
                if (mounted) setState(() => draft = null);
              }, primary: true),
            ],
          ]),
        ),
    ]);
  }
}
