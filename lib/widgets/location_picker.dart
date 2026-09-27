import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../theme/app_theme.dart';
import 'common.dart';
import 'basemap.dart';

/// Lets a parent move the picker, like VenueLocationPickerHandle.flyTo.
class LocationPickerController {
  _VenueLocationPickerState? _state;
  void flyTo(double lat, double lng) => _state?._flyTo(lat, lng);
}

/// Port of components/VenueLocationPicker.tsx (tap to drop a pin; coordinates overlay; "flyTo" from address search).
class VenueLocationPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final void Function(double lat, double lng) onLocationChange;
  final LocationPickerController? controller;
  final double height;
  const VenueLocationPicker({super.key, this.initialLat, this.initialLng, required this.onLocationChange, this.controller, this.height = 250});

  @override
  State<VenueLocationPicker> createState() => _VenueLocationPickerState();
}

class _VenueLocationPickerState extends State<VenueLocationPicker> {
  final _map = MapController();
  late LatLng? _pin = widget.initialLat != null && widget.initialLng != null ? LatLng(widget.initialLat!, widget.initialLng!) : null;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  void _flyTo(double lat, double lng) {
    setState(() => _pin = LatLng(lat, lng));
    _map.move(LatLng(lat, lng), 16);
    widget.onLocationChange(lat, lng);
  }

  @override
  Widget build(BuildContext context) => Container(
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
        child: Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: LatLng(widget.initialLat ?? 40.42, widget.initialLng ?? -3.70),
              initialZoom: 13,
              backgroundColor: Basemap.background,
              onTap: (_, p) {
                setState(() => _pin = p);
                widget.onLocationChange(p.latitude, p.longitude);
              },
            ),
            children: [
              const Basemap(),
              if (_pin != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _pin!,
                    width: 36,
                    height: 36,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.place, size: 32, color: Tw.fuchsia500, shadows: [Shadow(color: Color(0x88000000), blurRadius: 6)]),
                  ),
                ]),
            ],
          ),
          if (_pin != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
                child: Text('${_pin!.latitude.toStringAsFixed(6)}, ${_pin!.longitude.toStringAsFixed(6)}',
                    style: tw(10).copyWith(fontFamily: 'monospace')),
              ),
            )
          else
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                  child: Text('Haz clic para colocar el pin', style: tw(12, weight: bold)),
                ),
              ),
            ),
        ]),
      );
}

/// Port of components/venue-admin/LocationPicker.tsx (storefront pin, 280px, zoom 15 when set).
class StorefrontLocationPicker extends StatelessWidget {
  final ({double latitude, double longitude})? location;
  final ValueChanged<({double latitude, double longitude})> onChange;
  const StorefrontLocationPicker({super.key, required this.location, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final loc = location;
    return Container(
      height: 280,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(loc?.latitude ?? 40.4168, loc?.longitude ?? -3.7038),
          initialZoom: loc != null ? 15 : 12,
          backgroundColor: Basemap.background,
          onTap: (_, p) => onChange((latitude: p.latitude, longitude: p.longitude)),
        ),
        children: [
          const Basemap(),
          if (loc != null)
            MarkerLayer(markers: [
              Marker(
                point: LatLng(loc.latitude, loc.longitude),
                width: 32,
                height: 42,
                alignment: Alignment.topCenter,
                child: Column(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Tw.fuchsia600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Tw.white, width: 2),
                      boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.4), blurRadius: 12)],
                    ),
                    child: const Icon(Icons.storefront, size: 14, color: Tw.white),
                  ),
                  CustomPaint(size: const Size(12, 8), painter: _Triangle(Tw.fuchsia600)),
                ]),
              ),
            ]),
        ],
      ),
    );
  }
}

class _Triangle extends CustomPainter {
  final Color color;
  const _Triangle(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Triangle old) => old.color != color;
}
