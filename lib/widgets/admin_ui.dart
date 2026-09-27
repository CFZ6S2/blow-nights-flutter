import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/firestore_utils.dart';
import '../navigation.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'language_selector.dart';

/// Shared building blocks for the admin / B2B panels (super-admin, admin, city-manager, master-partner, venue-admin).

/// httpsCallable(functions, name)(data) → res.data as a map.
Future<Map<String, dynamic>> callFn(String name, [Map<String, Object?>? data]) async {
  final res = await FirebaseFunctions.instance.httpsCallable(name).call(data);
  final d = res.data;
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}

/// `e.message` of a callable/Firestore error, like the web's `toast(e.message || fallback)`.
String errorMessage(Object e, String fallback) {
  if (e is FirebaseFunctionsException) return e.message ?? fallback;
  final s = e.toString();
  final i = s.indexOf('] ');
  return i >= 0 ? s.substring(i + 2) : fallback;
}

/// `https://ui-avatars.com/api/?name=…&background=random` fallback used by the admin lists.
String avatarUrl(Map<String, dynamic> u) {
  final foto = u['fotoUrl'];
  if (foto is String && foto.isNotEmpty) return foto;
  return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent((u['nick'] as String?) ?? 'U')}&background=random';
}

String shortDate(Object? v) {
  final d = parseDate(v);
  return d == null ? '' : '${d.day}/${d.month}/${d.year}';
}

/// `bg-white/5 border border-white/10 rounded-3xl p-6`.
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 24,
    this.color,
    this.borderColor,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? Tw.w(0.05)) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor ?? Tw.w(0.1)),
        ),
        child: child,
      );
}

/// Section title: `text-sm font-black uppercase tracking-widest text-slate-300`.
class AdminSectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const AdminSectionTitle(this.text, {super.key, this.color = Tw.slate300, this.icon});

  @override
  Widget build(BuildContext context) => Row(children: [
        if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 8)],
        Expanded(child: Label(text, size: 13, color: color)),
      ]);
}

/// Stat tile: icon + uppercase label on top, big number below.
class AdminStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final bool centered;
  const AdminStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.trailing,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) => AdminCard(
        padding: const EdgeInsets.all(16),
        radius: 16,
        child: centered
            ? Column(children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 4),
                Text(value, style: tw(24, weight: black)),
                Label(label, color: Tw.slate500, align: TextAlign.center, maxLines: 2),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Label(label, color: Tw.slate500, maxLines: 2)),
                  ?trailing,
                ]),
                const SizedBox(height: 8),
                Text(value, style: tw(28, weight: black)),
              ]),
      );
}

/// Two-column grid of equal tiles (web `grid grid-cols-2 gap-4`).
class AdminGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double gap;
  const AdminGrid({super.key, required this.children, this.columns = 2, this.gap = 12});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final row = children.sublist(i, (i + columns).clamp(0, children.length));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = 0; j < columns; j++) ...[
            if (j > 0) SizedBox(width: gap),
            Expanded(child: j < row.length ? row[j] : const SizedBox.shrink()),
          ],
        ]),
      ));
    }
    return Column(children: [
      for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: gap), rows[i]],
    ]);
  }
}

/// Small colored button: `px-4 py-2 bg-{color} rounded-lg text-xs font-bold uppercase`.
class AdminButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final Color? textColor;
  final bool outlined;
  final bool loading;
  final bool expand;
  final double fontSize;
  final EdgeInsets padding;
  const AdminButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color = Tw.fuchsia600,
    this.textColor,
    this.outlined = false,
    this.loading = false,
    this.expand = false,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || loading;
    final fg = textColor ?? (outlined ? color : Tw.white);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: fontSize + 4, color: fg),
        if ((loading || icon != null) && label.isNotEmpty) const SizedBox(width: 8),
        if (label.isNotEmpty)
          Flexible(
            child: Text(label.toUpperCase(),
                textAlign: TextAlign.center, style: tw(fontSize, weight: bold, color: fg, tracking: 0.05)),
          ),
      ],
    );
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Pressable(
        onTap: disabled ? () {} : onTap!,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: outlined ? color.withValues(alpha: 0.15) : color,
            borderRadius: BorderRadius.circular(12),
            border: outlined ? Border.all(color: color.withValues(alpha: 0.3)) : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Pill badge: `px-2 py-1 bg-{color}/20 text-{color} rounded-md text-[10px] font-bold uppercase`.
class AdminBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color? background;
  const AdminBadge(this.text, {super.key, this.color = Tw.slate400, this.background});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background ?? color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(text.toUpperCase(), style: tw(10, weight: bold, color: color)),
      );
}

InputDecoration adminInputDecoration(String? hint, {Color focus = Tw.fuchsia500}) => InputDecoration(
      hintText: hint,
      hintStyle: tw(14, color: Tw.slate500),
      isDense: true,
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Tw.w(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: focus)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );

/// `bg-black/30 border border-white/10 rounded-xl px-4 py-3 text-sm focus:border-fuchsia-500`.
class AdminInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool obscure;
  final Color focus;
  const AdminInput({
    super.key,
    required this.controller,
    this.hint,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.obscure = false,
    this.focus = Tw.fuchsia500,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        keyboardType: keyboardType,
        maxLines: maxLines,
        obscureText: obscure,
        textInputAction: onSubmitted != null ? TextInputAction.search : null,
        style: tw(14),
        cursorColor: focus,
        decoration: adminInputDecoration(hint, focus: focus),
      );
}

