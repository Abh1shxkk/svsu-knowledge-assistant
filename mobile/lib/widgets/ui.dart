/// Small building blocks shared by every screen, matching the web app's components.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../util.dart';

// ---------- Text styles ----------
TextStyle sm(BuildContext c) => TextStyle(fontSize: 13, color: c.pal.fg);
TextStyle xs(BuildContext c) => TextStyle(fontSize: 12, color: c.pal.fg3);
TextStyle muted(BuildContext c) => TextStyle(fontSize: 13, color: c.pal.fg3);
TextStyle mono(BuildContext c) => TextStyle(fontFamily: monoFont, fontSize: 12, color: c.pal.fg3);
TextStyle bold(BuildContext c) => TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.pal.fg);

/// Pill colours by kind: ok, warn, bad, info, mute, mute2.
(Color, Color) tone(BuildContext c, String kind) {
  final p = c.pal;
  return switch (kind) {
    'ok' => (p.greenSoft, p.green),
    'warn' => (p.amberSoft, p.amber),
    'bad' => (p.redSoft, p.red),
    'info' => (p.accentSoft, p.accent),
    'mute2' => (p.surface3, p.fg2),
    _ => (p.surface3, p.fg3),
  };
}

const statusTone = {
  'Active': 'ok', 'Pending': 'warn', 'Changes requested': 'warn', 'Draft': 'mute',
  'Superseded': 'mute2', 'Withdrawn': 'bad', 'Expired': 'mute', 'Rejected': 'bad',
};

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.kind, this.icon});
  final String text;
  final String? kind;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone(context, kind ?? statusTone[text] ?? 'mute');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
        Flexible(child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

const _ftLabel = {'pdf': 'PDF', 'scan': 'SCAN', 'docx': 'DOCX', 'xlsx': 'XLSX', 'img': 'IMG', 'txt': 'TXT'};

/// File-type badge.
class Ft extends StatelessWidget {
  const Ft(this.kind, {super.key});
  final String kind;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = switch (kind) { 'pdf' => p.red, 'scan' => p.amber, 'docx' => p.accent, 'xlsx' => p.green, _ => p.fg3 };
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: .5))),
      child: Text(_ftLabel[kind] ?? 'FILE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color, letterSpacing: .3)),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.onRemove});
  final String text;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(8, 3, onRemove == null ? 8 : 2, 3),
        decoration: BoxDecoration(color: context.pal.surface3, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text, style: TextStyle(fontSize: 11.5, color: context.pal.fg2)),
          if (onRemove != null)
            InkWell(onTap: onRemove, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close, size: 13, color: context.pal.fg3))),
        ]),
      );
}

class Tags extends StatelessWidget {
  const Tags(this.tags, {super.key});
  final List<String> tags;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 4, runSpacing: 4, children: [for (final t in tags) TagChip(t)]);
}

/// A coloured note: warn, bad, info or ok.
class Note extends StatelessWidget {
  const Note({super.key, required this.kind, this.title, this.text, this.child});
  final String kind;
  final String? title;
  final String? text;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone(context, kind);
    final icon = switch (kind) { 'bad' => Icons.block, 'ok' => Icons.check_circle_outline, _ => Icons.warning_amber_rounded };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) Text(title!, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: context.pal.fg)),
            if (text != null && text!.isNotEmpty) Text(text!, style: TextStyle(fontSize: 13, color: context.pal.fg)),
            ?child,
          ]),
        ),
      ]),
    );
  }
}

class DateBox extends StatelessWidget {
  const DateBox(this.date, {super.key, this.inverse = false});
  final String date;
  final bool inverse;
  @override
  Widget build(BuildContext context) {
    final d = parseIso(date);
    final p = context.pal;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: inverse ? Colors.white.withValues(alpha: .1) : p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: inverse ? null : Border.all(color: p.line),
      ),
      child: Column(children: [
        Text(d == null ? '' : monthShort(d).toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: inverse ? p.heroFg.withValues(alpha: .7) : p.red)),
        Text(d == null ? '?' : '${d.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: inverse ? p.heroFg : p.fg)),
      ]),
    );
  }
}

/// "3 days overdue", "Due today", "In 5 days"…
class Due extends StatelessWidget {
  const Due(this.date, {super.key, this.done = false});
  final String date;
  final bool done;
  @override
  Widget build(BuildContext context) {
    if (done) return const Pill('Completed', kind: 'ok');
    final n = daysTo(date);
    if (n < 0) return Pill('${plural(-n, 'day')} overdue', kind: 'bad');
    if (n == 0) return const Pill('Due today', kind: 'bad');
    if (n <= 7) return Pill('In ${plural(n, 'day')}', kind: 'warn');
    return Pill('In $n days', kind: 'mute');
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.text, this.icon, this.size = 32});
  final String? text;
  final IconData? icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: context.pal.accentSoft, borderRadius: BorderRadius.circular(size * .32)),
        child: icon != null
            ? Icon(icon, size: size * .5, color: context.pal.accent)
            : Text(text ?? '', style: TextStyle(fontSize: size * .36, fontWeight: FontWeight.w700, color: context.pal.accent)),
      );
}

