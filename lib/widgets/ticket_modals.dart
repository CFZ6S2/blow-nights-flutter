import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../models/firestore_utils.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Shared modal shell used by TransferTicketModal, ReportFraudModal, ListTicketModal, ClaimTicketModal.
Future<T?> showWebModal<T>(BuildContext context, Widget child) => showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'modal',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: Material(color: Colors.transparent, child: child),
          ),
        ),
      ),
      transitionBuilder: (_, a, _, c) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: c),
      ),
    );

String _fnError(Object e, String fallback) {
  if (e is FirebaseFunctionsException) return (e.message ?? fallback).replaceAll('FirebaseError: ', '');
  return fallback;
}

class _ModalCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final Color? titleColor;
  final String subtitle;
  final Color border;
  final List<Widget> children;
  const _ModalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.titleColor,
    Color? border,
  }) : border = border ?? const Color(0x1AFFFFFF);

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(maxWidth: 448, maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: Tw.slate900,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: border),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: tw(18, weight: black, tracking: -0.025, color: titleColor ?? Tw.white)),
                  Text(subtitle, style: tw(12, color: Tw.slate400)),
                ]),
              ),
              GestureDetector(onTap: () => Navigator.of(context).pop(), child: const Icon(Icons.close, color: Tw.slate500, size: 20)),
            ]),
            const SizedBox(height: 24),
            ...children,
          ]),
        ),
      );
}

Widget _iconBox(IconData icon, Color color, {Gradient? gradient}) => Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: gradient == null ? color.withValues(alpha: 0.2) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: gradient == null ? color : Tw.white),
    );

Widget _fieldLabel(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: tw(12, weight: bold, color: Tw.slate300)));

InputDecoration _input(String hint, {Color focus = Tw.fuchsia500, Widget? prefix, Widget? suffix}) => InputDecoration(
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
      fillColor: Tw.slate950,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Tw.w(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: focus)),
    );

Widget _errorBox(String e) => Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Tw.red500.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 14, color: Tw.red400),
        const SizedBox(width: 8),
        Expanded(child: Text(e, style: tw(12, color: Tw.red400))),
      ]),
    );

Widget _actions(BuildContext context,
        {required bool loading,
        required bool enabled,
        required VoidCallback onSubmit,
        required Gradient gradient,
        required IconData icon,
        required String label,
        String cancel = 'Cancelar'}) =>
    Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(children: [
        Expanded(
          child: Pressable(
            onTap: loading ? () {} : () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12)),
              child: Label(cancel, size: 12, weight: bold, color: Tw.slate300, tracking: 0.05, align: TextAlign.center),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Opacity(
            opacity: enabled && !loading ? 1 : 0.5,
            child: Pressable(
              onTap: enabled && !loading ? onSubmit : () {},
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(12)),
                child: loading
                    ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.white)))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(icon, size: 14, color: Tw.white),
                        const SizedBox(width: 6),
                        Flexible(child: Label(label, size: 12, color: Tw.white, tracking: 0.05, maxLines: 1)),
                      ]),
              ),
            ),
          ),
        ),
      ]),
    );

/// Port of TransferTicketModal.tsx
class TransferTicketModal extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const TransferTicketModal({super.key, required this.ticket});

  @override
  State<TransferTicketModal> createState() => _TransferTicketModalState();
}

