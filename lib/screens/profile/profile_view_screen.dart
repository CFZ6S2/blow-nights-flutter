import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../models/user_model.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/social.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/match_overlay.dart';
import '../../widgets/profile_overlay.dart' show VipBadge;

const _defaultInterests = ['Gimnasio', 'Cine', 'Viajes', 'Música', 'Gaming'];

/// Port of app/[city]/profile/view/page.tsx
class ProfileViewScreen extends StatefulWidget {
  final String userId;
  final String? pingVenueId;
  const ProfileViewScreen({super.key, required this.userId, this.pingVenueId});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  final _db = FirebaseFirestore.instance;
  final _scroll = ScrollController();
  final _pager = PageController();
  UserProfile? _profile;
  Map<String, dynamic>? _pingVenue;
  bool _loading = true;
  int _activePhoto = 0;
  bool _hasLiked = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final me = auth.user;
    final myProfile = auth.profile;
    final anonymous = context.read<I18n>().t('profileView.anonymous');
    try {
      final snap = await _db.collection('users').doc(widget.userId).get();
      if (snap.exists) {
        _profile = UserProfile.fromDoc(snap);
        if (me != null && widget.userId != me.uid) {
          final vip = ['plus', 'black'].contains(myProfile?.membershipTier);
          if (!(vip && myProfile?.data['incognito'] == true)) {
            await _db.collection('visits').add({
              'visitorId': me.uid,
              'visitedId': widget.userId,
              'visitorNick': myProfile?.nick.isNotEmpty == true ? myProfile!.nick : anonymous,
              'visitorFoto': myProfile?.fotoUrl ?? '',
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
          final like = await _db.collection('likes').doc('${me.uid}_${widget.userId}').get();
          if (like.exists) _hasLiked = true;
        }
        final pingId = widget.pingVenueId;
        if (pingId != null && pingId.isNotEmpty) {
          final v = await _db.collection('venues').doc(pingId).get();
          if (v.exists) _pingVenue = {'id': pingId, ...?v.data()};
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chat() async {
    final auth = context.read<AuthProvider>();
    final me = auth.user;
    if (me == null) {
      openRoute(context, AppRoute.login, replace: true);
      return;
    }
    if (!['plus', 'black'].contains(auth.profile?.membershipTier)) {
      final matches = await _db.collection('matches').where('users', arrayContains: me.uid).get();
      final hasMatch = matches.docs.any((d) => (d.data()['users'] as List?)?.contains(widget.userId) == true);
      if (!hasMatch) {
        if (mounted) openRoute(context, AppRoute.premium);
        return;
      }
    }
    HapticFeedback.selectionClick();
    final chatId = await getOrCreateChat(me.uid, widget.userId);
    if (mounted) openRoute(context, AppRoute.chatDetail, args: {'id': chatId});
  }

  Future<void> _like({bool isSuper = false}) async {
    if (context.read<AuthProvider>().user == null) {
      openRoute(context, AppRoute.login, replace: true);
      return;
    }
    if (_hasLiked && !isSuper) return;
    isSuper ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
    final res = await sendLike(widget.userId, isSuper: isSuper);
    if (!mounted) return;
    if (res.isMatch && res.matchData != null) {
      showMatchOverlay(context, res.matchData!);
    } else if (res.error == null) {
      setState(() => _hasLiked = true);
    }
  }

  void _page(DragEndDetails d, int count) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 200) return;
    final next = (_activePhoto + (v < 0 ? 1 : -1)).clamp(0, count - 1);
    if (next != _activePhoto) _pager.animateToPage(next, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final p = _profile;
    if (p == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(context.t('profileView.profileNotFound'), textAlign: TextAlign.center, style: tw(24, weight: black)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Label(context.t('profileView.back'), size: 14, weight: bold, color: Tw.fuchsia500),
              ),
            ]),
          ),
        ),
      );
    }

    final auth = context.watch<AuthProvider>();
    final me = auth.profile;
    final myUid = auth.user?.uid;
    final photos = [p.fotoUrl, ...p.extraPhotos].where((s) => s.isNotEmpty).toList();
    final distance = (me?.lat != null && me?.lng != null && p.lat != null && p.lng != null)
        ? calculateDistance(me!.lat!, me.lng!, p.lat!, p.lng!)
        : null;
    final interests = p.data['intereses'] == null ? _defaultInterests : p.intereses;
    final privatePhotos = p.privatePhotos;
    final permitted = myUid != null && asStringList(p.data['permittedUsers']).contains(myUid);
    final complexion = safeStr(p.data['complexion']);

    final size = MediaQuery.of(context).size;
    final top = MediaQuery.of(context).padding.top;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final headerY = (offset / 500 * 150).clamp(0.0, 150.0);
    final headerOpacity = 1 - (offset / 400 * 0.6).clamp(0.0, 0.6);
    final headerScale = offset < 0 ? 1 + (-offset / 100 * 0.2).clamp(0.0, 0.2) : 1.0;

    return Scaffold(
      body: Stack(children: [
        // Parallax photo header
        Positioned(
          top: headerY,
          left: 0,
          right: 0,
          height: size.height * 0.65,
          child: Opacity(
            opacity: headerOpacity,
            child: Transform.scale(
              scale: headerScale,
              child: Stack(children: [
                PageView.builder(
                  controller: _pager,
                  itemCount: photos.isEmpty ? 1 : photos.length,
                  onPageChanged: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _activePhoto = i);
                  },
                  itemBuilder: (_, i) => Stack(fit: StackFit.expand, children: [
                    if (photos.isEmpty)
                      Container(color: Tw.slate900)
                    else
                      AnimatedScale(
                        scale: _activePhoto == i ? 1.05 : 1,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        child: NetImage(photos[i]),
                      ),
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Tw.slate950, Color(0x33020617), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
                Positioned(
                  top: top + 16,
                  left: 16,
                  right: 16,
                  child: Row(children: [
                    for (var i = 0; i < photos.length; i++)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i <= _activePhoto ? Tw.white : Tw.w(0.2),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        // Scrollable content; the transparent top area forwards horizontal swipes to the carousel.
        ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) => _page(d, photos.length),
              child: SizedBox(height: size.height * 0.55),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 160),
              decoration: BoxDecoration(
                color: Tw.slate950.withValues(alpha: 0.8),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
                border: Border(top: BorderSide(color: Tw.w(0.05))),
                boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, -20))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text('${p.nick}${p.edad != null ? ', ${p.edad}' : ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(24, weight: black, tracking: -0.025)),
                        ),
                        if (p.verified) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.verified, size: 30, color: Tw.blue500),
                        ],
                        if (p.online) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Tw.green500.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: Tw.green500.withValues(alpha: 0.3)),
                            ),
                            child: Label(context.t('profileView.online'), size: 8, color: Tw.green400),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.near_me, size: 12, color: Tw.slate500),
                        const SizedBox(width: 8),
                        Flexible(child: Label('A ${distance ?? '0.5'} ${context.t('profileView.kmFromYou')}')),
                      ]),
                    ]),
                  ),
                  if (['plus', 'black'].contains(p.membershipTier)) const VipBadge(),
                ]),
                const SizedBox(height: 24),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _chip(p.rol == 'party_only' ? context.t('profileView.onlyParty') : p.rol, Tw.w(0.05), Tw.slate300),
                  _chip(p.intencion, Tw.fuchsia500.withValues(alpha: 0.1), Tw.fuchsia400),
                  if (complexion.isNotEmpty) _chip(complexion, Tw.indigo500.withValues(alpha: 0.1), Tw.indigo400),
                ]),
                const SizedBox(height: 32),
                Row(children: [
                  Expanded(child: _metric(context.t('profileView.height'), p.altura, 'cm')),
                  const SizedBox(width: 16),
                  Expanded(child: _metric(context.t('profileView.weight'), p.peso, 'kg')),
                ]),
                const SizedBox(height: 40),
                Label(context.t('profileView.interests'), color: Tw.slate500, tracking: 0.2),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (i, interest) in interests.indexed)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 300 + i * 50),
                      builder: (_, v, c) => Opacity(opacity: v, child: Transform.scale(scale: 0.8 + 0.2 * v, child: c)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Tw.w(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Tw.w(0.05)),
                        ),
                        child: Text('#$interest', style: tw(10, weight: bold, color: Tw.slate400)),
                      ),
                    ),
                ]),
                const SizedBox(height: 32),
                Label(context.t('profileView.aboutMe'), color: Tw.slate500, tracking: 0.2),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Tw.w(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Tw.w(0.05)),
                  ),
                  child: Text(p.bio.isNotEmpty ? p.bio : context.t('profileView.noDescription'),
                      style: tw(18, weight: medium, color: Tw.slate300, height: 1.6)),
                ),
                if (privatePhotos.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Row(children: [
                    const Icon(Icons.lock, size: 12, color: Color(0xFFEAB308)),
                    const SizedBox(width: 8),
                    Expanded(child: Label(context.t('profileView.privateAlbum'), color: const Color(0xFFEAB308), tracking: 0.2)),
                    if (!permitted) Label('${privatePhotos.length} ${context.t('profileView.photos')}', size: 8, color: Tw.slate500),
                  ]),
                  const SizedBox(height: 16),
                  if (permitted)
                    GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (final url in privatePhotos)
                          Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
                            child: NetImage(url),
                          ),
                      ],
                    )
                  else
                    Pressable(
                      onTap: _chat,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Tw.w(0.05),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.2)),
                        ),
                        child: Column(children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFEAB308).withValues(alpha: 0.1)),
                            child: const Icon(Icons.lock_person, color: Color(0xFFEAB308)),
                          ),
                          const SizedBox(height: 12),
                          Text(context.t('profileView.privateContent'), style: tw(14, weight: bold)),
                          const SizedBox(height: 4),
                          Label(context.t('profileView.requestAccess'), weight: FontWeight.w400, color: Tw.slate500),
                        ]),
                      ),
                    ),
                ],
              ]),
            ),
          ],
        ),
        // Top actions
        Positioned(
          top: top + 32,
          left: 24,
          right: 24,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _glassButton(Icons.expand_more, () => Navigator.of(context).maybePop()),
            _glassButton(Icons.more_horiz, () {}),
          ]),
        ),
        if (_pingVenue != null) _pingBanner(context, p, _pingVenue!),
        // Fixed actions dock
        Positioned(
          left: 0,
          right: 0,
          bottom: 40 + MediaQuery.of(context).padding.bottom,
          child: Center(
            child: Container(
              width: (size.width * 0.9).clamp(0.0, 384.0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Tw.slate900.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Tw.w(0.1)),
                boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 60, offset: Offset(0, 25))],
              ),
              child: Row(children: [
                _dockButton(const Icon(Icons.star, color: Color(0xFFEAB308)), () => _like(isSuper: true)),
                const SizedBox(width: 8),
                _dockButton(const Icon(Icons.card_giftcard, color: Tw.emerald400),
                    () => openRoute(context, AppRoute.entradas, args: {'gift': widget.userId})),
                const SizedBox(width: 8),
                Expanded(
                  child: Pressable(
                    onTap: () => _like(),
                    scale: 0.95,
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _hasLiked ? Tw.slate800 : null,
                        gradient: _hasLiked ? null : const LinearGradient(colors: [Tw.fuchsia600, Tw.purple600, Tw.indigo600]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Label(_hasLiked ? context.t('profileView.sent') : context.t('profileView.like'),
                          color: _hasLiked ? Tw.slate500 : Tw.white, tracking: 0.2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _dockButton(const Icon(Icons.chat_bubble, color: Tw.white), _chat),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _pingBanner(BuildContext context, UserProfile p, Map<String, dynamic> venue) {
    final loc = parseLocation(venue);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 32, 16, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Colors.transparent]),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 400),
          builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, -100 * (1 - v)), child: c)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Tw.slate900.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.orange500.withValues(alpha: 0.5)),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
            ),
            child: Column(children: [
              Row(children: [
                const Text('🔥', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p.nick} ${context.t('profileView.invitedToDate')}', style: tw(12, weight: bold)),
                    const SizedBox(height: 2),
                    Label('${context.t('profileView.imAt')} ${safeStr(venue['name'])}', color: const Color(0xFFFB923C)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Pressable(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.google.com/maps/search/?api=1&query=${loc?.lat},${loc?.lng}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.map, size: 14, color: Tw.white),
                        const SizedBox(width: 8),
                        Label(context.t('profileView.howToGetThere'), weight: bold, color: Tw.white, tracking: 0.05),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Pressable(
                    onTap: () => _like(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Tw.orange500, Tw.amber500]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Tw.amber500.withValues(alpha: 0.5), blurRadius: 15)],
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.chat, size: 14, color: Tw.white),
                        const SizedBox(width: 8),
                        Label(context.t('profileView.openChat'), color: Tw.white, tracking: 0.05),
                      ]),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _glassButton(IconData icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Tw.w(0.1)),
          ),
          child: Icon(icon, color: Tw.white),
        ),
      );

  Widget _dockButton(Widget child, VoidCallback onTap) => Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16)),
          child: child,
        ),
      );

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: bg)),
        child: Label(text, weight: bold, color: fg, tracking: 0.05),
      );

  Widget _metric(String label, int? value, String unit) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tw.w(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.w(0.05)),
        ),
        child: Column(children: [
          Label(label, size: 9, color: Tw.slate500),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${value ?? '--'} ', style: tw(24, weight: black)),
            TextSpan(text: unit, style: tw(10, color: Tw.slate500)),
          ])),
        ]),
      );
}
