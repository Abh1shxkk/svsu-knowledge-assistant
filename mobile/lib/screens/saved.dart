import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/answer.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';
import '../widgets/viewer.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> with StoreListener {
  String tab = 'chats';

  @override
  Widget build(BuildContext context) {
    final saved = store.chats.where((c) => c.saved).toList();
    final bmA = store.bmAnswers, bmP = store.bmPassages;
    return AppScaffold(
      route: '/saved',
      title: 'Saved Chats & Bookmarks',
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: gap([
        Text('Conversations, answers and document passages you kept for later.', style: muted(context)),
        TabsBar(
          tabs: [('chats', 'Saved conversations', saved.length), ('answers', 'Bookmarked answers', bmA.length), ('passages', 'Bookmarked passages', bmP.length)],
          active: tab,
          onChange: (k) => setState(() => tab = k),
        ),
        if (tab == 'chats')
          Section(
            children: saved.isEmpty
                ? [const EmptyBox('No saved conversations. Use “Save” in a conversation to keep it here.')]
                : [
                    for (final c in saved)
                      Row2(
                        lead: const Avatar(icon: Icons.chat_bubble_outline, size: 30),
                        title: c.savedName.isNotEmpty ? c.savedName : c.title,
                        meta: '${plural((c.msgs.length / 2).ceil(), 'question')} · ${AppStore.chatGroup(c)}'
                            '${c.msgs.isNotEmpty ? ' · first: ${c.msgs.first.text}' : ''}',
                        onTap: () => context.go('/ask?c=${c.id}'),
                        trail: PopupMenuButton<String>(
                          onSelected: (k) async {
                            if (k == 'rename') showSheet(context, title: 'Rename conversation', builder: (_) => _RenameChat(chat: c));
                            if (k == 'remove' && await store.save('chats', c.copy({'saved': false}))) store.toast('Removed from saved');
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Rename')),
                            PopupMenuItem(value: 'remove', child: Text('Remove from saved')),
                          ],
                        ),
                      ),
                  ],
          ),
        if (tab == 'answers')
          Section(
            children: bmA.isEmpty
                ? [const EmptyBox('No bookmarked answers yet.')]
                : [
                    for (final b in bmA)
                      () {
                        final chat = store.chats.where((c) => c.id == b.s('chat')).firstOrNull;
                        final m = chat?.msgs.where((x) => x.id == b.s('msg')).firstOrNull;
                        final a = m?.answer;
                        var preview = a == null ? '' : answerText(a).replaceAll(RegExp(r'\[\d+\]'), '');
                        if (preview.length > 170) preview = '${preview.substring(0, 170)}…';
                        return Row2(
                          lead: const Avatar(icon: Icons.bookmark_border, size: 30),
                          title: b.s('q'),
                          meta: '$preview\n${a?.cites.length ?? 0} sources · bookmarked ${b.s('when')}',
                          onTap: chat == null ? null : () => context.go('/ask?c=${chat.id}'),
                          trail: IconButton(
                            tooltip: 'Remove bookmark',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              if (await store.remove('bm_answers', b.id)) store.toast('Bookmark removed');
                            },
                          ),
                        );
                      }(),
                  ],
          ),
        if (tab == 'passages')
          Section(
            children: bmP.isEmpty
                ? [const EmptyBox('No bookmarked passages. Open a citation and choose “Bookmark passage”.')]
                : [
                    for (final b in bmP)
                      () {
                        final d = store.getDoc(b.s('doc'));
                        return Row2(
                          lead: const Avatar(icon: Icons.description_outlined, size: 30),
                          title: '“${b.s('quote')}”',
                          titleStyle: const TextStyle(fontFamily: docFont, fontSize: 14),
                          wrapTitle: true,
                          meta: '${d?.title ?? ''} · ${d?.ref ?? ''}, p.${b.j['page']}${b.s('note').isNotEmpty ? ' · Note: ${b.s('note')}' : ''}',
                          onTap: () => openViewer(context, ViewerArgs(doc: b.s('doc'), page: (b.j['page'] as num?)?.toInt() ?? 1, block: b.s('block'), quote: b.s('quote'))),
                          trail: IconButton(
                            tooltip: 'Remove bookmark',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              if (await store.remove('bm_passages', b.id)) store.toast('Bookmark removed');
                            },
                          ),
                        );
                      }(),
                  ],
          ),
      ], 12)),
    );
  }
}

class _RenameChat extends StatefulWidget {
  const _RenameChat({required this.chat});
  final Chat chat;
  @override
  State<_RenameChat> createState() => _RenameChatState();
}

class _RenameChatState extends State<_RenameChat> {
  late String name = widget.chat.savedName.isNotEmpty ? widget.chat.savedName : widget.chat.title;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Field(label: 'Name', child: Input(initial: name, autofocus: true, onChanged: (v) => name = v)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Rename', () async {
            if (name.trim().isEmpty) return;
            if (await store.save('chats', widget.chat.copy({'title': name.trim(), 'savedName': name.trim()}))) {
              if (context.mounted) Navigator.pop(context);
              store.toast('Renamed');
            }
          }, primary: true),
        ]),
      ]);
}
