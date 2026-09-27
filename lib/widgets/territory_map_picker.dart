import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import 'admin_ui.dart';
import 'common.dart';
import 'basemap.dart';

/// utils/polygonValidation.ts — [coords] is a closed ring of [lng, lat].
({bool valid, String? error}) validatePolygon(List<List<double>> coords) {
  if (coords.length < 4) return (valid: false, error: 'Mínimo tres vértices requeridos');
  if (coords.length > 100) return (valid: false, error: 'Límite de 100 vértices excedido');
  bool ok(List<double> c) => c.length >= 2 && c[0].isFinite && c[1].isFinite && c[0].abs() <= 180 && c[1].abs() <= 90;
  if (!coords.every(ok)) return (valid: false, error: 'Coordenadas inválidas');
  final first = coords.first, last = coords.last;
  if (first[0] != last[0] || first[1] != last[1]) return (valid: false, error: 'Polígono sin cerrar');
  return (valid: true, error: null);
}

/// Port of components/TerritoryMapPicker.tsx: tap to add vertices; emits the open ring ([lng, lat]) or null.
class TerritoryMapPicker extends StatefulWidget {
  final List<List<double>>? initialPolygon;
  final LatLng? center;
  final ValueChanged<List<List<double>>?> onPolygonChange;
  const TerritoryMapPicker({super.key, this.initialPolygon, this.center, required this.onPolygonChange});

  @override
  State<TerritoryMapPicker> createState() => _TerritoryMapPickerState();
}

class _TerritoryMapPickerState extends State<TerritoryMapPicker> {
  late List<List<double>> _points = [...?widget.initialPolygon];

  void _emit() {
    if (_points.length >= 3) {
      widget.onPolygonChange(validatePolygon([..._points, _points.first]).valid ? [..._points] : null);
    } else {
      widget.onPolygonChange(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final latLngs = [for (final p in _points) LatLng(p[1], p[0])];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 350,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
        child: Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.center ?? const LatLng(40.42, -3.70),
              initialZoom: 11,
              backgroundColor: Basemap.background,
              onTap: (_, p) {
                setState(() => _points = [..._points, [p.longitude, p.latitude]]);
                _emit();
              },
            ),
            children: [
              const Basemap(),
              if (latLngs.length >= 3)
                PolygonLayer(polygons: [
                  Polygon(
                    points: latLngs,
                    color: Tw.fuchsia500.withValues(alpha: 0.15),
                    borderColor: Tw.fuchsia500,
                    borderStrokeWidth: 2,
                  ),
                ])
              else if (latLngs.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(points: latLngs, color: Tw.fuchsia500, strokeWidth: 2, pattern: StrokePattern.dashed(segments: const [8, 8])),
                ]),
              MarkerLayer(markers: [
                for (var i = 0; i < latLngs.length; i++)
                  Marker(
                    point: latLngs[i],
                    width: 12,
                    height: 12,
                    child: Container(
                      decoration: BoxDecoration(
                        color: i == 0 ? Tw.green500 : Tw.fuchsia500,
                        shape: BoxShape.circle,
                        border: Border.all(color: Tw.white, width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
                      ),
                    ),
                  ),
              ]),
            ],
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
              child: Text('${_points.length} puntos | ${_points.length >= 3 ? 'Polígono válido' : 'Mín. 3 puntos'}',
                  style: tw(10, weight: bold)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        AdminButton(
          label: 'Deshacer punto',
          color: Tw.w(0.1),
          onTap: _points.isEmpty
              ? null
              : () {
                  setState(() => _points = _points.sublist(0, _points.length - 1));
                  _emit();
                },
        ),
        const SizedBox(width: 8),
        AdminButton(
          label: 'Borrar todo',
          color: Tw.red400,
          outlined: true,
          onTap: _points.isEmpty
              ? null
              : () {
                  setState(() => _points = []);
                  widget.onPolygonChange(null);
                },
        ),
      ]),
    ]);
  }
}

/// Port of components/TerritoryPreviewMap.tsx: venue dots + optional yellow test pin, auto-centred.
class TerritoryPreviewMap extends StatelessWidget {
  final List<({double lat, double lng, String name})> venues;
  final ({double lat, double lng, String label})? testPoint;
  const TerritoryPreviewMap({super.key, required this.venues, this.testPoint});

  @override
  Widget build(BuildContext context) {
    final pts = [for (final v in venues) LatLng(v.lat, v.lng), if (testPoint != null) LatLng(testPoint!.lat, testPoint!.lng)];
    var center = const LatLng(40.42, -3.70);
    var zoom = 5.0;
    if (pts.isNotEmpty) {
      center = LatLng(pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
          pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length);
      zoom = 12;
      if (pts.length > 1) {
        double span(Iterable<double> xs) => xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
        final maxSpan = [span(pts.map((p) => p.latitude)), span(pts.map((p) => p.longitude))].reduce((a, b) => a > b ? a : b);
        zoom = maxSpan > 5 ? 4 : maxSpan > 2 ? 6 : maxSpan > 0.5 ? 8 : maxSpan > 0.1 ? 10 : 12;
      }
    }
    Widget dot(Color c, double size) => Container(
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Tw.white, width: 2)),
          width: size,
          height: size,
        );
    return Container(
      height: 300,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
      child: Stack(children: [
        FlutterMap(
          key: ValueKey('$center-$zoom'),
          options: MapOptions(initialCenter: center, initialZoom: zoom, backgroundColor: Basemap.background),
          children: [
            const Basemap(),
            MarkerLayer(markers: [
              for (final v in venues)
                Marker(point: LatLng(v.lat, v.lng), width: 12, height: 12, child: Tooltip(message: v.name, child: dot(Tw.fuchsia500, 12))),
              if (testPoint != null)
                Marker(
                  point: LatLng(testPoint!.lat, testPoint!.lng),
                  width: 16,
                  height: 16,
                  child: Tooltip(message: testPoint!.label, child: dot(Tw.amber400, 16)),
                ),
            ]),
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              dot(Tw.fuchsia500, 8),
              Text(' ${venues.length} venues', style: tw(10, weight: bold)),
              if (testPoint != null) ...[const SizedBox(width: 8), dot(Tw.amber400, 8), Text(' test', style: tw(10, weight: bold))],
            ]),
          ),
        ),
      ]),
    );
  }
}
