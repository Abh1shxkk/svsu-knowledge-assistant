import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/answer.dart';
import '../widgets/modals.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';
import '../widgets/viewer.dart';

const _suggestions = [
  ('One source', 'How many casual leaves can teaching staff take?'),
  ('Multiple sources', 'What do faculty need to do for the end-term exams?'),
  ('Revised policy', 'Has the earned leave rule changed?'),
  ('Conflicting instructions', 'When is the last date for the second instalment fee?'),
  ('Historical record', 'What was the casual leave limit in 2024?'),
  ('Insufficient evidence', 'What is the maternity leave policy for contract staff?'),
  ('हिन्दी प्रश्न', 'परीक्षा ड्यूटी में रिपोर्टिंग का समय क्या है?'),
];

class AskScreen extends StatefulWidget {
  const AskScreen({super.key, this.q, this.chat, this.group});
  final String? q;
  final String? chat;
  final String? group;
  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> with StoreListener {
  final text = TextEditingController();
  final scroll = ScrollController();
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    // Links: open a chat (?c=), ask a question (?q=), or search a group of documents (?group=dept:Examination).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final g = widget.group, c = widget.chat, q = widget.q;
      if (g != null) {
        store.setScope(g);
        store.activeChat = null;
      }
      if (c != null && store.chats.any((x) => x.id == c)) {
        store.activeChat = c;
        store.changed();
      } else if (q != null && q.isNotEmpty) {
        store.activeChat = null;
        ask(q);
      } else {
        store.changed();
      }
    });
  }

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> ask(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    final userMsg = {'id': nid('m'), 'role': 'user', 'text': q};
    final aiMsg = {'id': nid('m'), 'role': 'ai', 'q': q, 'pending': true};
    var chat = store.active;
    Json chatJ;
    if (chat == null) {
      chatJ = {'id': nid('ch'), 'title': q.length > 48 ? '${q.substring(0, 46)}…' : q, 'msgs': [userMsg, aiMsg], 'saved': false, 'at': DateTime.now().toUtc().toIso8601String()};
      store.activeChat = chatJ['id'] as String;
    } else {
      chatJ = chat.copy({'msgs': [...chat.msgs.map((m) => m.j), userMsg, aiMsg]});
    }
    await store.save('chats', chatJ);
    chat = Chat(chatJ);
    _toBottom();

    var draft = '';
    try {
      final answer = await api.askStream({
        'question': q,
        'scope_ids': store.scopeDocs.map((d) => d.id).toList(),
        'lang': store.ansLang, // "auto": answer in the question's own language, Hinglish included
        // Earlier questions in this chat, so a follow-up like "and in 2023?" can be rewritten in full.
        'history': (chat.msgs.where((m) => m.isUser).map((m) => m.text).toList()..removeLast()),
      }, ({status, delta}) {
        if (delta != null) draft += delta;
        _show(chat!.id, aiMsg['id'] as String, delta != null ? {'draft': draft} : {'status': status});
      });
      _finish(chat.id, aiMsg['id'] as String, {'answer': answer}); // unanswered questions are logged by the server
    } catch (e) {
      _finish(chat.id, aiMsg['id'] as String, {'error': '$e'});
    }
  }

  /// Progress while the answer is made: shown on screen only, saved once the answer is complete.
  void _show(String chatId, String msgId, Json patch) {
    store.setLocal('chats', [
      for (final c in store.raw('chats'))
        c['id'] != chatId ? c : {...c, 'msgs': [for (final m in c['msgs'] as List) (m as Map)['id'] == msgId ? {...m, ...patch} : m]},
    ]);
    _toBottom();
  }

  void _finish(String chatId, String msgId, Json patch) {
    final c = store.chats.where((x) => x.id == chatId).firstOrNull;
    if (c == null) return;
    store.save('chats', c.copy({
      'msgs': [
        for (final m in c.msgs)
          m.id == msgId ? ({...m.j, 'pending': false, ...patch}..remove('status')..remove('draft')) : m.j,
      ],
    }));
    _toBottom();
  }

  void onCite(Msg m, int i) {
    final cites = m.answer?.cites ?? const [];
    if (i < 0 || i >= cites.length) return;
    final c = cites[i];
    openViewer(context, ViewerArgs(doc: c.doc, page: c.page, block: c.block, quote: c.quote, cites: cites, idx: i));
  }

  void send() {
    final q = text.text;
    text.clear();
    ask(q);
  }

  Future<void> deleteChat(Chat chat) async {
    if (!await confirm(context,
        title: 'Delete conversation?',
        body: Text("Delete “${chat.title}”? Its answers and any bookmarks of them are removed. This can't be undone."),
        action: 'Delete')) {
      return;
    }
    if (store.activeChat == chat.id) store.activeChat = null;
    if (await store.remove('chats', chat.id)) {
      store.setLocal('bm_answers', store.raw('bm_answers').where((b) => b['chat'] != chat.id).toList());
      store.toast('Conversation deleted');
    }
  }

  Future<void> saveChat(Chat chat) async {
    if (await store.save('chats', chat.copy({'saved': !chat.saved, 'savedName': chat.savedName.isNotEmpty ? chat.savedName : chat.title}))) {
      store.toast(chat.saved ? 'Removed from saved conversations' : 'Conversation saved');
    }
  }

  void openPanel(int tab) {
    final cited = <String>{
      for (final m in store.active?.msgs ?? <Msg>[]) ...?m.answer?.cites.map((c) => c.doc),
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .85,
        child: DefaultTabController(
          length: 2,
          initialIndex: tab,
          child: Column(children: [
            const TabBar(tabs: [
              Tab(icon: Icon(Icons.description_outlined, size: 18), text: 'Documents'),
              Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'Chats'),
            ]),
            Expanded(
              child: ListenableBuilder(
                listenable: store,
                builder: (ctx, _) => TabBarView(children: [
                  _DocsPanel(cited: cited),
                  _ChatList(
                    onOpen: (id) {
                      store.activeChat = id;
                      store.changed();
                      Navigator.pop(ctx);
                      _toBottom();
                    },
                    onNew: () {
                      store.activeChat = null;
                      store.changed();
                      Navigator.pop(ctx);
                    },
                    onDelete: deleteChat,
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final active = store.active;
    final inScope = store.scopeDocs.length;
    final msgs = active?.msgs ?? const <Msg>[];
    if (msgs.length != _lastCount) {
      _lastCount = msgs.length;
      _toBottom();
    }
    return AppScaffold(
      route: '/ask',
      title: active?.title ?? 'New conversation',
      actions: [
        IconButton(tooltip: 'Conversations', icon: const Icon(Icons.history), onPressed: () => openPanel(1)),
        if (active != null && msgs.isNotEmpty)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (k) {
              if (k == 'export') showExport(context, active.title, _exportItems(active));
              if (k == 'save') saveChat(active);
              if (k == 'new') {
                store.activeChat = null;
                store.changed();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: ListTile(leading: Icon(Icons.add), title: Text('New conversation'))),
              const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.ios_share), title: Text('Export'))),
              PopupMenuItem(value: 'save', child: ListTile(leading: Icon(active.saved ? Icons.bookmark : Icons.bookmark_border), title: Text(active.saved ? 'Saved' : 'Save'))),
            ],
          ),
      ],
      body: Column(children: [
        InkWell(
          onTap: () => openPanel(0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.line))),
            child: Row(children: [
              Icon(Icons.layers_outlined, size: 17, color: p.accent),
              const SizedBox(width: 8),
              Flexible(child: Text(store.groupLabel(store.scope.group), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5), overflow: TextOverflow.ellipsis)),
              Text(' · ${plural(inScope, 'document')}', style: muted(context)),
              const Spacer(),
              Text('Change', style: TextStyle(color: p.accent, fontSize: 13)),
            ]),
          ),
        ),
        Expanded(
          child: msgs.isEmpty
              ? _Welcome(onAsk: ask)
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) => _Message(m: msgs[i], chat: active!, onCite: onCite, onAsk: ask),
                ),
        ),
        Container(
          decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.line))),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: TextField(
                    controller: text,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(hintText: 'Ask in Hindi or English, e.g. “आकस्मिक अवकाश कितने दिन का है?”'),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(onPressed: send, icon: const Icon(Icons.send, size: 20), tooltip: 'Send'),
              ]),
              Row(children: [
                Icon(Icons.language, size: 15, color: p.fg3),
                const SizedBox(width: 4),
                Text('Answer in', style: xs(context)),
                const SizedBox(width: 4),
                DropdownButton<String>(
                  value: const ['auto', 'en', 'hi'].contains(store.ansLang) ? store.ansLang : 'auto',
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  style: TextStyle(fontSize: 12.5, color: p.fg),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Same as question')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'hi', child: Text('हिन्दी')),
                  ],
                  onChanged: (v) {
                    store.ansLang = v ?? 'auto';
                    store.changed();
                  },
                ),
                const Spacer(),
                Flexible(child: Text('Only from the records, always cited', style: xs(context), overflow: TextOverflow.ellipsis)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Question-and-answer pairs of a chat, for export.
List<ExportItem> _exportItems(Chat chat) => [
      for (final m in chat.msgs)
        if (!m.isUser && m.answer != null) (q: m.q, answer: m.answer!),
    ];

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAsk});
  final void Function(String) onAsk;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Ask about SVSU letters, notices and policies', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          'Answers come only from documents you are allowed to see. Every claim has a numbered citation — tap a number to open the source at the exact passage.',
          style: muted(context),
        ),
        const SizedBox(height: 16),
        for (final (k, q) in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onAsk(q),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k, style: xs(context)),
                    const SizedBox(height: 2),
                    Text(q, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
}

