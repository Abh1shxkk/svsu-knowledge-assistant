/// The frame around every screen: the menu (the web's sidebar), the top bar with search, Ask,
/// notifications and theme, and the check that the person may open the screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'ui.dart';

class NavItem {
  const NavItem(this.route, this.label, this.icon, [this.visible]);
  final String route;
  final String label;
  final IconData icon;
  final bool Function()? visible;
}

/// Order and names match the web app.
final nav = [
  const NavItem('/', 'Dashboard', Icons.dashboard_outlined),
  const NavItem('/ask', 'Ask AI', Icons.chat_bubble_outline),
  const NavItem('/library', 'Document Library', Icons.description_outlined),
  NavItem('/upload', 'Upload Documents', Icons.upload_outlined, () => store.canUpload),
  NavItem('/review', 'Review & Approvals', Icons.verified_user_outlined, () => store.canApprove),
  const NavItem('/collections', 'Collections', Icons.layers_outlined),
  const NavItem('/deadlines', 'Actions & Deadlines', Icons.calendar_today_outlined),
  const NavItem('/saved', 'Saved Chats & Bookmarks', Icons.bookmark_border),
  NavItem('/reports', 'Reports & Feedback', Icons.bar_chart, () => store.canApprove),
  NavItem('/admin', 'Administration', Icons.tune, () => store.isAdmin),
];

/// Pages only some roles may open: the server enforces the data; this keeps the screens honest.
bool mayOpen(String route) {
  final top = '/${route.split('/').where((x) => x.isNotEmpty).firstOrNull ?? ''}';
  final item = nav.where((n) => n.route == top).firstOrNull;
  return item?.visible?.call() ?? true;
}

/// Notifications, worked out by the server; refreshed on each screen and every minute.
class Notices extends ValueNotifier<List<Json>> {
  Notices._() : super(const []);
  static final instance = Notices._();
  Timer? _timer;
  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    value = const [];
  }

  Future<void> refresh() async {
    if (api.token == null) return;
    try {
      value = await api.notifications();
    } catch (_) {}
  }
}

class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key, required this.route, required this.title, required this.body, this.actions = const [], this.fab, this.showAsk = true, this.bottom});
  final String route;
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? fab;
  final bool showAsk;
  final PreferredSizeWidget? bottom;
  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  @override
  void initState() {
    super.initState();
    Notices.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final allowed = mayOpen(widget.route);
    return PopScope(
      canPop: widget.route == '/' || context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(widget.title),
          bottom: widget.bottom,
          actions: [
            ...widget.actions,
            IconButton(
              tooltip: 'Search documents',
              icon: const Icon(Icons.search),
              onPressed: () => showSearchSheet(context),
            ),
            const _Bell(),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (k) {
                if (k == 'theme') {
                  setTheme(store.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
                } else if (k == 'profile') {
                  context.go('/profile');
                } else if (k == 'logout') {
                  store.logout();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'theme',
                  child: ListTile(
                    leading: Icon(store.themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                    title: Text(store.themeMode == ThemeMode.dark ? 'Light mode' : 'Dark mode'),
                  ),
                ),
                const PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('My profile'))),
                const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'))),
              ],
            ),
          ],
        ),
        floatingActionButton: widget.fab ??
            (widget.showAsk && widget.route != '/ask'
                ? FloatingActionButton.extended(
                    heroTag: 'ask',
                    onPressed: () => context.go('/ask'),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Ask AI'),
                  )
                : null),
        body: allowed ? widget.body : const _NoAccess(),
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.verified_user_outlined, size: 36, color: context.pal.fg3),
            const SizedBox(height: 10),
            const Text("You don't have access to this page", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Ask an administrator if you need it.', style: muted(context)),
            const SizedBox(height: 14),
            btn('Back to dashboard', () => context.go('/'), primary: true),
          ]),
        ),
      );
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final here = GoRouterState.of(context).uri.path;
    final active = here.startsWith('/library') ? '/library' : here.startsWith('/collections') ? '/collections' : '/${here.split('/').where((x) => x.isNotEmpty).firstOrNull ?? ''}';
    final pending = store.documents.where((d) => d.status == 'Pending').length;
    final soon = store.deadlines.where((x) => !x.done && daysTo(x.date) >= 0 && daysTo(x.date) <= 14).length;
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(children: [
              Image.asset('assets/logo.png', width: 38, height: 38),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SVSU Assistant', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('Records & policies', style: xs(context)),
              ]),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              for (final n in nav.where((n) => n.visible?.call() ?? true))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: ListTile(
                    dense: true,
                    selected: active == n.route,
                    selectedTileColor: p.accentSoft,
                    selectedColor: p.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    leading: Icon(n.icon, size: 21),
                    title: Text(n.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: switch (n.route) {
                      '/review' when pending > 0 => _Badge(pending),
                      '/deadlines' when soon > 0 => _Badge(soon),
                      _ => null,
                    },
                    onTap: () {
                      Navigator.pop(context);
                      context.go(n.route);
                    },
                  ),
                ),
            ]),
          ),
          const Divider(),
          ListTile(
            leading: Avatar(text: store.myInitials, size: 36),
            title: Text(store.myName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(store.role, style: xs(context)),
            onTap: () {
              Navigator.pop(context);
              context.go('/profile');
            },
            trailing: IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout, size: 20), onPressed: () => store.logout()),
          ),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: context.pal.accent, borderRadius: BorderRadius.circular(99)),
        child: Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.pal.accentInk)),
      );
}

