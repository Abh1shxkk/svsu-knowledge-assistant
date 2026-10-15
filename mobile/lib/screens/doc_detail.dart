import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/modals.dart';
import '../widgets/original.dart';
import '../widgets/paper.dart';
import '../widgets/text_review.dart';
import '../widgets/ui.dart';
import '../widgets/viewer.dart';
import 'doc_modals.dart';

class DocDetailScreen extends StatefulWidget {
  const DocDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<DocDetailScreen> createState() => _DocDetailScreenState();
}

class _DocDetailScreenState extends State<DocDetailScreen> with StoreListener {
  String tab = 'overview';

  @override
  Widget build(BuildContext context) {
    final d = store.getDoc(widget.id);
    if (d == null) return Scaffold(appBar: AppBar(), body: const EmptyBox('Document not found.'));
    final full = store.fullDoc(d.id);
    final approver = store.canApprove;
    final editable = store.canEditDoc(d);
    final dls = store.deadlines.where((x) => x.doc == d.id).toList();
    final bms = store.bmPassages.where((x) => x.s('doc') == d.id).toList();
    final tabs = <(String, String, int?)>[
      ('overview', 'Overview', null), ('preview', 'Preview', null), ('text', 'Extracted text', null), ('approvals', 'Approval history', null),
      ('versions', 'Versions', d.versions.length),
      ('related', 'Related', d.related.length + (d.revisionOf != null ? 1 : 0) + (d.supersededBy != null ? 1 : 0)),
      ('access', 'Access', null), ('deadlines', 'Actions & deadlines', dls.length), ('bookmarks', 'Bookmarks', bms.length),
    ];

    Future<void> restore() async {
      if (await store.save('documents', d.copy({'status': 'Active'}))) store.toast('Document restored to Active');
    }

    Future<void> resubmit() async {
      final step = {'step': d.status == 'Draft' ? 'Submitted for approval' : 'Resubmitted for approval', 'by': store.myName, 'date': todayIso(), 'kind': ''};
      if (await store.save('documents', d.copy({'status': 'Pending', 'approvals': [...d.approvals.map((a) => a.j), step]}))) {
        store.toast('Submitted for approval');
      }
    }

    /// Administrators only. Withdraw keeps the record; delete removes it and everything that points at it.
    Future<void> deleteDoc() async {
      final ok = await confirm(context,
          title: 'Delete document permanently?',
          body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Delete “${d.title}” (${d.ref})? This removes it from the library and AI answers, along with its text, search data, deadlines, '
                'bookmarks, links and reported conflicts, and takes it out of collections.'),
            const SizedBox(height: 8),
            Text('The audit log keeps a note that it was deleted. To keep the record for history, use Withdraw instead.', style: muted(context)),
          ]),
          action: 'Delete permanently');
      if (!ok) return;
      if (await store.remove('documents', d.id)) {
        store.toast('Document deleted');
        if (context.mounted) context.go('/library');
      }
    }

    final actions = <(String, IconData, VoidCallback, bool)>[ // label, icon, action, danger
      if (store.canUpload && d.status == 'Active') ('Add revision', Icons.refresh, () => showAddRevision(context, d), false),
      if (approver) ('Link a document', Icons.link, () => showLinkDoc(context, d), false),
      if (approver && d.status != 'Withdrawn') ('Withdraw', Icons.block, () => showWithdraw(context, d), true),
      if (approver && d.status == 'Withdrawn') ('Restore', Icons.restore, restore, false),
      if (store.isAdmin) ('Delete', Icons.delete_outline, deleteDoc, true),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(d.ref, style: const TextStyle(fontFamily: monoFont, fontSize: 15)),
        actions: [
          if (editable) IconButton(tooltip: 'Edit details', icon: const Icon(Icons.edit_outlined), onPressed: () => showEditMeta(context, d)),
          if (actions.isNotEmpty)
            PopupMenuButton<int>(
              onSelected: (i) => actions[i].$3(),
              itemBuilder: (_) => [
                for (var i = 0; i < actions.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: ListTile(
                      leading: Icon(actions[i].$2, color: actions[i].$4 ? context.pal.red : null),
                      title: Text(actions[i].$1, style: TextStyle(color: actions[i].$4 ? context.pal.red : null)),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          store.full.remove(d.id);
          await store.load();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 40), children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Pill(d.status), Ft(d.fileType), Text('${d.type} · ${d.dept} · ${fmtD(d.date)}', style: muted(context)),
          ]),
          const SizedBox(height: 8),
          Text(d.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (answerableSt.contains(d.status)) btn('Ask about this', () => context.go('/ask?group=${Uri.encodeComponent('doc:${d.id}')}'), icon: Icons.auto_awesome, primary: true),
            btn('Open viewer', () => openViewer(context, ViewerArgs(doc: d.id)), icon: Icons.visibility_outlined),
            if (d.file != null) DownloadOriginal(doc: d),
            if (!approver && store.isMine(d) && const ['Draft', 'Changes requested'].contains(d.status)) btn('Submit for approval', resubmit, primary: true),
          ]),
          const SizedBox(height: 14),
          TabsBar(tabs: tabs, active: tab, onChange: (k) => setState(() => tab = k)),
          const SizedBox(height: 12),
          switch (tab) {
            'overview' => _Overview(d: d, full: full, approver: approver),
            'preview' => d.previewable
                ? OriginalPages(doc: d)
                : full == null
                    ? const Loading()
                    : Pages(doc: full, onBookmark: (page, block) => _bookmarkPassage(full, page, block)),
            'text' => _TextTab(d: d, full: full, editable: editable),
            'approvals' => Section(padded: true, children: [_Timeline(steps: d.approvals)]),
            'versions' => Section(
                title: 'Version history',
                trailing: store.canUpload && d.status == 'Active' ? btn('Add revision', () => showAddRevision(context, d), icon: Icons.refresh) : null,
                children: [
                  for (final (i, v) in d.versions.reversed.indexed)
                    Row2(
                      lead: Text('v${v['v']}', style: const TextStyle(fontFamily: monoFont, fontSize: 13)),
                      title: str(v['note']),
                      meta: '${fmtD(str(v['date']))} · ${str(v['by'])}',
                      trail: i == 0 ? const Pill('Current', kind: 'info') : null,
                    ),
                ],
              ),
            'related' => _Related(d: d, approver: approver),
            'access' => _Access(d: d, editable: editable),
            'deadlines' => Section(
                title: 'Actions and deadlines from this document',
                children: [
                  if (store.canUpload)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        btn('Add deadline', () => showDeadline(context, docId: d.id), icon: Icons.add),
                        btn('Find deadlines', () => _findDeadlines(d), icon: Icons.auto_awesome),
                      ]),
                    ),
                  if (dls.isEmpty) EmptyBox('No deadlines yet.${store.canUpload ? ' Use “Find deadlines” or add one.' : ''}'),
                  for (final x in dls)
                    Row2(
                      lead: DateBox(x.date),
                      title: x.title,
                      meta: '${x.owner} · ${x.aud}',
                      trail: Due(x.date, done: x.done),
                      onTap: () => openViewer(context, ViewerArgs(doc: x.doc, page: x.page, block: x.block, quote: x.quote)),
                    ),
                ],
              ),
            'bookmarks' => Section(
                title: 'Bookmarked passages',
                children: bms.isEmpty
                    ? [const EmptyBox('No bookmarks yet. Open the Preview tab and long-press a paragraph to bookmark it.')]
                    : [
                        for (final b in bms)
                          Row2(
                            lead: const Avatar(icon: Icons.bookmark_border, size: 28),
                            title: '“${b.s('quote')}”',
                            titleStyle: const TextStyle(fontFamily: docFont, fontSize: 14),
                            wrapTitle: true,
                            meta: 'Page ${b.j['page']}${b.s('note').isNotEmpty ? ' · ${b.s('note')}' : ''}',
                            trail: const Icon(Icons.chevron_right),
                            onTap: () => openViewer(context, ViewerArgs(doc: d.id, page: (b.j['page'] as num?)?.toInt() ?? 1, block: b.s('block'), quote: b.s('quote'))),
                          ),
                      ],
              ),
            _ => const SizedBox.shrink(),
          },
        ]),
      ),
    );
  }

  Future<void> _bookmarkPassage(Doc doc, int page, String block) async {
    final b = doc.pages[page - 1].where((x) => x.id == block).firstOrNull;
    final quote = b == null || b.isRow ? '' : b.plain.replaceFirst(RegExp(r'^\d+\.\s*'), '');
    if (await store.save('bm_passages', {'id': nid('bp'), 'doc': doc.id, 'page': page, 'block': block, 'quote': quote, 'note': '', 'when': todayIso()})) {
      store.toast('Passage bookmarked');
    }
  }

  Future<void> _findDeadlines(Doc doc) async {
    store.toast('Reading the document for dates…');
    try {
      final found = await api.deadlines(doc.id);
      var added = 0;
      for (final dl in found) {
        if (!store.deadlines.any((x) => x.doc == doc.id && x.title == dl['title'] && x.date == dl['date']) &&
            await store.save('deadlines', {...dl, 'id': nid('dl'), 'dept': doc.dept})) {
          added++;
        }
      }
      store.toast(added > 0 ? '$added deadline(s) added' : 'No new deadlines found');
    } catch (e) {
      store.toast('$e');
    }
  }
}