class _TransferTicketModalState extends State<TransferTicketModal> {
  final _recipient = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recipient.addListener(() => setState(() {}));
  }

  Future<void> _submit() async {
    final clean = _recipient.text.trim();
    if (clean.isEmpty) {
      setState(() => _error = 'Introduce el @nick o correo electrónico del destinatario.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('transferTicket')
          .call({'ticketId': widget.ticket['id'], 'targetUserIdentifier': clean});
      if (mounted) Navigator.of(context).pop(res.data is Map ? (res.data as Map)['message'] as String? ?? '' : '');
    } catch (e) {
      setState(() => _error = _fnError(e, 'Error al transferir la entrada. Inténtalo de nuevo.'));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return _ModalCard(
      icon: _iconBox(Icons.send, Tw.fuchsia400),
      title: context.t('wallet.transfer_modal_title', fallback: 'Transferir entrada'),
      subtitle: safeStr(t['eventTitle'] ?? t['venueName']).isEmpty ? 'Entrada Blow Nights' : safeStr(t['eventTitle'] ?? t['venueName']),
      children: [
        _fieldLabel('Destinatario (@nick o email)'),
        TextField(
          controller: _recipient,
          enabled: !_loading,
          style: tw(14),
          decoration: _input('ej: @pedro o colega@gmail.com', prefix: const Icon(Icons.alternate_email, size: 18, color: Tw.slate500)),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Tw.emerald500.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.savings, size: 16, color: Tw.emerald400),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '0€ comisiones:', style: tw(12, weight: bold, color: Tw.emerald400)),
                  const TextSpan(text: ' En Blow Nights no cobramos gastos de gestión ni por transferir a tus amigos.'),
                ]),
                style: tw(12, color: Tw.emerald400),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tw.slate950, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.warning, size: 12, color: Tw.amber400),
              const SizedBox(width: 6),
              Expanded(child: Text('Tu código QR quedará invalidado de inmediato.', style: tw(11, weight: bold, color: Tw.amber400))),
            ]),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: '🛡️ '),
                TextSpan(text: 'Escudo Anti-Fraude:', style: tw(11, weight: bold, color: Tw.slate400)),
                const TextSpan(text: ' Si acordaste un pago con el destinatario (Bizum, etc.) y no te paga, podrás '),
                TextSpan(text: 'recuperar tu entrada y bloquear su acceso', style: tw(11, weight: bold, color: Tw.slate400)),
                const TextSpan(text: ' en cualquier momento antes de que empiece la fiesta.'),
              ]),
              style: tw(11, color: Tw.slate400, height: 1.4),
            ),
          ]),
        ),
        if (_error != null) _errorBox(_error!),
        _actions(context,
            loading: _loading,
            enabled: _recipient.text.trim().isNotEmpty,
            onSubmit: _submit,
            gradient: const LinearGradient(colors: [Tw.fuchsia600, Color(0xFFDB2777)]),
            icon: Icons.send,
            label: 'Transferir gratis'),
      ],
    );
  }
}

/// Port of ReportFraudModal.tsx
class ReportFraudModal extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const ReportFraudModal({super.key, required this.ticket});

  @override
  State<ReportFraudModal> createState() => _ReportFraudModalState();
}

class _ReportFraudModalState extends State<ReportFraudModal> {
  static const _reasons = [
    ('No me envió el Bizum / pago acordado', 'No me envió el Bizum / pago acordado'),
    ('Usuario sospechoso / intentó timarme', 'Usuario sospechoso / intentó timarme'),
    ('Error al transferir / destinatario incorrecto', 'Error al transferir / destinatario equivocado'),
    ('Otro motivo de incumplimiento', 'Otro motivo de incumplimiento'),
  ];
  String _reason = _reasons.first.$1;
  final _details = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('reportTicketFraud').call({
        'ticketId': widget.ticket['id'],
        'reason': _reason,
        'details': _details.text.trim(),
      });
      final msg = res.data is Map ? (res.data as Map)['message'] as String? : null;
      if (mounted) Navigator.of(context).pop(msg ?? 'Entrada recuperada y receptor bloqueado.');
    } catch (e) {
      setState(() => _error = _fnError(e, 'Error al procesar el reporte. Inténtalo de nuevo.'));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => _ModalCard(
        border: Tw.red500.withValues(alpha: 0.2),
        icon: _iconBox(Icons.gavel, Tw.red400),
        title: context.t('wallet.report_modal_title', fallback: 'Escudo Anti-Fraude'),
        titleColor: Tw.red400,
        subtitle: 'Recuperar entrada cedida',
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x66450A0A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.red500.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.block, size: 14, color: Tw.red400),
                const SizedBox(width: 6),
                Text('Bloqueo fulminante del receptor', style: tw(12, weight: bold, color: Tw.red400)),
              ]),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Vas a revocar el acceso a '),
                  TextSpan(text: safeStr(widget.ticket['client_name']).isEmpty ? 'este usuario' : safeStr(widget.ticket['client_name']),
                      style: tw(11, weight: bold, color: Tw.slate300)),
                  const TextSpan(
                      text: '. Su código QR dejará de funcionar de inmediato en la puerta del garito, la entrada volverá a tu posesión con un nuevo QR y registraremos el fraude contra su cuenta.'),
                ]),
                style: tw(11, color: Tw.slate300, height: 1.5),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Motivo del reporte'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: Tw.slate950, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _reason,
                isExpanded: true,
                dropdownColor: Tw.slate900,
                style: tw(12),
                items: [for (final r in _reasons) DropdownMenuItem(value: r.$1, child: Text(r.$2))],
                onChanged: _loading ? null : (v) => setState(() => _reason = v ?? _reason),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Detalles adicionales (opcional)'),
          TextField(
            controller: _details,
            enabled: !_loading,
            maxLines: 2,
            style: tw(12),
            decoration: _input('Explica brevemente lo ocurrido...', focus: Tw.red500),
          ),
          if (_error != null) _errorBox(_error!),
          _actions(context,
              loading: _loading,
              enabled: true,
              onSubmit: _submit,
              gradient: const LinearGradient(colors: [Color(0xFFDC2626), Color(0xFFE11D48)]),
              icon: Icons.shield,
              label: 'Bloquear y recuperar'),
        ],
      );
}

