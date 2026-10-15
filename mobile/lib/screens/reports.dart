import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/charts.dart';
import '../widgets/modals.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';

String _csvCell(dynamic v) => '"${'$v'.replaceAll('"', '""')}"';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with StoreListener {
  String fbFilter = 'all';
  Json? sum;
  bool sumFailed = false;

  @override
  void initState() {
    super.initState();
    api.reportSummary().then((s) {
      if (mounted) setState(() => sum = s);
    }, onError: (_) {
      if (mounted) setState(() => sumFailed = true);
    });
  }

  Future<void> resolveU(Rec u) async {
    if (await store.save('unanswered', u.copy({'status': 'Resolved'}))) store.toast('Marked as resolved');
  }

  Future<void> resolveC(Rec c) async {
    if (await store.save('conflicts', c.copy({'status': 'Resolved'}))) store.toast('Conflict marked resolved');
  }

  void copyCsv() {
    final rows = store.unanswered.map((u) => [u.s('q'), u.j['count'] ?? 0, u.s('last'), u.s('dept'), u.s('status')].map(_csvCell).join(','));
    Clipboard.setData(ClipboardData(text: ['Question,Times asked,Last asked,Department,Status', ...rows].join('\n')));
    store.toast('Copied as CSV');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fb = store.feedback;
    final up = fb.where((f) => f.s('rating') == 'up').length;
    final helpfulPct = fb.isEmpty ? 0 : (up / fb.length * 100).round();
    final openUnans = store.unanswered.where((u) => u.s('status') != 'Resolved').length;
    final fbs = fb.where((f) => fbFilter == 'all' || f.s('rating') == 'down').toList();
    final weeks = <Pt>[
      for (final w in (sum?['weeks'] as List? ?? const [])) (label: str((w as Map)['label']), value: (w['value'] as num?)?.toInt() ?? 0),
    ];
    Widget kpi(String label, String value, String small) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: muted(context), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              Text(small, style: xs(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );

    return AppScaffold(
      route: '/reports',
      title: 'Reports & Feedback',
      actions: [IconButton(tooltip: 'Copy unanswered questions as CSV', icon: const Icon(Icons.copy_all), onPressed: copyCsv)],
      body: RefreshIndicator(
        onRefresh: store.load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: gap([
          Text('Usage figures, questions the records could not answer, and feedback that needs follow-up.', style: muted(context)),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.3,
            children: [
              kpi('Questions this month', sum == null ? '—' : '${sum!['month']}', 'Asked by everyone, across all conversations'),
              kpi('Answered with citations', sum == null ? '—' : '${sum!['cited']}%', 'Rest: clarifications or no record'),
              kpi('Unanswered (open)', '$openUnans', 'Need a document uploaded'),
              kpi('Rated helpful', '$helpfulPct%', '${fb.length} ratings'),
            ],
          ),
          const _QualityCard(),
          Section(title: 'Questions per week', sub: 'Last 8 weeks', padded: true, children: [
            if (sum != null) BarChart(points: weeks) else if (sumFailed) Text("Couldn't load the figures.", style: muted(context)) else const Loading(),
          ]),
          Section(
            title: 'Open conflicts between documents',
            children: store.conflicts.isEmpty
                ? [const EmptyBox('No open conflicts.')]
                : [
                    for (final cf in store.conflicts)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.warning_amber_rounded, size: 18, color: p.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(cf.s('topic'), style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                '${strs(cf.j['docs']).map((id) => store.getDoc(id)?.ref ?? 'a removed document').join(' vs ')} · reported ${fmtD(cf.s('reported'))} by ${cf.s('by')}',
                                style: xs(context),
                              ),
                              const SizedBox(height: 6),
                              Wrap(spacing: 8, runSpacing: 6, children: [
                                if (strs(cf.j['docs']).length >= 2)
                                  btn('Compare', () => showCompare(context, strs(cf.j['docs'])[0], strs(cf.j['docs'])[1], cf.s('topic'))),
                                if (cf.s('status') == 'Open') btn('Mark resolved', () => resolveC(cf), icon: Icons.check) else const Pill('Resolved', kind: 'ok'),
                              ]),
                            ]),
                          ),
                        ]),
                      ),
                  ],
          ),
          Section(
            title: 'Unanswered questions',
            sub: 'Count shows how often it was asked',
            children: store.unanswered.isEmpty
                ? [const EmptyBox('No unanswered questions.')]
                : [
                    for (final u in store.unanswered)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Text(u.s('q'), style: const TextStyle(fontWeight: FontWeight.w500))),
                            const SizedBox(width: 8),
                            Pill(u.s('status'), kind: u.s('status') == 'Resolved' ? 'ok' : u.s('status') == 'Open' ? 'warn' : 'info'),
                          ]),
                          if (u.s('note').isNotEmpty)
                            Text('${u.s('requested_by').isNotEmpty ? '${u.s('requested_by')}: ' : ''}${u.s('note')}', style: xs(context)),
                          const SizedBox(height: 2),
                          Text('Asked ${u.j['count'] ?? 0}× · last ${fmtD(u.s('last'))} · ${u.s('dept')}', style: xs(context)),
                          if (u.s('status') != 'Resolved')
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(spacing: 6, runSpacing: 6, children: [
                                btn('Assign', () => showSheet(context, title: 'Assign question', builder: (_) => _Assign(u: u))),
                                btn('Request document', () => showRequestDoc(context, u.s('q'), dept: u.s('dept'))),
                                btn('Resolve', () => resolveU(u), icon: Icons.check),
                              ]),
                            ),
                        ]),
                      ),
                  ],
          ),
          Section(
            title: 'Answer feedback',
            trailing: null,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Seg<String>(
                  options: [('all', 'All (${fb.length})', null), ('down', 'Not helpful (${fb.length - up})', null)],
                  value: fbFilter,
                  onChanged: (v) => setState(() => fbFilter = v),
                ),
              ),
              if (fbs.isEmpty) const EmptyBox('No feedback yet.'),
              for (final f in fbs)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(f.s('rating') == 'up' ? Icons.thumb_up_outlined : Icons.thumb_down_outlined, size: 17, color: f.s('rating') == 'up' ? p.green : p.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.s('q'), style: const TextStyle(fontWeight: FontWeight.w500)),
                        if (f.s('reason').isNotEmpty || f.s('comment').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              if (f.s('reason').isNotEmpty) TagChip(f.s('reason')),
                              if (f.s('comment').isNotEmpty) Text(f.s('comment'), style: sm(context)),
                            ]),
                          ),
                        Text('${f.s('who')} · ${fmtD(f.s('when'))}', style: xs(context)),
                      ]),
                    ),
                  ]),
                ),
            ],
          ),
        ], 14)),
      ),
    );
  }
}

