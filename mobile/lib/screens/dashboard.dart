import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/answer.dart';
import '../widgets/charts.dart';
import '../widgets/ui.dart';
import '../widgets/shell.dart';
import '../widgets/viewer.dart';

class DashboardScreen extends StoreScreen {
  const DashboardScreen({super.key});

  @override
  Widget buildScreen(BuildContext context) {
    final ds = store.permitted;
    final active = ds.where((d) => d.status == 'Active').length;
    final pending = ds.where((d) => d.status == 'Pending').length;
    final history = ds.where((d) => notInForce.contains(d.status)).length;
    final newThisWeek = ds.where((d) => d.status == 'Active' && daysTo(d.date) >= -7 && daysTo(d.date) <= 0).length;
    final upcoming = store.deadlines.where((x) => !x.done && daysTo(x.date) >= 0).toList()..sort((a, b) => a.date.compareTo(b.date));
    final expiring = ds.where((d) => d.status == 'Active' && d.expiry.isNotEmpty && daysTo(d.expiry) >= 0 && daysTo(d.expiry) <= 30).toList()
      ..sort((a, b) => a.expiry.compareTo(b.expiry));
    final openUnans = store.unanswered.where((u) => u.s('status') != 'Resolved').toList();

    // Uploads per month, last 6 months.
    final now = DateTime.now();
    final months = [for (var i = 0; i < 6; i++) DateTime(now.year, now.month - 5 + i, 1)];
    final uploads = <Pt>[
      for (final m in months) (label: monthShort(m), value: ds.where((d) => d.uploadedOn.length >= 7 && d.uploadedOn.substring(0, 7) == isoOf(m).substring(0, 7)).length),
    ];
    // Documents per subject, top 6.
    final tagCount = <String, int>{};
    for (final d in ds) {
      for (final t in d.tags) {
        tagCount[t] = (tagCount[t] ?? 0) + 1;
      }
    }
    final subjects = (tagCount.entries.toList()..sort((a, b) => b.value - a.value)).take(6).map((e) => (label: e.key, value: e.value)).toList();
    // Deadlines due per week, next 6 weeks.
    final weeks = <Pt>[
      for (var i = 0; i < 6; i++) (label: i == 0 ? 'Now' : '+${i}w', value: upcoming.where((x) => daysTo(x.date) ~/ 7 == i).length),
    ];
    final depts = ds.map((d) => d.dept).toSet().length;

    return AppScaffold(
      route: '/',
      title: 'Dashboard',
      body: RefreshIndicator(
        onRefresh: store.load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: gap([
          _Hero(docs: ds.length, depts: depts),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: [
              _Stat('Total documents', ds.length, '/library'),
              _Stat('Active', active, '/library?status=Active'),
              store.canUpload
                  ? _Stat('Pending approvals', pending, store.canApprove ? '/review' : '/library?status=Pending')
                  : _Stat('Published this week', newThisWeek, '/library?status=Active'),
              _Stat('No longer in force', history, '/library?status=history'),
            ],
          ),
          if (store.canUpload) const _ForYou(),
          _DeadlinePanel(upcoming: upcoming),
          Row(children: [
            const Expanded(child: Text('Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            if (store.canApprove) TextButton(onPressed: () => context.go('/reports'), child: const Text('Reports ›')),
          ]),
          _Tile(title: 'Uploads', chip: 'Last 6 months', value: uploads.last.value, sub: 'this month', child: AreaChart(points: uploads)),
          _Tile(
            title: 'Documents by subject',
            chip: 'Top subjects',
            child: subjects.isEmpty
                ? Text('No subject tags yet. Tags are added when documents are uploaded or edited.', style: muted(context))
                : HBars(points: subjects, onTap: (t) => context.go('/library?subject=${Uri.encodeComponent(t)}')),
          ),
          _Tile(
            title: 'Upcoming deadlines',
            chip: 'Next 6 weeks',
            value: upcoming.isEmpty ? null : upcoming.length,
            sub: '${upcoming.where((x) => daysTo(x.date) <= 7).length} this week',
            child: upcoming.isEmpty
                ? Text('Nothing due. Open a document and choose Find deadlines to add the dates it sets.', style: muted(context))
                : BarChart(points: weeks, thin: true),
          ),
          _Tile(
            title: 'Expiring soon',
            chip: 'Next 30 days',
            value: expiring.isEmpty ? null : expiring.length,
            sub: expiring.length == 1 ? 'document' : 'documents',
            child: expiring.isEmpty
                ? Text('No active document expires in the next 30 days. Expired documents are kept and used only as history.', style: muted(context))
                : Column(children: [
                    for (final d in expiring.take(5))
                      InkWell(
                        onTap: () => context.push('/library/${d.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Expanded(child: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: sm(context))),
                            Text(daysTo(d.expiry) == 0 ? 'today' : 'in ${plural(daysTo(d.expiry), 'day')}', style: xs(context)),
                          ]),
                        ),
                      ),
                  ]),
          ),
          Section(
            title: 'Recent documents',
            trailing: TextButton(onPressed: () => context.go('/library'), child: const Text('Library ›')),
            children: ds.isEmpty
                ? [const EmptyBox('No documents yet.')]
                : [
                    for (final d in ([...ds]..sort((a, b) => b.uploadedOn.compareTo(a.uploadedOn))).take(5))
                      Row2(
                        lead: Ft(d.fileType),
                        title: d.title,
                        meta: '${fmtD(d.uploadedOn)} · ${d.uploadedBy}',
                        trail: Pill(d.status),
                        onTap: () => context.push('/library/${d.id}'),
                      ),
                  ],
          ),
          Section(
            title: 'Recent conversations',
            trailing: TextButton(onPressed: () => context.go('/saved'), child: const Text('Saved ›')),
            children: store.chats.isEmpty
                ? [const EmptyBox('No conversations yet. Ask a question to start.')]
                : [
                    for (final c in store.chats.take(5))
                      Row2(
                        lead: const Avatar(icon: Icons.chat_bubble_outline, size: 30),
                        title: c.title,
                        meta: '${AppStore.chatGroup(c)} · ${plural((c.msgs.length / 2).ceil(), 'question')}',
                        trail: _lastLabel(c).isEmpty ? null : Pill(_lastLabel(c), kind: kindInfo[_lastLabel(c)] ?? 'mute'),
                        onTap: () => context.go('/ask?c=${c.id}'),
                      ),
                  ],
          ),
          if (store.canApprove)
            Section(
              title: 'Questions the records could not answer',
              trailing: Text('${openUnans.length} open', style: xs(context)),
              children: openUnans.isEmpty
                  ? [const EmptyBox('Every question so far was answered from the records.')]
                  : [
                      for (final u in openUnans.take(5))
                        Row2(
                          lead: const Avatar(icon: Icons.search, size: 30),
                          title: u.s('q'),
                          meta: 'Asked ${u.j['count']}× · ${u.s('dept')}',
                          trail: const Icon(Icons.chevron_right),
                          onTap: () => context.go('/ask?q=${Uri.encodeComponent(u.s('q'))}'),
                        ),
                    ],
            ),
        ], 14)),
      ),
    );
  }

  static String _lastLabel(Chat c) => c.msgs.reversed.where((m) => !m.isUser).firstOrNull?.answer?.label ?? '';
}

