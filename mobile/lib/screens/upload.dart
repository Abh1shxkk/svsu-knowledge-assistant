import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/pick.dart';
import '../widgets/shell.dart';
import '../widgets/text_review.dart';
import '../widgets/ui.dart';

/// One file being uploaded: read by the server, then described here and submitted.
class _Item {
  _Item(this.id, this.name);
  final String id;
  final String name;
  String kind = 'pdf';
  List<List<TextBlock>> pages = [];
  num? ocr;
  String? ocrEngine;
  Json meta = {};
  String status = 'processing'; // processing, ready, submitted, draft
  String? docId;
  Map<String, String> errors = {};
  Json? dup;
  Json? file;
  List<String> unsure = [];
}

const _required = [
  ('title', 'Enter the document title'), ('ref', 'Enter the reference number'), ('type', 'Choose a document type'),
  ('authority', 'Choose the issuing authority'), ('dept', 'Choose the department'), ('date', 'Enter the document date'),
  ('visibility', 'Choose who can see this'),
];

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> with StoreListener {
  final queue = <_Item>[];
  String? selId;
  String mode = 'one';

  _Item? get sel => queue.where((q) => q.id == selId).firstOrNull;

  Future<void> addFiles(List<Picked> files) async {
    final l = store.lists;
    for (final f in files) {
      final it = _Item(nid('q'), f.name)..meta = {'institution': l.insts.firstOrNull};
      setState(() {
        queue.add(it);
        selId ??= it.id;
      });
      try {
        final res = await api.extract(f.path, f.name);
        setState(() {
          it
            ..kind = str(res['kind'])
            ..pages = pagesOf(res['pages'])
            ..ocr = res['ocr'] as num?
            ..ocrEngine = res['ocr_engine'] as String?
            ..status = 'ready'
            ..dup = res['duplicate'] == null ? null : Map<String, dynamic>.from(res['duplicate'] as Map)
            ..file = res['file'] == null ? null : Map<String, dynamic>.from(res['file'] as Map)
            ..unsure = strs(res['unsure'])
            ..meta = {'institution': l.insts.firstOrNull, ...Map<String, dynamic>.from(res['suggestion'] as Map? ?? {})};
        });
      } catch (e) {
        store.toast('${f.name}: $e');
        setState(() => queue.remove(it));
      }
    }
  }

  void setMeta(_Item it, Json patch) => setState(() {
        it.meta = {...it.meta, ...patch};
        it.errors = {};
      });

  /// Submit for approval, or save as a draft (only the title is needed) to finish later.
  Future<void> submit(_Item it, {bool draft = false}) async {
    final m = it.meta;
    final l = store.lists;
    String g(String k) => str(m[k]);
    final errors = <String, String>{};
    if (draft) {
      if (g('title').trim().isEmpty) errors['title'] = 'Add a title to save a draft';
    } else {
      for (final (k, msg) in _required) {
        if (g(k).isEmpty) errors[k] = msg;
      }
      if (strs(m['audience']).isEmpty) errors['audience'] = 'Choose at least one audience';
      if (strs(m['tags']).isEmpty) errors['tags'] = 'Choose at least one subject tag';
      if (g('revRel').isNotEmpty && g('revRel') != 'new' && g('revDoc').isEmpty) errors['revDoc'] = 'Choose the document this revises';
      if (g('expiry').isNotEmpty && g('effective').isNotEmpty && g('expiry').compareTo(g('effective')) < 0) {
        errors['expiry'] = 'Expiry date must be after the effective date';
      }
    }
    if (errors.isNotEmpty) {
      setState(() => it.errors = errors);
      store.toast('Fill in the highlighted fields');
      return;
    }
    final id = it.docId ?? nid('D');
    final by = store.myName;
    final doc = {
      'id': id, 'title': g('title').trim(), 'ref': g('ref'), 'type': g('type'), 'authority': g('authority'), 'dept': g('dept'),
      'institution': g('institution').isNotEmpty ? g('institution') : l.insts.firstOrNull ?? '',
      'date': g('date'), 'effective': g('effective').isNotEmpty ? g('effective') : g('date'), 'expiry': g('expiry'),
      'audience': strs(m['audience']), 'tags': strs(m['tags']),
      // a draft with no access chosen stays at the most restricted level
      'visibility': g('visibility').isNotEmpty ? g('visibility') : (l.vis.lastOrNull ?? ''),
      'status': draft ? 'Draft' : 'Pending', 'fileType': it.kind, 'description': g('description'), 'uploadedBy': by, 'uploadedOn': todayIso(),
      'lang': it.pages.any((p) => p.any((b) => isHindi(b.plain))) ? 'hi' : 'en',
      'related': strs(m['related']),
      'revisionOf': g('revRel').isNotEmpty && g('revRel') != 'new' && g('revDoc').isNotEmpty ? g('revDoc') : null,
      'supersededBy': null,
      'versions': [{'v': '1.0', 'date': todayIso(), 'by': by, 'note': 'Original upload'}],
      'approvals': [{'step': draft ? 'Saved as draft' : 'Submitted for approval', 'by': by, 'date': todayIso(), 'kind': '', 'note': 'Uploaded from ${it.name}'}],
      'pages': pagesJson(it.pages), 'file': it.file, 'unsure': it.unsure,
      if (it.ocr != null) 'ocr': it.ocr,
    };
    if (!await store.save('documents', doc)) return;
    setState(() {
      it.status = draft ? 'draft' : 'submitted';
      it.docId = id;
    });
    store.toast(draft ? 'Draft saved. You can finish it later from the document record.' : 'Submitted for approval');
  }

  @override
  Widget build(BuildContext context) {
    final s = sel;
    return AppScaffold(
      route: '/upload',
      title: 'Upload Documents',
      showAsk: false,
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 40), children: gap([
        Text('Add official letters, notices, circulars and policies. Files are read, tagged and sent for approval before the assistant can use them.',
            style: muted(context)),
        Row(children: [
          Expanded(child: Seg<String>(options: const [('one', 'One by one', null), ('bulk', 'Bulk import', null)], value: mode, onChanged: (v) => setState(() => mode = v))),
          if (store.canApprove) ...[const SizedBox(width: 8), btn('Review queue', () => context.go('/review'), icon: Icons.verified_user_outlined)],
        ]),
        if (mode == 'bulk') const _BulkImport() else ...[
          _DropCard(onPick: () async => addFiles(await pickFiles()), onCamera: () async {
            final p = await takePhoto();
            if (p != null) addFiles([p]);
          }),
          Section(
            title: 'Upload queue',
            trailing: Text('${queue.where((q) => q.status != 'processing').length} of ${queue.length} ready', style: xs(context)),
            children: queue.isEmpty
                ? [const EmptyBox('No files yet. Choose files to begin.')]
                : [
                    for (final it in queue)
                      Material(
                        color: it.id == selId ? context.pal.accentSoft : Colors.transparent,
                        child: Row2(
                          lead: Ft(it.kind),
                          title: it.name,
                          meta: switch (it.status) {
                            'processing' => 'Reading…',
                            'submitted' => '✓ Submitted',
                            'draft' => 'Draft saved',
                            _ => it.dup != null ? 'Possible duplicate · needs details' : 'Ready · add details',
                          },
                          trail: it.status == 'processing'
                              ? const Spinner(size: 16)
                              : IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => setState(() {
                                    queue.remove(it);
                                    if (selId == it.id) selId = queue.firstOrNull?.id;
                                  }),
                                ),
                          onTap: () => setState(() => selId = it.id),
                        ),
                      ),
                  ],
          ),
          if (s == null)
            Section(title: 'How uploading works', padded: true, children: [
              for (final (i, (a, b)) in const [
                ('Add files', 'Choose your own files or photograph a paper document. Each is read and (for scans) run through OCR.'),
                ('Automatic checks', 'Details and tags are suggested, and duplicates of existing documents are flagged.'),
                ('Review the details', 'Check and edit the suggestions. Save a draft to finish later.'),
                ('Submit for approval', 'An approver checks the document before it appears in the library and AI answers.'),
              ].indexed)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. $a', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(b, style: muted(context)),
                ]),
            ])
          else if (s.status == 'processing')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(children: [
                  const Spinner(size: 26),
                  const SizedBox(height: 10),
                  Text('Reading ${s.name}', style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                  Text('Extracting text, suggesting details and checking for duplicates…', style: muted(context), textAlign: TextAlign.center),
                ]),
              ),
            )
          else if (s.status == 'submitted' || s.status == 'draft')
            Section(padded: true, children: [
              Note(kind: 'ok', text: '“${str(s.meta['title'])}” ${s.status == 'draft' ? 'was saved as a draft.' : 'was submitted for approval.'}'),
              Text(
                s.status == 'draft'
                    ? 'Only you and approvers can see it. Open the record to finish the details and submit it.'
                    : 'It will appear in the library and AI answers once an approver publishes it.',
                style: muted(context),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (store.canApprove && s.status == 'submitted') btn('Open review queue', () => context.go('/review'), primary: true),
                if (s.docId != null) btn('View document record', () => context.push('/library/${s.docId}')),
              ]),
            ])
          else
            _DetailsForm(item: s, setMeta: (p) => setMeta(s, p), onSubmit: (draft) => submit(s, draft: draft), refresh: () => setState(() {})),
        ],
      ], 14)),
    );
  }
}

