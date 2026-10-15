import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';

class CollectionsScreen extends StoreScreen {
  const CollectionsScreen({super.key});

  @override
  Widget buildScreen(BuildContext context) => AppScaffold(
        route: '/collections',
        title: 'Collections',
        fab: FloatingActionButton.extended(
          heroTag: 'newcoll',
          onPressed: () => showSheet(context, title: 'New collection', builder: (_) => _NewCollection(outer: context)),
          icon: const Icon(Icons.add),
          label: const Text('New collection'),
        ),
        body: RefreshIndicator(
          onRefresh: store.load,
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: [
            Text('Documents grouped by department and subject automatically, plus groups you make. Open one to ask questions limited to it.', style: muted(context)),
            for (final g in store.scopeGroups.where((g) => g.kind != 'coll')) ...[
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Text('By ${g.label == 'Departments' ? 'department' : 'subject'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Text('Updated automatically as documents are published', style: xs(context)),
              const SizedBox(height: 8),
              if (g.items.isEmpty)
                const Card(child: EmptyBox('Published documents will be grouped here.'))
              else
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.45,
                  children: [
                    for (final i in g.items)
                      _CollCard(
                        title: i.label,
                        count: i.count,
                        foot: Row(children: [
                          Expanded(child: Text(plural(i.count, 'document'), style: xs(context), overflow: TextOverflow.ellipsis)),
                          Icon(Icons.auto_awesome, size: 14, color: context.pal.accent),
                          Text(' Ask', style: TextStyle(fontSize: 12, color: context.pal.accent)),
                        ]),
                        onTap: () => context.go('/ask?group=${Uri.encodeComponent(i.value)}'),
                      ),
                  ],
                ),
            ],
            const Padding(padding: EdgeInsets.only(top: 18, bottom: 8), child: Text('Made by people', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            if (store.collections.isEmpty) const Card(child: EmptyBox('No collections yet. Use “New collection” to group documents for a team or task.')),
            for (final co in store.collections)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CollCard(
                  title: co.name,
                  count: co.docs.length,
                  desc: co.desc,
                  foot: Row(children: [
                    Expanded(child: Text('${plural(co.docs.length, 'document')} · ${co.ownerName}', style: xs(context), overflow: TextOverflow.ellipsis)),
                    Text('Updated ${fmtD(co.updated)}', style: xs(context)),
                  ]),
                  onTap: () => context.push('/collections/${co.id}'),
                ),
              ),
          ]),
        ),
      );
}

class _CollCard extends StatelessWidget {
  const _CollCard({required this.title, required this.count, this.desc, required this.foot, required this.onTap});
  final String title;
  final int count;
  final String? desc;
  final Widget foot;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 22,
              child: Stack(children: [
                for (var n = 0; n < count.clamp(0, 4); n++)
                  Positioned(
                    left: n * 9.0,
                    child: Container(width: 16, height: 21, decoration: BoxDecoration(color: p.paper, border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(3))),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (desc != null && desc!.isNotEmpty) Text(desc!, maxLines: 2, overflow: TextOverflow.ellipsis, style: muted(context)),
            if (desc == null) const Spacer() else const SizedBox(height: 8),
            foot,
          ]),
        ),
      ),
    );
  }
}

class _NewCollection extends StatefulWidget {
  const _NewCollection({required this.outer});
  final BuildContext outer;
  @override
  State<_NewCollection> createState() => _NewCollectionState();
}

class _NewCollectionState extends State<_NewCollection> {
  String name = '', desc = '';
  final docs = <String>[];
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Field(label: 'Name', child: Input(hint: 'e.g. NAAC documentation 2026', onChanged: (v) => name = v)),
        Field(label: 'Description', child: Input(maxLines: 2, onChanged: (v) => desc = v)),
        Field(label: 'Documents', child: _DocPicker(docs: store.permitted, selected: docs, onChanged: () => setState(() {}))),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Create collection', () async {
            if (name.trim().isEmpty) {
              store.toast('Name the collection');
              return;
            }
            final co = {'id': nid('C'), 'name': name, 'desc': desc, 'docs': docs, 'ownerName': store.myName, 'updated': todayIso()};
            if (await store.save('collections', co)) {
              if (context.mounted) Navigator.pop(context);
              store.toast('Collection created');
              if (widget.outer.mounted) widget.outer.push('/collections/${co['id']}');
            }
          }, primary: true),
        ]),
      ], 12));
}

