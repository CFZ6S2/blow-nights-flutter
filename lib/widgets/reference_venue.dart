import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Port of components/venues/ReferenceVenueNotice.tsx: what a reference venue says about itself — a real place,
/// not associated with Blow Nights, that its owner can claim. Never a partner badge, tickets or a bar.
class ReferenceBadge extends StatelessWidget {
  const ReferenceBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Tw.slate700.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
        child: Label(context.t('reference_venue.badge'), size: 8, color: Tw.slate300, tracking: 0.05),
      );
}

class ReferenceVenueNotice extends StatelessWidget {
  final VoidCallback onClaim;
  const ReferenceVenueNotice({super.key, required this.onClaim});

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Tw.slate700.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.w(0.1)),
              ),
              child: const Icon(Icons.place, size: 20, color: Tw.slate300),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const ReferenceBadge(),
                const SizedBox(height: 6),
                Text(context.t('reference_venue.not_associated'), style: tw(14, weight: bold, color: const Color(0xFFE2E8F0))),
                const SizedBox(height: 4),
                Text(context.t('reference_venue.what_you_can_do'), style: tw(12, color: Tw.slate400, height: 1.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Divider(color: Tw.w(0.1), height: 1),
          const SizedBox(height: 16),
          Text(context.t('reference_venue.are_you_owner'), style: tw(12, color: Tw.slate300)),
          const SizedBox(height: 12),
          GradientButton(
            label: context.t('reference_venue.claim_button'),
            icon: Icons.storefront,
            onTap: onClaim,
            expand: true,
            radius: 12,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            gradient: const LinearGradient(colors: [Tw.purple600, Tw.indigo600]),
          ),
          const SizedBox(height: 12),
          Text(context.t('reference_venue.osm_attribution'), style: tw(10, color: Tw.slate500)),
        ]),
      );
}