/// A card with an optional header row (title, trailing actions).
class Section extends StatelessWidget {
  const Section({super.key, this.title, this.sub, this.trailing, required this.children, this.padded = false});
  final String? title;
  final String? sub;
  final Widget? trailing;
  final List<Widget> children;
  final bool padded;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: xs(context))),
                  ]),
                ),
                ?trailing,
              ]),
            ),
          if (title != null) const Divider(),
          if (padded)
            Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap(children, 12)))
          else
            ...children,
        ]),
      );
}

List<Widget> gap(List<Widget> items, double size) => [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: size), items[i]],
    ];

class EmptyBox extends StatelessWidget {
  const EmptyBox(this.text, {super.key, this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        child: Column(children: [
          Text(text, textAlign: TextAlign.center, style: muted(context)),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 10), child: action),
        ]),
      );
}

class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 18, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CircularProgressIndicator(strokeWidth: 2, color: color ?? context.pal.accent));
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.all(30), child: Center(child: Spinner(size: 24)));
}

/// A tappable list row: lead · title/meta · trail.
class Row2 extends StatelessWidget {
  const Row2({super.key, this.lead, required this.title, this.meta, this.trail, this.onTap, this.titleStyle, this.wrapTitle = false});
  final Widget? lead;
  final String title;
  final String? meta;
  final Widget? trail;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;
  final bool wrapTitle;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.line))),
          child: Row(children: [
            if (lead != null) ...[lead!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: titleStyle ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    maxLines: wrapTitle ? null : 2, overflow: wrapTitle ? null : TextOverflow.ellipsis),
                if (meta != null && meta!.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(meta!, style: xs(context), maxLines: 3, overflow: TextOverflow.ellipsis)),
              ]),
            ),
            if (trail != null) ...[const SizedBox(width: 8), trail!],
          ]),
        ),
      );
}

/// Label: value rows (metadata).
class KV extends StatelessWidget {
  const KV(this.rows, {super.key, this.labelWidth = 120});
  final List<(String, Widget)> rows;
  final double labelWidth;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: labelWidth, child: Text(k, style: muted(context))),
              Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13.5), child: v)),
            ]),
          ),
      ]);
}

Widget kvText(String s, {bool isMono = false}) => Text(s, style: isMono ? const TextStyle(fontFamily: monoFont, fontSize: 13) : null);

/// A labelled form field with an optional hint or error underneath.
class Field extends StatelessWidget {
  const Field({super.key, this.label, this.req = false, this.hint, this.error, required this.child});
  final String? label;
  final bool req;
  final String? hint;
  final String? error;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(TextSpan(text: label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.pal.fg2), children: [
              if (req) TextSpan(text: ' *', style: TextStyle(color: context.pal.red)),
            ])),
          ),
        child,
        if (error != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(error!, style: TextStyle(fontSize: 12, color: context.pal.red)))
        else if (hint != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint!, style: xs(context))),
      ]);
}

class Input extends StatelessWidget {
  const Input({super.key, this.controller, this.initial, this.onChanged, this.hint, this.maxLines = 1, this.obscure = false,
      this.keyboard, this.error = false, this.autofocus = false, this.onSubmitted, this.style, this.prefix});
  final TextEditingController? controller;
  final String? initial;
  final ValueChanged<String>? onChanged;
  final String? hint;
  final int? maxLines;
  final bool obscure;
  final TextInputType? keyboard;
  final bool error;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final Widget? prefix;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        initialValue: controller == null ? initial : null,
        onChanged: onChanged,
        maxLines: obscure ? 1 : maxLines,
        minLines: 1,
        obscureText: obscure,
        keyboardType: keyboard,
        autofocus: autofocus,
        onFieldSubmitted: onSubmitted,
        style: style ?? const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: prefix,
          enabledBorder: error ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.pal.red)) : null,
        ),
      );
}

/// A dropdown; "" is shown as [empty] when given.
class Select extends StatelessWidget {
  const Select({super.key, required this.value, required this.items, required this.onChanged, this.empty, this.labels, this.error = false, this.enabled = true});
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final String? empty;
  final Map<String, String>? labels;
  final bool error;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final all = [if (empty != null) '', ...items.where((i) => i.isNotEmpty || empty == null)];
    final v = all.contains(value) ? value : (all.isEmpty ? null : all.first);
    return DropdownButtonFormField<String>(
      initialValue: v,
      key: ValueKey('$v${all.length}'),
      isExpanded: true,
      items: [
        for (final i in all)
          DropdownMenuItem(value: i, child: Text(i.isEmpty ? empty! : (labels?[i] ?? i), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
      ],
      onChanged: enabled ? (x) => onChanged(x ?? '') : null,
      decoration: InputDecoration(
        enabledBorder: error ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.pal.red)) : null,
      ),
    );
  }
}

