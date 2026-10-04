import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/singbox_provider.dart';
import 'services/ads_service.dart';
import 'services/geo_service.dart';
import 'screens/settings_screen.dart';
import 'screens/home_screen.dart';

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

// ─── Info Screen ─────────────────────────────────────────────
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('About', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OnyxVPN', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Version 2.0.0', style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
            const SizedBox(height: 24),
            _InfoCard(
              icon: '☁️',
              title: 'Warp',
              desc: 'Cloudflare WireGuard — سريع ومستقر، يجرب 3 مفاتيح تلقائياً',
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: '🔐',
              title: 'Psiphon',
              desc: 'VLESS/WS tunnel — الأفضل للدول المحجوبة',
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: '🐙',
              title: 'Mahsa',
              desc: 'Reality & VLESS من GitHub — متجدد تلقائياً',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String icon;
  final String title;
  final String desc;

  const _InfoCard({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E1C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A1A2E)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