class _DropCard extends StatelessWidget {
  const _DropCard({required this.onPick, required this.onCamera});
  final VoidCallback onPick;
  final VoidCallback onCamera;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line2, width: 1.5)),
      child: Column(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.upload_outlined, color: p.accent),
        ),
        const SizedBox(height: 10),
        const Text('Add documents', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text('PDF, scanned PDF, Word (.docx), Excel (.xlsx), CSV, images (JPG, PNG) and text files. Save older .doc and .xls files in the newer format first.',
            textAlign: TextAlign.center, style: muted(context)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          btn('Choose files', onPick, icon: Icons.folder_open_outlined, primary: true, small: false),
          btn('Take a photo', onCamera, icon: Icons.photo_camera_outlined, small: false),
        ]),
        const SizedBox(height: 10),
        Text('Scanned PDFs and photos are read with OCR. The assistant searches the text after approval.', textAlign: TextAlign.center, style: xs(context)),
      ]),
    );
  }
}

class _DetailsForm extends StatelessWidget {
  const _DetailsForm({required this.item, required this.setMeta, required this.onSubmit, required this.refresh});
  final _Item item;
  final void Function(Json) setMeta;
  final void Function(bool draft) onSubmit;
  final VoidCallback refresh;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final l = store.lists;
    final m = it.meta;
    final active = store.documents.where((d) => d.status == 'Active').toList();
    String g(String k) => str(m[k]);
    void toggle(String k, String v) => setMeta({k: strs(m[k]).contains(v) ? strs(m[k]).where((x) => x != v).toList() : [...strs(m[k]), v]});
    Widget fld(String k, String label, {bool req = false}) {
      final err = it.errors[k];
      final choices = switch (k) { 'type' => l.types, 'authority' => l.auths, 'dept' => l.depts, 'institution' => l.insts, _ => null };
      return Field(
        label: label,
        req: req,
        error: err,
        child: choices != null
            ? Select(value: g(k), items: choices, empty: 'Select…', error: err != null, onChanged: (v) => setMeta({k: v}))
            : const ['date', 'effective', 'expiry'].contains(k)
                ? DateInput(value: g(k), error: err != null, clearable: k != 'date', onChanged: (v) => setMeta({k: v}))
                : Input(key: ValueKey('${it.id}$k'), initial: g(k), error: err != null, onChanged: (v) {
                    m[k] = v;
                    if (it.errors.isNotEmpty) setMeta({});
                  }),
      );
    }

