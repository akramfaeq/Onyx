// ─── Sing-box Config Builder ──────────────────────────────────
// يبني كونفيغ sing-box JSON كامل لكل mode

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'warp_service.dart';
import 'mahsa_service.dart';

class V2RayConfigs {

  // ─── DNS ──────────────────────────────────────────────────
  static Map<String, dynamic> _dns({bool blockAds = true}) => {
    'servers': [
      {'tag': 'cf',    'address': '1.1.1.1',     'detour': 'proxy'},
      {'tag': 'local', 'address': '8.8.8.8',     'detour': 'direct'},
      if (blockAds) {'tag': 'block', 'address': 'rcode://success'},
    ],
    'rules': [
      {'outbound': 'any', 'server': 'local'},
      if (blockAds) {'geosite': ['category-ads-all'], 'server': 'block'},
    ],
    'final': 'cf',
  };

  // ─── Inbounds (TUN) ───────────────────────────────────────
  static List<Map<String, dynamic>> _inbounds({List<String> excluded = const []}) => [
    {
      'type':         'tun',
      'tag':          'tun-in',
      'address':      ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
      'auto_route':   true,
      'strict_route': false,
      'sniff':        true,
      if (excluded.isNotEmpty) 'exclude_package': excluded,
    }
  ];

  // ─── Route ────────────────────────────────────────────────
  static Map<String, dynamic> _route({required String cc, bool blockAds = true}) => {
    'rules': [
      {'protocol':      'dns',                    'outbound': 'dns-out'},
      {'ip_is_private': true,                     'outbound': 'direct'},
      if (blockAds) {'geosite': ['category-ads-all'], 'outbound': 'block'},
      {'geoip':         [cc],                     'outbound': 'direct'},
      {'geosite':       [cc],                     'outbound': 'direct'},
    ],
    'final':                 'proxy',
    'auto_detect_interface': true,
  };

  static List<Map<String, dynamic>> _base() => [
    {'type': 'direct', 'tag': 'direct'},
    {'type': 'block',  'tag': 'block'},
    {'type': 'dns',    'tag': 'dns-out'},
  ];

  // ════════════════════════════════════════════════════════════
  // ① WARP — WireGuard من Cloudflare
  // ════════════════════════════════════════════════════════════
  static Future<String> warp({
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
    bool forceNewKeys = false,
  }) async {
    final keys = await WarpService.getKeys(forceRefresh: forceNewKeys);

    final privateKey = keys?.privateKey    ?? '4GgaQCy368kz1QjIHkQMCf35CJ3XeFBUKQfaYkANE1w=';
    final peerPub    = keys?.peerPublicKey ?? 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=';
    final reserved   = keys?.reserved      ?? [0, 0, 0];
    final v4         = keys?.v4Address     ?? '172.16.0.2';
    final v6         = keys?.v6Address     ?? '2606:4700:110:8f0b::2';

    Map<String, dynamic> wg(String tag, int port) => {
      'type':            'wireguard',
      'tag':             tag,
      'server':          'engage.cloudflareclient.com',
      'server_port':     port,
      'local_address':   ['$v4/32', '$v6/128'],
      'private_key':     privateKey,
      'peer_public_key': peerPub,
      'reserved':        reserved,
      'mtu':             1280,
    };

    return jsonEncode({
      'log':      {'level': 'warn'},
      'dns':      _dns(blockAds: blockAds),
      'inbounds': _inbounds(excluded: excludedApps),
      'outbounds': [
        {
          'type':      'urltest',
          'tag':       'proxy',
          'outbounds': ['warp-2408', 'warp-500', 'warp-1701', 'warp-4500'],
          'url':       'https://www.gstatic.com/generate_204',
          'interval':  '3m',
          'tolerance': 50,
        },
        wg('warp-2408', 2408),
        wg('warp-500',  500),
        wg('warp-1701', 1701),
        wg('warp-4500', 4500),
        ..._base(),
      ],
      'route': _route(cc: countryCode, blockAds: blockAds),
    });
  }

  // ════════════════════════════════════════════════════════════
  // ② PSIPHON — native outbound مدمج في hiddify-core.aar
  // sing-box يتصل بسيرفرات Psiphon تلقائياً بدون أي إعداد
  // نفس الطريقة التي يستخدمها hiddify داخلياً
  // ════════════════════════════════════════════════════════════
  static Future<String> psiphon({
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
  }) async {
    return jsonEncode({
      'log':      {'level': 'warn'},
      'dns':      _dns(blockAds: blockAds),
      'inbounds': _inbounds(excluded: excludedApps),
      'outbounds': [
        {
          'type': 'psiphon',
          'tag':  'proxy',
        },
        ..._base(),
      ],
      'route': _route(cc: countryCode, blockAds: blockAds),
    });
  }

  // ════════════════════════════════════════════════════════════
  // ③ MAHSA — سيرفرات من GitHub
  // ════════════════════════════════════════════════════════════
  static Future<String?> mahsa({
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
  }) async {
    final links = await MahsaService.getLinks(maxCount: 8);
    if (links.isEmpty) return null;

    final outbounds = <Map<String, dynamic>>[];
    for (final link in links) {
      final o = _parseLink(link);
      if (o != null) outbounds.add(o);
      if (outbounds.length >= 6) break;
    }
    if (outbounds.isEmpty) return null;

    return _buildFromOutbounds(
      outbounds: outbounds,
      countryCode: countryCode,
      excludedApps: excludedApps,
      blockAds: blockAds,
    );
  }

