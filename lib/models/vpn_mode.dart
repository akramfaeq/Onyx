// ─── الـ modes الرئيسية ─────────────────────────────────────────────
// patterniha: مصدر ثاني في الـ fallback chain (داخلي فقط، مو في الـ UI)

enum VpnMode { warp, psiphon, warpPsiphon, mahsa, patterniha, pythonServers, custom }

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

  static const warp = VpnModeInfo(
    mode:     VpnMode.warp,
    name:     'Warp',
    subtitle: 'Cloudflare WireGuard',
    emoji:    '☁️',
    tag:      'CF',
  );

  static const psiphon = VpnModeInfo(
    mode:     VpnMode.psiphon,
    name:     'Psiphon',
    subtitle: 'Multi-hop tunnel',
    emoji:    '🔐',
    tag:      'Bypass',
  );

  static const warpPsiphon = VpnModeInfo(
    mode:     VpnMode.warpPsiphon,
    name:     'Warp+',
    subtitle: 'Warp via Psiphon',
    emoji:    '⚡',
    tag:      'Fast',
  );

  static const mahsa = VpnModeInfo(
    mode:     VpnMode.mahsa,
    name:     'Mahsa',
    subtitle: 'Reality · GitHub',
    emoji:    '🐙',
    tag:      'Mix',
  );

  // patterniha — في الـ fallback chain فقط، مو في الـ UI
  static const patterniha = VpnModeInfo(
    mode:     VpnMode.patterniha,
    name:     'Patterniha',
    subtitle: 'Community servers',
    emoji:    '🌐',
    tag:      'ALT',
  );

  static const pythonServers = VpnModeInfo(
    mode:     VpnMode.pythonServers,
    name:     'Python Servers',
    subtitle: 'Fast community servers',
    emoji:    '🌍',
    tag:      'FAST',
  );

  static const custom = VpnModeInfo(
    mode:     VpnMode.custom,
    name:     'Add Link',
    subtitle: 'Custom config',
    emoji:    '+',
    tag:      '',
  );

  // الـ UI يعرض هذي فقط — patterniha مخفية (fallback داخلي)
  static const all = [warpPsiphon, mahsa, pythonServers, custom];
}
