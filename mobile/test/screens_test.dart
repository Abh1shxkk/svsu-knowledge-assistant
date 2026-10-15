// Opens every screen against a fake API that serves the backend's sample data (backend/seed.json),
// on a phone-sized screen, and fails on any exception or layout overflow.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svsu_assistant/api.dart';
import 'package:svsu_assistant/main.dart';
import 'package:svsu_assistant/store.dart';
import 'package:svsu_assistant/widgets/shell.dart';

late Map<String, dynamic> seed;

Map<String, dynamic> _answer() => {
      'source': 'documents',
      'label': 'Conflicting instructions',
      'banner': {'kind': 'conflict', 'text': 'Two documents give different dates.'},
      'body': [
        {'p': 'Teaching staff get **8 casual leaves** a year {1}. The fee is due on 31 October {2}.'},
        {'ul': ['Apply on the ERP {1}', 'Get HOD approval']},
        {'table': {'head': ['Item', 'Date'], 'rows': [['Fee', '31 Oct {2}'], ['Exam', '10 Nov']]}},
      ],
      'cites': [
        {'doc': 'D01', 'page': 1, 'block': 'b2', 'quote': 'In supersession'},
        {'doc': 'D06', 'page': 1, 'block': 'b2', 'quote': ''},
      ],
      'follow': ['What about earned leave?'],
      'queries': ['casual leave teaching staff'],
      'checks': ['8 casual leaves'],
    };

Map<String, dynamic> records(String role) {
  final docs = [for (final d in seed['docs'] as List) Map<String, dynamic>.from(d as Map)..remove('pages')];
  return {
    'documents': docs,
    'collections': seed['collections'],
    'deadlines': seed['deadlines'],
    'chats': [
      {
        'id': 'ch1', 'title': 'Casual leave', 'saved': true, 'at': DateTime.now().toUtc().toIso8601String(),
        'msgs': [
          {'id': 'm1', 'role': 'user', 'text': 'How many casual leaves?'},
          {'id': 'm2', 'role': 'ai', 'q': 'How many casual leaves?', 'answer': _answer()},
        ],
      },
    ],
    'bm_answers': [{'id': 'ba1', 'chat': 'ch1', 'msg': 'm2', 'q': 'How many casual leaves?', 'when': '2026-10-10'}],
    'bm_passages': seed['bmPassages'],
    'feedback': seed['feedback'],
    'unanswered': seed['unanswered'],
    'conflicts': seed['conflicts'],
    'users': role == 'Administrator' ? seed['users'] : [],
    'audit': role == 'Administrator' ? seed['audit'] : [],
    'reminders': [{'id': 'rm1', 'deadline': 'dl1', 'days': 3, 'via': ['In the app']}],
    'prefs': [],
    'settings': [
      {'id': 'lists', for (final k in ['TAGS', 'AUDS', 'DEPTS', 'TYPES', 'AUTHS', 'INSTS', 'VIS', 'VIS_DESC']) k: seed[k]},
      {'id': 'ai', ...seed['aiSettings'] as Map},
      {'id': 'roles', 'matrix': seed['roleMatrix']},
      {'id': 'security', 'requireMfa': false},
    ],
  };
}

http.Client fakeApi(String role) => MockClient((req) async {
      final p = req.url.path.replaceFirst('/api', '');
      Map<String, dynamic>? doc(String id) {
        for (final d in seed['docs'] as List) {
          if ((d as Map)['id'] == id) return Map<String, dynamic>.from(d);
        }
        return null;
      }

      Object? body;
      if (p == '/me') {
        body = {'login_id': 'tester', 'name': 'Test Person', 'email': 't@svsu.example', 'role': role, 'dept': 'Administration'};
      } else if (p == '/records') {
        body = records(role);
      } else if (p == '/notifications') {
        body = [{'key': 'pending:2', 'text': '2 documents waiting for your approval', 'href': '/review'}];
      } else if (p.startsWith('/search')) {
        body = ['D01'];
      } else if (RegExp(r'^/documents/[^/]+/checks$').hasMatch(p)) {
        body = [['ok', 'Reference number found'], ['warn', 'No expiry date']];
      } else if (RegExp(r'^/documents/[^/]+$').hasMatch(p)) {
        body = doc(p.split('/').last);
      } else if (p.contains('/file')) {
        return http.Response('{"detail":"The original file isn\'t stored for this document."}', 404);
      } else if (p == '/reports/summary') {
        body = {'month': 42, 'cited': 88, 'weeks': [for (var i = 0; i < 8; i++) {'label': 'W${i + 1}', 'value': i * 2}]};
      } else if (p == '/reports/quality') {
        body = {
          'running': false,
          'latest': {
            'id': 'q1', 'at': '2026-10-10T10:00:00Z', 'questions': 30, 'paragraph_found': 90, 'document_found': 93, 'cited_right_document': 87,
            'answered_correctly': 80, 'correct_by_style': {'English': 85, 'Hindi': 70},
            'misses': [{'question': 'Q?', 'answer': 'A', 'got': 'B', 'found': true}],
          },
        };
      } else if (p == '/admin/openai-key') {
        body = {'source': 'env', 'last4': 'abcd'};
      } else if (p == '/accounts/mfa') {
        body = ['tester'];
      } else if (p == '/me/mfa') {
        body = {'on': false, 'required': false, 'recovery_left': 0};
      } else if (p == '/imports') {
        body = [
          {'batch': 'b1', 'by': 'Test', 'publish': false, 'updated': '2026-10-10T10:00:00Z', 'counts': {'done': 3, 'failed': 1}, 'failed': [{'name': 'x.pdf', 'error': 'Unreadable'}]},
        ];
      } else if (p == '/ask/stream') {
        final events = [
          {'status': 'Searching the records…'},
          {'delta': 'Teaching staff get '},
          {'done': _answer()},
        ];
        return http.Response.bytes(utf8.encode(events.map((e) => 'data: ${jsonEncode(e)}\n\n').join()), 200, headers: {'content-type': 'text/event-stream'});
      } else if (req.method == 'PUT' || req.method == 'DELETE') {
        body = {'ok': true};
      } else {
        return http.Response('{"detail":"Not found: $p"}', 404);
      }
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    });

