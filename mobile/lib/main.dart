import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'screens/admin.dart';
import 'screens/ask.dart';
import 'screens/collections.dart';
import 'screens/dashboard.dart';
import 'screens/deadlines.dart';
import 'screens/doc_detail.dart';
import 'screens/library.dart';
import 'screens/login.dart';
import 'screens/profile.dart';
import 'screens/reports.dart';
import 'screens/review.dart';
import 'screens/saved.dart';
import 'screens/upload.dart';
import 'store.dart';
import 'theme.dart';
import 'update.dart';
import 'widgets/shell.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await api.init();
  final prefs = await SharedPreferences.getInstance();
  store.themeMode = prefs.getString('svsu_theme') == 'dark' ? ThemeMode.dark : ThemeMode.light;
  themeMode.value = store.themeMode;
  setTheme = (m) {
    store.themeMode = m;
    themeMode.value = m;
    store.changed();
    prefs.setString('svsu_theme', m == ThemeMode.dark ? 'dark' : 'light');
  };
  runApp(const SvsuApp());
}

/// Light or dark; the app redraws only when this changes, not on every record change.
final themeMode = ValueNotifier(ThemeMode.light);

/// Routes mirror the web app's paths, so notification links work as they are.
final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final atLogin = state.matchedLocation == '/login';
    if (api.token == null) return atLogin ? null : '/login';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/', builder: (_, _) => const Gate(child: DashboardScreen())),
    GoRoute(
      path: '/ask',
      builder: (_, s) => Gate(child: AskScreen(q: s.uri.queryParameters['q'], chat: s.uri.queryParameters['c'], group: s.uri.queryParameters['group'], key: ValueKey(s.uri.toString()))),
    ),
    GoRoute(
      path: '/library',
      builder: (_, s) => Gate(child: LibraryScreen(params: s.uri.queryParameters, key: ValueKey(s.uri.toString()))),
      routes: [GoRoute(path: ':id', builder: (_, s) => Gate(child: DocDetailScreen(id: s.pathParameters['id']!)))],
    ),
    GoRoute(path: '/upload', builder: (_, _) => const Gate(child: UploadScreen())),
    GoRoute(path: '/review', builder: (_, _) => const Gate(child: ReviewScreen())),
    GoRoute(
      path: '/collections',
      builder: (_, _) => const Gate(child: CollectionsScreen()),
      routes: [GoRoute(path: ':id', builder: (_, s) => Gate(child: CollectionDetailScreen(id: s.pathParameters['id']!)))],
    ),
    GoRoute(path: '/deadlines', builder: (_, _) => const Gate(child: DeadlinesScreen())),
    GoRoute(path: '/saved', builder: (_, _) => const Gate(child: SavedScreen())),
    GoRoute(path: '/reports', builder: (_, _) => const Gate(child: ReportsScreen())),
    GoRoute(path: '/admin', builder: (_, _) => const Gate(child: AdminScreen())),
    GoRoute(path: '/profile', builder: (_, _) => const Gate(child: ProfileScreen())),
  ],
);

class SvsuApp extends StatefulWidget {
  const SvsuApp({super.key});
  @override
  State<SvsuApp> createState() => _SvsuAppState();
}

class _SvsuAppState extends State<SvsuApp> {
  @override
  void initState() {
    super.initState();
    api.onUnauthorized = () => store.logout();
    store.onSignedOut = () {
      Notices.instance.stop();
      router.go('/login');
    };
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (context, mode, _) => MaterialApp.router(
          title: 'SVSU Assistant',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: messengerKey,
          theme: buildTheme(Pal.light, Brightness.light),
          darkTheme: buildTheme(Pal.dark, Brightness.dark),
          themeMode: mode,
          routerConfig: router,
        ),
      );
}

/// Loads the person's records before showing a screen, like the web app's layout.
class Gate extends StatefulWidget {
  const Gate({super.key, required this.child});
  final Widget child;
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with StoreListener {
  @override
  void initState() {
    super.initState();
    if (!store.loaded && store.error.isEmpty) {
      store.load().then((_) {
        if (store.loaded) Notices.instance.start();
      });
    } else if (store.loaded) {
      Notices.instance.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (store.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) checkForUpdate(context);
      });
      return widget.child;
    }
    final err = store.error;
    return Scaffold(
      body: Center(
        child: err.isNotEmpty && err != 'no-session'
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text("Couldn't reach the server.", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(err, textAlign: TextAlign.center, style: muted(context)),
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, children: [
                        btn('Try again', () {
                          store.error = '';
                          store.load().then((_) {
                            if (store.loaded) Notices.instance.start();
                          });
                          store.changed();
                        }, primary: true),
                        btn('Sign out', () => store.logout()),
                      ]),
                    ]),
                  ),
                ),
              )
            : const Spinner(size: 28),
      ),
    );
  }
}