class _Message extends StatelessWidget {
  const _Message({required this.m, required this.chat, required this.onCite, required this.onAsk});
  final Msg m;
  final Chat chat;
  final void Function(Msg, int) onCite;
  final void Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(16).copyWith(bottomRight: const Radius.circular(4))),
          child: SelectableText(m.text, style: TextStyle(color: p.accentInk, fontSize: 14.5)),
        ),
      );
    }
    Widget box(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
    if (m.pending) {
      final draft = (m.draft ?? '').replaceAll(RegExp(r'\s*\[\d+(?:\s*,\s*\d+)*\]'), '').replaceAll('**', '');
      return box([
        if (draft.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(draft, style: TextStyle(fontSize: 14.5, height: 1.5, color: p.fg2))),
        Row(children: [
          const Spinner(size: 15),
          const SizedBox(width: 10),
          Expanded(child: Text(m.status ?? 'Searching the records…', style: muted(context))),
        ]),
      ]);
    }
    if (m.error != null) return box([Note(kind: 'bad', text: m.error)]);
    final a = m.answer;
    if (a == null) return const SizedBox.shrink();
    final bm = store.bmAnswers.where((b) => b.s('msg') == m.id).firstOrNull;
    final cited = a.cites.map((c) => c.doc).toSet().toList();
    return box([
      Row(children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.auto_awesome, size: 15, color: p.accent),
        ),
        const SizedBox(width: 8),
        const Text('SVSU Assistant', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        const SizedBox(width: 8),
        if (store.ai.showConf && a.label.isNotEmpty) Flexible(child: Pill(a.label, kind: kindInfo[a.label] ?? 'mute')),
      ]),
      if (a.queries.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.search, size: 14, color: p.fg3),
            const SizedBox(width: 6),
            Expanded(child: Text('Searched for: ${a.queries.join(' · ')}', style: xs(context))),
          ]),
        ),
      const SizedBox(height: 10),
      AnswerView(answer: a, onCite: (i) => onCite(m, i), onAsk: onAsk),
      if (a.checks.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Note(
            kind: 'warn',
            title: 'Check before relying on this.',
            text: "A second reading couldn't find these in the cited records: ${a.checks.join(' · ')}",
          ),
        ),
      if (a.label == 'Conflicting instructions' && cited.length >= 2)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            btn('Compare both documents', () => showCompare(context, cited[0], cited[1], m.q)),
            btn('Report conflict', () => reportConflict(cited.take(2).toList(), m.q)),
          ]),
        ),
      if (a.label == 'Insufficient evidence')
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(alignment: Alignment.centerLeft, child: btn('Request a document', () => showRequestDoc(context, m.q, dept: store.session?.dept), icon: Icons.description_outlined)),
        ),
      if (a.label == 'Outside your scope')
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: btn('Search all permitted documents', () {
              store.clearScope();
              onAsk(m.q);
            }, primary: true),
          ),
        ),
      const SizedBox(height: 6),
      const Divider(),
      Row(children: [
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: answerText(a)));
            store.toast('Copied');
          },
        ),
        IconButton(
          tooltip: bm != null ? 'Bookmarked' : 'Bookmark',
          icon: Icon(bm != null ? Icons.bookmark : Icons.bookmark_border, size: 19, color: bm != null ? p.accent : null),
          onPressed: () async {
            if (bm != null) {
              if (await store.remove('bm_answers', bm.id)) store.toast('Bookmark removed');
            } else if (await store.save('bm_answers', {'id': nid('ba'), 'chat': chat.id, 'msg': m.id, 'q': m.q, 'when': todayIso()})) {
              store.toast('Answer bookmarked');
            }
          },
        ),
        IconButton(tooltip: 'Export', icon: const Icon(Icons.ios_share, size: 18), onPressed: () => showExport(context, m.q, [(q: m.q, answer: a)])),
        const Spacer(),
        IconButton(
          tooltip: 'Helpful',
          icon: Icon(m.fb == 'up' ? Icons.thumb_up : Icons.thumb_up_outlined, size: 18, color: m.fb == 'up' ? p.green : null),
          onPressed: () => rate(chat, m, 'up'),
        ),
        IconButton(
          tooltip: 'Not helpful',
          icon: Icon(m.fb == 'down' ? Icons.thumb_down : Icons.thumb_down_outlined, size: 18, color: m.fb == 'down' ? p.red : null),
          onPressed: () => showFeedback(context, chat, m),
        ),
      ]),
    ]);
  }
}

