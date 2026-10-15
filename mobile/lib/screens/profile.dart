import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/mfa.dart';
import '../widgets/shell.dart';
import '../widgets/ui.dart';

const _roleHelp = {
  'Administrator': 'Everything, including users, roles, access levels and settings.',
  'Approver': 'Upload, approve or reject documents, and see reports.',
  'Uploader': 'Upload documents and submit them for approval.',
  'Viewer': "Ask questions and read the documents you're allowed to see.",
};

class ProfileScreen extends StoreScreen {
  const ProfileScreen({super.key});

  @override
  Widget buildScreen(BuildContext context) {
    final u = store.session;
    final isTestAdmin = u?.dev ?? false;
    return AppScaffold(
      route: '/profile',
      title: 'My profile',
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: gap([
        Text('Your details, password and how the app looks for you.', style: muted(context)),
        Section(title: 'Your details', padded: true, children: [
          Row(children: [
            Avatar(text: store.myInitials, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(store.myName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text('${u?.role} · Login ID ${u?.loginId}', style: muted(context)),
              ]),
            ),
          ]),
          if (isTestAdmin)
            const Note(kind: 'warn', text: "You're signed in as the local test admin, which has no profile. Create your own account to edit details here.")
          else
            _DetailsForm(key: ValueKey(u?.loginId)),
          KV([
            ('Login ID', kvText(u?.loginId ?? '', isMono: true)),
            ('Department', kvText((u?.dept ?? '').isEmpty ? '—' : u!.dept)),
            ('Role', kvText('${u?.role} · ${_roleHelp[u?.role ?? 'Viewer'] ?? ''}')),
          ], labelWidth: 100),
          Text('Login ID, department and role decide what you can see, so only an administrator can change them.', style: xs(context)),
        ]),
        if (!isTestAdmin) const Section(title: 'Password', padded: true, children: [_PasswordForm()]),
        if (!isTestAdmin) const Section(title: 'Two-step verification', padded: true, children: [_TwoStep()]),
        Section(title: 'Appearance', padded: true, children: [
          Row(children: [
            const Expanded(child: Text('Theme')),
            Seg<ThemeMode>(
              options: const [(ThemeMode.light, 'Light', Icons.light_mode_outlined), (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined)],
              value: store.themeMode,
              onChanged: setTheme,
            ),
          ]),
        ]),
        Section(title: 'Server', padded: true, children: [
          Text(api.baseUrl, style: mono(context)),
          btn('Sign out', () => store.logout(), icon: Icons.logout),
        ]),
      ], 14)),
    );
  }
}

class _DetailsForm extends StatefulWidget {
  const _DetailsForm({super.key});
  @override
  State<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends State<_DetailsForm> {
  late final name = TextEditingController(text: store.session?.name ?? '');
  late final email = TextEditingController(text: store.session?.email ?? '');
  String error = '';
  bool busy = false;

  Future<void> save() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final updated = await api.updateProfile(name.text, email.text);
      store.session = Session({...?store.session?.j, ...updated});
      store.changed();
      store.toast('Profile saved');
    } catch (e) {
      setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Field(label: 'Full name', child: Input(controller: name)),
        Field(label: 'Email', child: Input(controller: email, keyboard: TextInputType.emailAddress)),
        if (error.isNotEmpty) Note(kind: 'bad', text: error),
        Align(alignment: Alignment.centerRight, child: btn(busy ? 'Saving…' : 'Save details', busy ? null : save, primary: true)),
      ], 12));
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm();
  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final current = TextEditingController(), next = TextEditingController(), again = TextEditingController();
  String error = '';
  bool busy = false;

  Future<void> submit() async {
    if (next.text != again.text) {
      setState(() => error = "The new passwords don't match.");
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await api.changePassword(current.text, next.text);
      current.clear();
      next.clear();
      again.clear();
      store.toast('Password changed');
    } catch (e) {
      setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
        Field(label: 'Current password', child: Input(controller: current, obscure: true)),
        Field(label: 'New password', child: Input(controller: next, obscure: true)),
        Field(label: 'Repeat new password', child: Input(controller: again, obscure: true)),
        Text('At least 10 characters, mixing letters with numbers or symbols.', style: xs(context)),
        if (error.isNotEmpty) Note(kind: 'bad', text: error),
        Align(alignment: Alignment.centerRight, child: btn(busy ? 'Saving…' : 'Change password', busy ? null : submit, primary: true)),
      ], 12));
}

/// A code from an authenticator app after the password, so a stolen password alone isn't enough.
class _TwoStep extends StatefulWidget {
  const _TwoStep();
  @override
  State<_TwoStep> createState() => _TwoStepState();
}

class _TwoStepState extends State<_TwoStep> {
  Json? st;
  String mode = ''; // "", "setup" or "off"
  final password = TextEditingController();
  String error = '';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() => api.myMfa().then((s) {
        if (mounted) setState(() => st = s);
      }, onError: (e) {
        if (mounted) setState(() => error = '$e');
      });

  Future<void> turnOff() async {
    setState(() => error = '');
    try {
      await api.mfaDisable(password.text);
      password.clear();
      setState(() => mode = '');
      refresh();
      store.toast('Two-step verification is off');
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = st;
    if (s == null) return error.isNotEmpty ? Note(kind: 'bad', text: error) : const Loading();
    if (mode == 'setup') {
      return SetupMfa(
        start: api.mfaSetup,
        confirm: (c) async => List<String>.from((await api.mfaEnable(c))['recovery'] as List? ?? const []),
        onDone: () {
          setState(() => mode = '');
          refresh();
          store.toast('Two-step verification is on');
        },
      );
    }
    final on = s['on'] == true, required = s['required'] == true;
    final left = (s['recovery_left'] as num?)?.toInt() ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap([
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Pill(on ? 'On' : 'Off', kind: on ? 'ok' : 'mute'),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            on
                ? 'Sign-in asks for a code from your phone. $left recovery code${left == 1 ? '' : 's'} left.'
                : "Add a code from your phone to your password, so a stolen password alone can't open your account.",
            style: sm(context),
          ),
        ),
      ]),
      if (!on) btn('Set up', () => setState(() => mode = 'setup'), primary: true),
      if (on && !required && mode != 'off') btn('Turn off', () => setState(() => mode = 'off')),
      if (on && required)
        Text("Required for your role, so it can't be turned off. Lost your phone? Use a recovery code, or ask an administrator to reset it.", style: xs(context)),
      if (mode == 'off') ...[
        Input(controller: password, obscure: true, hint: 'Your password'),
        Row(children: [
          btn('Turn off', turnOff, danger: true),
          const SizedBox(width: 8),
          TextButton(onPressed: () => setState(() => mode = ''), child: const Text('Cancel')),
        ]),
      ],
      if (error.isNotEmpty) Note(kind: 'bad', text: error),
    ], 10));
  }
}