/// Port of ListTicketModal.tsx
class ListTicketModal extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const ListTicketModal({super.key, required this.ticket});

  @override
  State<ListTicketModal> createState() => _ListTicketModalState();
}

class _ListTicketModalState extends State<ListTicketModal> {
  late final int _originalCents = asInt(widget.ticket['price'] ?? widget.ticket['amount']);
  late final String _originalEuros = (_originalCents / 100).toStringAsFixed(2);
  late final _price = TextEditingController(
      text: widget.ticket['resalePrice'] != null ? (asInt(widget.ticket['resalePrice']) / 100).toStringAsFixed(2) : _originalEuros);
  final _notes = TextEditingController();
  final _whatsapp = TextEditingController();
  String _contact = 'chat';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _price.addListener(() => setState(() {}));
  }

  Future<void> _submit() async {
    final i18n = context.read<I18n>();
    final euros = double.tryParse(_price.text.replaceAll(',', '.'));
    if (euros == null || euros < 0) {
      setState(() => _error = i18n.t('resale.error_invalid_price', fallback: 'Introduce un precio válido mayor o igual a 0.'));
      return;
    }
    final cents = (euros * 100).round();
    if (_originalCents > 0 && cents > _originalCents) {
      setState(() => _error = i18n.t('resale.error_anti_scalp',
          fallback: 'Por política anti-especulación, el precio máximo no puede superar el original ($_originalEuros€).'));
      return;
    }
    if (_contact != 'chat' && _whatsapp.text.trim().isEmpty) {
      setState(() => _error = i18n.t('resale.error_whatsapp_required', fallback: 'Introduce tu número de WhatsApp para que los compradores puedan escribirte.'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('listTicketForResale').call({
        'ticketId': widget.ticket['id'],
        'resalePrice': cents,
        'notes': _notes.text.trim(),
        'contactMethod': _contact,
        if (_contact != 'chat') 'whatsappNumber': _whatsapp.text.trim(),
      });
      final msg = res.data is Map ? (res.data as Map)['message'] as String? : null;
      if (mounted) Navigator.of(context).pop((msg ?? '¡Entrada publicada en el mercado de la comunidad!', cents));
    } catch (e) {
      setState(() => _error = _fnError(e, 'No se pudo publicar la entrada. Inténtalo de nuevo.'));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    Widget contactBtn(String v, IconData icon, String label, Color c) => Expanded(
          child: Pressable(
            onTap: () => setState(() => _contact = v),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _contact == v ? c.withValues(alpha: 0.2) : Tw.w(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _contact == v ? c : Tw.w(0.1)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 14, color: _contact == v ? c : Tw.slate400),
                const SizedBox(width: 8),
                Text(label, style: tw(12, weight: bold, color: _contact == v ? c : Tw.slate400)),
              ]),
            ),
          ),
        );
    return _ModalCard(
      icon: _iconBox(Icons.storefront, Tw.emerald500, gradient: const LinearGradient(colors: [Color(0xFF059669), Color(0xFF14B8A6)])),
      title: context.t('resale.modal_title', fallback: 'Poner entrada en venta'),
      subtitle: '${safeStr(t['venueName'] ?? t['venueId'])} — ${safeStr(t['tierName'] ?? t['ticketType']).isEmpty ? 'Entrada' : safeStr(t['tierName'] ?? t['ticketType'])}',
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Tw.emerald500.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.verified, size: 18, color: Tw.emerald400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('0€ Gastos de gestión intermediarios', style: tw(11, weight: bold, color: const Color(0xFF6EE7B7))),
                Text('El 100% del dinero acordado va directo a ti sin que la plataforma te reste un solo céntimo.',
                    style: tw(10, color: Tw.emerald400.withValues(alpha: 0.8))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _fieldLabel(context.t('resale.price_label', fallback: 'Precio de venta (€)'))),
          if (_originalCents > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Original: '),
                TextSpan(text: '$_originalEuros€', style: tw(10, weight: bold, color: Tw.slate500)),
                const TextSpan(text: ' (Máx permitido)'),
              ]), style: tw(10, color: Tw.slate500)),
            ),
        ]),
        TextField(
          controller: _price,
          enabled: !_loading,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: tw(14, weight: black, color: Tw.emerald400),
          decoration: _input('ej: 15.00', focus: Tw.emerald500, suffix: Padding(
            padding: const EdgeInsets.only(right: 16, top: 14),
            child: Text('EUR', style: tw(12, weight: bold, color: Tw.slate500)),
          )),
        ),
        const SizedBox(height: 4),
        Text('⚖️ Por política anti-especulación, no se permite vender a un precio superior al original.', style: tw(9, color: Tw.slate500)),
        const SizedBox(height: 16),
        _fieldLabel(context.t('resale.contact_method', fallback: '¿Cómo prefieres que te contacten?')),
        Row(children: [
          contactBtn('chat', Icons.chat, 'Chat en la app', Tw.fuchsia300),
          const SizedBox(width: 8),
          contactBtn('whatsapp', Icons.phone, 'WhatsApp', const Color(0xFF6EE7B7)),
        ]),
        if (_contact != 'chat') ...[
          const SizedBox(height: 16),
          Text('Tu número de WhatsApp (con prefijo)', style: tw(11, weight: bold, color: Tw.slate300)),
          const SizedBox(height: 4),
          TextField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            style: tw(12),
            decoration: _input('+34 600 000 000', focus: Tw.emerald500),
          ),
        ],
        const SizedBox(height: 16),
        _fieldLabel(context.t('resale.notes_label', fallback: 'Detalles o ventajas de la entrada (opcional)')),
        TextField(
          controller: _notes,
          maxLength: 200,
          maxLines: 2,
          style: tw(12),
          decoration: _input('ej: Incluye 1 copa antes de la 01:30. No puedo ir por viaje.', focus: Tw.emerald500).copyWith(counterText: ''),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tw.slate950, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.shield, size: 12, color: Tw.fuchsia400),
              const SizedBox(width: 4),
              Text('¿Cómo funciona la venta?', style: tw(10, weight: bold, color: Tw.slate300)),
            ]),
            const SizedBox(height: 4),
            Text('1. La entrada aparecerá visible en el feed público de /entradas.', style: tw(10, color: Tw.slate400)),
            Text('2. El comprador te escribe, acordáis el pago directo (ej. Bizum) y se la transfieres a su @nick con 1 click.', style: tw(10, color: Tw.slate400)),
            Text('3. Si el comprador no cumple con el pago, tienes el botón Reportar impago para revocar su QR y recuperar tu entrada al instante.',
                style: tw(10, color: Tw.slate400)),
          ]),
        ),
        if (_error != null) _errorBox(_error!),
        _actions(context,
            loading: _loading,
            enabled: _price.text.trim().isNotEmpty,
            onSubmit: _submit,
            gradient: const LinearGradient(colors: [Color(0xFF059669), Color(0xFF0D9488)]),
            icon: Icons.storefront,
            label: 'Publicar en feed'),
      ],
    );
  }
}