/// The documents the assistant searches: pick a group (department, subject, collection), then untick any
/// to leave out. Documents cited in the open conversation are marked.
class _DocsPanel extends StatefulWidget {
  const _DocsPanel({required this.cited});
  final Set<String> cited;
  @override
  State<_DocsPanel> createState() => _DocsPanelState();
}

class _DocsPanelState extends State<_DocsPanel> {
  String find = '';
  @override
  Widget build(BuildContext context) {
    final group = store.scope.group, off = store.scope.off;
    final inGroup = store.groupDocs(group);
    final shown = inGroup.where((d) => find.isEmpty || '${d.title} ${d.ref}'.toLowerCase().contains(find.toLowerCase())).toList();
    final searched = inGroup.where((d) => !off.contains(d.id)).length;
    final options = <String>['all'];
    final labels = <String, String>{'all': 'All documents (${store.answerable.length})'};
    if (group.startsWith('doc:')) {
      options.add(group);
      labels[group] = 'This document only';
    }
    for (final g in store.scopeGroups) {
      for (final i in g.items) {
        options.add(i.value);
        labels[i.value] = '${g.label == 'Departments' ? 'Dept' : g.label == 'Subjects' ? 'Subject' : 'Collection'}: ${i.label} (${i.count})';
      }
    }
    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 20), children: [
      Field(label: 'Search in', child: Select(value: group, items: options, labels: labels, onChanged: (v) => store.setScope(v))),
      if (inGroup.length > 6) ...[
        const SizedBox(height: 8),
        TextField(onChanged: (v) => setState(() => find = v), decoration: const InputDecoration(hintText: 'Find in this list', prefixIcon: Icon(Icons.search, size: 18))),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text('Searching $searched of ${inGroup.length}', style: xs(context))),
          if (inGroup.length > 1) ...[
            TextButton(onPressed: () => store.setScope(group), child: const Text('All')),
            TextButton(onPressed: () => store.setScope(group, inGroup.map((d) => d.id).toList()), child: const Text('None')),
          ],
        ]),
      ),
      if (inGroup.isEmpty) const EmptyBox('No published documents here yet.'),
      for (final d in shown)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.cited.contains(d.id) ? context.pal.accent : context.pal.line),
          ),
          child: Row(children: [
            Checkbox(
              value: !off.contains(d.id),
              onChanged: (_) => store.setScope(group, off.contains(d.id) ? off.where((x) => x != d.id).toList() : [...off, d.id]),
            ),
            Expanded(
              child: InkWell(
                onTap: () => openViewer(context, ViewerArgs(doc: d.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.title, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5, color: off.contains(d.id) ? context.pal.fg3 : null)),
                    Text('${d.ref} · ${d.dept}', style: xs(context)),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: widget.cited.contains(d.id)
                  ? Tooltip(message: 'Cited in this conversation', child: Icon(Icons.auto_awesome, size: 16, color: context.pal.accent))
                  : d.status != 'Active'
                      ? Pill(d.status)
                      : const SizedBox.shrink(),
            ),
          ]),
        ),
    ]);
  }
}

