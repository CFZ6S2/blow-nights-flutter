import 'package:flutter/widgets.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Light basemap for every FlutterMap: OpenFreeMap "positron" vector style, no API key.
/// César asked for a light map (the web radar's dark style strains the eyes); positron is the
/// lightest OpenFreeMap style to render. Carto raster tiles now return an "API KEY REQUIRED" watermark.
class Basemap extends StatelessWidget {
  const Basemap({super.key});

  static const _styleUrl = 'https://tiles.openfreemap.org/styles/positron';

  /// The style's own background colour, used as MapOptions.backgroundColor so tiles don't flash dark while loading.
  static const background = Color(0xFFF2F3F0);

  static Future<Style>? _style;

  /// Loaded once per app run; a failed load (offline) is retried on the next build.
  static Future<Style> _load() => _style ??= StyleReader(uri: _styleUrl).read().onError<Object>((e, st) {
        _style = null;
        Error.throwWithStackTrace(e, st);
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<Style>(
        future: _load(),
        builder: (_, snap) {
          final style = snap.data;
          if (style == null) return const SizedBox.shrink();
          return VectorTileLayer(tileProviders: style.providers, theme: style.theme, sprites: style.sprites);
        },
      );
}
