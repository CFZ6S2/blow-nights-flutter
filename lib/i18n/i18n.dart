import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  final String code;
  final String label;
  final String flag;
  const AppLanguage(this.code, this.label, this.flag);
}

const appLanguages = <AppLanguage>[
  AppLanguage('es', 'ES', '🇪🇸'),
  AppLanguage('en', 'EN', '🇬🇧'),
  AppLanguage('de', 'DE', '🇩🇪'),
  AppLanguage('pt', 'PT', '🇵🇹'),
  AppLanguage('ca', 'CA', '🏴'),
  AppLanguage('fr', 'FR', '🇫🇷'),
  AppLanguage('it', 'IT', '🇮🇹'),
  AppLanguage('el', 'GR', '🇬🇷'),
  AppLanguage('ru', 'RU', '🇷🇺'),
  AppLanguage('ar', 'AR', '🇸🇦'),
  AppLanguage('he', 'HE', '🇮🇱'),
  AppLanguage('ro', 'RO', '🇷🇴'),
];

const _fallback = 'es';
const _prefsKey = 'i18nextLng';

/// Port of the web's i18next setup: same JSON files, same keys, es fallback.
class I18n extends ChangeNotifier {
  String _lang = _fallback;
  Map<String, dynamic> _current = const {};
  Map<String, dynamic> _fallbackRes = const {};

  String get language => _lang;
  Locale get locale => Locale(_lang);
  bool get isRtl => _lang == 'ar' || _lang == 'he';

  Future<void> init() async {
    _fallbackRes = await _load(_fallback);
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(_prefsKey);
    } catch (_) {}
    final device = ui.PlatformDispatcher.instance.locale.languageCode;
    final code = _supported(saved) ?? _supported(device) ?? _fallback;
    await _apply(code);
  }

  Future<void> changeLanguage(String code) async {
    final c = _supported(code);
    if (c == null || c == _lang) return;
    await _apply(c);
    try {
      (await SharedPreferences.getInstance()).setString(_prefsKey, c);
    } catch (_) {}
  }

  Future<void> _apply(String code) async {
    _current = code == _fallback ? _fallbackRes : await _load(code);
    _lang = code;
    notifyListeners();
  }

  String? _supported(String? code) {
    if (code == null) return null;
    final base = code.split(RegExp('[-_]')).first.toLowerCase();
    return appLanguages.any((l) => l.code == base) ? base : null;
  }

  /// A missing/corrupt locale file must never block startup; keys then fall back to their defaults.
  /// assets/i18n/ are verbatim copies of the web locales (re-copied when the web changes); keys that exist only in
  /// the app (friend finder) live in assets/i18n_app/ and are merged on top so a re-copy never loses them.
  Future<Map<String, dynamic>> _load(String code) async {
    Future<Map<String, dynamic>> read(String path) async {
      try {
        return jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('i18n: failed to load $path: $e');
        return {};
      }
    }

    final res = await read('assets/i18n/$code.json');
    res.addAll(await read('assets/i18n_app/$code.json'));
    return res;
  }

  /// t('nav.radar'), t('venuesPage.people', count: 3), t('x', params: {'name': 'A'}), t('k', fallback: 'Default')
  String t(String key, {String? fallback, int? count, Map<String, Object?>? params}) {
    final allParams = <String, Object?>{...?params, 'count': ?count};
    String? value;
    if (count != null) {
      for (final suffix in _pluralSuffixes(count)) {
        value = _lookup(_current, '${key}_$suffix') ?? _lookup(_fallbackRes, '${key}_$suffix');
        if (value != null) break;
      }
    }
    value ??= _lookup(_current, key) ?? _lookup(_fallbackRes, key) ?? fallback ?? key;
    return _interpolate(value, allParams);
  }

  // i18next resolves "a.b.c" against nested objects AND flat keys that contain dots.
  static String? _lookup(Map<String, dynamic> res, String key) {
    final v = _deepFind(res, key.split('.'));
    return v is String ? v : null;
  }

  static Object? _deepFind(Object? node, List<String> parts) {
    if (parts.isEmpty) return node;
    if (node is! Map) return null;
    for (var i = parts.length; i >= 1; i--) {
      final k = parts.sublist(0, i).join('.');
      if (node.containsKey(k)) {
        final found = _deepFind(node[k], parts.sublist(i));
        if (found != null) return found;
      }
    }
    return null;
  }

  static String _interpolate(String s, Map<String, Object?> params) {
    if (params.isEmpty || !s.contains('{{')) return s;
    return s.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'), (m) {
      final v = params[m[1]];
      return v == null ? m[0]! : v.toString();
    });
  }

  List<String> _pluralSuffixes(int n) {
    final cat = switch (_lang) {
      'ru' => n % 10 == 1 && n % 100 != 11
          ? 'one'
          : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14))
              ? 'few'
              : 'many',
      'ar' => n == 0
          ? 'zero'
          : n == 1
              ? 'one'
              : n == 2
                  ? 'two'
                  : (n % 100 >= 3 && n % 100 <= 10)
                      ? 'few'
                      : (n % 100 >= 11)
                          ? 'many'
                          : 'other',
      'he' => n == 1 ? 'one' : n == 2 ? 'two' : 'other',
      'fr' => n <= 1 ? 'one' : 'other',
      _ => n == 1 ? 'one' : 'other',
    };
    return [cat, if (cat != 'other') 'other'];
  }

  /// Web uses toLocaleDateString with the active language; mirror that.
  String get dateLocale => switch (_lang) {
        'es' => 'es_ES',
        'en' => 'en_GB',
        'ca' => 'ca',
        _ => _lang,
      };
}

extension I18nContext on BuildContext {
  I18n get i18n => watch<I18n>();
  String t(String key, {String? fallback, int? count, Map<String, Object?>? params}) =>
      watch<I18n>().t(key, fallback: fallback, count: count, params: params);
}
