import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/vpn_provider.dart';
import 'services/supabase_service.dart';
import 'services/ads_service.dart';
import 'services/cache_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Hive يتهيأ أول — أسرع من أي شيء
  await CacheService.initialize();
  NotificationService.initialize();

  // الباقي بالخلفية ولا يوقف التطبيق
  try { await SupabaseService.initialize(); } catch (_) {}
  try { await AdsService.initialize(); } catch (_) {}

  final vpnProvider = VpnProvider();

  // زر Disconnect من الـ notification يفصل الـ VPN
  NotificationService.onDisconnect = () => vpnProvider.disconnect();

  runApp(
    ChangeNotifierProvider(
      create: (_) => vpnProvider,
      child: const OnyxVPNApp(),
    ),
  );
}

class OnyxVPNApp extends StatelessWidget {
  const OnyxVPNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnyxVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0A0A14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7B5CF0),
          surface: Color(0xFF12121E),
        ),
        fontFamily: 'SF Pro Display',
      ),
      home: const HomeScreen(),
    );
  }
}
