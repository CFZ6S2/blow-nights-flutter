import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/venue_claim.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';

/// Port of components/venues/ClaimVenueModal.tsx: claim a reference venue (functions submitVenueClaim) with contact
/// details and, optionally, a photo of a document proving ownership (CIF, activity licence…), uploaded to the
/// claimant's private folder. The claim goes to review; the claimant follows it in "Mis reclamaciones", never in a
/// panel they can't enter yet. Resolves to [ClaimSheetResult.sent] or [ClaimSheetResult.login]: the caller navigates.
Future<ClaimSheetResult?> showClaimVenueSheet(BuildContext context, {required String venueId, required String venueName}) =>
    showModalBottomSheet<ClaimSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClaimVenueSheet(venueId: venueId, venueName: venueName),
    );

enum ClaimSheetResult { sent, login }

class _ClaimVenueSheet extends StatefulWidget {
  final String venueId;
  final String venueName;
  const _ClaimVenueSheet({required this.venueId, required this.venueName});

  @override
  State<_ClaimVenueSheet> createState() => _ClaimVenueSheetState();
}

class _ClaimVenueSheetState extends State<_ClaimVenueSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _role = claimRoles.first;
  XFile? _file;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
    if (x != null && mounted) setState(() => _file = x);
  }

  Future<void> _submit() async {
    final i18n = context.read<I18n>();
    final user = context.read<AuthProvider>().user;
    if (user == null || _sending) return;
    if (!isValidClaimContact(_name.text, _phone.text)) {
      showToast(context, i18n.t('venue_claim.fill_contact'), error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      Map<String, String>? document;
      final file = _file;
      if (file != null) {
        final Uint8List bytes = await file.readAsBytes();
        final contentType = claimDocumentContentType(file.name, file.mimeType);
        if (bytes.length > claimDocumentMaxBytes) {
          if (mounted) showToast(context, i18n.t('venue_claim.bad_file'), error: true);
          if (mounted) setState(() => _sending = false);
          return;
        }
        final filePath = claimDocumentPath(user.uid, file.name, DateTime.now().millisecondsSinceEpoch);
        await FirebaseStorage.instance.ref(filePath).putData(bytes, SettableMetadata(contentType: contentType));
        document = {'filePath': filePath, 'note': file.name.length > 200 ? file.name.substring(0, 200) : file.name};
      }
      await FirebaseFunctions.instance.httpsCallable('submitVenueClaim').call({
        'venueId': widget.venueId,
        'contact': {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'roleAtVenue': _role},
        'document': ?document,
      });
      if (!mounted) return;
      showToast(context, i18n.t('venue_claim.sent'));
      Navigator.of(context).pop(ClaimSheetResult.sent);
      return;
    } on FirebaseFunctionsException catch (e) {
      if (mounted) showToast(context, e.message ?? i18n.t('venue_claim.error'), error: true);
    } catch (_) {
      if (mounted) showToast(context, i18n.t('venue_claim.error'), error: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  Widget _label(String key) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 12),
        child: Label(context.t(key), size: 10, color: Tw.slate500, tracking: 0.1),
      );

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthProvider>().user != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          decoration: BoxDecoration(
            color: Tw.slate900,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tw.purple500.withValues(alpha: 0.4)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(context.t('venue_claim.title', params: {'name': widget.venueName}), style: tw(16, weight: bold)),
                ),
                GestureDetector(
                  onTap: _sending ? null : () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 20, color: Tw.slate500),
                ),
              ]),
              const SizedBox(height: 12),
              if (!loggedIn) ...[
                Text(context.t('venue_claim.login_first'), style: tw(12, color: Tw.slate300)),
                const SizedBox(height: 16),
                _button(context.t('venue_claim.login_button'), Tw.purple600, () => Navigator.of(context).pop(ClaimSheetResult.login)),
              ] else ...[
                Text(context.t('venue_claim.intro'), style: tw(12, color: Tw.slate400, height: 1.5)),
                _label('venue_claim.name'),
                AdminInput(controller: _name, focus: Tw.purple500),
                _label('venue_claim.phone'),
                AdminInput(controller: _phone, keyboardType: TextInputType.phone, hint: '+34 600 000 000', focus: Tw.purple500),
                _label('venue_claim.role'),
                AdminSelect<String>(
                  value: _role,
                  items: [for (final r in claimRoles) (r, context.t('venue_claim.role_$r'))],
                  onChanged: _sending ? null : (r) => setState(() => _role = r ?? _role),
                ),
                _label('venue_claim.document'),
                Pressable(
                  onTap: _sending ? () {} : _pick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _file != null ? Tw.emerald500.withValues(alpha: 0.5) : Tw.w(0.1)),
                    ),
                    child: Row(children: [
                      Icon(_file != null ? Icons.check_circle : Icons.add_photo_alternate, size: 18,
                          color: _file != null ? Tw.emerald400 : Tw.slate400),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_file?.name ?? context.t('venue_claim.document'),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(13, color: Tw.slate300)),
                      ),
                      if (_file != null)
                        GestureDetector(
                          onTap: _sending ? null : () => setState(() => _file = null),
                          child: const Icon(Icons.close, size: 16, color: Tw.slate500),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Text(context.t('venue_claim.document_hint_photo'), style: tw(10, color: Tw.slate500, height: 1.4)),
                const SizedBox(height: 12),
                Text(context.t('venue_claim.trial_note'), style: tw(10, color: Tw.slate500, height: 1.4)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _button(context.t('venue_claim.cancel'), Tw.slate800, _sending ? null : () => Navigator.of(context).pop(),
                      fg: Tw.slate300)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _button(_sending ? context.t('venue_claim.sending') : context.t('venue_claim.send'), Tw.purple600,
                        _sending ? null : _submit),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _button(String label, Color bg, VoidCallback? onTap, {Color fg = Tw.white}) => Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Pressable(
          onTap: onTap ?? () {},
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Text(label, textAlign: TextAlign.center, style: tw(12, weight: bold, color: fg)),
          ),
        ),
      );
}
