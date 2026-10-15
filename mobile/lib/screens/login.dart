import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/mfa.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final loginId = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  bool busy = false;
  String error = '';
  String? mfa; // "code" or "setup", after the password
  String? ticket;
  bool hide = true;

  Future<void> enter(String token) async {
    await api.setToken(token);
    await store.load();
    if (store.loaded) Notices.instance.start();
    if (mounted) context.go('/');
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (ticket != null) {
        final r = await api.loginMfa(ticket!, code.text.trim());
        await enter('${r['token']}');
        return;
      }
      final r = await api.login(loginId.text.trim(), password.text);
      if (r['token'] != null) {
        await enter('${r['token']}');
        return;
      }
      setState(() {
        mfa = r['mfa'] as String?;
        ticket = r['ticket'] as String?;
      });
    } catch (e) {
      setState(() => error = '$e'.isEmpty ? 'Sign in failed.' : '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  void serverSettings() {
    final c = TextEditingController(text: api.baseUrl);
    showSheet(context, title: 'Server', builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('The address of the SVSU Assistant API. Change it only if IT asks you to.', style: muted(ctx)),
          const SizedBox(height: 12),
          Field(label: 'API address', child: Input(controller: c, keyboard: TextInputType.url)),
          SheetFoot(children: [
            btn('Reset', () => c.text = defaultApiUrl),
            btn('Save', () async {
              await api.setBaseUrl(c.text);
              if (ctx.mounted) Navigator.pop(ctx);
              store.toast('Server saved');
            }, primary: true),
          ]),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (mfa == 'setup') {
      return Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Set up two-step verification', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Your role needs a code from your phone as well as your password. This takes a minute, once.', style: muted(context)),
            const SizedBox(height: 18),
            SetupMfa(
              start: () => api.loginMfaSetup(ticket!),
              confirm: (c) async {
                final r = await api.loginMfa(ticket!, c);
                await api.setToken('${r['token']}');
                return List<String>.from(r['recovery'] as List? ?? const []);
              },
              onDone: () => enter(api.token!),
            ),
          ]),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
            color: p.heroBg,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Image.asset('assets/logo.png', width: 40, height: 40),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Swami Vivekanand Subharti University', style: TextStyle(color: p.heroFg, fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('Subhartipuram, Meerut · Uttar Pradesh', style: TextStyle(color: p.heroFg.withValues(alpha: .7), fontSize: 12)),
                  ]),
                ),
                IconButton(onPressed: serverSettings, icon: Icon(Icons.settings_outlined, color: p.heroFg.withValues(alpha: .7)), tooltip: 'Server'),
              ]),
              const SizedBox(height: 26),
              Text('SVSU Knowledge Assistant', style: TextStyle(color: p.heroFg, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('विश्वविद्यालय के पत्र, सूचनाएँ और नीतियाँ — एक जगह, प्रमाण सहित।', style: TextStyle(color: p.heroFg.withValues(alpha: .85), fontSize: 14)),
              const SizedBox(height: 14),
              for (final (i, t) in [
                (Icons.description_outlined, "Answers only from the university's own letters, notices and policies"),
                (Icons.check, 'Every answer cites the exact page and passage'),
                (Icons.language, 'Ask in Hindi or English'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Icon(i, size: 16, color: p.heroFg.withValues(alpha: .8)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t, style: TextStyle(color: p.heroFg.withValues(alpha: .85), fontSize: 13))),
                  ]),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (mfa == 'code') ...[
                  const Text('Two-step verification', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Enter the 6-digit code from your authenticator app. Lost your phone? Enter one of your recovery codes instead.', style: muted(context)),
                  const SizedBox(height: 16),
                  Field(
                    label: 'Code',
                    child: TextField(
                      controller: code,
                      autofocus: true,
                      keyboardType: TextInputType.visiblePassword,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      style: const TextStyle(fontFamily: monoFont, fontSize: 18, letterSpacing: 2),
                      onSubmitted: (_) => submit(),
                    ),
                  ),
                ] else ...[
                  const Text('Sign in', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Use the Login ID and password your administrator gave you.', style: muted(context)),
                  const SizedBox(height: 16),
                  Field(
                    label: 'Login ID',
                    child: TextField(
                      controller: loginId,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(hintText: 'e.g. 636325823'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Field(
                    label: 'Password',
                    child: TextField(
                      controller: password,
                      obscureText: hide,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => hide = !hide),
                        ),
                      ),
                    ),
                  ),
                ],
                if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Note(kind: 'bad', text: error)),
                const SizedBox(height: 18),
                btn(mfa != null ? 'Verify' : 'Sign in', busy ? null : () {
                  TextInput.finishAutofillContext();
                  submit();
                }, icon: mfa != null ? Icons.check : Icons.person_outline, primary: true, small: false, busy: busy),
                const SizedBox(height: 10),
                if (mfa != null)
                  TextButton(
                    onPressed: () => setState(() {
                      mfa = null;
                      ticket = null;
                      code.clear();
                      error = '';
                    }),
                    child: const Text('Back'),
                  )
                else
                  Text('No account? Ask an administrator to add you in Administration → Users.', style: xs(context), textAlign: TextAlign.center),
                const SizedBox(height: 18),
                Text('For staff of Swami Vivekanand Subharti University', style: xs(context), textAlign: TextAlign.center),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