class _DocPicker extends StatelessWidget {
  const _DocPicker({required this.docs, required this.selected, required this.onChanged});
  final List<Doc> docs;
  final List<String> selected;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(border: Border.all(color: context.pal.line), borderRadius: BorderRadius.circular(10)),
        child: docs.isEmpty
            ? Padding(padding: const EdgeInsets.all(12), child: Text('Every document is already in this collection.', style: muted(context)))
            : ListView(shrinkWrap: true, children: [
                for (final d in docs)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(d.id),
                    onChanged: (v) {
                      v == true ? selected.add(d.id) : selected.remove(d.id);
                      onChanged();
                    },
                    title: Text(d.title, style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(d.ref, style: mono(context)),
                  ),
              ]),
      );
}

class CollectionDetailScreen extends StatefulWidget {
  const CollectionDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> with StoreListener {
  @override
  Widget build(BuildContext context) {
    final co = store.collections.where((c) => c.id == widget.id).firstOrNull;
    if (co == null) return Scaffold(appBar: AppBar(), body: const EmptyBox('Collection not found.'));
    final ds = co.docs.map(store.getDoc).whereType<Doc>().toList();
    final mine = store.ownsItem(co);

    Future<void> removeDoc(String docId) async {
      if (await store.save('collections', co.copy({'docs': co.docs.where((x) => x != docId).toList(), 'updated': todayIso()}))) {
        store.toast('Removed from collection');
      }
    }

    Future<void> del() async {
      if (!await confirm(context, title: 'Delete collection?', body: Text('Delete “${co.name}”? The ${co.docs.length} documents in it are not deleted.'), action: 'Delete collection')) {
        return;
      }
      if (await store.remove('collections', co.id)) {
        store.toast('Collection deleted');
        if (context.mounted) context.go('/collections');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(co.name),
        actions: [
          if (mine)
            PopupMenuButton<String>(
              onSelected: (k) {
                if (k == 'add') showSheet(context, title: 'Add documents', builder: (_) => _AddDocs(co: co));
                if (k == 'rename') showSheet(context, title: 'Rename collection', builder: (_) => _RenameColl(co: co));
                if (k == 'delete') del();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'add', child: ListTile(leading: Icon(Icons.add), title: Text('Add documents'))),
                const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename'))),
                PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: context.pal.red), title: Text('Delete', style: TextStyle(color: context.pal.red)))),
              ],
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 40), children: gap([
        if (co.desc.isNotEmpty || co.ownerName.isNotEmpty)
          Text([if (co.desc.isNotEmpty) co.desc, if (co.ownerName.isNotEmpty) 'by ${co.ownerName}'].join(' · '), style: muted(context)),
        btn('Ask this collection', () => context.go('/ask?group=${Uri.encodeComponent('coll:${co.id}')}'), icon: Icons.auto_awesome, primary: true, small: false),
        Section(
          children: ds.isEmpty
              ? [const EmptyBox('This collection is empty. Add documents to start.')]
              : [
                  for (final d in ds)
                    Row2(
                      lead: Ft(d.fileType),
                      title: d.title,
                      meta: '${d.ref} · ${d.dept}',
                      onTap: () => context.push('/library/${d.id}'),
                      trail: Row(mainAxisSize: MainAxisSize.min, children: [
                        Pill(d.status),
                        if (mine) IconButton(tooltip: 'Remove from collection', icon: const Icon(Icons.close, size: 18), onPressed: () => removeDoc(d.id)),
                      ]),
                    ),
                ],
        ),
      ], 12)),
    );
  }
}

class _AddDocs extends StatefulWidget {
  const _AddDocs({required this.co});
  final Collection co;
  @override
  State<_AddDocs> createState() => _AddDocsState();
}

class _AddDocsState extends State<_AddDocs> {
  final sel = <String>[];
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _DocPicker(docs: store.permitted.where((d) => !widget.co.docs.contains(d.id)).toList(), selected: sel, onChanged: () => setState(() {})),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Add selected', () async {
            if (await store.save('collections', widget.co.copy({'docs': [...widget.co.docs, ...sel], 'updated': todayIso()}))) {
              if (context.mounted) Navigator.pop(context);
              store.toast('${sel.length} document(s) added');
            }
          }, primary: true),
        ]),
      ]);
}

class _RenameColl extends StatefulWidget {
  const _RenameColl({required this.co});
  final Collection co;
  @override
  State<_RenameColl> createState() => _RenameCollState();
}

class _RenameCollState extends State<_RenameColl> {
  late String name = widget.co.name, desc = widget.co.desc;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Field(label: 'Name', child: Input(initial: name, onChanged: (v) => name = v)),
        Field(label: 'Description', child: Input(initial: desc, maxLines: 2, onChanged: (v) => desc = v)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Save', () async {
            if (await store.save('collections', widget.co.copy({'name': name, 'desc': desc, 'updated': todayIso()}))) {
              if (context.mounted) Navigator.pop(context);
              store.toast('Collection updated');
            }
          }, primary: true),
        ]),
      ], 12));
}