/// Port of ClaimTicketModal.tsx
class ClaimTicketModal extends StatefulWidget {
  final String initialTicketId;
  const ClaimTicketModal({super.key, this.initialTicketId = ''});

  @override
  State<ClaimTicketModal> createState() => _ClaimTicketModalState();
}

class _ClaimTicketModalState extends State<ClaimTicketModal> {
  late final _ticket = TextEditingController(text: widget.initialTicketId);
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ticket.addListener(() => setState(() {}));
  }

  Future<void> _submit() async {
    final clean = _ticket.text.trim();
    if (clean.isEmpty) {
      setState(() => _error = 'Introduce el localizador o enlace/código de acceso de tu entrada.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    String? accessToken, ticketId;
    if (clean.contains('access=')) {
      accessToken = Uri.tryParse(clean)?.queryParameters['access'] ??
          Uri.splitQueryString(clean.split('?').length > 1 ? clean.split('?')[1] : '')['access'];
    } else if (clean.length >= 24 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
      accessToken = clean;
    } else {
      ticketId = clean;
    }
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('claimGuestTicket').call({
        'accessToken': ?accessToken,
        'ticketId': ?ticketId,
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      });
      final msg = res.data is Map ? (res.data as Map)['message'] as String? : null;
      if (mounted) Navigator.of(context).pop(msg ?? '¡Entrada vinculada con éxito a tu cuenta!');
    } catch (e) {
      setState(() => _error = _fnError(e, 'No se pudo vincular la entrada. Comprueba los datos.'));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => _ModalCard(
        icon: _iconBox(Icons.download, Tw.purple400),
        title: context.t('wallet.claim_modal_title', fallback: 'Reclamar entrada web'),
        subtitle: 'Vincular compra de invitado a tu cuenta',
        children: [
          Text(
            '¿Compraste tu entrada en la web sin registrarte? Introdúcela aquí para guardarla en tu monedero de la app, cederla gratis a un amigo o protegerte contra timos.',
            style: tw(12, color: Tw.slate300, height: 1.6),
          ),
          const SizedBox(height: 24),
          _fieldLabel('Localizador de entrada o enlace web'),
          TextField(
            controller: _ticket,
            enabled: !_loading,
            style: tw(12),
            decoration: _input('ej: auto_abc123 o pega el enlace del email'),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Email usado en la compra (opcional)'),
          TextField(
            controller: _email,
            enabled: !_loading,
            keyboardType: TextInputType.emailAddress,
            style: tw(12),
            decoration: _input('tucorreo@ejemplo.com'),
          ),
          if (_error != null) _errorBox(_error!),
          _actions(context,
              loading: _loading,
              enabled: _ticket.text.trim().isNotEmpty,
              onSubmit: _submit,
              gradient: const LinearGradient(colors: [Tw.purple600, Tw.fuchsia600]),
              icon: Icons.download,
              label: 'Vincular a mi app'),
        ],
      );
}

/// Port of BuybackListModal.tsx
class BuybackListModal extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final String currencySymbol;
  const BuybackListModal({super.key, required this.ticket, required this.currencySymbol});

  @override
  State<BuybackListModal> createState() => _BuybackListModalState();
}

class _BuybackListModalState extends State<BuybackListModal> {
  bool _loading = false;
  bool _loadingTier = true;
  String? _error;
  late final int _originalCents = asInt(widget.ticket['priceCents']);
  int _currentCents = 0;

  @override
  void initState() {
    super.initState();
    _loadTier();
  }

  Future<void> _loadTier() async {
    final t = widget.ticket;
    try {
      if (t['eventId'] != null && t['venueId'] != null) {
        final db = FirebaseFirestore.instance;
        final ref = t['isIndependent'] == true
            ? db.collection('events').doc(t['eventId'])
            : db.collection('venues').doc(t['venueId']).collection('events').doc(t['eventId']);
        final snap = await ref.get();
        if (snap.exists) {
          final tiers = snap.data()?['ticket_tiers'];
          final tier = tiers is List ? tiers.whereType<Map>().where((x) => x['id'] == t['ticketType']).firstOrNull : null;
          _currentCents = tier != null ? ((asDouble(tier['price']) ?? 0) * 100).round() : _originalCents;
        }
      } else {
        _currentCents = _originalCents;
      }
    } catch (_) {
      _currentCents = _originalCents;
    }
    if (mounted) setState(() => _loadingTier = false);
  }

  Future<void> _confirm() async {
    final i18n = context.read<I18n>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('listTicketForBuyback').call({'ticketId': widget.ticket['id']});
      final msg = res.data is Map ? (res.data as Map)['message'] as String? : null;
      if (mounted) Navigator.of(context).pop(msg ?? i18n.t('buyback.success', fallback: '¡Entrada listada para recompra!'));
    } catch (e) {
      setState(() => _error = _fnError(e, i18n.t('buyback.error_generic', fallback: 'Error al solicitar la recompra.')));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    const zinc900 = Color(0xFF18181B), zinc800 = Color(0xFF27272A), zinc700 = Color(0xFF3F3F46), zinc400 = Color(0xFFA1A1AA);
    final sym = widget.currencySymbol;
    final refund = (_originalCents / 100).toStringAsFixed(2);
    final current = (_currentCents / 100).toStringAsFixed(2);
    Widget row(String l, String v, {bool big = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: Text(l, style: tw(14, color: zinc400))),
            Text(v, style: big ? tw(18, weight: bold, color: Tw.green400) : tw(14, weight: semibold)),
          ]),
        );
    return Container(
      constraints: const BoxConstraints(maxWidth: 448),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: zinc900, borderRadius: BorderRadius.circular(16), border: Border.all(color: zinc700)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('buyback.title', fallback: 'No puedo ir'), style: tw(20, weight: bold)),
        const SizedBox(height: 8),
        Text(
          context.t('buyback.description',
              fallback: 'Devuelve tu entrada al pool oficial. Cuando alguien la compre al precio actual, recibirás el reembolso automáticamente en tu tarjeta.'),
          style: tw(14, color: zinc400),
        ),
        const SizedBox(height: 16),
        if (_loadingTier)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else ...[
          row(context.t('buyback.original_price', fallback: 'Pagaste'), '$refund$sym'),
          row(context.t('buyback.current_price', fallback: 'Precio actual del tramo'), '$current$sym'),
          const Divider(color: zinc700),
          const SizedBox(height: 12),
          row(context.t('buyback.your_refund', fallback: 'Recibirás'), '$refund$sym', big: true),
          if (_currentCents - _originalCents > 0)
            Text(context.t('buyback.spread_note', fallback: 'La diferencia de precio se destina a gestión de inventario de la plataforma.'),
                style: tw(12, color: const Color(0xFF71717A))),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Tw.red500.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Tw.red500.withValues(alpha: 0.4)),
            ),
            child: Text(_error!, style: tw(14, color: const Color(0xFFFCA5A5))),
          ),
          const SizedBox(height: 16),
        ],
        Row(children: [
          Expanded(
            child: Pressable(
              onTap: _loading ? () {} : () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: zinc800, borderRadius: BorderRadius.circular(12)),
                child: Text(context.t('common.cancel', fallback: 'Cancelar'), textAlign: TextAlign.center, style: tw(14, weight: medium, color: const Color(0xFFD4D4D8))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: _loading || _loadingTier || _originalCents <= 0 ? 0.5 : 1,
              child: Pressable(
                onTap: _loading || _loadingTier || _originalCents <= 0 ? () {} : _confirm,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    _loading ? context.t('common.processing', fallback: 'Procesando...') : context.t('buyback.confirm', fallback: 'Solicitar recompra'),
                    textAlign: TextAlign.center,
                    style: tw(14, weight: bold),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