class _TextTab extends StatelessWidget {
  const _TextTab({required this.d, required this.full, required this.editable});
  final Doc d;
  final Doc? full;
  final bool editable;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          d.fileType == 'scan'
              ? 'Text from the OCR layer (${d.ocr ?? '?'}% confidence). Check against the scan before relying on figures.'
              : 'Text extracted from the file. This is what the assistant searches.',
          style: muted(context),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          btn('Copy text', full == null ? null : () {
            Clipboard.setData(ClipboardData(text: docText(full!)));
            store.toast('Copied');
          }, icon: Icons.copy),
          if (editable && full != null && d.unsure.isNotEmpty)
            btn('Mark as checked', () async {
              if (await store.save('documents', d.copy({'pages': full!.j['pages'], 'unsure': <String>[]}))) store.toast('Marked as checked');
            }, icon: Icons.check),
        ]),
        const SizedBox(height: 10),
        if (full?.hasPages ?? false)
          TextReview(
            pages: full!.pages,
            unsure: d.unsure,
            editable: editable,
            onSave: (pages) async {
              final versions = [...d.versions, {'v': d.nextVersion, 'date': todayIso(), 'by': store.myName, 'note': 'Text corrected'}];
              if (await store.save('documents', d.copy({'pages': pagesJson(pages), 'unsure': <String>[], 'versions': versions}))) {
                store.toast('Text saved. The assistant now searches the corrected text.');
              }
            },
          )
        else
          const Loading(),
      ]);
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});
  final List<ApprovalStep> steps;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (steps.isEmpty) return Text('No steps recorded.', style: muted(context));
    return Column(children: [
      for (final (i, a) in steps.indexed)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Column(children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(shape: BoxShape.circle, color: switch (a.kind) { 'ok' => p.green, 'warn' => p.amber, 'bad' => p.red, _ => p.accent }),
              ),
              if (i < steps.length - 1) Expanded(child: Container(width: 2, color: p.line)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.step, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${fmtD(a.date)} · ${a.by}', style: xs(context)),
                  if (a.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(a.note, style: sm(context))),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.d, required this.full, required this.approver});
  final Doc d;
  final Doc? full;
  final bool approver;
  @override
  Widget build(BuildContext context) {
    final sup = d.supersededBy != null ? store.getDoc(d.supersededBy) : null;
    final lastNote = d.approvals.reversed.where((a) => a.note.isNotEmpty).firstOrNull?.note;
    Future<void> removeTag(String t) async {
      if (d.tags.length == 1) {
        store.toast('A document needs at least one subject tag');
        return;
      }
      if (await store.save('documents', d.copy({'tags': d.tags.where((x) => x != t).toList()}))) store.toast('Removed tag “$t”');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
      if (d.status == 'Superseded' && sup != null) Note(kind: 'warn', title: 'Superseded.', text: 'Replaced by ${sup.ref}. Kept for historical questions.'),
      if (d.status == 'Withdrawn') Note(kind: 'bad', title: 'Withdrawn.', text: d.withdrawReason),
      if (d.status == 'Pending') const Note(kind: 'warn', title: 'Waiting for approval.', text: 'Not used in AI answers until it is approved.'),
      if (d.status == 'Draft') const Note(kind: 'info', title: 'Draft.', text: "Only you and approvers can see it. Submit it for approval when it's ready."),
      if (d.status == 'Changes requested') Note(kind: 'warn', title: 'Changes requested.', text: lastNote ?? 'Edit the details, then submit it again.'),
      if (d.status == 'Rejected') Note(kind: 'bad', title: 'Rejected.', text: lastNote),
      Section(title: 'Details', padded: true, children: [
        KV([
          ('Reference number', kvText(d.ref, isMono: true)),
          ('Document type', kvText(d.type)),
          ('Issuing authority', kvText(d.authority)),
          ('Issuing department', kvText(d.dept)),
          ('Institution', kvText(d.institution)),
          ('Document date', kvText(fmtD(d.date))),
          ('Effective date', kvText(fmtD(d.effective))),
          ('Expiry date', kvText(d.expiry.isNotEmpty ? fmtD(d.expiry) : 'Not applicable')),
          ('Applicable audience', kvText(d.audience.join(', '))),
          (
            'Subject tags',
            Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final t in d.tags) TagChip(t, onRemove: approver ? () => removeTag(t) : null),
              if (approver)
                InkWell(
                  onTap: () => showAddTag(context, d),
                  child: Padding(padding: const EdgeInsets.all(4), child: Text('+ Add tag', style: TextStyle(color: context.pal.accent, fontSize: 13))),
                ),
            ]),
          ),
          ('Visibility', kvText(d.visibility)),
          ('Uploaded', kvText('${fmtD(d.uploadedOn)} by ${d.uploadedBy}')),
          ('Description', kvText(d.description.isEmpty ? '—' : d.description)),
        ]),
      ]),
      Section(title: 'First page', children: [
        Container(
          color: context.pal.surface2,
          constraints: const BoxConstraints(maxHeight: 380),
          padding: const EdgeInsets.all(12),
          child: ClipRect(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: d.previewable ? OriginalFile(doc: d) : (full == null ? const Loading() : Pages(doc: full!, only: 0, zoom: .8)),
            ),
          ),
        ),
      ]),
    ], 12));
  }
}

