import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../models/firestore_utils.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Port of components/VenueReviews.tsx
class VenueReviews extends StatefulWidget {
  final String venueId;
  final String venueName;
  const VenueReviews({super.key, required this.venueId, required this.venueName});

  @override
  State<VenueReviews> createState() => _VenueReviewsState();
}

class _VenueReviewsState extends State<VenueReviews> {
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _showForm = false;
  int _rating = 0;
  final _comment = TextEditingController();
  bool _submitting = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('reviews')
        .where('venueId', isEqualTo: widget.venueId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((s) => setState(() {
              _reviews = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
              _loading = false;
            }), onError: (_) => setState(() => _loading = false));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null || auth.profile == null || _rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance.collection('reviews').add({
        'venueId': widget.venueId,
        'userId': auth.user!.uid,
        'userNick': auth.profile!.nick.isEmpty ? 'Anon' : auth.profile!.nick,
        'userPhoto': auth.profile!.fotoUrl.isEmpty ? null : auth.profile!.fotoUrl,
        'rating': _rating,
        'comment': _comment.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _comment.clear();
      setState(() {
        _rating = 0;
        _showForm = false;
      });
    } catch (_) {}
    if (mounted) setState(() => _submitting = false);
  }

  Widget _stars(num value, {bool interactive = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var s = 1; s <= 5; s++)
          GestureDetector(
            onTap: interactive ? () => setState(() => _rating = s) : null,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                s <= (interactive ? value : value.round()) ? Icons.star : Icons.star_border,
                size: interactive ? 28 : 18,
                color: s <= value ? const Color(0xFFFACC15) : Tw.slate700,
              ),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().user?.uid;
    final hasReviewed = uid != null && _reviews.any((r) => r['userId'] == uid);
    final avg = _reviews.isEmpty ? 0.0 : _reviews.map((r) => asDouble(r['rating']) ?? 0).reduce((a, b) => a + b) / _reviews.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Label(context.t('reviews.title'), size: 14, color: Tw.slate500, tracking: 0.2)),
        if (_reviews.isNotEmpty) ...[
          _stars(avg),
          const SizedBox(width: 4),
          Text(avg.toStringAsFixed(1), style: tw(12, weight: black, color: const Color(0xFFFACC15))),
          const SizedBox(width: 8),
          Text('(${_reviews.length})', style: tw(10, color: Tw.slate600)),
        ],
      ]),
      const SizedBox(height: 16),
      if (uid != null && !hasReviewed) ...[
        GlassCard(
          onTap: () => setState(() => _showForm = !_showForm),
          radius: 16,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.rate_review, size: 14, color: Tw.slate400),
            const SizedBox(width: 8),
            Text(context.t('reviews.write_review'), style: tw(12, weight: bold, color: Tw.slate400)),
          ]),
        ),
        const SizedBox(height: 16),
      ],
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        child: !_showForm
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GlassCard(
                  radius: 24,
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(context.t('reviews.rate_venue', params: {'name': widget.venueName}),
                        textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.slate400)),
                    const SizedBox(height: 8),
                    Center(child: _stars(_rating, interactive: true)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _comment,
                      maxLength: 500,
                      maxLines: 3,
                      style: tw(14),
                      decoration: InputDecoration(
                        hintText: context.t('reviews.comment_placeholder'),
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: GlassCard(
                          onTap: () => setState(() => _showForm = false),
                          radius: 12,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(context.t('reviews.cancel'), textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.slate400)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Opacity(
                          opacity: _rating == 0 || _submitting ? 0.4 : 1,
                          child: Pressable(
                            onTap: _submit,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(12)),
                              child: Label(_submitting ? context.t('reviews.sending') : context.t('reviews.submit'),
                                  size: 12, color: Tw.white, tracking: 0.05, align: TextAlign.center),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
      ),
      if (_loading)
        for (var i = 0; i < 2; i++)
          Container(height: 80, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16)))
      else if (_reviews.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(children: [
            const Icon(Icons.reviews, size: 30, color: Tw.slate700),
            const SizedBox(height: 8),
            Text(context.t('reviews.no_reviews'), style: tw(12, color: Tw.slate600)),
          ]),
        )
      else
        for (final r in _reviews)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.06))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ClipOval(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: NetImage(
                      r['userPhoto'] as String?,
                      placeholder: Container(
                        color: Tw.slate800,
                        alignment: Alignment.center,
                        child: Text(safeStr(r['userNick']).isEmpty ? '' : safeStr(r['userNick'])[0].toUpperCase(),
                            style: tw(12, weight: bold, color: Tw.slate500)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(safeStr(r['userNick']), overflow: TextOverflow.ellipsis, style: tw(12, weight: bold))),
                      _stars(asDouble(r['rating']) ?? 0),
                    ]),
                    if (parseDate(r['createdAt']) != null)
                      Text(DateFormat('d/M/yyyy').format(parseDate(r['createdAt'])!), style: tw(9, color: Tw.slate600)),
                  ]),
                ),
              ]),
              if (safeStr(r['comment']).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(safeStr(r['comment']), style: tw(12, color: Tw.slate400, height: 1.6)),
              ],
            ]),
          ),
    ]);
  }
}
