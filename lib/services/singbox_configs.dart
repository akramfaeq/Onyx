// ─── كونفيغات sing-box مع كل الميزات ──────────────────────────
// ① DNS Leak Protection  ② GeoIP Routing  ③ Split Tunneling  ④ Speed Test

class SingboxConfigs {

  // ─── DNS Leak Protection - مشترك بكل الكونفيغات ─────────────
  // remote = عبر VPN (للمواقع المحجوبة)
  // local  = مباشر (للمواقع المحلية)
  // fakeip = يمنع تسريب الـ DNS نهائياً
  static const _dnsBlock = '''
  "dns": {
    "servers": [
      {
        "tag": "remote",
        "address": "https://1.1.1.1/dns-query",
        "strategy": "ipv4_only",
        "detour": "proxy"
      },
      {
        "tag": "local",
        "address": "https://8.8.8.8/dns-query",
        "strategy": "ipv4_only",
        "detour": "direct"
      },
      {
        "tag": "block-dns",
        "address": "rcode://success"
      }
    ],
    "rules": [
      { "outbound": "any",           "server": "local"     },
      { "geosite": ["private"],      "server": "local"     },
      { "geosite": ["ads"],          "server": "block-dns" }
    ],
    "final": "remote",
    "independent_cache": true,
    "strategy": "ipv4_only"
  }''';

  // ─── GeoIP Routing - مشترك بكل الكونفيغات ───────────────────
  // المواقع المحلية تمر مباشرة، المحجوبة عبر VPN
  static String _routeBlock(String countryCode) => '''
  "route": {
    "geoip": {
      "download_url": "https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db",
      "download_detour": "proxy"
    },
    "geosite": {
      "download_url": "https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db",
      "download_detour": "proxy"
    },
    "rules": [
      { "protocol": "dns",                        "outbound": "dns-out"  },
      { "geosite": ["private"],                   "outbound": "direct"   },
      { "geoip":   ["private"],                   "outbound": "direct"   },
      { "geosite": ["ads"],                       "outbound": "block"    },
      { "geoip":   ["${countryCode.toLowerCase()}"], "outbound": "direct" }
    ],
    "final": "proxy",
    "auto_detect_interface": true,
    "override_android_vpn": true
  }''';

  // ─── TUN inbound مع Split Tunneling ──────────────────────────
  // excluded_packages = هذي التطبيقات ما تمر بالـ VPN
  static String _tunBlock({List<String> excludedApps = const []}) {
    final excluded = excludedApps.isEmpty
        ? ''
        : ', "excluded_packages": [${excludedApps.map((a) => '"$a"').join(', ')}]';
    return '''
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "inet4_address": "172.19.0.1/30",
      "inet6_address": "fdfe:dcba:9876::1/126",
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": false,
      "domain_strategy": "ipv4_only"$excluded
    }
  ]''';
  }

  // ─── Speed Test outbound - urltest يختار الأسرع تلقائياً ─────
  static const _speedTestOutbound = '''
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": [],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "3m",
      "tolerance": 50,
      "idle_timeout": "30m"
    }''';

  // ══════════════════════════════════════════════════════════════
  // ① WARP
  // ══════════════════════════════════════════════════════════════
  static String warp({
    String countryCode = 'iq',
    List<String> excludedApps = const [],
  }) => '''{
  "log": { "level": "warn" },
  $_dnsBlock,
  ${_tunBlock(excludedApps: excludedApps)},
  "outbounds": [
    {
      "type": "wireguard",
      "tag": "proxy",
      "server": "engage.cloudflareclient.com",
      "server_port": 2408,
      "local_address": ["172.16.0.2/32", "2606:4700:110:8f0b:40cd:2a15:fbb7:e78c/128"],
      "private_key": "4GgaQCy368kz1QjIHkQMCf35CJ3XeFBUKQfaYkANE1w=",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": [0, 0, 0],
      "mtu": 1280
    },
    { "type": "direct", "tag": "direct" },
    { "type": "block",  "tag": "block"  },
    { "type": "dns",    "tag": "dns-out" }
  ],
  ${_routeBlock(countryCode)}
}''';

