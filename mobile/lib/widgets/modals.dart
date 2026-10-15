/// Sheets used from more than one screen. Each one saves through the store, so the server decides.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'answer.dart';
import 'original.dart';
import 'paper.dart';
import 'ui.dart';

// ---------- Answer feedback ----------
const reasons = ['Incorrect information', 'Wrong or missing source', 'Outdated document used', 'Conflicting information', 'Incomplete answer', 'Wrong language'];

/// One feedback entry per answer: rating again replaces it.
Future<void> rate(Chat chat, Msg m, String rating, [String reason = '', String comment = '']) async {
  await store.save('chats', chat.copy({
    'msgs': [for (final x in chat.msgs) x.id == m.id ? {...x.j, 'fb': rating} : x.j],
  }));
  final ok = await store.save('feedback', {
    'id': 'fb-${m.id}', 'q': m.q, 'rating': rating, 'reason': reason, 'comment': comment, 'who': store.myName, 'when': todayIso(),
  });
  if (ok) store.toast(rating == 'up' ? 'Thanks. Marked as helpful.' : 'Feedback sent to Reports & Feedback');
}

void showFeedback(BuildContext context, Chat chat, Msg m) => showSheet(context,
    title: 'What was wrong with this answer?', builder: (_) => _Feedback(chat: chat, m: m));

class _Feedback extends StatefulWidget {
  const _Feedback({required this.chat, required this.m});
  final Chat chat;
  final Msg m;
  @override
  State<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends State<_Feedback> {
  String reason = reasons.first;
  String comment = '';
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in reasons) ChoiceChip(label: Text(r), selected: reason == r, onSelected: (_) => setState(() => reason = r)),
        ]),
        const SizedBox(height: 14),
        Field(label: 'Comment (optional)', child: Input(maxLines: 3, hint: 'What should the answer have said?', onChanged: (v) => comment = v)),
        const SizedBox(height: 8),
        Text('Feedback goes to Reports & Feedback for the document owners.', style: xs(context)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Send feedback', () {
            Navigator.pop(context);
            rate(widget.chat, widget.m, 'down', reason, comment);
          }, primary: true),
        ]),
      ]);
}

// ---------- Export cited summary ----------
typedef ExportItem = ({String q, Answer answer});

String summaryText(List<ExportItem> items) => items.map((it) {
      final src = [
        for (var i = 0; i < it.answer.cites.length; i++)
          () {
            final c = it.answer.cites[i];
            final d = store.getDoc(c.doc);
            return '[${i + 1}] ${d != null ? '${d.title} (${d.ref})' : c.doc}, page ${c.page} — "${c.quote}"';
          }(),
      ];
      return ['Q: ${it.q}', answerText(it.answer), if (src.isNotEmpty) ...['Sources', ...src]].join('\n');
    }).join('\n\n');

void showExport(BuildContext context, String title, List<ExportItem> items) =>
    showSheet(context, title: 'Export cited summary', builder: (_) => _Export(title: title, items: items));

class _Export extends StatefulWidget {
  const _Export({required this.title, required this.items});
  final String title;
  final List<ExportItem> items;
  @override
  State<_Export> createState() => _ExportState();
}

class _ExportState extends State<_Export> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final text = summaryText(widget.items);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        constraints: const BoxConstraints(maxHeight: 340),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.pal.line)),
        child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 12.5, height: 1.45))),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        btn('Copy', () {
          Clipboard.setData(ClipboardData(text: text));
          store.toast('Copied');
        }, icon: Icons.copy),
        btn('Share text', () => shareText('${widget.title}\n\n$text', subject: widget.title), icon: Icons.share_outlined),
        btn(busy ? 'Preparing…' : 'Word document', busy ? null : () async {
          setState(() => busy = true);
          try {
            final bytes = await api.exportDocx(widget.title, [for (final it in widget.items) {'q': it.q, 'answer': it.answer.j}]);
            await openBytes(bytes, 'svsu-cited-summary.docx', mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
          } catch (e) {
            store.toast('$e');
          }
          if (mounted) setState(() => busy = false);
        }, icon: Icons.description_outlined, primary: true),
      ]),
    ]);
  }
}

