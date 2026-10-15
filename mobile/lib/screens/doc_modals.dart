import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets/pick.dart';
import '../widgets/ui.dart';

void showEditMeta(BuildContext context, Doc d) => showSheet(context, title: 'Edit details', builder: (_) => _EditMeta(doc: d));

class _EditMeta extends StatefulWidget {
  const _EditMeta({required this.doc});
  final Doc doc;
  @override
  State<_EditMeta> createState() => _EditMetaState();
}

class _EditMetaState extends State<_EditMeta> {
  late final Json m = Map.of(widget.doc.j);
  void set(String k, dynamic v) => setState(() => m[k] = v);
  List<String> ls(String k) => strs(m[k]);
  void toggle(String k, String v) => set(k, ls(k).contains(v) ? ls(k).where((x) => x != v).toList() : [...ls(k), v]);

  Future<void> submit() async {
    final eff = str(m['effective']), exp = str(m['expiry']);
    if (exp.isNotEmpty && eff.isNotEmpty && exp.compareTo(eff) < 0) {
      store.toast('Expiry date must be after the effective date');
      return;
    }
    final d = Doc(m);
    final versions = [...d.versions, {'v': d.nextVersion, 'date': todayIso(), 'by': store.myName, 'note': 'Metadata edited'}];
    if (await store.save('documents', {...m, 'versions': versions})) {
      if (mounted) Navigator.pop(context);
      store.toast('Details saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = store.lists;
    Widget text(String label, String k) => Field(label: label, child: Input(initial: str(m[k]), onChanged: (v) => m[k] = v));
    Widget sel(String label, String k, List<String> items) => Field(label: label, child: Select(value: str(m[k]), items: items, onChanged: (v) => set(k, v)));
    Widget date(String label, String k) => Field(label: label, child: DateInput(value: str(m[k]), clearable: k == 'expiry', onChanged: (v) => set(k, v)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
      text('Title', 'title'),
      text('Reference number', 'ref'),
      sel('Type', 'type', l.types),
      sel('Issuing authority', 'authority', l.auths),
      sel('Department', 'dept', l.depts),
      sel('Institution', 'institution', l.insts),
      date('Document date', 'date'),
      date('Effective date', 'effective'),
      date('Expiry date', 'expiry'),
      Field(label: 'Audience', child: MultiChips(options: l.auds, selected: ls('audience'), onToggle: (v) => toggle('audience', v))),
      Field(label: 'Subject tags', child: MultiChips(options: l.tags, selected: ls('tags'), onToggle: (v) => toggle('tags', v))),
      Field(label: 'Description', child: Input(initial: str(m['description']), maxLines: 3, onChanged: (v) => m['description'] = v)),
      SheetFoot(children: [btn('Cancel', () => Navigator.pop(context)), btn('Save changes', submit, primary: true)]),
    ], 12));
  }
}

void showWithdraw(BuildContext context, Doc d) => showSheet(context, title: 'Withdraw document', builder: (_) => _Withdraw(doc: d));

class _Withdraw extends StatefulWidget {
  const _Withdraw({required this.doc});
  final Doc doc;
  @override
  State<_Withdraw> createState() => _WithdrawState();
}

class _WithdrawState extends State<_Withdraw> {
  String reason = '';
  String date = todayIso();
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Note(kind: 'bad', text: '“${widget.doc.title}” will stop being used in AI answers. It stays in the library, marked Withdrawn, for the record.'),
        Field(label: 'Reason or withdrawing order', req: true, child: Input(maxLines: 3, hint: 'e.g. Withdrawn vide Office Order SVSU/REG/ADM/2026/120', onChanged: (v) => reason = v)),
        Field(label: 'Withdrawal date', child: DateInput(value: date, onChanged: (v) => setState(() => date = v))),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Withdraw document', () async {
            if (reason.trim().isEmpty) {
              store.toast('Add a reason');
              return;
            }
            final d = widget.doc;
            final ok = await store.save('documents', d.copy({
              'status': 'Withdrawn',
              'withdrawReason': reason,
              'approvals': [...d.approvals.map((a) => a.j), {'step': 'Withdrawn', 'by': store.myName, 'date': date, 'kind': 'bad', 'note': reason}],
            }));
            if (ok) {
              if (context.mounted) Navigator.pop(context);
              store.toast('Document withdrawn. It will no longer be used in answers.');
            }
          }, danger: true),
        ]),
      ], 12));
}

/// Links are two-way: both documents list each other as related.
Future<bool> setLink(Doc a, Doc b, bool linked) async {
  Json edit(Doc d, String other) => d.copy({
        'related': linked ? {...d.related, other}.toList() : d.related.where((x) => x != other).toList(),
      });
  return await store.save('documents', edit(a, b.id)) && await store.save('documents', edit(store.getDoc(b.id) ?? b, a.id));
}

void showLinkDoc(BuildContext context, Doc d) => showSheet(context, title: 'Link a related document', builder: (_) => _LinkDoc(doc: d));

class _LinkDoc extends StatefulWidget {
  const _LinkDoc({required this.doc});
  final Doc doc;
  @override
  State<_LinkDoc> createState() => _LinkDocState();
}

