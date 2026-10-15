/// Records as the server sends them. Each wraps its JSON so that saving a changed copy keeps every
/// field the server has, including ones this app doesn't show.
library;

import 'api.dart';

String str(dynamic v) => v == null ? '' : (v is String ? v : '$v');
List<String> strs(dynamic v) => v is List ? v.map(str).toList() : const [];

/// Answers saved before the server cleaned them may hold objects where text belongs; show their text.
String txt(dynamic x) => x is String
    ? x
    : x is Map
        ? str(x.values.isEmpty ? '' : x.values.first)
        : str(x);

class Rec {
  const Rec(this.j);
  final Json j;
  String get id => str(j['id']);
  String s(String k) => str(j[k]);
  Json copy(Json patch) => {...j, ...patch};
}

const statuses = ['Active', 'Pending', 'Draft', 'Changes requested', 'Superseded', 'Withdrawn', 'Expired', 'Rejected'];

class TextBlock {
  const TextBlock(this.j);
  final Json j;
  String get id => str(j['id']);
  dynamic get text => j['text'];
  String get kind => str(j['kind']);
  bool get isRow => j['text'] is List;
  List<String> get cells => strs(j['text']);
  String get plain => j['text'] is List ? strs(j['text']).join(' | ') : str(j['text']);
}

List<List<TextBlock>> pagesOf(dynamic v) =>
    v is List ? v.map((p) => (p as List).map((b) => TextBlock(Map<String, dynamic>.from(b as Map))).toList()).toList() : [];
List<List<Json>> pagesJson(List<List<TextBlock>> pages) => pages.map((p) => p.map((b) => b.j).toList()).toList();

class ApprovalStep {
  const ApprovalStep(this.j);
  final Json j;
  String get step => str(j['step']);
  String get by => str(j['by']);
  String get date => str(j['date']);
  String get kind => str(j['kind']);
  String get note => str(j['note']);
}

class Doc extends Rec {
  const Doc(super.j);
  String get title => s('title');
  String get ref => s('ref');
  String get type => s('type');
  String get authority => s('authority');
  String get dept => s('dept');
  String get institution => s('institution');
  String get date => s('date');
  String get effective => s('effective');
  String get expiry => s('expiry');
  List<String> get audience => strs(j['audience']);
  List<String> get tags => strs(j['tags']);
  String get visibility => s('visibility');
  String get status => s('status');
  String get fileType => s('fileType');
  String get lang => s('lang');
  String get description => s('description');
  String get uploadedBy => s('uploadedBy');
  String get uploadedOn => s('uploadedOn');
  List<String> get related => strs(j['related']);
  String? get revisionOf => j['revisionOf'] as String?;
  String? get supersededBy => j['supersededBy'] as String?;
  String get withdrawReason => s('withdrawReason');
  List<Json> get versions => List<Json>.from(j['versions'] as List? ?? const []);
  List<ApprovalStep> get approvals => (j['approvals'] as List? ?? const []).map((a) => ApprovalStep(Map<String, dynamic>.from(a as Map))).toList();
  bool get hasPages => j['pages'] != null;
  List<List<TextBlock>> get pages => pagesOf(j['pages']);
  num? get ocr => j['ocr'] as num?;
  bool get sample => j['sample'] == true;
  String? get uploaderId => j['uploader_id'] as String?;
  Json? get file => j['file'] == null ? null : Map<String, dynamic>.from(j['file'] as Map);
  String get mime => str(file?['mime']);
  List<String> get unsure => strs(j['unsure']);
  bool get isPdf => mime == 'application/pdf';
  bool get isImage => mime.startsWith('image/');
  /// PDFs and photos can be shown as they are; for text, Word and Excel the text view is the document.
  bool get previewable => isPdf || isImage;
  /// Pages in the original file (PDFs), or one for a photo.
  int get originalPages => isPdf ? ((file?['pages'] as num?)?.toInt() ?? 1) : 1;
  String get nextVersion {
    final v = versions.isEmpty ? '1.0' : str(versions.last['v']);
    return ((double.tryParse(v) ?? 1.0) + 0.1).toStringAsFixed(1);
  }
}