class _Related extends StatelessWidget {
  const _Related({required this.d, required this.approver});
  final Doc d;
  final bool approver;
  @override
  Widget build(BuildContext context) {
    final rel = <(String, String)>[
      if (d.revisionOf != null) (d.revisionOf!, 'Revision of (replaces)'),
      if (d.supersededBy != null) (d.supersededBy!, 'Superseded by'),
      for (final r in d.related) (r, 'Related'),
    ];
    final rows = [
      for (final (rid, label) in rel)
        if (store.getDoc(rid) case final r?)
          Row2(
            title: r.title,
            meta: '$label · ${r.ref}',
            onTap: () => context.push('/library/${r.id}'),
            trail: Row(mainAxisSize: MainAxisSize.min, children: [
              Pill(r.status),
              if (approver && label == 'Related')
                IconButton(
                  tooltip: 'Remove link',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    if (await setLink(d, r, false)) store.toast('Link removed');
                  },
                ),
            ]),
          ),
    ];
    return Section(
      title: 'Related documents',
      trailing: approver ? btn('Link', () => showLinkDoc(context, d), icon: Icons.link) : null,
      children: rows.isEmpty ? [const EmptyBox('No linked documents yet.')] : rows,
    );
  }
}

class _Access extends StatelessWidget {
  const _Access({required this.d, required this.editable});
  final Doc d;
  final bool editable;
  @override
  Widget build(BuildContext context) {
    final l = store.lists;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
      Section(title: 'Who can see this document', padded: true, children: [
        RadioCards(
          options: l.vis,
          value: d.visibility,
          enabled: editable,
          describe: l.visDesc,
          onChanged: (v) async {
            if (await store.save('documents', d.copy({'visibility': v}))) store.toast('Access changed to $v');
          },
        ),
      ]),
      Section(title: 'How access works', padded: true, children: [
        Text.rich(const TextSpan(children: [
          TextSpan(text: 'Access is separate from subject tags. ', style: TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: 'Tags describe what a document is about. Access decides who may open it and who the AI can answer from.'),
        ]), style: sm(context)),
        Text('The assistant only reads documents the person asking is allowed to open.', style: sm(context)),
        Text('Current audience: ${d.audience.join(', ')}. Audience is informational and does not grant access.', style: muted(context)),
      ]),
    ], 12));
  }
}
