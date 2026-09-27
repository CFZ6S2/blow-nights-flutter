import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../models/user_model.dart';
import '../navigation.dart';
import '../providers/auth_provider.dart';
import '../services/social.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'match_overlay.dart';

/// Port of components/ProfileOverlay.tsx
Future<void> showProfileOverlay(BuildContext context, String userId) => Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => ProfileOverlay(userId: userId),
        transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
      ),
    );

class ProfileOverlay extends StatefulWidget {
  final String userId;
  const ProfileOverlay({super.key, required this.userId});

  @override
  State<ProfileOverlay> createState() => _ProfileOverlayState();
}

class _ProfileOverlayState extends State<ProfileOverlay> with TickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _scroll = ScrollController();
  final _pager = PageController();
  UserProfile? _profile;
  bool _loading = true;
  int _activePhoto = 0;
  bool _hasLiked = false;
  bool _showOptions = false;
  bool _matched = false;
  final Map<int, bool> _nsfwRevealed = {};
  late final _likeAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final _superAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
  String? _myUid;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    _myUid = auth.user?.uid;
    try {
      final snap = await _db.collection('users').doc(widget.userId).get();
      if (snap.exists) {
        _profile = UserProfile.fromDoc(snap);
        final me = auth.user;
        if (me != null && widget.userId != me.uid) {
          await _db.collection('users').doc(me.uid).update({'viewingProfileId': widget.userId});
          _db.collection('visits').doc('${me.uid}_${widget.userId}').set({
            'visitorId': me.uid,
            'visitedId': widget.userId,
            'visitorNick': auth.profile?.nick.isNotEmpty == true ? auth.profile!.nick : 'Usuario',
            'visitorFoto': auth.profile?.fotoUrl ?? '',
            'timestamp': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          final like = await _db.collection('likes').doc('${me.uid}_${widget.userId}').get();
          if (like.exists) _hasLiked = true;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    final uid = _myUid;
    if (uid != null) {
      _db.collection('users').doc(uid).update({'viewingProfileId': null}).catchError((_) {});
    }
    _scroll.dispose();
    _pager.dispose();
    _likeAnim.dispose();
    _superAnim.dispose();
    super.dispose();
  }

  Future<void> _like({bool isSuper = false}) async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) {
      openRoute(context, AppRoute.login, replace: true);
      return;
    }
    if (_hasLiked && !isSuper) return;
    if (isSuper) {
      _superAnim.forward(from: 0);
      HapticFeedback.heavyImpact();
    } else {
      _likeAnim.forward(from: 0);
      HapticFeedback.mediumImpact();
    }
    final res = await sendLike(widget.userId, isSuper: isSuper);
    if (!mounted) return;
    if (res.isMatch && res.matchData != null) {
      HapticFeedback.heavyImpact();
      setState(() => _matched = true);
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) showMatchOverlay(context, res.matchData!);
    } else if (res.error == null) {
      setState(() => _hasLiked = true);
    }
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final p = _profile;
    if (p == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final auth = context.watch<AuthProvider>();
    final me = auth.profile;
    final isOwn = auth.user?.uid == widget.userId;
    final isMatch = _matched || p.matches.contains(auth.user?.uid ?? '');
    final hasAccess = isOwn || isMatch;
    final publicPhotos = [p.fotoUrl, ...p.extraPhotos].where((s) => s.isNotEmpty).toList();
    final privatePhotos = p.privatePhotos.where((s) => s.isNotEmpty).toList();
    final allPhotos = [...publicPhotos, ...privatePhotos];
    final nsfw = (p.data['nsfwPhotos'] is List) ? (p.data['nsfwPhotos'] as List).whereType<num>().map((n) => n.toInt()).toSet() : <int>{};
    final distance = (me?.lat != null && me?.lng != null && p.lat != null && p.lng != null)
        ? calculateDistance(me!.lat!, me.lng!, p.lat!, p.lng!).toString()
        : '0.5';
    final isVip = ['plus', 'black'].contains(p.membershipTier);

    final h = MediaQuery.of(context).size.height;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final headerY = (offset / 500 * 150).clamp(0.0, 150.0);
    final headerOpacity = 1 - (offset / 400 * 0.6).clamp(0.0, 0.6);
    final contentFade = 1 - (offset / 100 * 0.1).clamp(0.0, 0.1);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Container(
              color: Tw.slate950,
              child: Stack(children: [
                // Parallax photo header
                Positioned(
                  top: headerY,
                  left: 0,
                  right: 0,
                  height: h * 0.65,
                  child: Opacity(
                    opacity: headerOpacity,
                    child: Stack(children: [
                      PageView.builder(
                        controller: _pager,
                        itemCount: allPhotos.isEmpty ? 1 : allPhotos.length,
                        onPageChanged: (i) {
                          HapticFeedback.selectionClick();
                          setState(() => _activePhoto = i);
                        },
                        itemBuilder: (_, i) {
                          if (allPhotos.isEmpty) return Container(color: Tw.slate900);
                          final isPrivate = i >= publicPhotos.length;
                          final locked = isPrivate && !hasAccess;
                          final blurNsfw = nsfw.contains(i) && (me?.nsfwBlur ?? true) && _nsfwRevealed[i] != true;
                          final sigma = (locked ? 40.0 : 0) + (blurNsfw ? 30.0 : 0) + (_activePhoto == i ? 0 : 4);
                          return Stack(fit: StackFit.expand, children: [
                            AnimatedScale(
                              scale: _activePhoto == i ? 1.05 : 1,
                              duration: const Duration(milliseconds: 400),
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(sigmaX: sigma / 2, sigmaY: sigma / 2),
                                child: ColorFiltered(
                                  colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: locked ? 0.5 : 0), BlendMode.darken),
                                  child: NetImage(allPhotos[i]),
                                ),
                              ),
                            ),
                            if (blurNsfw && !locked)
                              GestureDetector(
                                onTap: () => setState(() => _nsfwRevealed[i] = true),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(Icons.visibility_off, color: Tw.w(0.8), size: 30),
                                    const SizedBox(height: 8),
                                    Label(context.t('overlay.nsfw_reveal'), size: 9, color: Tw.w(0.7)),
                                  ]),
                                ),
                              ),
                            if (locked)
                              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Tw.w(0.1),
                                    border: Border.all(color: Tw.w(0.2)),
                                  ),
                                  child: const Icon(Icons.lock, size: 36, color: Tw.amber500),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(color: Tw.w(0.1)),
                                  ),
                                  child: Label(context.t('overlay.private_album'), color: Tw.white, tracking: 0.3),
                                ),
                              ]),
                            const IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Tw.slate950, Color(0x1A020617), Colors.transparent],
                                  ),
                                ),
                              ),
                            ),
                          ]);
                        },
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 16,
                        left: 16,
                        right: 16,
                        child: Row(children: [
                          for (var i = 0; i < allPhotos.length; i++)
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
                      _burst(_likeAnim, Icons.favorite, Tw.fuchsia500, Tw.fuchsia400, 12, 150, 120),
                      _burst(_superAnim, Icons.star, Tw.amber500, const Color(0xFFFDE047), 20, 250, 150),
                    ]),
                  ),
                ),
                // Scrollable content sheet
                NotificationListener<OverscrollNotification>(
                  onNotification: (n) {
                    if (n.overscroll < -12 && _scroll.offset <= 0) Navigator.of(context).maybePop();
                    return false;
                  },
                  child: ListView(
                    controller: _scroll,
                    padding: EdgeInsets.only(top: h * 0.55),
                    children: [
                      Opacity(
                        opacity: contentFade,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(32, 16, 32, 160),
                          decoration: BoxDecoration(
                            color: Tw.slate950.withValues(alpha: 0.8),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
                            border: Border(top: BorderSide(color: Tw.w(0.05))),
                            boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, -20))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Center(
                              child: Container(width: 48, height: 4, decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(99))),
                            ),
                            const SizedBox(height: 24),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
                                    Text('${p.nick}${p.edad != null ? ', ${p.edad}' : ''} ${p.mood ?? ''}',
                                        style: tw(24, weight: black, tracking: -0.025)),
                                    if (p.online)
                                      _statusPill('Online', Tw.green400, Tw.green500)
                                    else if (p.data['lastSeen'] != null)
                                      _statusPill(context.t('overlay.active_at', params: {'time': formatLastSeen(p.data['lastSeen'])}),
                                          Tw.slate500, Tw.slate500),
                                  ]),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    const Icon(Icons.near_me, size: 12, color: Tw.slate500),
                                    const SizedBox(width: 8),
                                    Label(context.t('overlay.distance', params: {'distance': distance})),
                                  ]),
                                ]),
                              ),
                              if (isVip) const VipBadge(),
                            ]),
                            const SizedBox(height: 24),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              _chip(roleLabel(p.rol, (k, f) => context.t(k, fallback: f)), Tw.w(0.05), Tw.slate300),
                              _chip(p.intencion, Tw.fuchsia500.withValues(alpha: 0.1), Tw.fuchsia400),
                            ]),
                            const SizedBox(height: 32),
                            Row(children: [
                              Expanded(child: _metric(context.t('overlay.height'), p.altura, 'cm')),
                              const SizedBox(width: 16),
                              Expanded(child: _metric(context.t('overlay.weight'), p.peso, 'kg')),
                            ]),
                            const SizedBox(height: 40),
                            Label(context.t('overlay.interests'), color: Tw.slate500, tracking: 0.2),
                            const SizedBox(height: 16),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final i in p.intereses)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Tw.w(0.05),
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(color: Tw.w(0.1)),
                                  ),
                                  child: Text(i, style: tw(14, weight: medium, color: Tw.slate300)),
                                ),
                            ]),
                            const SizedBox(height: 32),
                            Label(context.t('overlay.about_me'), color: Tw.slate500, tracking: 0.2),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Tw.w(0.05),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Tw.w(0.05)),
                              ),
                              child: Text(p.bio.isNotEmpty ? p.bio : context.t('overlay.no_bio'),
                                  style: tw(18, weight: medium, color: Tw.slate300, height: 1.6)),
                            ),
                            if (privatePhotos.isNotEmpty && !hasAccess) ...[
                              const SizedBox(height: 32),
                              _privateAlbumCard(context, privatePhotos.length),
                            ],
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
                // Floating actions
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 40 + MediaQuery.of(context).padding.bottom,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: math.min(384, MediaQuery.of(context).size.width * 0.95)),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Tw.slate900.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Tw.w(0.1)),
                          boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 60, offset: Offset(0, 25))],
                        ),
                        child: Row(children: [
                          _roundAction(child: const Icon(Icons.star, color: Tw.amber500), onTap: () => _like(isSuper: true)),
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
                                  gradient: _hasLiked
                                      ? null
                                      : const LinearGradient(colors: [Tw.fuchsia600, Tw.purple600, Tw.indigo600]),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Label(_hasLiked ? context.t('overlay.sent') : context.t('overlay.like'),
                                    color: _hasLiked ? Tw.slate500 : Tw.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _roundAction(
                            gradient: const LinearGradient(colors: [Tw.orange500, Tw.amber500]),
                            child: const Text('🍹', style: TextStyle(fontSize: 20)),
                            onTap: () => openRoute(context, AppRoute.barGift, args: {'giftNick': p.nick}),
                          ),
                          const SizedBox(width: 8),
                          _roundAction(child: const Icon(Icons.chat_bubble, color: Tw.white), onTap: _chat),
                        ]),
                      ),
                    ),
                  ),
                ),
                // Top controls
                Positioned(
                  top: MediaQuery.of(context).padding.top + 32,
                  left: 24,
                  right: 24,
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _glassButton(Icons.expand_more, () => Navigator.of(context).pop()),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      _glassButton(Icons.more_horiz, () => setState(() => _showOptions = !_showOptions)),
                      if (_showOptions) ...[
                        const SizedBox(height: 8),
                        _optionsMenu(context),
                      ],
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionsMenu(BuildContext context) {
    final i18n = context.read<I18n>();
    final uid = context.read<AuthProvider>().user?.uid;
    return Container(
      width: 192,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Tw.slate900.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Tw.w(0.1)),
      ),
      child: Column(children: [
        _optionRow(Icons.flag, i18n.t('overlay.report'), Tw.orange500, () async {
          if (uid == null) return;
          if (await confirmDialog(context, message: i18n.t('overlay.report_confirm'), confirmText: i18n.t('overlay.report'), danger: true)) {
            await reportUser(uid, widget.userId, i18n.t('overlay.report_reason_inappropriate', fallback: 'Comportamiento inapropiado'));
            if (!mounted) return;
            showToast(this.context, i18n.t('overlay.report_sent'));
            setState(() => _showOptions = false);
          }
        }),
        Divider(color: Tw.w(0.05), height: 1, indent: 8, endIndent: 8),
        _optionRow(Icons.block, i18n.t('overlay.block'), Tw.red500, () async {
          if (uid == null) return;
          if (await confirmDialog(context, message: i18n.t('overlay.block_confirm'), confirmText: i18n.t('overlay.block'), danger: true)) {
            await blockUser(uid, widget.userId);
            if (mounted) Navigator.of(this.context).pop();
          }
        }),
      ]),
    );
  }

  Widget _optionRow(IconData icon, String label, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(label, style: tw(14, weight: bold, color: color)),
          ]),
        ),
      );

  Widget _glassButton(IconData icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
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

  Widget _roundAction({required Widget child, required VoidCallback onTap, Gradient? gradient}) => Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: gradient == null ? Tw.w(0.05) : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      );

  Widget _statusPill(String text, Color fg, Color border) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: border.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: border.withValues(alpha: 0.3)),
        ),
        child: Label(text, size: 8, color: fg),
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

  Widget _privateAlbumCard(BuildContext context, int count) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.slate900, Tw.slate950]),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Tw.w(0.05)),
        ),
        child: Column(children: [
          Container(height: 4, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tw.amber400, Tw.fuchsia500]))),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Tw.amber500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Tw.amber500.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.lock, size: 30, color: Tw.amber500),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('overlay.private_album'), style: tw(20, weight: black, tracking: -0.025)),
                    Label(context.t('overlay.hidden_photos', count: count), color: Tw.slate500),
                  ]),
                ),
              ]),
              const SizedBox(height: 24),
              Text(context.t('overlay.private_desc'), style: tw(14, color: Tw.slate400, height: 1.6)),
              const SizedBox(height: 32),
              Pressable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  showToast(context, context.read<I18n>().t('overlay.access_requested_alert'));
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
                  child: Label(context.t('overlay.request_access'), color: Tw.black, tracking: 0.2, align: TextAlign.center),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _burst(AnimationController c, IconData icon, Color main, Color particle, int n, double dist, double size) =>
      IgnorePointer(
        child: AnimatedBuilder(
          animation: c,
          builder: (_, _) {
            if (!c.isAnimating) return const SizedBox.shrink();
            final t = c.value;
            final scale = t < 0.5 ? t / 0.5 * 1.5 : 1.5 - (t - 0.5) / 0.5 * 0.3;
            final opacity = t < 0.5 ? t / 0.5 : 1 - (t - 0.5) / 0.5;
            return Center(
              child: Opacity(
                opacity: opacity.clamp(0, 1),
                child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                  for (var i = 0; i < n; i++)
                    Transform.translate(
                      offset: Offset(math.cos(i * 2 * math.pi / n) * dist * t, math.sin(i * 2 * math.pi / n) * dist * t),
                      child: Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: particle)),
                    ),
                  Transform.scale(
                    scale: scale,
                    child: Icon(icon, size: size, color: main, shadows: [Shadow(color: main, blurRadius: 30)]),
                  ),
                ]),
              ),
            );
          },
        ),
      );
}

class VipBadge extends StatelessWidget {
  final double fontSize;
  const VipBadge({super.key, this.fontSize = 9});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Tw.amber400, Color(0xFFCA8A04)]),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text('VIP', style: tw(fontSize, weight: black, color: Tw.black)),
      );
}