    Widget sec(String title, String? small, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (small != null) TextSpan(text: '  $small', style: xs(context)),
          ])),
          const SizedBox(height: 10),
          ...gap(children, 12),
        ]);

    return Section(
      title: it.name,
      sub: '${it.kind.toUpperCase()}${it.ocr != null ? ' · OCR by ${it.ocrEngine} · ${it.ocr}% confidence' : ''}',
      padded: true,
      children: [
        if (it.dup != null)
          Note(kind: 'warn', title: 'This may be a duplicate.', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('It matches “${str(it.dup!['title'])}” (${str(it.dup!['ref'])}), already ${str(it.dup!['status']).toLowerCase()}.', style: sm(context)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              btn('View existing', () => context.push('/library/${it.dup!['id']}')),
              btn('Upload as a new revision', () {
                setMeta({'revRel': 'revision', 'revDoc': it.dup!['id']});
                it.dup = null;
                refresh();
                store.toast('Set as a revision of the existing document');
              }),
              TextButton(onPressed: () {
                it.dup = null;
                refresh();
              }, child: const Text("It's a different document")),
            ]),
          ])),
        sec('Extracted text', 'What the assistant will search. Check it, and correct any mistakes.', [
          if (it.pages.isEmpty)
            Text('No text could be read from this file.', style: muted(context))
          else
            TextReview(
              key: ValueKey(it.id),
              pages: it.pages,
              unsure: it.unsure,
              editable: true,
              onSave: (pages) async {
                it
                  ..pages = pages
                  ..unsure = [];
                refresh();
                store.toast('Text updated');
              },
            ),
        ]),
        const Divider(),
        sec('Document details', null, [
          fld('title', 'Document title', req: true),
          fld('ref', 'Reference / letter number', req: true),
          fld('type', 'Document type', req: true),
          fld('authority', 'Issuing authority', req: true),
          fld('dept', 'Issuing department', req: true),
          fld('institution', 'Institution / college'),
          fld('date', 'Document date', req: true),
          fld('effective', 'Effective date'),
          fld('expiry', 'Expiry date'),
          Field(label: 'Applicable audience', req: true, error: it.errors['audience'], child: MultiChips(options: l.auds, selected: strs(m['audience']), onToggle: (v) => toggle('audience', v))),
        ]),
        const Divider(),
        sec('Subject tags', 'What the document is about', [
          Field(error: it.errors['tags'], child: MultiChips(options: l.tags, selected: strs(m['tags']), onToggle: (v) => toggle('tags', v))),
        ]),
        const Divider(),
        sec('Visibility and access', 'Who may open it', [
          Field(error: it.errors['visibility'], child: RadioCards(options: l.vis, value: g('visibility'), describe: l.visDesc, onChanged: (v) => setMeta({'visibility': v}))),
        ]),
        const Divider(),
        sec('Relationships', null, [
          Field(
            label: 'Revision relationship',
            child: Select(
              value: g('revRel').isEmpty ? 'new' : g('revRel'),
              items: const ['new', 'revision', 'supersedes'],
              labels: const {'new': 'New document', 'revision': 'Revision of an existing document', 'supersedes': 'Supersedes an existing document'},
              onChanged: (v) => setMeta({'revRel': v}),
            ),
          ),
          if (g('revRel').isNotEmpty && g('revRel') != 'new')
            Field(
              label: 'Which document?',
              req: true,
              error: it.errors['revDoc'],
              hint: 'The older document will be marked superseded on approval',
              child: Select(
                value: g('revDoc'),
                items: [for (final d in active) d.id],
                labels: {for (final d in active) d.id: '${d.ref} — ${d.title}'},
                empty: 'Select…',
                error: it.errors['revDoc'] != null,
                onChanged: (v) => setMeta({'revDoc': v}),
              ),
            ),
          if (active.isNotEmpty)
            Field(
              label: 'Related documents',
              hint: 'Optional.',
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(border: Border.all(color: context.pal.line), borderRadius: BorderRadius.circular(10)),
                child: ListView(shrinkWrap: true, children: [
                  for (final d in active)
                    CheckboxListTile(
                      dense: true,
                      value: strs(m['related']).contains(d.id),
                      onChanged: (_) => toggle('related', d.id),
                      title: Text('${d.ref} — ${d.title}', style: const TextStyle(fontSize: 13)),
                    ),
                ]),
              ),
            ),
        ]),
        Field(label: 'Description or remarks', child: Input(key: ValueKey('${it.id}desc'), initial: g('description'), maxLines: 3, onChanged: (v) => m['description'] = v)),
        Text('Fields marked * are required to submit.', style: xs(context)),
        Row(children: [
          Expanded(child: btn('Save draft', () => onSubmit(true), icon: Icons.save_outlined, small: false)),
          const SizedBox(width: 8),
          Expanded(child: btn('Submit for approval', () => onSubmit(false), primary: true, small: false)),
        ]),
      ],
    );
  }
}

