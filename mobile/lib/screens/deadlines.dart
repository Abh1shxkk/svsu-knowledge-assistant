import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/modals.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';
import '../widgets/viewer.dart';

final _groups = <(String, bool Function(Deadline))>[
  ('This week', (x) => !x.done && daysTo(x.date) >= 0 && daysTo(x.date) <= 7),
  ('Later this month and next', (x) => !x.done && daysTo(x.date) > 7),
  ('Overdue', (x) => !x.done && daysTo(x.date) < 0),
  ('Completed', (x) => x.done),
];

class DeadlinesScreen extends StatefulWidget {
  const DeadlinesScreen({super.key});
  @override
  State<DeadlinesScreen> createState() => _DeadlinesScreenState();
}

class _DeadlinesScreenState extends State<DeadlinesScreen> with StoreListener {
  String filter = 'upcoming';
  String dept = '';
  String view = 'list';
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  void show(Deadline x) => openViewer(context, ViewerArgs(doc: x.doc, page: x.page, block: x.block, quote: x.quote));

  Future<void> toggleDone(Deadline x) async {
    if (await store.save('deadlines', x.copy({'done': !x.done}))) store.toast(x.done ? 'Marked as not done' : 'Marked as done');
  }

  Future<void> del(Deadline x) async {
    if (await confirm(context, title: 'Delete deadline?', body: Text('Delete “${x.title}” (due ${fmtD(x.date)})? The document is not changed.'), action: 'Delete')) {
      if (await store.remove('deadlines', x.id)) store.toast('Deadline deleted');
    }
  }

