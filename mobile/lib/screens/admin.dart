import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';

const _roles = ['Administrator', 'Approver', 'Uploader', 'Viewer'];
const _caps = [
  ('Administrator', [1, 1, 1, 1]), ('Approver', [1, 1, 1, 0]), ('Uploader', [1, 1, 0, 0]), ('Viewer', [1, 0, 0, 0]),
];

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with StoreListener {
  String tab = 'users';
  List<String> mfaOn = [];

  @override
  void initState() {
    super.initState();
    api.mfaUsers().then((m) {
      if (mounted) setState(() => mfaOn = m);
    }, onError: (_) {});
  }

  Future<bool> saveLists(Json patch) => store.save('settings', {...?store.setting('lists'), 'id': 'lists', ...patch});
  Future<void> saveAi(Json patch) async {
    if (await store.save('settings', {...?store.setting('ai'), 'id': 'ai', ...patch})) store.toast('AI settings saved');
  }

  int docsWith(bool Function(Doc) fn) => store.documents.where(fn).length;
  bool self(User u) => u.loginId == store.session?.loginId;

  @override
  Widget build(BuildContext context) => AppScaffold(
        route: '/admin',
        title: 'Administration',
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: gap([
          Text('Manage people, access, tags and how the assistant answers.', style: muted(context)),
          TabsBar(
            tabs: const [('users', 'Users & roles', null), ('access', 'Access levels', null), ('tags', 'Subject tags', null), ('depts', 'Departments', null), ('audit', 'Audit log', null), ('ai', 'AI settings', null)],
            active: tab,
            onChange: (k) => setState(() => tab = k),
          ),
          ...switch (tab) {
            'users' => _users(),
            'access' => _access(),
            'tags' => [_tags()],
            'depts' => [_depts()],
            'audit' => [const _AuditLog()],
            'ai' => [const _OpenAiKey(), _aiSettings()],
            _ => <Widget>[],
          },
        ], 14)),
      );

  List<Widget> _users() {
    final p = context.pal;
    return [
      Section(
        title: 'Users and roles',
        trailing: btn('Add user', () => showSheet(context, title: 'Add user', builder: (_) => const _AddUser()), icon: Icons.add, primary: true),
        children: [
          for (final u in store.users)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Avatar(text: initials(u.name), size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text([u.email, u.dept].where((x) => x.isNotEmpty).join(' · '), style: xs(context)),
                      Text('Last active ${u.last.isEmpty ? '—' : u.last}', style: xs(context)),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (k) => _userAction(k, u),
                    itemBuilder: (_) => [
                      if (u.loginId != null) const PopupMenuItem(value: 'pw', child: Text('Reset password')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (u.loginId != null && mfaOn.contains(u.loginId)) const PopupMenuItem(value: 'mfa', child: Text('Reset two-step verification')),
                      if (!self(u)) PopupMenuItem(value: 'active', child: Text(u.active ? 'Deactivate' : 'Reactivate')),
                      if (!self(u)) PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: p.red))),
                    ],
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: 170,
                    child: Tooltip(
                      message: self(u) ? "You can't change your own role" : '',
                      child: Select(
                        value: u.role,
                        items: _roles,
                        enabled: !self(u),
                        onChanged: (role) async {
                          if (await store.save('users', u.copy({'role': role}))) store.toast('${u.name} is now $role');
                        },
                      ),
                    ),
                  ),
                  Pill(u.loginId != null && mfaOn.contains(u.loginId) ? 'Two-step on' : 'Two-step off', kind: u.loginId != null && mfaOn.contains(u.loginId) ? 'ok' : 'mute'),
                  Pill(u.active ? 'Active' : 'Deactivated', kind: u.active ? 'ok' : 'mute'),
                ]),
              ]),
            ),
        ],
      ),
      Section(title: 'Sign-in security', children: [
        SwitchListTile(
          value: store.requireMfa,
          title: const Text('Require two-step verification for Administrators and Approvers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text("They set it up the next time they sign in. Five wrong passwords or codes in a row always lock that account's sign-in for 5 minutes.", style: xs(context)),
          onChanged: (v) async {
            if (await store.save('settings', {'id': 'security', 'requireMfa': v})) store.toast(v ? 'Two-step verification required' : 'Two-step verification optional');
          },
        ),
      ]),
      Section(title: 'What each role can do', padded: true, children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(1.6)},
          children: [
            TableRow(children: [for (final h in const ['Role', 'Ask & view', 'Upload', 'Approve', 'Manage users']) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(h, style: xs(context)))]),
            for (final (r, a) in _caps)
              TableRow(children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(r, style: sm(context))),
                for (final x in a) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: x == 1 ? Icon(Icons.check, size: 17, color: p.green) : Text('—', style: muted(context))),
              ]),
          ],
        ),
      ]),
    ];
  }

  Future<void> _userAction(String k, User u) async {
    switch (k) {
      case 'pw':
        showSheet(context, title: 'Reset password', builder: (_) => _ResetPassword(loginId: u.loginId!, name: u.name));
      case 'edit':
        showSheet(context, title: 'Edit user', builder: (_) => _EditUser(u: u));
      case 'mfa':
        if (await confirm(context,
            title: 'Reset two-step verification?',
            body: Text('Use this when ${u.name} has lost their phone and recovery codes. They sign in with their password and set it up again.'),
            action: 'Reset')) {
          try {
            await api.resetMfa(u.loginId!);
            setState(() => mfaOn = mfaOn.where((x) => x != u.loginId).toList());
            store.toast('Two-step verification reset for ${u.name}');
          } catch (e) {
            store.toast('$e');
          }
        }
      case 'active':
        if (await store.save('users', u.copy({'active': !u.active}))) store.toast(u.active ? '${u.name} deactivated' : '${u.name} reactivated');
      case 'delete':
        if (await confirm(context,
            title: 'Delete user?',
            body: Text('Delete ${u.name} (${u.loginId})? They will no longer be able to sign in. Their documents stay. To keep their history, deactivate them instead.'),
            action: 'Delete user')) {
          if (await store.remove('users', u.id)) store.toast('${u.name} deleted');
        }
    }
  }

  List<Widget> _access() {
    final l = store.lists;
    final matrix = store.roleMatrix;
    return [
      const Note(kind: 'info', title: 'Access levels control who can open a document and who the AI may answer from.', text: 'They are set per document and are independent of subject tags.'),
      Section(title: 'Access levels by role', sub: 'Tick to allow', children: [
        for (final MapEntry(key: r, value: a) in matrix.entries)
          ExpansionTile(
            title: Text(r, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('${a.where((x) => x == 1).length} of ${l.vis.length} levels', style: xs(context)),
            children: [
              for (var i = 0; i < l.vis.length && i < a.length; i++)
                CheckboxListTile(
                  dense: true,
                  value: a[i] == 1,
                  title: Text(l.vis[i]),
                  onChanged: r == 'Administrator'
                      ? null
                      : (v) async {
                          final m = {...matrix, r: [for (var j = 0; j < a.length; j++) j == i ? (v == true ? 1 : 0) : a[j]]};
                          if (await store.save('settings', {'id': 'roles', 'matrix': m})) store.toast('Access updated for $r');
                        },
                ),
            ],
          ),
      ]),
      for (final v in l.vis)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))), Pill('${docsWith((d) => d.visibility == v)} docs', kind: 'mute')]),
              const SizedBox(height: 4),
              Text(l.visDesc(v), style: muted(context)),
            ]),
          ),
        ),
    ];
  }

  Widget _tags() {
    final l = store.lists;
    return Section(title: 'Subject tags', children: [
      _AddToList(
        placeholder: 'New tag name',
        onAdd: (t) async {
          if (l.tags.contains(t)) {
            store.toast('That tag already exists');
            return;
          }
          if (await saveLists({'TAGS': [...l.tags, t]})) store.toast('Tag added');
        },
      ),
      for (final t in l.tags)
        () {
          final n = docsWith((d) => d.tags.contains(t));
          return Row2(
            lead: const Icon(Icons.sell_outlined, size: 18),
            title: t,
            meta: plural(n, 'document'),
            trail: PopupMenuButton<String>(
              onSelected: (k) async {
                if (k == 'rename') showSheet(context, title: 'Rename tag', builder: (_) => _RenameTag(tag: t));
                if (k == 'delete') {
                  if (n > 0) {
                    store.toast('“$t” is used on $n document(s). Remove it from those or rename the tag instead.');
                    return;
                  }
                  if (await saveLists({'TAGS': l.tags.where((x) => x != t).toList()})) store.toast('Tag deleted');
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
          );
        }(),
    ]);
  }

  Widget _depts() {
    final l = store.lists;
    return Section(title: 'Departments', children: [
      _AddToList(
        placeholder: 'New department',
        onAdd: (t) async {
          if (l.depts.contains(t)) {
            store.toast('Already exists');
            return;
          }
          if (await saveLists({'DEPTS': [...l.depts, t]})) store.toast('Department added');
        },
      ),
      for (final t in l.depts)
        Row2(
          lead: const Icon(Icons.layers_outlined, size: 18),
          title: t,
          meta: '${docsWith((d) => d.dept == t)} documents · ${store.users.where((u) => u.dept == t).length} users',
        ),
    ]);
  }

  Widget _aiSettings() {
    final ai = store.ai;
    return Section(title: 'Answer behaviour', children: [
      for (final (k, label, hint, lock) in const [
        ('requireCite', 'Require a citation for every claim', 'Answers without supporting passages are blocked. Always on.', true),
        ('histOnly', 'Use superseded documents only for historical questions', 'Prevents old rules appearing in answers about current policy.', false),
        ('showConf', 'Show evidence strength label', 'Displays the label on each answer.', false),
        ('logUnans', 'Log unanswered questions', 'Questions with no supporting record go to Reports for follow-up.', false),
      ])
        SwitchListTile(
          value: ai.flag(k, true),
          title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(hint, style: xs(context)),
          onChanged: lock ? null : (v) => saveAi({k: v}),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Field(
          label: 'Default answer language',
          hint: 'Used when the person hasn’t chosen one',
          child: Select(
            value: ai.lang,
            items: const ['auto', 'en', 'hi'],
            labels: const {'auto': 'Same as question', 'en': 'English', 'hi': 'हिन्दी'},
            onChanged: (v) => saveAi({'lang': v}),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Field(
          label: 'Passages read per answer',
          hint: 'More gives fuller answers on broad questions, but costs more and takes longer',
          child: Select(value: '${ai.maxSources}', items: const ['4', '6', '8', '10', '12'], onChanged: (v) => saveAi({'maxSources': int.parse(v)})),
        ),
      ),
    ]);
  }
}

class _AddToList extends StatefulWidget {
  const _AddToList({required this.placeholder, required this.onAdd});
  final String placeholder;
  final void Function(String) onAdd;
  @override
  State<_AddToList> createState() => _AddToListState();
}

class _AddToListState extends State<_AddToList> {
  final c = TextEditingController();
  void add() {
    if (c.text.trim().isEmpty) return;
    widget.onAdd(c.text.trim());
    c.clear();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          Expanded(child: Input(controller: c, hint: widget.placeholder, onSubmitted: (_) => add())),
          const SizedBox(width: 8),
          btn('Add', add, icon: Icons.add, primary: true),
        ]),
      );
}

class _AddUser extends StatefulWidget {
  const _AddUser();
  @override
  State<_AddUser> createState() => _AddUserState();
}

class _AddUserState extends State<_AddUser> {
  late final Json u = {'name': '', 'email': '', 'login_id': '', 'dept': store.lists.depts.firstOrNull ?? '', 'role': 'Viewer', 'password': ''};
  bool busy = false;

  Future<void> create() async {
    if (str(u['name']).trim().isEmpty || str(u['login_id']).trim().isEmpty || str(u['password']).isEmpty) {
      store.toast('Name, Login ID and password are required');
      return;
    }
    setState(() => busy = true);
    try {
      await api.createAccount(u);
      await store.load();
      if (mounted) Navigator.pop(context);
      store.toast('Account created. They can sign in with that Login ID and password.');
    } catch (e) {
      store.toast('$e');
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Field(label: 'Full name', child: Input(onChanged: (v) => u['name'] = v)),
        Field(label: 'Login ID', hint: 'What they type to sign in', child: Input(hint: 'e.g. their employee ID', onChanged: (v) => u['login_id'] = v)),
        Field(label: 'University email', child: Input(keyboard: TextInputType.emailAddress, onChanged: (v) => u['email'] = v)),
        Field(label: 'Department', child: Select(value: str(u['dept']), items: store.lists.depts, onChanged: (v) => setState(() => u['dept'] = v))),
        Field(label: 'Role', child: Select(value: str(u['role']), items: _roles, onChanged: (v) => setState(() => u['role'] = v))),
        Field(label: 'Temporary password', hint: 'Share it with the user; they should change it later', child: Input(onChanged: (v) => u['password'] = v)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn(busy ? 'Creating…' : 'Add user', busy ? null : create, primary: true),
        ]),
      ], 12));
}