class _Assign extends StatefulWidget {
  const _Assign({required this.u});
  final Rec u;
  @override
  State<_Assign> createState() => _AssignState();
}

class _AssignState extends State<_Assign> {
  late String dept = widget.u.s('dept');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('“${widget.u.s('q')}”', style: sm(context)),
        const SizedBox(height: 12),
        Field(label: 'Department', child: Select(value: dept, items: store.lists.depts, onChanged: (v) => setState(() => dept = v))),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Assign', () async {
            if (await store.save('unanswered', widget.u.copy({'dept': dept, 'status': 'Assigned'}))) {
              if (context.mounted) Navigator.pop(context);
              store.toast('Assigned to $dept');
            }
          }, primary: true),
        ]),
      ]);
}

/// Results of the automatic answer-quality test (questions written from random paragraphs).
class _QualityCard extends StatefulWidget {
  const _QualityCard();
  @override
  State<_QualityCard> createState() => _QualityCardState();
}

class _QualityCardState extends State<_QualityCard> {
  Json? data;
  Timer? timer;
  bool? _running;

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

  void tick() {
    api.quality().then((d) {
      if (!mounted) return;
      setState(() => data = d);
      final running = d['running'] == true;
      if (running != _running) {
        _running = running;
        timer?.cancel();
        timer = Timer.periodic(Duration(seconds: running ? 8 : 60), (_) => tick());
      }
    }, onError: (_) {});
  }

  Future<void> run(bool fresh) async {
    try {
      await api.runQuality(fresh);
      store.toast('Test started. It takes a few minutes.');
      tick();
    } catch (e) {
      store.toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = data?['latest'] as Map?;
    final running = data?['running'] == true;
    final figures = [
      ('Right paragraph found', r?['paragraph_found'], 'search found the paragraph the question was written from'),
      ('Right document cited', r?['cited_right_document'], 'the answer cited that document'),
      ('Answered correctly', r?['answered_correctly'], 'judged against the expected answer'),
    ];
    final byStyle = Map<String, dynamic>.from(r?['correct_by_style'] as Map? ?? {});
    final misses = (r?['misses'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Section(
      title: 'Answer quality',
      sub: r != null ? 'Automatic test of ${r['questions']} questions · ${fmtDateTime(str(r['at']))}' : 'No test has been run yet',
      padded: true,
      children: [
        if (store.isAdmin)
          running
              ? const Row(children: [Spinner(size: 15), SizedBox(width: 8), Text('Running…')])
              : Wrap(spacing: 8, runSpacing: 8, children: [
                  btn('Run test', () => run(false), icon: Icons.refresh),
                  Tooltip(message: 'Write new questions from the documents as they are now', child: btn('New questions', () => run(true))),
                ]),
        if (r == null)
          Text(store.isAdmin ? 'Run a test to measure how well the assistant answers from your documents.' : 'An administrator can run the test.', style: muted(context))
        else ...[
          for (final (label, v, hint) in figures)
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(hint, style: xs(context)),
                ]),
              ),
              Text(v == null ? '—' : '$v%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ]),
          if (byStyle.isNotEmpty)
            Text('Correct by how the question was asked: ${byStyle.entries.map((e) => '${e.key} ${e.value}%').join(' · ')}', style: sm(context)),
          Text(
            'Questions are written by the AI from random paragraphs, so they are usually clearer than real ones: treat these figures as the best case. '
            'Answers people rate 👎 show where real questions go wrong.',
            style: xs(context),
          ),
          if (misses.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Answers judged wrong (${misses.length})', style: sm(context)),
              children: [
                for (final m in misses)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border.all(color: context.pal.line), borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(str(m['question']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Expected: ${str(m['answer'])}', style: sm(context)),
                      Text('Answer given: ${str(m['got'])}', style: xs(context)),
                      Text('Paragraph found: ${m['found'] == true ? 'Yes' : 'No'}', style: xs(context)),
                    ]),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}