// ---------- Compare two documents · report a conflict ----------
Future<void> reportConflict(List<String> docs, String topic) async {
  if (store.conflicts.any((c) => c.s('status') == 'Open' && strs(c.j['docs']).join() == docs.join())) {
    store.toast('This conflict is already reported');
    return;
  }
  final ok = await store.save('conflicts', {'id': nid('cf'), 'docs': docs, 'topic': topic, 'status': 'Open', 'reported': todayIso(), 'by': store.myName});
  if (ok) store.toast('Conflict reported to the document owners');
}

void showCompare(BuildContext context, String a, String b, String topic) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComparePage(a: a, b: b, topic: topic)));

class ComparePage extends StatefulWidget {
  const ComparePage({super.key, required this.a, required this.b, required this.topic});
  final String a, b, topic;
  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Widget pane(String id) {
    final d = store.fullDoc(id);
    if (d == null) return const Loading();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [Pill(d.status), const SizedBox(width: 8), Expanded(child: Text(d.title, style: bold(context)))]),
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('${d.ref} · ${fmtD(d.date)} · ${d.authority}', style: mono(context))),
      Pages(doc: d, zoom: .85),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final da = store.getDoc(widget.a), db = store.getDoc(widget.b);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Compare documents'),
          bottom: TabBar(tabs: [Tab(text: da?.ref ?? 'First'), Tab(text: db?.ref ?? 'Second')]),
        ),
        body: TabBarView(children: [pane(widget.a), pane(widget.b)]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: btn('Close', () => Navigator.pop(context), small: false)),
              const SizedBox(width: 8),
              Expanded(child: btn('Report conflict', () {
                Navigator.pop(context);
                reportConflict([widget.a, widget.b], widget.topic);
              }, primary: true, small: false)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------- Request a document ----------
void showRequestDoc(BuildContext context, String q, {String? dept}) =>
    showSheet(context, title: 'Request a document', builder: (_) => _RequestDoc(q: q, dept: dept));

class _RequestDoc extends StatefulWidget {
  const _RequestDoc({required this.q, this.dept});
  final String q;
  final String? dept;
  @override
  State<_RequestDoc> createState() => _RequestDocState();
}

class _RequestDocState extends State<_RequestDoc> {
  late String d = (widget.dept ?? '').isNotEmpty ? widget.dept! : (store.lists.depts.firstOrNull ?? '');
  late final note = TextEditingController(text: 'Please upload the rule or circular that answers: “${widget.q}”');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('“${widget.q}”', style: sm(context)),
        const SizedBox(height: 12),
        Field(label: 'Department', child: Select(value: d, items: store.lists.depts, onChanged: (v) => setState(() => d = v))),
        const SizedBox(height: 12),
        Field(label: 'Note', child: Input(controller: note, maxLines: 3)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Send request', () async {
            try {
              await api.requestDoc(widget.q, d, note.text);
              if (context.mounted) Navigator.pop(context);
              store.toast('Request sent to $d');
              store.load();
            } catch (e) {
              store.toast('$e');
            }
          }, primary: true),
        ]),
      ]);
}

// ---------- Deadlines ----------
void showDeadline(BuildContext context, {String? docId, Deadline? deadline}) =>
    showSheet(context, title: deadline != null ? 'Edit deadline' : 'Add a deadline', builder: (_) => _DeadlineForm(docId: docId, deadline: deadline));

class _DeadlineForm extends StatefulWidget {
  const _DeadlineForm({this.docId, this.deadline});
  final String? docId;
  final Deadline? deadline;
  @override
  State<_DeadlineForm> createState() => _DeadlineFormState();
}

class _DeadlineFormState extends State<_DeadlineForm> {
  late final title = TextEditingController(text: widget.deadline?.title ?? '');
  late String date = widget.deadline?.date ?? todayIso();
  late final owner = TextEditingController(text: widget.deadline?.owner ?? 'HODs');
  late final aud = TextEditingController(text: widget.deadline?.aud ?? 'Teaching staff');
  late String doc = widget.deadline?.doc ?? widget.docId ?? (store.permitted.firstOrNull?.id ?? '');