/// Many files at once: each is sent to the server and processed in the background (read, OCR,
/// details suggested, indexed). The app can be closed once sending finishes; progress is shown here.
class _BulkImport extends StatefulWidget {
  const _BulkImport();
  @override
  State<_BulkImport> createState() => _BulkImportState();
}

class _BulkImportState extends State<_BulkImport> {
  late String visibility = store.lists.vis.length > 1 ? store.lists.vis[1] : (store.lists.vis.firstOrNull ?? '');
  String dept = '';
  bool publish = false;
  ({int done, int total, int skipped, int errors})? sending;
  List<Json> batches = [];
  Timer? timer;
  int _interval = 0;

  bool get busy => batches.any((b) => ((b['counts'] as Map?)?['queued'] ?? 0) > 0 || ((b['counts'] as Map?)?['running'] ?? 0) > 0) || sending != null;

  @override
  void initState() {
    super.initState();
    tick();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  /// Refresh progress every few seconds while anything is being processed.
  void tick() {
    api.imports().then((b) {
      if (mounted) setState(() => batches = b);
      _schedule();
    }, onError: (_) => _schedule());
  }

  void _schedule() {
    if (!mounted) return;
    final want = busy ? 4 : 20;
    if (timer != null && _interval == want) return;
    timer?.cancel();
    _interval = want;
    timer = Timer.periodic(Duration(seconds: want), (_) => tick());
  }

  Future<void> start() async {
    final list = await pickFiles();
    final files = list.where((f) => supported.hasMatch(f.name)).toList();
    final skipped = list.length - files.length;
    if (files.isEmpty) {
      if (list.isNotEmpty || skipped > 0) store.toast('None of these files can be read (use PDF, Word, Excel, images or text)');
      return;
    }
    final batch = 'b${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    var done = 0, errors = 0;
    setState(() => sending = (done: 0, total: files.length, skipped: skipped, errors: 0));
    for (final f in files) {
      // one at a time, so a slow connection or a big folder doesn't overload the server
      try {
        await api.importFile(f.path, f.name, batch, visibility: visibility, publish: publish, dept: dept);
      } catch (_) {
        errors++;
      }
      done++;
      if (mounted) setState(() => sending = (done: done, total: files.length, skipped: skipped, errors: errors));
    }
    if (mounted) setState(() => sending = null);
    store.toast('${files.length - errors} file(s) queued${errors > 0 ? ', $errors couldn\'t be sent' : ''}');
    tick();
  }

  @override
  Widget build(BuildContext context) {
    final l = store.lists;
    final approver = store.canApprove;
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
      Section(title: 'Bulk import', padded: true, children: [
        Text(
          'Choose many files at once: in the file picker, long-press one file, then tap “Select all” to take a whole folder. '
          'Each file is read (OCR for scans), described by the assistant and indexed in the background. Details can be checked and corrected afterwards.',
          style: muted(context),
        ),
        Field(label: 'Who can see them', child: Select(value: visibility, items: l.vis, onChanged: (v) => setState(() => visibility = v))),
        Field(
          label: 'Department',
          hint: 'Leave as suggested to let the assistant pick per file',
          child: Select(value: dept, items: l.depts, empty: 'As suggested', onChanged: (v) => setState(() => dept = v)),
        ),
        Field(
          label: 'After reading',
          child: Select(
            value: publish ? 'publish' : 'review',
            items: [
              'review',
              if (approver) 'publish',
            ],
            labels: const {'review': 'Send to Review & Approvals', 'publish': 'Publish straight away'},
            enabled: approver,
            onChanged: (v) => setState(() => publish = v == 'publish'),
          ),
        ),
        if (publish)
          const Note(kind: 'warn', text: "Published files are used in answers immediately, with the assistant's suggested details. Check a few afterwards."),
        btn('Choose files', sending != null ? null : start, icon: Icons.upload_outlined, primary: true, small: false),
        if (sending != null)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Sending ${sending!.done} of ${sending!.total}…', style: sm(context))),
              if (sending!.skipped > 0) Text('${sending!.skipped} unsupported file(s) skipped', style: xs(context)),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: sending!.done / sending!.total, color: p.accent, backgroundColor: p.surface3, minHeight: 6),
            const SizedBox(height: 6),
            Text('Keep the app open until sending finishes; processing then continues on the server.', style: xs(context)),
          ]),
      ]),
      if (batches.isNotEmpty)
        Section(
          title: 'Imports',
          trailing: Text(busy ? 'Processing… refreshes automatically' : 'All finished', style: xs(context)),
          children: [
            for (final b in batches)
              () {
                final c = Map<String, dynamic>.from(b['counts'] as Map? ?? {});
                int n(String k) => (c[k] as num?)?.toInt() ?? 0;
                final total = c.values.fold<int>(0, (a, x) => a + ((x as num?)?.toInt() ?? 0));
                final finished = n('done') + n('duplicate') + n('failed');
                final failed = (b['failed'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${plural(total, 'file')} · ${b['publish'] == true ? 'published' : 'sent to review'}${str(b['by']).isNotEmpty ? ' · by ${b['by']}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    if (b['updated'] != null) Text(fmtDateTime(str(b['updated'])), style: xs(context)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: finished / (total == 0 ? 1 : total), color: p.accent, backgroundColor: p.surface3, minHeight: 6),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (n('done') > 0) Pill('${n('done')} imported', kind: 'ok'),
                      if (n('running') + n('queued') > 0) Pill('${n('running') + n('queued')} waiting', kind: 'info'),
                      if (n('duplicate') > 0) Pill('${n('duplicate')} already in the library', kind: 'mute'),
                      if (n('failed') > 0) Pill('${n('failed')} failed', kind: 'bad'),
                      if (n('failed') > 0)
                        btn('Retry failed', () async {
                          try {
                            final r = await api.retryImport(str(b['batch']));
                            store.toast('${r['requeued']} file(s) will be tried again');
                            tick();
                          } catch (e) {
                            store.toast('$e');
                          }
                        }),
                    ]),
                    if (failed.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('Why files failed', style: sm(context)),
                        children: [
                          for (final f in failed.take(50))
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text.rich(TextSpan(children: [
                                  TextSpan(text: str(f['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  TextSpan(text: ' — ${str(f['error'])}'),
                                ]), style: xs(context)),
                              ),
                            ),
                        ],
                      ),
                  ]),
                );
              }(),
          ],
        ),
    ], 14));
  }
}