class _Hero extends StatefulWidget {
  const _Hero({required this.docs, required this.depts});
  final int docs, depts;
  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final q = TextEditingController();
  void ask() {
    final t = q.text.trim();
    if (t.isNotEmpty) context.go('/ask?q=${Uri.encodeComponent(t)}');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final asked = [for (final c in store.chats) for (final m in c.msgs) if (m.isUser) m.text];
    final recentQs = asked.reversed.toSet().take(3).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: p.heroBg, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${greeting()}, ${store.myName.split(' ').first}', style: TextStyle(color: p.heroFg, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${fmtD(todayIso())} · ${plural(widget.docs, 'document')} you can open, across ${plural(widget.depts, 'department')}.',
            style: TextStyle(color: p.heroFg.withValues(alpha: .8), fontSize: 13)),
        const SizedBox(height: 14),
        TextField(
          controller: q,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => ask(),
          style: TextStyle(color: p.fg),
          decoration: InputDecoration(
            hintText: 'Ask anything, in Hindi or English',
            suffixIcon: IconButton(icon: Icon(Icons.auto_awesome, color: p.accent), onPressed: ask, tooltip: 'Ask'),
          ),
        ),
        if (recentQs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in recentQs)
              InkWell(
                onTap: () => context.go('/ask?q=${Uri.encodeComponent(t)}'),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)),
                  child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.heroFg, fontSize: 12.5)),
                ),
              ),
          ]),
        ],
        if (store.canUpload) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/upload'),
              icon: const Icon(Icons.upload_outlined, size: 17),
              label: const Text('Upload'),
              style: OutlinedButton.styleFrom(foregroundColor: p.heroFg, side: BorderSide(color: p.heroFg.withValues(alpha: .4))),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.href);
  final String label;
  final int value;
  final String href;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go(href),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(label, style: muted(context), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(fmtNum(value), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.chip, this.value, this.sub, required this.child});
  final String title, chip;
  final int? value;
  final String? sub;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
              Pill(chip, kind: 'mute'),
            ]),
            const SizedBox(height: 12),
            child,
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Text(sub ?? '', style: muted(context)),
                ]),
              ),
          ]),
        ),
      );
}