  Future<void> submit() async {
    if (title.text.trim().isEmpty || date.isEmpty || doc.isEmpty) {
      store.toast('Fill in what, when and the source document');
      return;
    }
    final d = await store.loadDoc(doc) ?? store.full[doc];
    if (d == null || !d.hasPages) {
      store.toast("Couldn't open that document");
      return;
    }
    // A new deadline points at the document's first paragraph; an edited one keeps its passage.
    final first = d.pages.isEmpty ? <TextBlock>[] : d.pages[0];
    final b = first.where((x) => x.kind != 'subj').firstOrNull ?? first.firstOrNull;
    final dl = widget.deadline;
    final keep = dl != null && dl.doc == doc;
    final item = {
      ...?dl?.j,
      'id': dl?.id ?? nid('dl'), 'title': title.text.trim(), 'date': date, 'owner': owner.text, 'aud': aud.text, 'doc': doc, 'dept': d.dept,
      'page': keep ? dl.page : 1, 'block': keep ? dl.block : (b?.id ?? ''), 'quote': keep ? dl.quote : (b != null && !b.isRow ? b.plain : ''),
    };
    if (await store.save('deadlines', item)) {
      if (mounted) Navigator.pop(context);
      store.toast(dl != null ? 'Deadline updated' : 'Deadline added');
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = store.permitted;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Field(label: 'What needs to be done?', child: Input(controller: title, autofocus: widget.deadline == null)),
      const SizedBox(height: 12),
      Field(label: 'Due date', child: DateInput(value: date, onChanged: (v) => setState(() => date = v))),
      const SizedBox(height: 12),
      Field(label: 'Responsible', child: Input(controller: owner)),
      const SizedBox(height: 12),
      Field(
        label: 'Source document',
        child: Select(value: doc, items: [for (final d in docs) d.id], labels: {for (final d in docs) d.id: '${d.ref} — ${d.title}'}, onChanged: (v) => setState(() => doc = v)),
      ),
      const SizedBox(height: 12),
      Field(label: 'Applies to', child: Input(controller: aud)),
      SheetFoot(children: [
        btn('Cancel', () => Navigator.pop(context)),
        btn(widget.deadline != null ? 'Save deadline' : 'Add deadline', submit, primary: true),
      ]),
    ]);
  }
}

const _when = [(0, 'On the day'), (1, '1 day before'), (3, '3 days before'), (7, '1 week before')];
const _channels = ['In the app', 'Email'];

void showReminder(BuildContext context, Deadline d) => showSheet(context, title: 'Set a reminder', builder: (_) => _Reminder(deadline: d));

class _Reminder extends StatefulWidget {
  const _Reminder({required this.deadline});
  final Deadline deadline;
  @override
  State<_Reminder> createState() => _ReminderState();
}

class _ReminderState extends State<_Reminder> {
  late final Rec? existing = store.reminders.where((r) => r.s('deadline') == widget.deadline.id).firstOrNull;
  late int days = (existing?.j['days'] as num?)?.toInt() ?? 3;
  late List<String> via = existing != null ? strs(existing!.j['via']) : List.of(_channels);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: widget.deadline.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: ' · due ${fmtD(widget.deadline.date)}'),
        ]), style: sm(context)),
        const SizedBox(height: 12),
        Field(
          label: 'Remind me',
          child: Select(value: '$days', items: [for (final w in _when) '${w.$1}'], labels: {for (final w in _when) '${w.$1}': w.$2}, onChanged: (v) => setState(() => days = int.parse(v))),
        ),
        const SizedBox(height: 12),
        Field(label: 'Send through', child: MultiChips(options: _channels, selected: via, onToggle: (c) => setState(() => via.contains(c) ? via.remove(c) : via.add(c)))),
        const SizedBox(height: 8),
        Text('Email needs an address on your profile and the mail server set up by IT.', style: xs(context)),
        SheetFoot(
          leading: existing == null
              ? null
              : btn('Remove', () async {
                  if (await store.remove('reminders', existing!.id)) {
                    if (context.mounted) Navigator.pop(context);
                    store.toast('Reminder removed');
                  }
                }, danger: true),
          children: [
            btn('Cancel', () => Navigator.pop(context)),
            btn('Save', () async {
              final r = {'id': existing?.id ?? nid('rm'), 'deadline': widget.deadline.id, 'days': days, 'via': via.isEmpty ? ['In the app'] : via};
              if (await store.save('reminders', r)) {
                if (context.mounted) Navigator.pop(context);
                store.toast('Reminder set');
              }
            }, primary: true),
          ],
        ),
      ]);
}
