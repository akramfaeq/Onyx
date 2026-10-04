import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/singbox_provider.dart';
import '../services/geo_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Consumer<SingboxProvider>(
        builder: (_, vpn, __) => ListView(
          padding: const EdgeInsets.all(20),
          children: [

            // ─── معلومات الدولة ───────────────────────────
            _SectionTitle('Your Location'),
            _InfoTile(
              icon: Icons.location_on_rounded,
              title: GeoService.userCountryName.isNotEmpty
                  ? GeoService.userCountryName
                  : 'Unknown',
              subtitle: 'Auto-detected · ${GeoService.userCountryCode}',
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 24),

            // ─── Split Tunneling ──────────────────────────
            _SectionTitle('Split Tunneling'),
            const SizedBox(height: 8),
            _SubTitle('Apps excluded from VPN (use direct connection)'),
            const SizedBox(height: 12),
            ...SplitTunnelingApps.common.map((app) => _AppToggle(
              app: app,
              enabled: !vpn.excludedApps.contains(app.packageName),
              onToggle: (val) {
                if (val) {
                  vpn.removeExcludedApp(app.packageName);
                } else {
                  vpn.addExcludedApp(app.packageName);
                }
              },
            )),
            const SizedBox(height: 24),

            // ─── DNS ──────────────────────────────────────
            _SectionTitle('DNS & Security'),
            _ToggleTile(
              icon: Icons.security_rounded,
              title: 'DNS Leak Protection',
              subtitle: 'Force DNS through VPN tunnel',
              value: true, // دائماً شغال
              onChanged: null, // لا يُغير
              color: const Color(0xFF10B981),
            ),
            _ToggleTile(
              icon: Icons.block_rounded,
              title: 'Block Ads & Trackers',
              subtitle: 'Block known ad domains',
              value: vpn.blockAds,
              onChanged: vpn.isConnected ? null : (v) => vpn.setBlockAds(v),
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 24),

            // ─── Speed Test ───────────────────────────────
            ('Connection'),
            _ActionTile(
              icon: Icons.speed_rounded,
              title: 'Auto Speed Test',
              subtitle: 'Select fastest server automatically',
              color: const Color(0xFF3B82F6),
              trailing: Switch(
                value: vpn.autoSpeedTest,
                onChanged: vpn.isConnected ? null : (v) => vpn.setAutoSpeedTest(v),
                activeColor: const Color(0xFF8B5CF6),
              ),
            ),
          ],
        ),
      ),
    );_SectionTitle
  }
}

// ─── Widgets ──────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF4B5563),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );
}

class _SubTitle extends StatelessWidget {
  final String text;
  const _SubTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  const _InfoTile({required this.icon, required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0E0E1C),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF1A1A2E)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          ],
        ),
      ],
    ),
  );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color color;
  const _ToggleTile({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF0E0E1C),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF1A1A2E)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: color,
        ),
      ],
    ),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget trailing;
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.trailing});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF0E0E1C),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF1A1A2E)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );
}

class _AppToggle extends StatelessWidget {
  final AppInfo app;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _AppToggle({required this.app, required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF0E0E1C),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF1A1A2E)),
    ),
    child: Row(
      children: [
        Text(app.emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(app.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(app.packageName, style: const TextStyle(color: Color(0xFF4B5563), fontSize: 10)),
            ],
          ),
        ),
        Switch(
          value: enabled,
          onChanged: onToggle,
          activeColor: const Color(0xFF8B5CF6),
        ),
      ],
    ),
  );
}

// ─── قائمة التطبيقات الشائعة للـ Split Tunneling ─────────────
class AppInfo {
  final String name;
  final String packageName;
  final String emoji;
  const AppInfo(this.name, this.packageName, this.emoji);
}

class SplitTunnelingApps {
  static const common = [
    AppInfo('YouTube',        'com.google.android.youtube',     '▶️'),
    AppInfo('WhatsApp',       'com.whatsapp',                   '💬'),
    AppInfo('Telegram',       'org.telegram.messenger',         '✈️'),
    AppInfo('Instagram',      'com.instagram.android',          '📷'),
    AppInfo('TikTok',         'com.zhiliaoapp.musically',       '🎵'),
    AppInfo('Twitter / X',    'com.twitter.android',            '🐦'),
    AppInfo('Google Maps',    'com.google.android.apps.maps',   '🗺️'),
    AppInfo('Google Chrome',  'com.android.chrome',             '🌐'),
    AppInfo('Netflix',        'com.netflix.mediaclient',        '🎬'),
    AppInfo('Snapchat',       'com.snapchat.android',           '👻'),
  ];
}
