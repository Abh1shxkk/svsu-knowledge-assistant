/// The same REST API the web app uses. The sign-in token is kept in the phone's secure storage.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://svsu.54-173-64-109.sslip.io/api');

/// Thrown with the server's message; status 401 means the session is missing or expired.
class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

class Api {
  Api._();
  static final Api instance = Api._();

  static const _tokenKey = 'svsu_token';
  static const _urlKey = 'svsu_api_url';
  final _secure = const FlutterSecureStorage();
  /// Replaceable in tests.
  http.Client client = http.Client();

  String baseUrl = defaultApiUrl;
  String? token;

  /// Called when the server says the session is no longer valid.
  void Function()? onUnauthorized;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_urlKey) ?? defaultApiUrl;
    try {
      token = await _secure.read(key: _tokenKey);
    } catch (_) {
      token = null;
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, baseUrl);
  }

  Future<void> setToken(String? t) async {
    token = t;
    try {
      if (t == null) {
        await _secure.delete(key: _tokenKey);
      } else {
        await _secure.write(key: _tokenKey, value: t);
      }
    } catch (_) {/* storage unavailable: the session lasts until the app closes */}
  }

  Map<String, String> _headers([Map<String, String>? extra]) => {
        if (token != null) 'Authorization': 'Bearer $token',
        ...?extra,
      };

  Future<http.Response> _check(String path, http.Response res) async {
    if (res.statusCode == 401 && !path.startsWith('/login')) {
      await setToken(null);
      onUnauthorized?.call();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiError(res.statusCode, _detail(res.bodyBytes) ?? 'Request failed (${res.statusCode})');
    }
    return res;
  }

  static String? _detail(List<int> body) {
    try {
      final j = jsonDecode(utf8.decode(body));
      final d = j is Map ? j['detail'] : null;
      if (d is String) return d;
      if (d is List && d.isNotEmpty) return d.map((e) => e is Map ? (e['msg'] ?? '$e') : '$e').join('; ');
    } catch (_) {}
    return null;
  }

  Future<http.Response> _send(String method, String path, {Object? json}) async {
    final uri = Uri.parse(baseUrl + path);
    final headers = _headers(json != null ? {'Content-Type': 'application/json'} : null);
    final body = json != null ? jsonEncode(json) : null;
    late http.Response res;
    try {
      res = await switch (method) {
        'GET' => client.get(uri, headers: headers),
        'POST' => client.post(uri, headers: headers, body: body),
        'PUT' => client.put(uri, headers: headers, body: body),
        'DELETE' => client.delete(uri, headers: headers),
        _ => throw ArgumentError(method),
      }
          .timeout(const Duration(minutes: 3));
    } on TimeoutException {
      throw ApiError(0, 'The server took too long to answer. Please try again.');
    } catch (e) {
      if (e is ApiError) rethrow;
      throw ApiError(0, "Couldn't reach the server. Check your internet connection.");
    }
    return _check(path, res);
  }

  Future<dynamic> _json(String method, String path, {Object? json}) async {
    final res = await _send(method, path, json: json);
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<Uint8List> _bytes(String method, String path, {Object? json}) async =>
      (await _send(method, path, json: json)).bodyBytes;

  Future<dynamic> _multipart(String path, Map<String, String> fields, String filePath, String fileName) async {
    final req = http.MultipartRequest('POST', Uri.parse(baseUrl + path))
      ..headers.addAll(_headers())
      ..fields.addAll(fields)
      ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    late http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(req).timeout(const Duration(minutes: 10)));
    } on TimeoutException {
      throw ApiError(0, 'The upload took too long. Please try again.');
    } catch (e) {
      if (e is ApiError) rethrow;
      throw ApiError(0, "Couldn't reach the server. Check your internet connection.");
    }
    await _check(path, res);
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static String enc(String s) => Uri.encodeComponent(s);

  // ---------- Sign in ----------
  /// A session, or (with two-step verification) a ticket for the code step: mfa "code" or "setup".
  Future<Json> login(String loginId, String password) async =>
      await _json('POST', '/login', json: {'login_id': loginId, 'password': password}) as Json;
  Future<Json> loginMfa(String ticket, String code) async =>
      await _json('POST', '/login/mfa', json: {'ticket': ticket, 'code': code}) as Json;
  Future<Json> loginMfaSetup(String ticket) async => await _json('POST', '/login/mfa/setup', json: {'ticket': ticket}) as Json;
  Future<Json> myMfa() async => await _json('GET', '/me/mfa') as Json;
  Future<Json> mfaSetup() async => await _json('POST', '/me/mfa/setup') as Json;
  Future<Json> mfaEnable(String code) async => await _json('POST', '/me/mfa/enable', json: {'code': code}) as Json;
  Future<void> mfaDisable(String password) => _json('POST', '/me/mfa/disable', json: {'password': password});
  Future<List<String>> mfaUsers() async => List<String>.from(await _json('GET', '/accounts/mfa') as List);
  Future<void> resetMfa(String loginId) => _json('DELETE', '/accounts/${enc(loginId)}/mfa');
  Future<Json> me() async => await _json('GET', '/me') as Json;

  // ---------- Records ----------
  Future<Json> records() async => await _json('GET', '/records') as Json;
  Future<void> put(String kind, String id, Object data) => _json('PUT', '/records/$kind/${enc(id)}', json: data);
  Future<void> remove(String kind, String id) => _json('DELETE', '/records/$kind/${enc(id)}');
  Future<Json> document(String id) async => await _json('GET', '/documents/${enc(id)}') as Json;
  Future<Uint8List> originalFile(String id) => _bytes('GET', '/documents/${enc(id)}/file');
  Future<Uint8List> originalPage(String id, int n) => _bytes('GET', '/documents/${enc(id)}/file/page/$n');
  /// Where a quote sits on page n of the original: boxes [x0, y0, x1, y1] as fractions of the page.
  Future<List<List<double>>> pageHighlight(String id, int n, String q) async {
    final j = await _json('GET', '/documents/${enc(id)}/file/page/$n/highlight?q=${enc(q.length > 1500 ? q.substring(0, 1500) : q)}') as Json;
    return [for (final r in j['rects'] as List) [for (final v in r as List) (v as num).toDouble()]];
  }
  Future<List<String>> search(String q) async => List<String>.from(await _json('GET', '/search?q=${enc(q)}') as List);
  Future<List<List<String>>> checks(String id) async =>
      (await _json('GET', '/documents/${enc(id)}/checks') as List).map((e) => List<String>.from(e as List)).toList();
  Future<List<Json>> notifications() async => List<Json>.from(await _json('GET', '/notifications') as List);
  Future<Json> reportSummary() async => await _json('GET', '/reports/summary') as Json;
  Future<void> requestDoc(String q, String dept, String note) =>
      _json('POST', '/unanswered/request', json: {'q': q, 'dept': dept, 'note': note});
  Future<void> renameTag(String old, String next) => _json('POST', '/admin/tags/rename', json: {'old': old, 'new': next});
  Future<List<Json>> deadlines(String docId) async => List<Json>.from(await _json('POST', '/documents/${enc(docId)}/deadlines') as List);

  // ---------- Asking ----------
  /// The answer, received while it is made: progress and the text as it is written, then the answer.
  Future<Json> askStream(Json body, void Function({String? status, String? delta}) onEvent) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/ask/stream'))
      ..headers.addAll(_headers({'Content-Type': 'application/json', 'Accept': 'text/event-stream'}))
      ..body = jsonEncode(body);
    late http.StreamedResponse res;
    try {
      res = await client.send(req).timeout(const Duration(minutes: 2));
    } catch (_) {
      throw ApiError(0, "Couldn't reach the server. Check your internet connection.");
    }
    if (res.statusCode != 200) {
      await _check('/ask/stream', http.Response.bytes(await res.stream.toBytes(), res.statusCode));
    }
    // Finishes as soon as the answer arrives; the connection is then closed without waiting for it.
    final result = Completer<Json>();
    var buf = '';
    late StreamSubscription<String> sub;
    void fail(Object e) {
      if (!result.isCompleted) result.completeError(e);
      sub.cancel();
    }

    sub = res.stream.transform(utf8.decoder).timeout(const Duration(minutes: 3)).listen(
      (chunk) {
        if (result.isCompleted) return;
        buf += chunk.replaceAll('\r\n', '\n');
        for (var i = buf.indexOf('\n\n'); i >= 0; i = buf.indexOf('\n\n')) {
          final line = buf.substring(0, i);
          buf = buf.substring(i + 2);
          if (!line.startsWith('data: ')) continue;
          try {
            final e = jsonDecode(line.substring(6)) as Json;
            if (e['done'] != null) {
              result.complete(e['done'] as Json);
              sub.cancel();
              return;
            }
            if (e['error'] != null) return fail(ApiError(0, '${e['error']}'));
            onEvent(status: e['status'] as String?, delta: e['delta'] as String?);
          } catch (e) {
            return fail(e is ApiError ? e : ApiError(0, 'The answer could not be read. Please try again.'));
          }
        }
      },
      onError: (_) => fail(ApiError(0, 'The connection dropped while the answer was being written. Please try again.')),
      onDone: () => fail(ApiError(0, 'The answer was cut off. Please try again.')),
      cancelOnError: true,
    );
    return result.future;
  }

  // ---------- Uploads ----------
  Future<Json> extract(String path, String name) async => await _multipart('/extract', {}, path, name) as Json;
  Future<void> importFile(String path, String name, String batch, {required String visibility, required bool publish, required String dept}) =>
      _multipart('/imports', {'batch': batch, 'visibility': visibility, 'publish': '$publish', 'dept': dept}, path, name);
  Future<List<Json>> imports() async => List<Json>.from(await _json('GET', '/imports') as List);
  Future<Json> retryImport(String batch) async => await _json('POST', '/imports/${enc(batch)}/retry') as Json;

  // ---------- Reports and administration ----------
  Future<Json> quality() async => await _json('GET', '/reports/quality') as Json;
  Future<void> runQuality(bool fresh) => _json('POST', '/reports/quality/run?new=$fresh');
  /// Administrators only. The key itself never comes back, only its last 4 characters.
  Future<Json> keyStatus() async => await _json('GET', '/admin/openai-key') as Json;
  Future<Json> setKey(String key) async => await _json('PUT', '/admin/openai-key', json: {'key': key}) as Json;
  Future<Json> removeKey() async => await _json('DELETE', '/admin/openai-key') as Json;
  Future<Uint8List> exportDocx(String title, List<Json> items) => _bytes('POST', '/export/docx', json: {'title': title, 'items': items});
  Future<void> createAccount(Json a) => _json('POST', '/accounts', json: a);
  Future<Json> updateProfile(String name, String email) async =>
      await _json('PUT', '/me/profile', json: {'name': name, 'email': email}) as Json;
  Future<void> changePassword(String current, String next) => _json('PUT', '/me/password', json: {'current': current, 'new': next});
  Future<void> resetPassword(String loginId, String password) =>
      _json('PUT', '/accounts/${enc(loginId)}/password', json: {'password': password});
}

final api = Api.instance;
