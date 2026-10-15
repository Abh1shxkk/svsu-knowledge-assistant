/// Setting up two-step verification: scan the QR code, type the first code, keep the recovery codes.
/// Used on the profile screen and during sign-in when a person's role requires it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'ui.dart';

class SetupMfa extends StatefulWidget {
  const SetupMfa({super.key, required this.start, required this.confirm, required this.onDone});
  final Future<Json> Function() start;
  final Future<List<String>> Function(String code) confirm;
  final VoidCallback onDone;
  @override
  State<SetupMfa> createState() => _SetupMfaState();
}

class _SetupMfaState extends State<SetupMfa> {
  Json? setup;
  final code = TextEditingController();
  List<String>? codes;
  String error = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    // once: each call makes a new key
    widget.start().then((s) {
      if (mounted) setState(() => setup = s);
    }, onError: (e) {
      if (mounted) setState(() => error = '$e');
    });
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final c = await widget.confirm(code.text.trim());
      setState(() => codes = c);
    } catch (e) {
      setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (codes != null) return RecoveryCodes(codes: codes!, onDone: widget.onDone);
    final secret = str(setup?['secret']);
    final key = RegExp(r'.{1,4}').allMatches(secret).map((m) => m.group(0)).join(' ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('1. Open an authenticator app (Google Authenticator, Microsoft Authenticator or similar).', style: sm(context)),
      const SizedBox(height: 4),
      Text('2. Scan this code from another phone, or add the key by hand. On this phone, tap "Copy key" and paste it into the app.', style: sm(context)),
      const SizedBox(height: 12),
      if (setup != null)
        Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.pal.line)),
            child: QrImageView(data: str(setup!['uri']), size: 180, backgroundColor: Colors.white),
          ),
        )
      else if (error.isEmpty)
        const Loading(),
      if (setup != null) ...[
        const SizedBox(height: 10),
        Center(child: Text('Key', style: muted(context))),
        Center(child: SelectableText(key, style: const TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1))),
        Center(
          child: TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: secret)),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy key'),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text('3. Enter the 6-digit code the app shows', style: sm(context)),
      const SizedBox(height: 6),
      Row(children: [
        SizedBox(
          width: 150,
          child: TextField(
            controller: code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontFamily: monoFont, fontSize: 18, letterSpacing: 3),
            decoration: const InputDecoration(counterText: ''),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 10),
        btn('Turn on', busy || setup == null || code.text.length != 6 ? null : submit, primary: true, busy: busy, small: false),
      ]),
      if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Note(kind: 'bad', text: error)),
    ]);
  }
}

class RecoveryCodes extends StatelessWidget {
  const RecoveryCodes({super.key, required this.codes, required this.onDone});
  final List<String> codes;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Note(
          kind: 'ok',
          title: 'Two-step verification is on.',
          text: "Keep these recovery codes somewhere safe. Each one works once, if you lose your phone. They won't be shown again.",
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.pal.line)),
          child: Wrap(spacing: 18, runSpacing: 8, children: [
            for (final c in codes) Text(c, style: const TextStyle(fontFamily: monoFont, fontSize: 15)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          btn('Copy', () => Clipboard.setData(ClipboardData(text: codes.join('\n'))), icon: Icons.copy),
          const SizedBox(width: 8),
          Expanded(child: btn("I've saved them", onDone, primary: true)),
        ]),
      ]);
}