/// `<select>` equivalent styled like the web's dark selects.
class AdminSelect<T> extends StatelessWidget {
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool dense;
  const AdminSelect({super.key, required this.value, required this.items, this.onChanged, this.hint, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final hasValue = items.any((i) => i.$1 == value);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(dense ? 8 : 12),
        border: Border.all(color: Tw.w(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: hasValue ? value : null,
          isExpanded: !dense,
          isDense: dense,
          dropdownColor: Tw.slate900,
          borderRadius: BorderRadius.circular(12),
          iconEnabledColor: Tw.slate400,
          hint: hint == null ? null : Text(hint!, style: tw(dense ? 12 : 14, color: Tw.slate500)),
          style: tw(dense ? 12 : 14),
          items: [
            for (final (v, label) in items)
              DropdownMenuItem<T>(value: v, child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// On/off switch: `h-7 w-14 rounded-full` with ✓/✕ knob.
class AdminToggle extends StatelessWidget {
  final bool value;
  final bool busy;
  final VoidCallback? onTap;
  final Color activeColor;
  const AdminToggle({super.key, required this.value, this.busy = false, this.onTap, this.activeColor = Tw.fuchsia600});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        child: Opacity(
          opacity: busy ? 0.5 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 28,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: value ? activeColor : Tw.slate800, borderRadius: BorderRadius.circular(99)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Tw.white, shape: BoxShape.circle),
                child: busy
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.slate400))
                    : Text(value ? '✓' : '✕', style: tw(10, weight: black, color: value ? activeColor : Tw.slate400)),
              ),
            ),
          ),
        ),
      );
}

/// Horizontal chip filter row (`flex gap-2 overflow-x-auto`).
class AdminChips<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelect;
  final Color color;
  const AdminChips({super.key, required this.items, required this.selected, required this.onSelect, this.color = Tw.fuchsia600});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (v, label) in items) ...[
            Pressable(
              onTap: () => onSelect(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: v == selected ? color : Tw.w(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: v == selected ? color : Tw.w(0.05)),
                ),
                child: Text(label.toUpperCase(),
                    style: tw(12, weight: bold, tracking: 0.05, color: v == selected ? Tw.white : Tw.slate400)),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ]),
      );
}

/// Centered loading / empty message (`text-center py-20 text-slate-500`).
class AdminEmpty extends StatelessWidget {
  final String text;
  final bool loading;
  const AdminEmpty(this.text, {super.key, this.loading = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(children: [
          if (loading) ...[
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)),
            const SizedBox(height: 16),
          ],
          Text(text, textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
        ]),
      );
}

/// Port of useConfirm().promptInput({ message, placeholder, confirmText }) → text or null when cancelled.
Future<String?> promptInput(BuildContext context,
    {required String message, String? placeholder, String? confirmText, String initial = '', bool multiline = false}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (ctx) => Dialog(
      backgroundColor: Tw.slate900,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Tw.w(0.1))),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center, style: tw(14, weight: medium, color: Tw.slate300, height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: multiline ? 4 : 1,
            style: tw(14),
            decoration: adminInputDecoration(placeholder),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: AdminButton(
                label: 'Cancelar',
                color: Tw.slate400,
                outlined: true,
                expand: true,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdminButton(
                label: confirmText ?? 'Confirmar',
                expand: true,
                onTap: () => Navigator.of(ctx).pop(ctrl.text),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

/// Full-screen form sheet used for the "create / edit" modals of the admin panels.
Future<T?> showAdminSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tw.slate900,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
              child: Row(children: [
                Expanded(child: Text(title, style: tw(18, weight: black))),
                IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close, color: Tw.slate400)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.of(ctx).padding.bottom),
                child: builder(ctx),
              ),
            ),
          ]),
        ),
      ),
    );

/// Uppercase field label above an input (`text-xs font-bold uppercase tracking-widest text-slate-500`).
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 12),
        child: Label(text, size: 11, weight: bold, color: Tw.slate500),
      );
}

/// Port of components/AdminTopBar.tsx: language, Admin, Panel Maestro, logout.
class AdminTopBar extends StatelessWidget {
  final bool showAdmin;
  final bool showMaster;
  const AdminTopBar({super.key, this.showAdmin = true, this.showMaster = true});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    Widget btn(IconData icon, VoidCallback onTap, {Color hover = Tw.slate400}) => Pressable(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
            child: Icon(icon, size: 18, color: hover),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const LanguageSelector(),
      if (showAdmin && auth.isAdmin) ...[const SizedBox(width: 8), btn(Icons.admin_panel_settings, () => openRoute(context, AppRoute.admin))],
      if (showMaster && auth.isSuperAdmin) ...[const SizedBox(width: 8), btn(Icons.workspace_premium, () => openRoute(context, AppRoute.superAdmin))],
      const SizedBox(width: 8),
      btn(Icons.logout, () async {
        await context.read<AuthProvider>().logout();
        if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      }),
    ]);
  }
}

/// `w-2 h-2 rounded-full animate-pulse`.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, required this.color, this.size = 8});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.5).animate(_c),
        child: Container(width: widget.size, height: widget.size, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
      );
}
