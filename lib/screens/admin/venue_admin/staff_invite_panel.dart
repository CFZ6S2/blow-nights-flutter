import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../i18n/i18n.dart';
import '../../../services/nfc_pass.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

const _panel = Color(0xFF11131F);
const _row = Color(0xFF1C1F38);
const _rowBorder = Color(0xFF3B3F68);
const _formBg = Color(0xFF07080D);
const _formBorder = Color(0xFF2B2F52);

String _time(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

/// Port of components/venue-admin/StaffInvitePanel.tsx ("Add staff"): a 24 h invite for door and/or bar, shown as a
/// QR and shared as a link; on Android this phone also hands it over by NFC while it's on screen
/// (services/nfc_pass.dart), so the employee taps phones in "I work at a venue".
class StaffInvitePanel extends StatefulWidget {
  final String venueId;
  final VoidCallback? onChanged;
  const StaffInvitePanel({super.key, required this.venueId, this.onChanged});

  @override
  State<StaffInvitePanel> createState() => _StaffInvitePanelState();
}

class _StaffInvitePanelState extends State<StaffInvitePanel> {
  final _scopes = {'door': true, 'bar': true};
  bool _creating = false;
  Map<String, dynamic>? _invite;
  List<Map<String, dynamic>> _live = [];

  @override
  void initState() {
    super.initState();
    _loadLive();
  }

  @override
  void didUpdateWidget(StaffInvitePanel old) {
    super.didUpdateWidget(old);
    if (old.venueId != widget.venueId) {
      _setInvite(null);
      _loadLive();
    }
  }

  @override
  void dispose() {
    NfcPass.hide(this);
    super.dispose();
  }

  String _label(String s) => s == 'door'
      ? context.t('staff_invite.scope_door', fallback: 'Puerta (entradas)')
      : context.t('staff_invite.scope_bar', fallback: 'Barra (consumiciones)');

  List<String> _list(Object? v) => [for (final x in (v is List ? v : const [])) '$x'];

  void _setInvite(Map<String, dynamic>? invite) {
    setState(() => _invite = invite);
    final url = invite?['url'];
    if (url is String) {
      NfcPass.show(this, url);
    } else {
      NfcPass.hide(this);
    }
  }

  Future<void> _loadLive() async {
    try {
      final res = await callFn('listStaffInvites', {'venueId': widget.venueId});
      if (mounted) setState(() => _live = [for (final i in (res['invites'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)]);
    } catch (_) {}
  }

  Future<void> _create() async {
    final picked = [for (final e in _scopes.entries) if (e.value) e.key];
    if (picked.isEmpty) {
      showToast(context, context.t('staff_invite.pick_scope', fallback: 'Elige puerta, barra o las dos.'), error: true);
      return;
    }
    setState(() => _creating = true);
    try {
      final res = await callFn('createStaffInvite', {'venueId': widget.venueId, 'scopes': picked});
      if (res['url'] is String) _setInvite(res);
      _loadLive();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, context.t('staff_invite.error', fallback: 'No se pudo generar la invitación.')), error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _revoke(String inviteId) async {
    try {
      await callFn('revokeStaffInvite', {'inviteId': inviteId});
      if (_invite?['inviteId'] == inviteId) _setInvite(null);
      if (mounted) showToast(context, context.t('staff_invite.revoked', fallback: 'Invitación desactivada'));
      _loadLive();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, context.t('staff_invite.error', fallback: 'No se pudo generar la invitación.')), error: true);
    }
  }

  String get _shareText {
    final venue = (_invite?['venueName'] as String?) ?? '';
    return '${context.t('staff_invite.whatsapp_text', fallback: 'Únete al equipo de {{venue}} en Blow Nights:', params: {'venue': venue})} ${_invite?['url']}';
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    return AdminCard(
      radius: 16,
      color: _panel,
      borderColor: Tw.fuchsia500.withValues(alpha: 0.3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('staff_invite.title', fallback: 'Añadir personal'), style: tw(20, weight: bold)),
        const SizedBox(height: 4),
        Text(context.t('staff_invite.desc'), style: tw(12, color: Tw.slate400)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final s in const ['door', 'bar'])
            FilterChip(
              selected: _scopes[s]!,
              onSelected: (on) => setState(() => _scopes[s] = on),
              avatar: Icon(s == 'door' ? Icons.qr_code_scanner : Icons.local_bar, size: 16, color: _scopes[s]! ? Tw.fuchsia300 : Tw.slate400),
              label: Text(_label(s), style: tw(13, weight: bold, color: _scopes[s]! ? Tw.white : Tw.slate400)),
              backgroundColor: _row,
              selectedColor: Tw.fuchsia600.withValues(alpha: 0.2),
              side: BorderSide(color: _scopes[s]! ? Tw.fuchsia500 : _rowBorder),
              showCheckmark: false,
            ),
          AdminButton(label: context.t('staff_invite.create', fallback: 'Generar QR'), loading: _creating, onTap: _create),
        ]),
        if (invite != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _formBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _formBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(12)),
                  child: QrImageView(data: invite['url'] as String, size: 176, padding: EdgeInsets.zero),
                ),
              ),
              const SizedBox(height: 12),
              Text(_list(invite['scopes']).map(_label).join(' · '), textAlign: TextAlign.center, style: tw(14, weight: bold)),
              const SizedBox(height: 6),
              Text(context.t('staff_invite.scan_hint'), textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
              if (NfcPass.available) ...[
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.nfc, size: 14, color: Tw.emerald400),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(context.t('staff_invite.nfc_hint'), textAlign: TextAlign.center, style: tw(12, color: Tw.emerald400)),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                AdminButton(
                  label: context.t('staff_invite.copy', fallback: 'Copiar enlace'),
                  color: Tw.slate400,
                  outlined: true,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: invite['url'] as String));
                    if (context.mounted) showToast(context, context.t('staff_invite.copied', fallback: 'Enlace copiado'));
                  },
                ),
                AdminButton(
                  label: context.t('staff_invite.whatsapp', fallback: 'Enviar por WhatsApp'),
                  color: Tw.emerald400,
                  outlined: true,
                  onTap: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText)}'), mode: LaunchMode.externalApplication),
                ),
                AdminButton(
                  label: context.t('finder.share', fallback: 'Compartir'),
                  icon: Icons.share,
                  color: Tw.slate400,
                  outlined: true,
                  onTap: () => SharePlus.instance.share(ShareParams(text: _shareText)),
                ),
                AdminButton(
                  label: context.t('staff_invite.revoke', fallback: 'Desactivar'),
                  color: Tw.red400,
                  outlined: true,
                  onTap: () => _revoke(invite['inviteId'] as String),
                ),
              ]),
              const SizedBox(height: 8),
              Text(context.t('staff_invite.expires', fallback: 'Caduca: {{time}}', params: {'time': _time((invite['expiresAt'] as num).toInt())}),
                  textAlign: TextAlign.center, style: tw(11, color: Tw.slate500)),
            ]),
          ),
        ],
        if (_live.isNotEmpty) ...[
          const SizedBox(height: 16),
          Label(context.t('staff_invite.live_title', fallback: 'Invitaciones activas'), color: Tw.slate500),
          const SizedBox(height: 8),
          for (final i in _live)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _row, borderRadius: BorderRadius.circular(12), border: Border.all(color: _rowBorder)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_list(i['scopes']).map(_label).join(' · '), style: tw(13, weight: bold)),
                    Text(
                      '${context.t('staff_invite.uses', fallback: 'Se han unido: {{count}}', params: {'count': i['uses'] ?? 0})} · '
                      '${context.t('staff_invite.expires', fallback: 'Caduca: {{time}}', params: {'time': _time((i['expiresAt'] as num).toInt())})}',
                      style: tw(11, color: Tw.slate400),
                    ),
                  ]),
                ),
                AdminButton(
                  label: context.t('staff_invite.revoke', fallback: 'Desactivar'),
                  color: Tw.red400,
                  outlined: true,
                  onTap: () => _revoke(i['inviteId'] as String),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}