class _EditUser extends StatefulWidget {
  const _EditUser({required this.u});
  final User u;
  @override
  State<_EditUser> createState() => _EditUserState();
}

class _EditUserState extends State<_EditUser> {
  late String name = widget.u.name, email = widget.u.email, dept = widget.u.dept;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Field(label: 'Full name', child: Input(initial: name, onChanged: (v) => name = v)),
        Field(label: 'University email', child: Input(initial: email, keyboard: TextInputType.emailAddress, onChanged: (v) => email = v)),
        Field(label: 'Department', child: Select(value: dept, items: store.lists.depts, onChanged: (v) => setState(() => dept = v))),
        Text("Login ID ${widget.u.loginId ?? ''} can't be changed. Change the role in the list.", style: xs(context)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Save', () async {
            if (name.trim().isEmpty) {
              store.toast('Enter a name');
              return;
            }
            if (await store.save('users', widget.u.copy({'name': name.trim(), 'email': email, 'dept': dept}))) {
              if (context.mounted) Navigator.pop(context);
              store.toast('User updated');
            }
          }, primary: true),
        ]),
      ], 12));
}

class _ResetPassword extends StatefulWidget {
  const _ResetPassword({required this.loginId, required this.name});
  final String loginId, name;
  @override
  State<_ResetPassword> createState() => _ResetPasswordState();
}

