import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/singbox_provider.dart';
import 'services/geo_service.dart';
import 'services/ads_service.dart';
import 'screens/settings_screen.dart';
import 'screens/home_screen.dart';
import 'screens/info_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // شاشة عمودية فقط
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // شفافية شريط الحالة
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF08080F),
  ));

  // FIX: كان يستدعي AdsService.init() لكن اسم الدالة هو initialize()
  await AdsService.initialize();

  // جيب دولة المستخدم الحقيقية (قبل VPN) — تُستخدم لاختيار أفضل mode
  await GeoService.load();

  runApp(const OnyxVpnApp());
}

class OnyxVpnApp extends StatelessWidget {
  const OnyxVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SingboxProvider(),
      child: MaterialApp(
        title: 'OnyxVPN',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF08080F),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF8B5CF6),
            surface: Color(0xFF0E0E1C),
          ),
          fontFamily: 'SF Pro Display',
        ),
        home: const HomeScreen(),
        routes: {
          '/info':     (_) => const InfoScreen(),
          '/settings': (_) => const SettingsScreen(),
        },
      ),
    );
  }
}