  Widget item(Deadline x) {
    final doc = store.getDoc(x.doc);
    final rem = store.reminders.where((r) => r.s('deadline') == x.id).firstOrNull;
    final days = (rem?.j['days'] as num?)?.toInt() ?? 0;
    final upl = store.canUpload;
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DateBox(x.date),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text('${x.owner} · ${x.aud}', style: xs(context)),
              InkWell(
                onTap: () => show(x),
                child: Text('${doc?.ref ?? 'Document'}, p.${x.page}', style: TextStyle(fontSize: 12, color: p.accent, decoration: TextDecoration.underline)),
              ),
              if (x.conflict) Text('Conflicts with another document', style: TextStyle(fontSize: 12, color: p.red)),
              if (rem != null)
                Row(children: [
                  Icon(Icons.notifications_none, size: 13, color: p.fg3),
                  Flexible(child: Text(' ${days > 0 ? '${plural(days, 'day')} before' : 'on the day'}', style: xs(context))),
                ]),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(right: 8), child: Due(x.date, done: x.done)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (!x.done)
            IconButton(
              tooltip: 'Remind me',
              icon: Icon(rem != null ? Icons.notifications_active : Icons.notifications_none, size: 20, color: rem != null ? p.accent : null),
              onPressed: () => showReminder(context, x),
            ),
          if (upl) ...[
            TextButton.icon(
              onPressed: () => toggleDone(x),
              icon: Icon(x.done ? Icons.undo : Icons.check, size: 17, color: x.done ? null : p.green),
              label: Text(x.done ? 'Undo' : 'Done', style: TextStyle(color: x.done ? null : p.green)),
            ),
            IconButton(tooltip: 'Edit deadline', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: () => showDeadline(context, deadline: x)),
            IconButton(tooltip: 'Delete deadline', icon: const Icon(Icons.delete_outline, size: 19), onPressed: () => del(x)),
          ],
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    var ds = store.deadlines..sort((a, b) => a.date.compareTo(b.date));
    if (dept.isNotEmpty) ds = ds.where((x) => x.dept == dept).toList();
    final list = switch (filter) {
      'upcoming' => ds.where((x) => !x.done && daysTo(x.date) >= 0).toList(),
      'overdue' => ds.where((x) => !x.done && daysTo(x.date) < 0).toList(),
      'done' => ds.where((x) => x.done).toList(),
      _ => ds,
    };
    return AppScaffold(
      route: '/deadlines',
      title: 'Actions & Deadlines',
      fab: store.canUpload
          ? FloatingActionButton.extended(heroTag: 'adddl', onPressed: () => showDeadline(context), icon: const Icon(Icons.add), label: const Text('Add deadline'))
          : null,
      body: RefreshIndicator(
        onRefresh: store.load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: gap([
          Text('Dates and required actions taken from documents. Each item links to the passage it came from.', style: muted(context)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Seg<String>(
              options: const [('upcoming', 'Upcoming', null), ('overdue', 'Overdue', null), ('done', 'Completed', null), ('all', 'All', null)],
              value: filter,
              onChanged: (v) => setState(() => filter = v),
            ),
          ),
          Select(value: dept, items: store.lists.depts, empty: 'All departments', onChanged: (v) => setState(() => dept = v)),
          Seg<String>(
            options: const [('list', 'List', Icons.view_list), ('cal', 'Calendar', Icons.calendar_month)],
            value: view,
            onChanged: (v) => setState(() => view = v),
          ),
          if (view == 'list') ...[
            if (list.isEmpty) const Card(child: EmptyBox('No deadlines match these filters.')),
            for (final (g, fn) in _groups)
              if (list.where(fn).isNotEmpty)
                Section(
                  title: g,
                  trailing: Text('${list.where(fn).length}', style: xs(context)),
                  children: [for (final x in list.where(fn)) item(x)],
                ),
          ] else
            _Calendar(
              month: month,
              deadlines: ds,
              onNav: (d) => setState(() => month = DateTime(month.year, month.month + d, 1)),
              onShow: show,
            ),
        ], 12)),
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.month, required this.deadlines, required this.onNav, required this.onShow});
  final DateTime month;
  final List<Deadline> deadlines;
  final void Function(int) onNav;
  final void Function(Deadline) onShow;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final start = (month.weekday + 6) % 7;
    final dim = DateTime(month.year, month.month + 1, 0).day;
    final today = todayIso();
    final cells = ((start + dim) / 7).ceil() * 7;
    final selectedMonth = deadlines.where((x) => x.date.startsWith(isoOf(month).substring(0, 7))).toList();
    return Section(
      title: monthYear(month),
      sub: 'Red items conflict with another document',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: () => onNav(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous month'),
        IconButton(onPressed: () => onNav(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next month'),
      ]),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: .8,
            children: [
              for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) Center(child: Text(d, style: xs(context))),
              for (var i = 0; i < cells; i++)
                () {
                  final dt = DateTime(month.year, month.month, i - start + 1);
                  final iso = isoOf(dt);
                  final evs = deadlines.where((x) => x.date == iso).toList();
                  final out = dt.month != month.month;
                  return InkWell(
                    onTap: evs.isEmpty ? null : () => evs.length == 1 ? onShow(evs.first) : _pick(context, evs),
                    child: Container(
                      margin: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: iso == today ? p.accent : p.line),
                        color: out ? p.surface2 : null,
                      ),
                      child: Column(children: [
                        Text('${dt.day}', style: TextStyle(fontSize: 12, color: out ? p.fg3 : p.fg, fontWeight: iso == today ? FontWeight.w700 : null)),
                        const Spacer(),
                        Wrap(spacing: 2, runSpacing: 2, children: [
                          for (final x in evs.take(3))
                            Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: x.conflict ? p.red : x.done ? p.fg3 : p.accent)),
                        ]),
                        const SizedBox(height: 4),
                      ]),
                    ),
                  );
                }(),
            ],
          ),
        ),
        for (final x in selectedMonth)
          Row2(
            lead: DateBox(x.date),
            title: x.title,
            meta: x.conflict ? 'Conflicts with another document' : (x.done ? 'Completed' : '${x.owner} · ${x.aud}'),
            onTap: () => onShow(x),
          ),
      ],
    );
  }

  void _pick(BuildContext context, List<Deadline> evs) => showSheet(context, title: fmtD(evs.first.date), builder: (ctx) => Column(children: [
        for (final x in evs)
          ListTile(
            title: Text(x.title),
            subtitle: Text(x.done ? 'Completed' : x.owner),
            onTap: () {
              Navigator.pop(ctx);
              onShow(x);
            },
          ),
      ]));
}
