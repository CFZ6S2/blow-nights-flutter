import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../providers/city_provider.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Port of components/CitySelector.tsx
class CitySelector extends StatelessWidget {
  const CitySelector({super.key});

  @override
  Widget build(BuildContext context) {
    final city = context.watch<CityProvider>();
    final current = city.currentCity;
    // Nothing to choose between until a city exists; "Cerca de ti" is always an option then.
    if (city.cities.isEmpty) return const SizedBox.shrink();
    return Builder(
      builder: (btn) => Pressable(
        onTap: () => _open(btn),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Tw.w(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Tw.w(0.1)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(current == null ? Icons.near_me : Icons.location_city, size: 14, color: Tw.fuchsia400),
            const SizedBox(width: 6),
            Label(current?.name ?? context.t('city.near_you')),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 12, color: Tw.slate600),
          ]),
        ),
      ),
    );
  }

  void _open(BuildContext btnCtx) {
    final box = btnCtx.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    showGeneralDialog(
      context: btnCtx,
      barrierDismissible: true,
      barrierLabel: 'city',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, _, _) {
        final city = ctx.watch<CityProvider>();
        final i18n = ctx.watch<I18n>();
        // Following the GPS ("Cerca de ti"), even when it found a city; a picked city is checked instead.
        final followsGps = city.currentCity == null || city.detectedByGPS;
        return Stack(children: [
          Positioned(
            top: origin.dy + box.size.height + 8,
            left: origin.dx,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 224,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Tw.slate900,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tw.w(0.1)),
                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 40)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Label(city.detectedByGPS ? i18n.t('city.detected') : i18n.t('city.select'), size: 9, weight: bold, color: Tw.slate500),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 192),
                    child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          city.setCurrentCity(null);
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: followsGps ? Tw.fuchsia500.withValues(alpha: 0.15) : null,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            const Icon(Icons.near_me, size: 16, color: Tw.fuchsia400),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(i18n.t('city.near_you'),
                                  overflow: TextOverflow.ellipsis,
                                  style: tw(12, weight: bold, color: followsGps ? Tw.fuchsia300 : Tw.slate300)),
                            ),
                            if (followsGps) const Icon(Icons.check, size: 14, color: Tw.fuchsia400),
                          ]),
                        ),
                      ),
                      for (final c in city.cities)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            city.setCurrentCity(c);
                            Navigator.of(ctx).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: city.cityId == c.id && !followsGps ? Tw.fuchsia500.withValues(alpha: 0.15) : null,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(children: [
                              Text(c.emoji ?? '🏙️', style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: tw(12, weight: bold, color: city.cityId == c.id && !followsGps ? Tw.fuchsia300 : Tw.slate300)),
                                  if (c.country != null) Text(c.country!, style: tw(9, color: Tw.slate500)),
                                ]),
                              ),
                              if (city.cityId == c.id && !followsGps) const Icon(Icons.check, size: 14, color: Tw.fuchsia400),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ]);
      },
      transitionBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
    );
  }
}
