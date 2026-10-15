import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/paper.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';

const _checklist = ['Content matches the signed original', 'Tags and audience are correct', 'Access level is appropriate', 'Older versions are linked'];

class ReviewScreen extends StoreScreen {
  const ReviewScreen({super.key});

  @override
  Widget buildScreen(BuildContext context) {
    final queue = store.documents.where((d) => const ['Pending', 'Changes requested'].contains(d.status)).toList();
    final decided = [
      for (final x in store.documents)
        for (final a in x.approvals)
          if (RegExp('Approved|Rejected|Changes|Withdrawn').hasMatch(a.step)) (a: a, doc: x),
    ]..sort((a, b) => b.a.date.compareTo(a.a.date));
    return AppScaffold(
      route: '/review',
      title: 'Review & Approvals',
      body: RefreshIndicator(
        onRefresh: store.load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: gap([
          Row(children: [
            Expanded(child: Text('Documents are only used in the library and AI answers after an approver publishes them.', style: muted(context))),
            const SizedBox(width: 8),
            Pill('${queue.length} waiting', kind: 'warn'),
          ]),
          if (queue.isEmpty)
            Card(
              child: EmptyBox('All caught up. No documents are waiting for review.', action: btn('Upload a document', () => context.go('/upload'))),
            )
          else
            Section(children: [
              for (final x in queue)
                Row2(
                  lead: Ft(x.fileType),
                  title: x.title,
                  meta: '${x.dept} · submitted ${fmtD(x.approvals.firstOrNull?.date)} by ${x.uploadedBy}',
                  trail: Pill(x.status),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewDocScreen(id: x.id))),
                ),
            ]),
          Section(
            title: 'Recent decisions',
            children: decided.isEmpty
                ? [const EmptyBox('No decisions yet.')]
                : [
                    for (final r in decided.take(8))
                      Row2(
                        title: r.doc.title,
                        meta: '${r.a.by} · ${fmtD(r.a.date)}',
                        trail: Pill(r.a.step, kind: r.a.kind.isEmpty ? 'mute' : r.a.kind),
                        onTap: () => context.push('/library/${r.doc.id}'),
                      ),
                  ],
          ),
        ], 14)),
      ),
    );
  }
}

/// One document under review: its text, details, automatic checks, the checklist and the decision.
class ReviewDocScreen extends StatefulWidget {
  const ReviewDocScreen({super.key, required this.id});
  final String id;
  @override
  State<ReviewDocScreen> createState() => _ReviewDocScreenState();
}

class _ReviewDocScreenState extends State<ReviewDocScreen> with StoreListener {
  final comment = TextEditingController();
  final ticked = <int>{};
  List<List<String>>? checks;
  bool showText = false;

  @override
  void initState() {
    super.initState();
    api.checks(widget.id).then((l) {
      if (mounted) setState(() => checks = l);
    }, onError: (_) {
      if (mounted) setState(() => checks = [['warn', 'Automatic checks could not run']]);
    });
  }

  Future<void> decide(String v) async {
    final d = store.getDoc(widget.id);
    if (d == null) return;
    if (v != 'approve' && comment.text.trim().isEmpty) {
      store.toast('Add a comment for the uploader');
      return;
    }
    if (v == 'approve' && ticked.length < _checklist.length) {
      store.toast('Tick every item on the reviewer checklist first');
      return;
    }
    final (status, step, kind, msg) = switch (v) {
      'approve' => ('Active', 'Approved and published', 'ok', 'Approved and published to the library'),
      'changes' => ('Changes requested', 'Changes requested', 'warn', 'Sent back to ${d.uploadedBy}'),
      _ => ('Rejected', 'Rejected', 'bad', 'Document rejected'),
    };
    final ok = await store.save('documents', d.copy({
      'status': status,
      'approvals': [...d.approvals.map((a) => a.j), {'step': step, 'by': store.myName, 'date': todayIso(), 'kind': kind, 'note': comment.text}],
    }));
    if (!ok) return;
    if (v == 'approve') {
      // a published revision replaces the older document
      final old = d.revisionOf != null ? store.getDoc(d.revisionOf) : null;
      if (old != null && old.status == 'Active') await store.save('documents', old.copy({'status': 'Superseded', 'supersededBy': d.id}));
      // links chosen at upload become two-way
      for (final rid in d.related) {
        final o = store.getDoc(rid);
        if (o != null && !o.related.contains(d.id)) await store.save('documents', o.copy({'related': [...o.related, d.id]}));
      }
    }
    store.toast(msg);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = store.getDoc(widget.id);
    if (d == null) return Scaffold(appBar: AppBar(), body: const EmptyBox('This document is no longer waiting for review.'));
    final full = store.fullDoc(d.id);
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(
        title: Text(d.ref, style: const TextStyle(fontFamily: monoFont, fontSize: 15)),
        actions: [TextButton(onPressed: () => context.push('/library/${d.id}'), child: const Text('Full record'))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 40), children: gap([
        Text(d.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        Section(padded: true, children: [
          KV([
            ('Type', kvText(d.type)), ('Authority', kvText(d.authority)), ('Effective', kvText(fmtD(d.effective))),
            ('Audience', kvText(d.audience.join(', '))), ('Tags', kvText(d.tags.join(', '))), ('Visibility', kvText(d.visibility)),
            if (d.revisionOf != null) ('Revises', kvText(store.getDoc(d.revisionOf)?.ref ?? '—')),
          ], labelWidth: 100),
        ]),
        Section(
          title: 'Document text',
          trailing: TextButton(onPressed: () => setState(() => showText = !showText), child: Text(showText ? 'Hide' : 'Show')),
          children: [
            if (showText)
              Container(
                color: p.surface2,
                padding: const EdgeInsets.all(12),
                child: full == null ? const Loading() : Pages(doc: full),
              ),
          ],
        ),
        Section(title: 'Automatic checks', padded: true, children: [
          if (checks == null)
            const Row(children: [Spinner(size: 15), SizedBox(width: 8), Text('Checking…')])
          else
            for (final c in checks!)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(c.first == 'ok' ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 18, color: c.first == 'ok' ? p.green : p.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(c.length > 1 ? c[1] : '', style: sm(context))),
              ]),
        ]),
        Section(title: 'Reviewer checklist', children: [
          for (final (i, t) in _checklist.indexed)
            CheckboxListTile(
              value: ticked.contains(i),
              onChanged: (_) => setState(() => ticked.contains(i) ? ticked.remove(i) : ticked.add(i)),
              title: Text(t, style: const TextStyle(fontSize: 14)),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
        ]),
        Field(label: 'Comment to uploader', child: Input(controller: comment, maxLines: 3, hint: 'Required when requesting changes or rejecting')),
        btn('Approve & publish', () => decide('approve'), icon: Icons.check, primary: true, small: false),
        Row(children: [
          Expanded(child: btn('Request changes', () => decide('changes'), small: false)),
          const SizedBox(width: 8),
          Expanded(child: btn('Reject', () => decide('reject'), danger: true, small: false)),
        ]),
      ], 12)),
    );
  }
}