class _ResetPasswordState extends State<_ResetPassword> {
  String pw = '';
  bool busy = false;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Text('Set a new password for ${widget.name} (Login ID ${widget.loginId}). Share it with them; they should change it later.', style: muted(context)),
        Field(label: 'New password', child: Input(autofocus: true, onChanged: (v) => pw = v)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn(busy ? 'Saving…' : 'Reset password', busy ? null : () async {
            if (pw.isEmpty) {
              store.toast('Enter a new password');
              return;
            }
            setState(() => busy = true);
            try {
              await api.resetPassword(widget.loginId, pw);
              if (context.mounted) Navigator.pop(context);
              store.toast('Password reset for ${widget.name}');
            } catch (e) {
              store.toast('$e');
              if (mounted) setState(() => busy = false);
            }
          }, primary: true),
        ]),
      ], 12));
}

class _RenameTag extends StatefulWidget {
  const _RenameTag({required this.tag});
  final String tag;
  @override
  State<_RenameTag> createState() => _RenameTagState();
}

class _RenameTagState extends State<_RenameTag> {
  late String name = widget.tag;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Field(label: 'New name', child: Input(initial: name, autofocus: true, onChanged: (v) => name = v)),
        Text('All documents with this tag will be updated.', style: xs(context)),
        SheetFoot(children: [
          btn('Cancel', () => Navigator.pop(context)),
          btn('Rename', () async {
            try {
              await api.renameTag(widget.tag, name.trim());
              if (context.mounted) Navigator.pop(context);
              store.toast('Tag renamed');
              store.load();
            } catch (e) {
              store.toast('$e');
            }
          }, primary: true),
        ]),
      ], 12));
}

