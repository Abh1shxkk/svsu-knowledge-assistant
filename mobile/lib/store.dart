/// App state: every record the server lets this person see, the session, and what the assistant searches.
/// Mirrors the web app's store, so both behave the same.
library;

import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'util.dart';

const kinds = [
  'documents', 'collections', 'deadlines', 'chats', 'bm_answers', 'bm_passages', 'feedback',
  'unanswered', 'conflicts', 'users', 'audit', 'reminders', 'prefs', 'settings',
];

/// What the assistant searches: a group of documents, minus any the person unticked.
/// group is `all`, `dept:<name>`, `tag:<subject>`, `coll:<collection id>` or `doc:<document id>`.
class Scope {
  const Scope(this.group, [this.off = const []]);
  final String group;
  final List<String> off;
}

final messengerKey = GlobalKey<ScaffoldMessengerState>();

const answerableSt = ['Active', 'Superseded', 'Expired'];
const editableSt = ['Draft', 'Pending', 'Changes requested'];
const notInForce = ['Superseded', 'Withdrawn', 'Expired'];

class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore instance = AppStore._();

  final Map<String, List<Json>> _rec = {for (final k in kinds) k: []};
  bool loaded = false;
  String error = '';
  Session? session;
  Scope scope = const Scope('all');
  String ansLang = 'auto';
  String? activeChat;
  ThemeMode themeMode = ThemeMode.light;
  /// Documents opened in full (with their text), by id.
  final Map<String, Doc> full = {};
  final Set<String> _loadingDocs = {};

  /// Called after sign-out so the app can show the sign-in screen.
  VoidCallback? onSignedOut;

  void changed() => notifyListeners();

  List<Json> raw(String kind) => _rec[kind]!;
  List<Doc> get documents => _rec['documents']!.map(Doc.new).toList();
  List<Collection> get collections => _rec['collections']!.map(Collection.new).toList();
  List<Deadline> get deadlines => _rec['deadlines']!.map(Deadline.new).toList();
  List<Chat> get chats => _rec['chats']!.map(Chat.new).toList();
  List<Rec> get bmAnswers => _rec['bm_answers']!.map(Rec.new).toList();
  List<Rec> get bmPassages => _rec['bm_passages']!.map(Rec.new).toList();
  List<Rec> get feedback => _rec['feedback']!.map(Rec.new).toList();
  List<Rec> get unanswered => _rec['unanswered']!.map(Rec.new).toList();
  List<Rec> get conflicts => _rec['conflicts']!.map(Rec.new).toList();
  List<User> get users => _rec['users']!.map(User.new).toList();
  List<Rec> get audit => _rec['audit']!.map(Rec.new).toList();
  List<Rec> get reminders => _rec['reminders']!.map(Rec.new).toList();
  List<Rec> get prefs => _rec['prefs']!.map(Rec.new).toList();

  Json? setting(String id) {
    for (final s in _rec['settings']!) {
      if (s['id'] == id) return s;
    }
    return null;
  }

  Lists get lists => Lists(setting('lists') ?? const {});
  AiSettings get ai => AiSettings(setting('ai') ?? const {});
  Map<String, List<int>> get roleMatrix {
    final m = setting('roles')?['matrix'] as Map?;
    return {for (final e in (m ?? {}).entries) '${e.key}': (e.value as List).map((x) => (x as num).toInt()).toList()};
  }

  bool get requireMfa => setting('security')?['requireMfa'] == true;

  Doc? getDoc(String? id) {
    if (id == null) return null;
    for (final d in _rec['documents']!) {
      if (d['id'] == id) return Doc(d);
    }
    return null;
  }

  Chat? get active {
    for (final c in _rec['chats']!) {
      if (c['id'] == activeChat) return Chat(c);
    }
    return null;
  }

  // ---------- Loading ----------
  Future<void> load() async {
    if (api.token == null) {
      error = 'no-session';
      notifyListeners();
      return;
    }
    try {
      final results = await Future.wait([api.me(), api.records()]);
      final first = !loaded;
      session = Session(results[0]);
      final records = results[1];
      for (final k in kinds) {
        _rec[k] = List<Json>.from((records[k] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      }
      full.clear();
      loaded = true;
      error = '';
      if (first) ansLang = ai.lang;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  /// A document with its full text, loaded on first use.
  Future<Doc?> loadDoc(String id) async {
    if (full[id] != null) return full[id];
    if (_loadingDocs.contains(id)) return null;
    _loadingDocs.add(id);
    try {
      final doc = Doc(await api.document(id));
      full[id] = doc;
      notifyListeners();
      return doc;
    } catch (_) {
      return null;
    } finally {
      _loadingDocs.remove(id);
    }
  }

  Doc? fullDoc(String? id) {
    if (id == null) return null;
    final d = full[id];
    if (d == null && getDoc(id) != null) loadDoc(id);
    return d;
  }

  Future<void> logout() async {
    await api.setToken(null);
    session = null;
    loaded = false;
    activeChat = null;
    for (final k in kinds) {
      _rec[k] = [];
    }
    full.clear();
    notifyListeners();
    onSignedOut?.call();
  }

  /// Saves on the server; the screen updates at once and goes back if the server refuses. True if saved.
  Future<bool> save(String kind, Json item) async {
    final list = _rec[kind]!;
    final before = List<Json>.from(list);
    final fullBefore = Map<String, Doc>.from(full);
    final id = item['id'];
    var shown = item;
    if (kind == 'documents') {
      // lists hold details only; the text lives in `full`
      shown = Map<String, dynamic>.from(item)..remove('pages');
      final cached = full[id];
      if (item['pages'] != null || cached != null) {
        full['$id'] = Doc({...?cached?.j, ...shown, 'pages': item['pages'] ?? cached?.j['pages']});
      }
    }
    final i = list.indexWhere((x) => x['id'] == id);
    _rec[kind] = i < 0 ? [shown, ...list] : [for (final x in list) x['id'] == id ? shown : x];
    notifyListeners();
    try {
      await api.put(kind, '$id', item);
      return true;
    } catch (e) {
      _rec[kind] = before;
      full
        ..clear()
        ..addAll(fullBefore);
      notifyListeners();
      toast('Not saved: $e');
      return false;
    }
  }

  Future<bool> remove(String kind, String id) async {
    final before = List<Json>.from(_rec[kind]!);
    _rec[kind] = _rec[kind]!.where((x) => x['id'] != id).toList();
    notifyListeners();
    try {
      await api.remove(kind, id);
      if (kind == 'documents') load(); // the server also removed its deadlines, bookmarks and links
      return true;
    } catch (e) {
      _rec[kind] = before;
      notifyListeners();
      toast('Not deleted: $e');
      return false;
    }
  }

  /// Changes shown on screen only (e.g. an answer as it streams in); saved later with [save].
  void setLocal(String kind, List<Json> list) {
    _rec[kind] = list;
    notifyListeners();
  }

  void toast(String msg) {
    final m = messengerKey.currentState;
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(milliseconds: 2800)));
  }

  void setScope(String group, [List<String> off = const []]) {
    scope = Scope(group, off);
    notifyListeners();
  }

  void clearScope() => setScope('all');

  // ---------- Roles ----------
  String get role => session?.role ?? 'Viewer';
  bool get canUpload => const ['Administrator', 'Approver', 'Uploader'].contains(role);
  bool get canApprove => const ['Administrator', 'Approver'].contains(role);
  bool get isAdmin => role == 'Administrator';
  bool isMine(Doc d) => d.uploaderId != null && d.uploaderId == session?.loginId;
  /// Uploaders may still change their own documents until they are published.
  bool canEditDoc(Doc d) => canApprove || (canUpload && isMine(d) && editableSt.contains(d.status));
  bool ownsItem(Collection c) => isAdmin || c.owner == null || c.owner == session?.loginId;
  String get myName => session?.name ?? 'User';
  String get myInitials => initials(myName);

  // ---------- Derived data ----------
  /// The server sends only documents this person may see.
  List<Doc> get permitted => documents;
  List<Doc> get answerable => documents.where((d) => answerableSt.contains(d.status)).toList();

  static (String, String) _split(String group) {
    final i = group.indexOf(':');
    return i < 0 ? (group, '') : (group.substring(0, i), group.substring(i + 1));
  }

  /// The answerable documents in a group (before any are unticked).
  List<Doc> groupDocs(String group) {
    final (kind, v) = _split(group);
    Collection? co;
    if (kind == 'coll') {
      for (final c in collections) {
        if (c.id == v) co = c;
      }
    }
    return answerable.where((d) => switch (kind) {
          'dept' => d.dept == v,
          'tag' => d.tags.contains(v),
          'coll' => co?.docs.contains(d.id) ?? false,
          'doc' => d.id == v,
          _ => true,
        }).toList();
  }

  List<Doc> get scopeDocs => groupDocs(scope.group).where((d) => !scope.off.contains(d.id)).toList();

  String groupLabel(String group) {
    final (kind, v) = _split(group);
    return switch (kind) {
      'coll' => collections.where((c) => c.id == v).firstOrNull?.name ?? 'Collection',
      'doc' => getDoc(v)?.title ?? 'One document',
      'all' => 'All documents',
      _ => v,
    };
  }

  /// Ready-made groups: every department and subject that has documents, plus the collections.
  List<({String label, String kind, List<({String value, String label, int count})> items})> get scopeGroups {
    final docs = answerable;
    List<(String, int)> count(Iterable<String> values) {
      final n = <String, int>{};
      for (final v in values) {
        if (v.isNotEmpty) n[v] = (n[v] ?? 0) + 1;
      }
      final e = n.entries.map((e) => (e.key, e.value)).toList()
        ..sort((a, b) => b.$2 != a.$2 ? b.$2 - a.$2 : a.$1.compareTo(b.$1));
      return e;
    }

    final groups = [
      ('Departments', 'dept', count(docs.map((d) => d.dept))),
      ('Subjects', 'tag', count(docs.expand((d) => d.tags))),
      ('Collections', 'coll', collections.map((c) => (c.id, groupDocs('coll:${c.id}').length)).toList()),
    ];
    return [
      for (final (label, kind, items) in groups)
        (
          label: label,
          kind: kind,
          items: [
            for (final (v, n) in items) (value: '$kind:$v', label: kind == 'coll' ? groupLabel('coll:$v') : v, count: n),
          ],
        ),
    ];
  }

  /// "Today", "Yesterday", "Previous 7 days" or the month, from a chat's start time.
  static String chatGroup(Chat c) {
    final at = c.at;
    if (at == null || at.length < 10) return (c.when ?? '').isNotEmpty ? c.when! : 'Earlier';
    final days = -daysTo(at.substring(0, 10));
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'Previous 7 days';
    final t = DateTime.tryParse(at)?.toLocal();
    return t == null ? 'Earlier' : monthYear(t);
  }
}

final store = AppStore.instance;

/// Rebuilds a screen whenever the records change.
mixin StoreListener<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }
}

/// A screen without its own state that redraws when the records change.
abstract class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});
  Widget buildScreen(BuildContext context);
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (c, _) => buildScreen(c));
}