class Cite {
  const Cite(this.j);
  final Json j;
  String get doc => str(j['doc']);
  int get page => (j['page'] as num?)?.toInt() ?? 1;
  String get block => str(j['block']);
  String get quote => str(j['quote']);
}

class Answer {
  const Answer(this.j);
  final Json j;
  String get label => txt(j['label']);
  Json? get banner => j['banner'] == null ? null : Map<String, dynamic>.from(j['banner'] as Map);
  List<Json> get body => (j['body'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  List<Cite> get cites => (j['cites'] as List? ?? const []).map((e) => Cite(Map<String, dynamic>.from(e as Map))).toList();
  List<String> get follow => (j['follow'] as List? ?? const []).map(txt).where((e) => e.isNotEmpty).toList();
  List<String> get queries => strs(j['queries']);
  List<String> get checks => strs(j['checks']);
}

class Msg {
  const Msg(this.j);
  final Json j;
  String get id => str(j['id']);
  String get role => str(j['role']);
  bool get isUser => role == 'user';
  String get text => str(j['text']);
  String get q => str(j['q']);
  bool get pending => j['pending'] == true;
  String? get status => j['status'] as String?;
  String? get draft => j['draft'] as String?;
  String? get error => j['error'] as String?;
  Answer? get answer => j['answer'] == null ? null : Answer(Map<String, dynamic>.from(j['answer'] as Map));
  String? get fb => j['fb'] as String?;
}

class Chat extends Rec {
  const Chat(super.j);
  String get title => s('title');
  List<Msg> get msgs => (j['msgs'] as List? ?? const []).map((m) => Msg(Map<String, dynamic>.from(m as Map))).toList();
  bool get saved => j['saved'] == true;
  String get savedName => s('savedName');
  String? get at => j['at'] as String?;
  String? get when => j['when'] as String?;
}

class Deadline extends Rec {
  const Deadline(super.j);
  String get title => s('title');
  String get date => s('date');
  String get doc => s('doc');
  int get page => (j['page'] as num?)?.toInt() ?? 1;
  String get block => s('block');
  String get quote => s('quote');
  String get owner => s('owner');
  String get aud => s('aud');
  String get dept => s('dept');
  bool get conflict => j['conflict'] == true;
  bool get done => j['done'] == true;
}

class Collection extends Rec {
  const Collection(super.j);
  String get name => s('name');
  String get desc => s('desc');
  List<String> get docs => strs(j['docs']);
  String? get owner => j['owner'] as String?;
  String get ownerName => s('ownerName').isNotEmpty ? s('ownerName') : s('owner');
  String get updated => s('updated');
}

class User extends Rec {
  const User(super.j);
  String get name => s('name');
  String get email => s('email');
  String get role => s('role');
  String get dept => s('dept');
  bool get active => j['active'] == true;
  String get last => s('last');
  String? get loginId => j['login_id'] as String?;
}

/// The signed-in person, from /me.
class Session {
  const Session(this.j);
  final Json j;
  String get loginId => str(j['login_id']);
  String get name => str(j['name']).isEmpty ? 'User' : str(j['name']);
  String get email => str(j['email']);
  String get role => str(j['role']).isEmpty ? 'Viewer' : str(j['role']);
  String get dept => str(j['dept']);
  bool get dev => j['dev'] == true;
}

class Lists {
  const Lists(this.j);
  final Json j;
  List<String> get tags => strs(j['TAGS']);
  List<String> get auds => strs(j['AUDS']);
  List<String> get depts => strs(j['DEPTS']);
  List<String> get types => strs(j['TYPES']);
  List<String> get auths => strs(j['AUTHS']);
  List<String> get insts => strs(j['INSTS']);
  List<String> get vis => strs(j['VIS']);
  String visDesc(String v) => str((j['VIS_DESC'] as Map?)?[v]);
}

class AiSettings {
  const AiSettings(this.j);
  final Json j;
  bool flag(String k, bool dflt) => j[k] is bool ? j[k] as bool : dflt;
  bool get showConf => flag('showConf', true);
  String get lang => str(j['lang']).isEmpty ? 'auto' : str(j['lang']);
  int get maxSources => (j['maxSources'] as num?)?.toInt() ?? 8;
}