/// A date field that opens the date picker.
class DateInput extends StatelessWidget {
  const DateInput({super.key, required this.value, required this.onChanged, this.error = false, this.clearable = false});
  final String value;
  final ValueChanged<String> onChanged;
  final bool error;
  final bool clearable;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: parseIso(value) ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
          );
          if (d != null) onChanged(isoOf(d));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            suffixIcon: clearable && value.isNotEmpty
                ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => onChanged(''))
                : const Icon(Icons.calendar_today_outlined, size: 18),
            enabledBorder: error ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.pal.red)) : null,
          ),
          child: Text(value.isEmpty ? 'Choose a date' : fmtD(value), style: TextStyle(fontSize: 14, color: value.isEmpty ? context.pal.fg3 : context.pal.fg)),
        ),
      );
}

/// Tick-box chips for picking several values (tags, audience…).
class MultiChips extends StatelessWidget {
  const MultiChips({super.key, required this.options, required this.selected, required this.onToggle});
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final o in options)
          FilterChip(
            label: Text(o),
            selected: selected.contains(o),
            onSelected: (_) => onToggle(o),
            showCheckmark: true,
            checkmarkColor: context.pal.accent,
            visualDensity: VisualDensity.compact,
          ),
      ]);
}

/// Radio cards with a title and description (visibility levels).
class RadioCards extends StatelessWidget {
  const RadioCards({super.key, required this.options, required this.value, required this.onChanged, this.describe, this.enabled = true});
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String Function(String)? describe;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
        children: gap([
          for (final o in options)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: enabled ? () => onChanged(o) : null,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: value == o ? context.pal.accent : context.pal.line2),
                  color: value == o ? context.pal.accentSoft : null,
                ),
                child: Row(children: [
                  Icon(value == o ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20,
                      color: !enabled ? context.pal.line2 : value == o ? context.pal.accent : context.pal.fg3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                      if (describe != null && describe!(o).isNotEmpty) Text(describe!(o), style: xs(context)),
                    ]),
                  ),
                ]),
              ),
            ),
        ], 8),
      );
}

/// A segmented choice (two to four options).
class Seg<T> extends StatelessWidget {
  const Seg({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String, IconData?)> options;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
        segments: [for (final (v, l, i) in options) ButtonSegment(value: v, label: Text(l), icon: i == null ? null : Icon(i, size: 16))],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
        showSelectedIcon: false,
        style: ButtonStyle(visualDensity: VisualDensity.compact, textStyle: WidgetStatePropertyAll(const TextStyle(fontSize: 13))),
      );
}

/// Small buttons used across screens.
Widget btn(String label, VoidCallback? onPressed, {IconData? icon, bool primary = false, bool danger = false, bool small = true, bool busy = false}) =>
    Builder(builder: (context) {
      final p = context.pal;
      final child = busy
          ? Spinner(size: 16, color: primary ? p.accentInk : null)
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ]);
      final pad = small ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : null;
      if (primary || danger) {
        return FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: danger ? p.red : null,
            foregroundColor: danger ? Colors.white : null,
            padding: pad,
            visualDensity: small ? VisualDensity.compact : null,
          ),
          child: child,
        );
      }
      return OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(padding: pad, visualDensity: small ? VisualDensity.compact : null),
        child: child,
      );
    });

// ---------- Sheets and dialogs ----------

/// A bottom sheet with a title, scrolling body and (optional) buttons at the bottom.
Future<T?> showSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .9),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), child: builder(ctx))),
          ]),
        ),
      ),
    );

/// The buttons at the bottom of a sheet form.
class SheetFoot extends StatelessWidget {
  const SheetFoot({super.key, required this.children, this.leading});
  final List<Widget> children;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(children: [
          ?leading,
          const Spacer(),
          ...gapH(children, 8),
        ]),
      );
}

List<Widget> gapH(List<Widget> items, double size) => [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(width: size), items[i]],
    ];

Future<bool> confirm(BuildContext context, {required String title, required Widget body, required String action, bool danger = true}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger ? FilledButton.styleFrom(backgroundColor: ctx.pal.red, foregroundColor: Colors.white) : null,
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Page header text: title and subtitle.
class PageHead extends StatelessWidget {
  const PageHead(this.title, {super.key, this.sub, this.actions = const []});
  final String title;
  final String? sub;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.3)),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub!, style: TextStyle(fontSize: 13.5, color: context.pal.fg2))),
        if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(spacing: 8, runSpacing: 8, children: actions)),
      ]);
}

/// Horizontal scrollable tabs with counts, like the web's Tabs.
class TabsBar extends StatelessWidget {
  const TabsBar({super.key, required this.tabs, required this.active, required this.onChange});
  final List<(String, String, int?)> tabs;
  final String active;
  final ValueChanged<String> onChange;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (k, label, count) in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(count == null ? label : '$label  $count'),
                selected: k == active,
                onSelected: (_) => onChange(k),
                showCheckmark: false,
                labelStyle: TextStyle(fontSize: 13, fontWeight: k == active ? FontWeight.w600 : FontWeight.w400, color: k == active ? context.pal.accent : context.pal.fg2),
              ),
            ),
        ]),
      );
}