class _LinkDocState extends State<_LinkDoc> {
  String r = '';
  @override
  Widget build(BuildContext context) {
    final options = store.documents.where((x) => x.id != widget.doc.id && !widget.doc.related.contains(x.id)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Field(
        label: 'Document',
        child: Select(value: r, items: [for (final x in options) x.id], empty: 'Select…', labels: {for (final x in options) x.id: '${x.ref} — ${x.title}'}, onChanged: (v) => setState(() => r = v)),
      ),
      SheetFoot(children: [
        btn('Cancel', () => Navigator.pop(context)),
        btn('Link document', () async {
          final other = store.getDoc(r);
          if (other == null) {
            store.toast('Choose a document');
            return;
          }
          if (await setLink(widget.doc, other, true)) {
            if (context.mounted) Navigator.pop(context);
            store.toast('Documents linked');
          }
        }, primary: true),
      ]),
    ]);
  }
}

void showAddTag(BuildContext context, Doc d) => showSheet(context, title: 'Add subject tag', builder: (_) => _AddTag(doc: d));

class _AddTag extends StatefulWidget {
  const _AddTag({required this.doc});
  final Doc doc;
  @override
  State<_AddTag> createState() => _AddTagState();
}

class _AddTagState extends State<_AddTag> {
  final sel = <String>[];
  @override
  Widget build(BuildContext context) {
    final free = store.lists.tags.where((t) => !widget.doc.tags.contains(t)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (free.isEmpty) Text('Every tag is already on this document.', style: muted(context)),
      MultiChips(options: free, selected: sel, onToggle: (t) => setState(() => sel.contains(t) ? sel.remove(t) : sel.add(t))),
      const SizedBox(height: 10),
      Text('Tags describe the subject. To change who can see the document, use the Access tab.', style: xs(context)),
      SheetFoot(children: [
        btn('Cancel', () => Navigator.pop(context)),
        btn('Add tags', () async {
          if (sel.isEmpty) {
            store.toast('Choose at least one tag');
            return;
          }
          if (await store.save('documents', widget.doc.copy({'tags': [...widget.doc.tags, ...sel]}))) {
            if (context.mounted) Navigator.pop(context);
            store.toast('${sel.length} tag(s) added');
          }
        }, primary: true),
      ]),
    ]);
  }
}

/// A revision is a new document that goes through approval; approving it supersedes this one.
void showAddRevision(BuildContext context, Doc d) => showSheet(context, title: 'Add a revision', builder: (_) => _AddRevision(doc: d, outer: context));

class _AddRevision extends StatefulWidget {
  const _AddRevision({required this.doc, required this.outer});
  final Doc doc;
  final BuildContext outer;
  @override
  State<_AddRevision> createState() => _AddRevisionState();
}

class _AddRevisionState extends State<_AddRevision> {
  Picked? file;
  late String v = widget.doc.nextVersion;
  String effective = todayIso();
  String note = '';
  bool busy = false;

  Future<void> submit() async {
    if (file == null || note.trim().isEmpty) {
      store.toast('Choose the revised file and say what changed');
      return;
    }
    setState(() => busy = true);
    try {
      final res = await api.extract(file!.path, file!.name);
      final d = widget.doc;
      final id = nid('D'), by = store.myName;
      final pages = pagesOf(res['pages']);
      final rev = {
        ...d.j,
        'id': id, 'status': 'Pending', 'effective': effective, 'revisionOf': d.id, 'supersededBy': null, 'related': <String>[],
        'pages': res['pages'], 'file': res['file'], 'fileType': res['kind'], 'ocr': res['ocr'], 'sample': false,
        'uploadedBy': by, 'uploadedOn': todayIso(),
        'lang': pages.any((p) => p.any((b) => isHindi(b.plain))) ? 'hi' : 'en',
        'versions': [...d.versions, {'v': v, 'date': todayIso(), 'by': by, 'note': note}],
        'approvals': [{'step': 'Revision submitted for approval', 'by': by, 'date': todayIso(), 'kind': '', 'note': '$note (from ${file!.name})'}],
      }..remove('withdrawReason');
      if (await store.save('documents', rev)) {
        if (mounted) Navigator.pop(context);
        store.toast('Revision submitted for approval');
        if (widget.outer.mounted) widget.outer.push('/library/$id');
      }
    } catch (e) {
      store.toast('$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Text('Upload a corrected or updated file for “${widget.doc.title}”. The current version stays live until the revision is approved.', style: muted(context)),
        Field(
          label: 'Revised file',
          child: OutlinedButton.icon(
            onPressed: () async {
              final f = await pickSource(context, multiple: false);
              if (f.isNotEmpty) setState(() => file = f.first);
            },
            icon: const Icon(Icons.attach_file),
            label: Text(file?.name ?? 'Choose a file', overflow: TextOverflow.ellipsis),
          ),
        ),
        Field(label: 'New version number', child: Input(initial: v, onChanged: (x) => v = x)),
        Field(label: 'Effective date', child: DateInput(value: effective, onChanged: (x) => setState(() => effective = x))),
        Field(label: 'What changed?', req: true, child: Input(maxLines: 3, hint: 'e.g. Corrected the effective date in clause 7', onChanged: (x) => note = x)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn(busy ? 'Reading the file…' : 'Submit revision', busy ? null : submit, primary: true, busy: busy),
        ]),
      ], 12));
}