void showSearchSheet(BuildContext context) {
  final c = TextEditingController();
  showSheet(context, title: 'Search documents', builder: (ctx) {
    void go() {
      Navigator.pop(ctx);
      context.go('/library?q=${Uri.encodeComponent(c.text.trim())}');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: c,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => go(),
        decoration: const InputDecoration(hintText: 'Search documents, reference numbers…', prefixIcon: Icon(Icons.search)),
      ),
      const SizedBox(height: 12),
      btn('Search', go, primary: true, small: false),
    ]);
  });
}

class _Bell extends StatelessWidget {
  const _Bell();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Json>>(
        valueListenable: Notices.instance,
        builder: (context, items, _) {
          final seen = _seen();
          final fresh = items.where((n) => !seen.contains(n['key'])).length;
          return IconButton(
            tooltip: fresh > 0 ? 'Notifications ($fresh new)' : 'Notifications',
            icon: Badge(isLabelVisible: fresh > 0, smallSize: 8, child: const Icon(Icons.notifications_none)),
            onPressed: () => _open(context),
          );
        },
      );

  static String get _prefsId => 'pf-${store.session?.loginId ?? ''}';
  static Set<String> _seen() => strsOf(store.prefs.where((p) => p.id == _prefsId).firstOrNull?.j['seen']).toSet();

  void _open(BuildContext context) {
    Notices.instance.refresh();
    showSheet(context, title: 'Notifications', builder: (ctx) => ValueListenableBuilder<List<Json>>(
          valueListenable: Notices.instance,
          builder: (ctx, items, _) {
            final seen = _seen();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (items.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      store.save('prefs', {'id': _prefsId, 'seen': [for (final n in items) n['key']]});
                      Navigator.pop(ctx);
                    },
                    child: const Text('Mark all read'),
                  ),
                ),
              if (items.isEmpty) const EmptyBox("You're all caught up."),
              for (final n in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Avatar(icon: Icons.notifications_none, size: 32),
                  title: Text('${n['text']}', style: TextStyle(fontSize: 14, fontWeight: seen.contains(n['key']) ? FontWeight.w400 : FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('${n['href']}');
                  },
                ),
            ]);
          },
        ));
  }
}

List<String> strsOf(dynamic v) => v is List ? v.map((e) => '$e').toList() : const [];

/// Light or dark, remembered on the phone.
void Function(ThemeMode) setTheme = (_) {};
