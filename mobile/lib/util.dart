/// Small formatting helpers shared by every screen. Dates are ISO "YYYY-MM-DD".
library;

import 'dart:math';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayIso() => isoOf(DateTime.now());

final _isoRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime? parseIso(String? d) => d != null && _isoRe.hasMatch(d) ? DateTime.parse('${d}T00:00:00') : null;

/// "13 Oct 2026" from an ISO date; anything else (older records) is shown as written.
String fmtD(String? d) {
  if (d == null || d.isEmpty) return '—';
  final t = parseIso(d);
  return t == null ? d : '${t.day} ${_months[t.month - 1]} ${t.year}';
}

String monthShort(DateTime d) => _months[d.month - 1];
String monthYear(DateTime d) => '${_monthsLong[d.month - 1]} ${d.year}';

/// "13 Oct 2026, 11:42 am" from an ISO timestamp.
String fmtDateTime(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return iso ?? '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${t.day} ${_months[t.month - 1]} ${t.year}, $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

int daysTo(String d) {
  final t = parseIso(d);
  if (t == null) return 0;
  final today = parseIso(todayIso())!;
  return (t.difference(today).inHours / 24).round();
}

final _rand = Random();
String nid(String prefix) =>
    prefix + DateTime.now().millisecondsSinceEpoch.toRadixString(36) + _rand.nextInt(1 << 20).toRadixString(36).padLeft(4, '0').substring(0, 4);

String initials(String name) => name
    .replaceFirst(RegExp(r'^(Dr\.|Prof\.)\s*'), '')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0])
    .take(2)
    .join();

final _hindi = RegExp(r'[ऀ-ॿ]');
bool isHindi(String s) => _hindi.hasMatch(s);

String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

String blockText(dynamic text) => text is List ? text.map((e) => '$e').join(' | ') : '${text ?? ''}';

String fmtNum(int n) {
  // Indian grouping: 12,34,567
  final s = n.abs().toString();
  if (s.length <= 3) return '${n < 0 ? '-' : ''}$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${n < 0 ? '-' : ''}${parts.join(',')},$last3';
}

String greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
}
