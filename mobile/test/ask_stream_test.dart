import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:svsu_assistant/api.dart';

void main() {
  test('askStream reads progress, text and the finished answer', () async {
    final events = [
      {'status': 'Searching the records…'},
      {'delta': 'Teaching staff get '},
      {'done': {'label': 'One source', 'body': [], 'cites': [], 'follow': []}},
    ];
    api.client = MockClient((_) async => http.Response.bytes(utf8.encode(events.map((e) => 'data: ${jsonEncode(e)}\n\n').join()), 200));
    final seen = <String>[];
    final a = await api.askStream({'question': 'q'}, ({status, delta}) => seen.add(status ?? delta ?? ''));
    expect(seen, ['Searching the records…', 'Teaching staff get ']);
    expect(a['label'], 'One source');
  });
}
