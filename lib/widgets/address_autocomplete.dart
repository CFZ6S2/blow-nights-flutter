import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../providers/platform_settings.dart' show uuidV4;
import '../theme/app_theme.dart';
import 'admin_ui.dart';
import 'common.dart';

/// Build with --dart-define-from-file=dart_defines.json (same key as NEXT_PUBLIC_GOOGLE_PLACES_API_KEY).
const _apiKey = String.fromEnvironment('PLACES_API_KEY');

/// Port of components/AddressAutocomplete.tsx (Google Places API (New) autocomplete + place details).
class AddressAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final void Function(({String address, double lat, double lng}) result)? onSelect;
  final String placeholder;
  final String lang;
  const AddressAutocomplete({super.key, required this.controller, this.onSelect, this.placeholder = 'Buscar dirección...', this.lang = 'es'});

  @override
  State<AddressAutocomplete> createState() => _AddressAutocompleteState();
}

class _AddressAutocompleteState extends State<AddressAutocomplete> {
  List<({String placeId, String description})> _results = [];
  bool _loading = false;
  Timer? _debounce;
  String _session = uuidV4();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.length < 3 || _apiKey.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
        headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': _apiKey},
        body: jsonEncode({'input': q, 'languageCode': widget.lang, 'sessionToken': _session}),
      );
      if (res.statusCode != 200) {
        setState(() => _results = []);
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = [
        for (final s in (data['suggestions'] as List? ?? const []))
          if (s is Map && s['placePrediction'] is Map)
            (
              placeId: (s['placePrediction']['placeId'] as String?) ?? '',
              description: ((s['placePrediction']['text'] as Map?)?['text'] as String?) ?? '',
            ),
      ].take(5).toList();
      if (mounted) setState(() => _results = list);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(({String placeId, String description}) p) async {
    widget.controller.text = p.description;
    setState(() => _results = []);
    FocusScope.of(context).unfocus();
    final onSelect = widget.onSelect;
    if (onSelect != null && _apiKey.isNotEmpty) {
      try {
        final res = await http.get(
          Uri.parse('https://places.googleapis.com/v1/places/${p.placeId}?fields=formattedAddress,location&sessionToken=$_session'),
          headers: {'X-Goog-Api-Key': _apiKey},
        );
        if (res.statusCode == 200) {
          final place = jsonDecode(res.body) as Map<String, dynamic>;
          final loc = place['location'] as Map?;
          onSelect((
            address: (place['formattedAddress'] as String?) ?? p.description,
            lat: (loc?['latitude'] as num?)?.toDouble() ?? 0,
            lng: (loc?['longitude'] as num?)?.toDouble() ?? 0,
          ));
        }
      } catch (_) {
        onSelect((address: p.description, lat: 0, lng: 0));
      }
    }
    _session = uuidV4();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: widget.controller,
          style: tw(14),
          cursorColor: Tw.fuchsia500,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () => _search(v));
          },
          decoration: adminInputDecoration(widget.placeholder).copyWith(
            prefixIcon: const Icon(Icons.location_on, size: 18, color: Tw.slate500),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)),
                  )
                : null,
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.slate700)),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final r in _results)
                InkWell(
                  onTap: () => _select(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.location_on, size: 12, color: Tw.slate500),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: tw(14, color: Tw.slate300))),
                    ]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Text('Powered by Google', textAlign: TextAlign.end, style: tw(10, color: Tw.slate600)),
              ),
            ]),
          ),
      ]);
}