/// What is waiting for this person, by role. Hidden for Viewers, who have no queue.
class _ForYou extends StatefulWidget {
  const _ForYou();
  @override
  State<_ForYou> createState() => _ForYouState();
}

class _ForYouState extends State<_ForYou> {
  String? key;
  int? mfa;
  num? score;
  bool scoreKnown = false;

  @override
  void initState() {
    super.initState();
    if (!store.isAdmin) return;
    api.keyStatus().then((k) => mounted ? setState(() => key = '${k['source']}') : null, onError: (_) {});
    api.mfaUsers().then((m) => mounted ? setState(() => mfa = m.length) : null, onError: (_) {});
    api.quality().then((q) {
      if (mounted) {
        setState(() {
          scoreKnown = true;
          score = (q['latest'] as Map?)?['answered_correctly'] as num?;
        });
      }
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ds = store.permitted;
    final mine = ds.where((d) => d.uploaderId == store.session?.loginId).toList();
    final tasks = <(String, IconData, String, String, String)>[]; // href, icon, title, meta, action
    void add(int n, (String, IconData, String, String, String) t) {
      if (n > 0) tasks.add(t);
    }

    final pending = ds.where((d) => d.status == 'Pending').length;
    final soon = ds.where((d) => d.status == 'Active' && d.expiry.isNotEmpty && daysTo(d.expiry) >= 0 && daysTo(d.expiry) <= 7).length;
    if (store.canApprove) {
      add(pending, ('/review', Icons.check, '${plural(pending, 'document')} waiting for review', 'Approve, request changes or reject', 'Review'));
      add(soon, ('/library?status=Active', Icons.schedule, '${plural(soon, 'document')} ${soon == 1 ? 'expires' : 'expire'} this week', 'Publish a replacement if the rule still applies', 'Open'));
    }
    final changes = mine.where((d) => d.status == 'Changes requested').length;
    final drafts = mine.where((d) => d.status == 'Draft').length;
    final unsure = ds.where((d) => d.unsure.isNotEmpty).length;
    add(changes, ('/library?status=Changes requested', Icons.warning_amber_rounded, '${plural(changes, 'upload')} need changes', 'An approver asked for corrections', 'Fix'));
    add(drafts, ('/library?status=Draft', Icons.description_outlined, '${plural(drafts, 'draft')} not submitted', 'Submit them for approval when ready', 'Open'));
    add(unsure, ('/library?check=1', Icons.search, '${plural(unsure, 'scan')} need a text check', 'Words the OCR was unsure of, highlighted', 'Check'));
    if (store.isAdmin) {
      add(key == 'none' ? 1 : 0, ('/admin', Icons.warning_amber_rounded, 'No OpenAI key', 'Search and answers stop working until one is set', 'Set key'));
      final leaders = store.users.where((u) => u.active && const ['Administrator', 'Approver'].contains(u.role)).length;
      if (mfa != null && mfa! < leaders) {
        tasks.add(('/admin', Icons.verified_user_outlined, 'Two-step verification on for $mfa of $leaders Administrators and Approvers', 'Accounts that can publish should use it', 'Users'));
      }
      if (scoreKnown) {
        tasks.add(('/reports', Icons.auto_awesome, score == null ? 'Answer quality not tested yet' : 'Answer quality: $score% correct in the last test',
            'Automatic test with questions from your documents', 'Reports'));
      }
    }
    return Section(
      title: 'For you',
      trailing: tasks.isEmpty ? null : Text(plural(tasks.length, 'item'), style: xs(context)),
      children: tasks.isEmpty
          ? [const EmptyBox('Nothing is waiting for you.')]
          : [
              for (final t in tasks)
                Row2(
                  lead: Avatar(icon: t.$2, size: 30),
                  title: t.$3,
                  meta: t.$4,
                  trail: Text(t.$5, style: TextStyle(color: context.pal.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                  onTap: () => context.go(t.$1),
                ),
            ],
    );
  }
}

/// Month calendar with deadline days marked, the next few deadlines, and a link to all.
class _DeadlinePanel extends StatefulWidget {
  const _DeadlinePanel({required this.upcoming});
  final List<Deadline> upcoming;
  @override
  State<_DeadlinePanel> createState() => _DeadlinePanelState();
}

class _DeadlinePanelState extends State<_DeadlinePanel> {
  DateTime cursor = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final y = cursor.year, m = cursor.month;
    final start = (DateTime(y, m, 1).weekday + 6) % 7; // Monday first
    final dim = DateTime(y, m + 1, 0).day;
    final today = todayIso();
    final byDay = <String, List<Deadline>>{};
    for (final x in store.deadlines) {
      (byDay[x.date] ??= []).add(x);
    }
    void show(Deadline x) => openViewer(context, ViewerArgs(doc: x.doc, page: x.page, block: x.block, quote: x.quote));
    final cells = [for (var i = 0; i < ((start + dim) / 7).ceil() * 7; i++) DateTime(y, m, i - start + 1)];
    final fg = p.heroFg;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.heroBg, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Deadlines', style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600))),
          IconButton(onPressed: () => setState(() => cursor = DateTime(y, m - 1, 1)), icon: Icon(Icons.chevron_left, color: fg), tooltip: 'Previous month'),
          IconButton(onPressed: () => setState(() => cursor = DateTime(y, m + 1, 1)), icon: Icon(Icons.chevron_right, color: fg), tooltip: 'Next month'),
        ]),
        Text(monthYear(cursor), style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 13)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.25,
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Center(child: Text(d, style: TextStyle(color: fg.withValues(alpha: .55), fontSize: 11))),
            for (final d in cells)
              () {
                final iso = isoOf(d);
                final list = byDay[iso];
                final out = d.month != m;
                return InkWell(
                  onTap: list == null ? null : () => show(list.first),
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: iso == today ? fg : (list != null ? p.chart.withValues(alpha: .45) : null),
                      ),
                      child: Text('${d.day}',
                          style: TextStyle(fontSize: 12, color: iso == today ? p.heroBg : fg.withValues(alpha: out ? .3 : .9), fontWeight: list != null ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  ),
                );
              }(),
          ],
        ),
        const SizedBox(height: 8),
        Text('COMING UP', style: TextStyle(color: fg.withValues(alpha: .6), fontSize: 11, letterSpacing: .8)),
        const SizedBox(height: 6),
        if (widget.upcoming.isEmpty) Text('Nothing due.', style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 13)),
        for (final x in widget.upcoming.take(4))
          InkWell(
            onTap: () => show(x),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                DateBox(x.date, inverse: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.title, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text('${store.getDoc(x.doc)?.ref ?? ''} · ${daysTo(x.date) == 0 ? 'today' : 'in ${plural(daysTo(x.date), 'day')}'}',
                        style: TextStyle(color: fg.withValues(alpha: .65), fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => context.go('/deadlines'),
          style: OutlinedButton.styleFrom(foregroundColor: fg, side: BorderSide(color: fg.withValues(alpha: .35))),
          child: const Text('View all deadlines'),
        ),
      ]),
    );
  }
}