class _ChatList extends StatefulWidget {
  const _ChatList({required this.onOpen, required this.onNew, required this.onDelete});
  final void Function(String) onOpen;
  final VoidCallback onNew;
  final void Function(Chat) onDelete;
  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Chat>>{};
    for (final c in store.chats) {
      (groups[AppStore.chatGroup(c)] ??= []).add(c);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 20), children: [
      btn('New conversation', widget.onNew, icon: Icons.add, primary: true, small: false),
      const SizedBox(height: 10),
      TextField(onChanged: (v) => setState(() => search = v), decoration: const InputDecoration(hintText: 'Search conversations', prefixIcon: Icon(Icons.search, size: 18))),
      const SizedBox(height: 6),
      if (store.chats.isEmpty) const EmptyBox('No conversations yet.'),
      for (final MapEntry(key: g, value: list) in groups.entries)
        if (list.any((c) => search.isEmpty || c.title.toLowerCase().contains(search.toLowerCase()))) ...[
          Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(g.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: .8, color: context.pal.fg3))),
          for (final c in list.where((c) => search.isEmpty || c.title.toLowerCase().contains(search.toLowerCase())))
            ListTile(
              contentPadding: const EdgeInsets.only(left: 8),
              selected: c.id == store.activeChat,
              selectedTileColor: context.pal.accentSoft,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
              subtitle: Text('${c.saved ? 'Saved · ' : ''}${plural((c.msgs.length / 2).ceil(), 'question')}', style: xs(context)),
              onTap: () => widget.onOpen(c.id),
              trailing: IconButton(tooltip: 'Delete conversation', icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => widget.onDelete(c)),
            ),
        ],
    ]);
  }
}