  // ══════════════════════════════════════════════════════════════
  // ② PSIPHON
  // ══════════════════════════════════════════════════════════════
  static String psiphon({
    String countryCode = 'ir',
    List<String> excludedApps = const [],
  }) => '''{
  "log": { "level": "warn" },
  $_dnsBlock,
  ${_tunBlock(excludedApps: excludedApps)},
  "outbounds": [
    { "type": "psiphon", "tag": "proxy" },
    { "type": "direct",  "tag": "direct"  },
    { "type": "block",   "tag": "block"   },
    { "type": "dns",     "tag": "dns-out" }
  ],
  ${_routeBlock(countryCode)}
}''';

  // ══════════════════════════════════════════════════════════════
  // ③ MAHSA - subscription link من GitHub
  // ══════════════════════════════════════════════════════════════
  static const mahsaUrl =
      'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/main/mci/sub_1.txt';

  // كونفيغ Mahsa مع Speed Test تلقائي
  static String mahsaConfig({
    required List<Map<String, dynamic>> outbounds,
    String countryCode = 'iq',
    List<String> excludedApps = const [],
  }) {
    final tags = outbounds.map((o) => o['tag'] as String).toList();
    return '''{
  "log": { "level": "warn" },
  $_dnsBlock,
  ${_tunBlock(excludedApps: excludedApps)},
  "outbounds": [
    {
      "type": "urltest",
      "tag": "proxy",
      "outbounds": ${tags.isEmpty ? '["direct"]' : '[${tags.map((t) => '"$t"').join(', ')}]'},
      "url": "https://www.gstatic.com/generate_204",
      "interval": "3m",
      "tolerance": 50
    },
    ${outbounds.map((o) => _encodeOutbound(o)).join(',\n    ')},
    { "type": "direct", "tag": "direct" },
    { "type": "block",  "tag": "block"  },
    { "type": "dns",    "tag": "dns-out" }
  ],
  ${_routeBlock(countryCode)}
}''';
  }

  static String _encodeOutbound(Map<String, dynamic> o) {
    final buf = StringBuffer('{');
    o.forEach((k, v) {
      if (v == null) return;
      buf.write('"$k": ');
      if (v is String) {
        buf.write('"$v"');
      } else if (v is Map || v is List) {
        buf.write(_jsonEncode(v));
      } else {
        buf.write(v);
      }
      buf.write(', ');
    });
    return '${buf.toString().trimRight().replaceAll(RegExp(r',$'), '')}}';
  }

  static String _jsonEncode(dynamic v) {
    if (v is Map) {
      final entries = v.entries
          .where((e) => e.value != null)
          .map((e) => '"${e.key}": ${_jsonEncode(e.value)}');
      return '{${entries.join(', ')}}';
    }
    if (v is List) {
      return '[${v.map(_jsonEncode).join(', ')}]';
    }
    if (v is String)  return '"$v"';
    if (v is bool)    return v.toString();
    return v.toString();
  }

  // ══════════════════════════════════════════════════════════════
  // ④ CUSTOM
  // ══════════════════════════════════════════════════════════════
  static String customTemplate({
    String countryCode = 'iq',
    List<String> excludedApps = const [],
  }) => '''{
  "log": { "level": "warn" },
  $_dnsBlock,
  ${_tunBlock(excludedApps: excludedApps)},
  "outbounds": [
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": ["auto"],
      "default": "auto"
    },
    $_speedTestOutbound,
    { "type": "direct", "tag": "direct" },
    { "type": "block",  "tag": "block"  },
    { "type": "dns",    "tag": "dns-out" }
  ],
  ${_routeBlock(countryCode)}
}''';
}