/// The OpenAI API key the assistant uses. Typed in once; afterwards only its last 4 characters are shown.
class _OpenAiKey extends StatefulWidget {
  const _OpenAiKey();
  @override
  State<_OpenAiKey> createState() => _OpenAiKeyState();
}

class _OpenAiKeyState extends State<_OpenAiKey> {
  Json? status;
  final key = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    api.keyStatus().then((s) {
      if (mounted) setState(() => status = s);
    }, onError: (e) {
      if (mounted) setState(() => error = '$e');
    });
  }

  Future<void> run(Future<Json> Function() action, String done) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final s = await action();
      setState(() => status = s);
      key.clear();
      store.toast(done);
    } catch (e) {
      setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    final source = str(s?['source']);
    final where = s == null
        ? 'Checking…'
        : source == 'admin'
            ? 'Using the key ending ••••${s['last4']}, saved by ${s['by']} on ${s['at']}.'
            : source == 'env'
                ? "Using the key from the server's settings file, ending ••••${s['last4']}."
                : "No key is set. The assistant can't answer questions or read uploads until one is added.";
    return Section(
      title: 'OpenAI API key',
      trailing: s == null ? null : Pill(source == 'none' ? 'Not set' : 'Connected', kind: source == 'none' ? 'bad' : 'ok'),
      padded: true,
      children: [
        Text(where, style: sm(context)),
        TextField(
          controller: key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(hintText: source == 'none' ? 'Paste the API key (sk-…)' : 'Paste a new key to replace it'),
          onChanged: (_) => setState(() {}),
        ),
        btn(busy ? 'Checking…' : 'Save key', busy || key.text.trim().isEmpty ? null : () => run(() => api.setKey(key.text.trim()), 'API key saved. The assistant uses it from now on.'), primary: true),
        if (error.isNotEmpty) Note(kind: 'bad', text: error),
        Text('The key is checked with OpenAI before it is saved, stored on the server only and never shown again. Create or revoke keys at platform.openai.com → API keys.',
            style: xs(context)),
        if (source == 'admin')
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            btn('Remove saved key', busy ? null : () => run(api.removeKey, 'Saved key removed')),
            const SizedBox(height: 4),
            Text("Goes back to the key in the server's settings file, if there is one.", style: xs(context)),
          ]),
      ],
    );
  }
}

class _AuditLog extends StatefulWidget {
  const _AuditLog();
  @override
  State<_AuditLog> createState() => _AuditLogState();
}

class _AuditLogState extends State<_AuditLog> {
  String act = '';
  @override
  Widget build(BuildContext context) {
    final acts = store.audit.map((a) => a.s('act')).toSet().toList();
    final rows = store.audit.where((a) => act.isEmpty || a.s('act') == act).toList();
    return Section(title: 'Audit log', children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: Select(value: act, items: acts, empty: 'All actions', onChanged: (v) => setState(() => act = v))),
      if (rows.isEmpty) const EmptyBox('No audit entries yet.'),
      if (rows.length > 300) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Showing 300 of ${rows.length}. Filter by action to narrow it.', style: xs(context))),
      for (final a in rows.take(300))
        Row2(
          title: a.s('what'),
          meta: '${a.s('t')} · ${a.s('who')}',
          trail: TagChip(a.s('act')),
        ),
    ]);
  }
}