Future<void> settle(WidgetTester t, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> boot(WidgetTester t, String role) async {
  t.view.physicalSize = const Size(1080, 2340); // a typical phone: 393 × 851 logical pixels
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  api.client = fakeApi(role);
  api.token = 'test-token';
  store.loaded = false;
  store.error = '';
  router.go('/');
  await t.pumpWidget(const SvsuApp());
  await settle(t);
  expect(store.loaded, isTrue, reason: store.error);
}

/// Closes the app and stops the notification timer before the framework checks for pending timers.
Future<void> finish(WidgetTester t) async {
  Notices.instance.stop();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

Future<void> visit(WidgetTester t, String route) async {
  router.go(route);
  await settle(t);
  noErrors(t, 'while showing $route');
}

/// Fails with the full diagnostic (which widget overflowed, and where) if anything went wrong.
void noErrors(WidgetTester t, String where) {
  final e = t.takeException();
  if (e is FlutterError) debugPrint('--- $where ${e.diagnostics.map((n) => n.toStringDeep()).join(" | ")}');
  expect(e, isNull, reason: where);
}

void main() {
  setUpAll(() {
    seed = jsonDecode(File('../backend/seed.json').readAsStringSync()) as Map<String, dynamic>;
  });

  const routes = [
    '/', '/ask', '/ask?c=ch1', '/library', '/library?status=history', '/library?q=leave', '/upload', '/review', '/collections',
    '/collections/C1', '/deadlines', '/saved', '/reports', '/admin', '/profile',
  ];

  testWidgets('every screen opens for an Administrator', (t) async {
    await boot(t, 'Administrator');
    for (final r in routes) {
      await visit(t, r);
    }
    await finish(t);
  });

  testWidgets('every document record opens, on every tab', (t) async {
    await boot(t, 'Administrator');
    for (final d in seed['docs'] as List) {
      await visit(t, '/library/${(d as Map)['id']}');
      for (final tab in ['Preview', 'Extracted text', 'Approval history', 'Versions', 'Related', 'Access', 'Actions & deadlines', 'Bookmarks', 'Overview']) {
        final f = find.textContaining(tab);
        if (f.evaluate().isEmpty) continue;
        await t.ensureVisible(f.first);
        await t.tap(f.first);
        await settle(t, 6);
        noErrors(t, 'tab $tab of ${d['id']}');
      }
    }
    await finish(t);
  });

  testWidgets('a Viewer sees no upload, review, reports or admin', (t) async {
    await boot(t, 'Viewer');
    for (final r in routes) {
      await visit(t, r);
    }
    router.go('/admin');
    await settle(t);
    expect(find.text("You don't have access to this page"), findsOneWidget);
    await finish(t);
  });

  testWidgets('asking streams an answer, and a citation opens the viewer', (t) async {
    await boot(t, 'Administrator');
    store.activeChat = null;
    await visit(t, '/ask');
    await t.enterText(find.byType(TextField).last, 'How many casual leaves?');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await settle(t, 20);
    noErrors(t, 'asking');
    expect(find.text('SVSU Assistant'), findsWidgets);
    expect(find.textContaining('Check before relying on this'), findsWidgets);
    // The numbered sources under the answer open the same viewer as the inline citation numbers.
    final source = find.textContaining('· page 1', findRichText: true).first;
    await t.ensureVisible(source);
    await t.tap(source);
    await settle(t, 15);
    noErrors(t, 'asking');
    expect(find.textContaining('Citation 1 of 2'), findsOneWidget);
    await t.tap(find.byTooltip('Next citation'));
    await settle(t, 10);
    expect(find.textContaining('Citation 2 of 2'), findsOneWidget);
    noErrors(t, 'asking');
    await finish(t);
  });
}
