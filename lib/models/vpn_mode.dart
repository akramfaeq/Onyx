// ─── الـ 4 خيارات الرئيسية للتطبيق ───────────────────────────

enum VpnMode { warp, psiphon, mahsa, custom }

class VpnModeInfo {
  final VpnMode mode;
  final String name;
  final String subtitle;
  final String emoji;
  final String tag;

  const VpnModeInfo({
    required this.mode,
    required this.name,
    required this.subtitle,
    required this.emoji,
    required this.tag,
  });

  // Warp → Cloudflare WireGuard config ثابت
  static const warp = VpnModeInfo(
    mode:     VpnMode.warp,
    name:     'Warp',
    subtitle: 'Cloudflare WireGuard',
    emoji:    '☁️',
    tag:      'CF',
  );

  // Psiphon → sing-box outbound من نوع psiphon
  static const psiphon = VpnModeInfo(
    mode:     VpnMode.psiphon,
    name:     'Psiphon',
    subtitle: 'Multi-hop tunnel',
    emoji:    '🔐',
    tag:      'Bypass',
  );

  // Mahsa → subscription link من GitHub (Reality/VLESS)
  static const mahsa = VpnModeInfo(
    mode:     VpnMode.mahsa,
    name:     'Mahsa',
    subtitle: 'Reality · GitHub',
    emoji:    '🐙',
    tag:      'Mix',
  );

  // Custom → المستخدم يحط رابطه
  static const custom = VpnModeInfo(
    mode:     VpnMode.custom,
    name:     'Add Link',
    subtitle: 'Custom config',
    emoji:    '+',
    tag:      '',
  );

  static const all = [warp, psiphon, mahsa, custom];
}