  // ════════════════════════════════════════════════════════════
  // ④ CUSTOM — subscription URL
  // ════════════════════════════════════════════════════════════
  static Future<String?> custom({
    required String url,
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
  }) async {
    try {
      final res = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'sing-box/1.0'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;

      final text  = _tryBase64(res.body.trim());
      final links = text.split('\n')
          .map((l) => l.trim())
          .where((l) =>
              l.startsWith('vless://')  ||
              l.startsWith('vmess://')  ||
              l.startsWith('trojan://') ||
              l.startsWith('ss://'))
          .toList();
      if (links.isEmpty) return null;

      final outbounds = <Map<String, dynamic>>[];
      for (final link in links) {
        final o = _parseLink(link);
        if (o != null) outbounds.add(o);
        if (outbounds.length >= 6) break;
      }
      if (outbounds.isEmpty) return null;

      return _buildFromOutbounds(
        outbounds: outbounds,
        countryCode: countryCode,
        excludedApps: excludedApps,
        blockAds: blockAds,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Build from outbounds ─────────────────────────────────
  static String _buildFromOutbounds({
    required List<Map<String, dynamic>> outbounds,
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
  }) {
    final tags = outbounds.map((o) => o['tag'] as String).toList();
    return jsonEncode({
      'log':      {'level': 'warn'},
      'dns':      _dns(blockAds: blockAds),
      'inbounds': _inbounds(excluded: excludedApps),
      'outbounds': [
        {
          'type':      'urltest',
          'tag':       'proxy',
          'outbounds': tags,
          'url':       'https://www.gstatic.com/generate_204',
          'interval':  '3m',
          'tolerance': 50,
        },
        ...outbounds,
        ..._base(),
      ],
      'route': _route(cc: countryCode, blockAds: blockAds),
    });
  }

  // ─── Link Parser ──────────────────────────────────────────
  static Map<String, dynamic>? _parseLink(String link) {
    try {
      final uri = Uri.parse(link);
      final tag = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'srv-${link.hashCode.abs() % 9999}';

      if (link.startsWith('vless://')) {
        final p = uri.queryParameters;
        return {
          'type':        'vless',
          'tag':         tag,
          'server':      uri.host,
          'server_port': uri.port,
          'uuid':        uri.userInfo,
          if ((p['flow'] ?? '').isNotEmpty) 'flow': p['flow'],
          'tls': {
            'enabled':     p['security'] == 'tls' || p['security'] == 'reality',
            'server_name': p['sni'] ?? p['host'] ?? uri.host,
            if (p['security'] == 'reality')
              'reality': {
                'enabled':    true,
                'public_key': p['pbk'] ?? '',
                'short_id':   p['sid'] ?? '',
              },
            'utls': {'enabled': true, 'fingerprint': p['fp'] ?? 'chrome'},
          },
          if (p['type'] != null && p['type'] != 'tcp')
            'transport': _parseTransport(p),
          'packet_encoding': 'xudp',
        };
      }

      if (link.startsWith('trojan://')) {
        final p = uri.queryParameters;
        return {
          'type':        'trojan',
          'tag':         tag,
          'server':      uri.host,
          'server_port': uri.port,
          'password':    uri.userInfo,
          'tls': {
            'enabled':     true,
            'server_name': p['sni'] ?? uri.host,
            'utls': {'enabled': true, 'fingerprint': p['fp'] ?? 'chrome'},
          },
          if (p['type'] != null && p['type'] != 'tcp')
            'transport': _parseTransport(p),
        };
      }

      if (link.startsWith('vmess://')) {
        final raw     = link.substring(8);
        final padded  = raw + '=' * ((4 - raw.length % 4) % 4);
        final decoded = jsonDecode(utf8.decode(base64.decode(padded))) as Map<String, dynamic>;
        return {
          'type':        'vmess',
          'tag':         decoded['ps'] as String? ?? tag,
          'server':      decoded['add'],
          'server_port': int.tryParse(decoded['port'].toString()) ?? 443,
          'uuid':        decoded['id'],
          'security':    decoded['scy'] ?? 'auto',
          'alter_id':    int.tryParse(decoded['aid'].toString()) ?? 0,
          'tls': {'enabled': decoded['tls'] == 'tls'},
          if (decoded['net'] != null && decoded['net'] != 'tcp')
            'transport': {
              'type': decoded['net'],
              if (decoded['path'] != null) 'path': decoded['path'],
              if (decoded['host'] != null) 'headers': {'Host': decoded['host']},
            },
        };
      }

      if (link.startsWith('ss://')) {
        final userInfo = uri.userInfo;
        final decoded  = utf8.decode(base64.decode(
            userInfo + '=' * ((4 - userInfo.length % 4) % 4)));
        final idx = decoded.indexOf(':');
        if (idx > 0) {
          return {
            'type':        'shadowsocks',
            'tag':         tag,
            'server':      uri.host,
            'server_port': uri.port,
            'method':      decoded.substring(0, idx),
            'password':    decoded.substring(idx + 1),
          };
        }
      }
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic>? _parseTransport(Map<String, String> p) {
    final type = p['type'];
    if (type == null || type == 'tcp') return null;
    if (type == 'ws')   return {'type': 'ws',   'path': p['path'] ?? '/', if (p['host'] != null) 'headers': {'Host': p['host']}};
    if (type == 'grpc') return {'type': 'grpc', 'service_name': p['serviceName'] ?? ''};
    if (type == 'h2')   return {'type': 'http', 'host': [if (p['host'] != null) p['host']!], 'path': p['path'] ?? '/'};
    return {'type': type};
  }

  static String _tryBase64(String input) {
    try {
      if (!input.contains('://')) {
        final padded  = input + '=' * ((4 - input.length % 4) % 4);
        final decoded = utf8.decode(base64.decode(padded));
        if (decoded.contains('://')) return decoded;
      }
    } catch (_) {}
    return input;
  }
}
