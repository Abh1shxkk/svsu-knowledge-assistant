import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';

class _Lib {
  String q = '', subject = '', dept = '', aud = '', type = '', status = '', vis = '', from = '', to = '';
  bool check = false;
  String sort = 'new';
  bool grid = false;
  int get active => [subject, dept, aud, type, status, vis, from, to].where((x) => x.isNotEmpty).length + (check ? 1 : 0);
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.params = const {}});
  final Map<String, String> params;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with StoreListener {
  // Seed search and status from the link (e.g. a dashboard figure or the search box).
  late final L = _Lib()
    ..q = widget.params['q'] ?? ''
    ..status = widget.params['status'] ?? ''
    ..subject = widget.params['subject'] ?? ''
    ..check = widget.params.containsKey('check');
  late final qc = TextEditingController(text: L.q);
  ({String q, Set<String> ids})? found;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (L.q.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    qc.dispose();
    super.dispose();
  }

  /// Searching the text inside documents happens on the server; the details are matched here too.
  void _search() {
    _debounce?.cancel();
    final q = L.q.trim().toLowerCase();
    if (q.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      api.search(q).then((ids) {
        if (mounted) setState(() => found = (q: q, ids: ids.toSet()));
      }, onError: (_) {
        if (mounted) setState(() => found = (q: q, ids: <String>{}));
      });
    });
  }

  List<Doc> get results {
    final q = L.q.trim().toLowerCase();
    final hits = found?.q == q ? found!.ids : null;
    var ds = store.permitted;
    if (q.isNotEmpty) {
      ds = ds.where((d) => (hits?.contains(d.id) ?? false) || '${d.title} ${d.ref} ${d.description} ${d.tags.join(' ')} ${d.dept}'.toLowerCase().contains(q)).toList();
    }
    if (L.subject.isNotEmpty) ds = ds.where((d) => d.tags.contains(L.subject)).toList();
    if (L.dept.isNotEmpty) ds = ds.where((d) => d.dept == L.dept).toList();
    if (L.aud.isNotEmpty) ds = ds.where((d) => d.audience.contains(L.aud)).toList();
    if (L.type.isNotEmpty) ds = ds.where((d) => d.type == L.type).toList();
    if (L.status.isNotEmpty) {
      ds = ds.where((d) => L.status == 'history'
          ? notInForce.contains(d.status)
          : L.status == 'Superseded'
              ? const ['Superseded', 'Withdrawn'].contains(d.status)
              : d.status == L.status).toList();
    }
    if (L.vis.isNotEmpty) ds = ds.where((d) => d.visibility == L.vis).toList();
    if (L.from.isNotEmpty) ds = ds.where((d) => d.date.compareTo(L.from) >= 0).toList();
    if (L.to.isNotEmpty) ds = ds.where((d) => d.date.compareTo(L.to) <= 0).toList();
    final sorters = <String, int Function(Doc, Doc)>{
      'new': (a, b) => b.date.compareTo(a.date),
      'old': (a, b) => a.date.compareTo(b.date),
      'title': (a, b) => a.title.compareTo(b.title),
      'eff': (a, b) => b.effective.compareTo(a.effective),
    };
    ds.sort(sorters[L.sort]);
    // Scans with words OCR was unsure of, the most first, to correct with Edit text.
    if (L.check) ds = ds.where((d) => d.unsure.isNotEmpty).toList()..sort((a, b) => b.unsure.length - a.unsure.length);
    return ds;
  }

  void clear() => setState(() {
        final keepQ = L.q;
        L
          ..subject = ''
          ..dept = ''
          ..aud = ''
          ..type = ''
          ..status = ''
          ..vis = ''
          ..from = ''
          ..to = ''
          ..check = false;
        L.q = keepQ;
      });

  void filters() {
    final l = store.lists;
    final statuses = [
      'Active',
      if (store.canUpload) ...['Draft', 'Pending', 'Changes requested', if (store.canApprove) 'Rejected'],
      'Superseded', 'Withdrawn', 'Expired', 'history',
    ];
    showSheet(context, title: 'Filters', builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
          void up(VoidCallback f) {
            set(f);
            setState(() {});
          }

          Widget sel(String label, String value, List<String> items, void Function(String) on, [Map<String, String>? labels]) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Field(label: label, child: Select(value: value, items: items, empty: 'Any', labels: labels, onChanged: (v) => up(() => on(v)))),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            sel('Subject', L.subject, l.tags, (v) => L.subject = v),
            sel('Department', L.dept, l.depts, (v) => L.dept = v),
            sel('Audience', L.aud, l.auds, (v) => L.aud = v),
            sel('Document type', L.type, l.types, (v) => L.type = v),
            sel('Status', L.status, statuses, (v) => L.status = v, {'history': 'No longer in force (all three)'}),
            sel('Visibility', L.vis, l.vis, (v) => L.vis = v),
            Row(children: [
              Expanded(child: Field(label: 'Dated from', child: DateInput(value: L.from, clearable: true, onChanged: (v) => up(() => L.from = v)))),
              const SizedBox(width: 10),
              Expanded(child: Field(label: 'Dated to', child: DateInput(value: L.to, clearable: true, onChanged: (v) => up(() => L.to = v)))),
            ]),
            if (store.canUpload)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: L.check,
                onChanged: (v) => up(() => L.check = v ?? false),
                title: const Text('Needs a text check'),
                subtitle: Text('Scans with words the OCR was unsure of', style: xs(ctx)),
              ),
            SheetFoot(children: [
              btn('Clear filters', () => up(clear)),
              btn('Show ${plural(results.length, 'document')}', () => Navigator.pop(ctx), primary: true),
            ]),
          ]);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final ds = results;
    return AppScaffold(
      route: '/library',
      title: 'Document Library',
      fab: store.canUpload
          ? FloatingActionButton.extended(heroTag: 'up', onPressed: () => context.go('/upload'), icon: const Icon(Icons.upload_outlined), label: const Text('Upload'))
          : null,
      body: RefreshIndicator(
        onRefresh: store.load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Every official letter, notice, circular and policy you are permitted to see. Superseded and withdrawn records stay here as history.',
                    style: muted(context)),
                const SizedBox(height: 10),
                TextField(
                  controller: qc,
                  onChanged: (v) {
                    setState(() => L.q = v);
                    _search();
                  },
                  decoration: InputDecoration(
                    hintText: 'Search title, reference number or text inside',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: L.q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() {
                              qc.clear();
                              L.q = '';
                            }),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: filters,
                    icon: Badge(isLabelVisible: L.active > 0, label: Text('${L.active}'), child: const Icon(Icons.filter_list, size: 18)),
                    label: const Text('Filters'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Select(
                      value: L.sort,
                      items: const ['new', 'old', 'eff', 'title'],
                      labels: const {'new': 'Newest first', 'old': 'Oldest first', 'eff': 'Effective date', 'title': 'Title A–Z'},
                      onChanged: (v) => setState(() => L.sort = v),
                    ),
                  ),
                  IconButton(
                    tooltip: L.grid ? 'List view' : 'Grid view',
                    onPressed: () => setState(() => L.grid = !L.grid),
                    icon: Icon(L.grid ? Icons.view_list : Icons.grid_view),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Text(plural(ds.length, 'document'), style: xs(context)),
                    const Spacer(),
                    if (L.active > 0) TextButton(onPressed: clear, child: const Text('Clear filters')),
                  ]),
                ),
              ]),
            ),
          ),
          if (ds.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Card(
                  child: EmptyBox('No documents match these filters. Try removing a filter or searching for a reference number.',
                      action: btn('Clear all filters', () => setState(() {
                            clear();
                            qc.clear();
                            L.q = '';
                          }))),
                ),
              ),
            )
          else if (L.grid)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: .72,
                children: [for (final d in ds) _DocCard(d: d)],
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
              sliver: SliverList.separated(
                itemCount: ds.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _DocRow(d: ds[i]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.d});
  final Doc d;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/library/${d.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Ft(d.fileType),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text('${d.ref} · ${d.type}', style: mono(context)),
                  const SizedBox(height: 2),
                  Text('${d.dept} · ${fmtD(d.date)} · ${d.visibility}', style: xs(context)),
                  if (d.audience.isNotEmpty) Text(d.audience.join(', '), style: xs(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Pill(d.status),
                    if (store.canUpload && d.unsure.isNotEmpty) Pill('${plural(d.unsure.length, 'word')} to check', kind: 'warn'),
                    for (final t in d.tags) TagChip(t),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.d});
  final Doc d;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/library/${d.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 86,
            color: p.surface2,
            padding: const EdgeInsets.all(12),
            child: Stack(children: [
              Center(
                child: Container(
                  width: 58,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: p.paper, border: Border.all(color: p.line)),
                  child: Column(children: [
                    for (final w in const [.4, 1.0, .85, .92, .7]) Container(margin: const EdgeInsets.only(bottom: 3), height: 3, width: 46 * w, color: p.line2),
                  ]),
                ),
              ),
              Positioned(right: 0, bottom: 0, child: Ft(d.fileType)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Pill(d.status)), const Spacer(), Text(fmtD(d.date), style: xs(context))]),
                const SizedBox(height: 6),
                Text(d.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(d.ref, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context)),
                const Spacer(),
                Wrap(spacing: 4, runSpacing: 4, children: [for (final t in d.tags.take(2)) TagChip(t)]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
