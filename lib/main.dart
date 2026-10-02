import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'i18n/i18n.dart';
import 'navigation.dart';
import 'providers/auth_provider.dart';
import 'providers/city_provider.dart';
import 'providers/platform_settings.dart';
import 'providers/venues_provider.dart';
import 'screens/shell.dart';
import 'services/finder_background.dart';
import 'services/finder_native.dart';
import 'services/firebase_init.dart';
import 'services/push_sync.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebase();
  // The radar service asks the app to renew its BLE key while it's alive (else it starts a headless engine).
  FinderNative.onRenewRequest(renewBleKeysNow);
  await initializeDateFormatting();
  final i18n = I18n();
  await i18n.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Tw.slate950,
  ));
  runApp(BlowNightsApp(i18n: i18n));
}

class BlowNightsApp extends StatelessWidget {
  final I18n i18n;
  const BlowNightsApp({super.key, required this.i18n});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: i18n),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CityProvider()),
        ChangeNotifierProvider(create: (_) => VenuesProvider()),
        ChangeNotifierProvider(create: (_) => UnreadChats()),
        ChangeNotifierProvider(create: (_) => ShellController()),
        ChangeNotifierProvider(create: (_) => PlatformSettings()),
      ],
      child: Consumer<I18n>(
        builder: (context, i18n, _) => MaterialApp(
          title: 'Blow Nights',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: rootMessengerKey,
          theme: AppTheme.darkTheme,
          locale: i18n.locale,
          supportedLocales: [for (final l in appLanguages) Locale(l.code)],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const RootGate(),
        ),
      ),
    );
  }
}
