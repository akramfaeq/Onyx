// --- Sing-box Config Builder ----------------------------------
// يبني config JSON لـ sing-box حسب الـ mode

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'warp_service.dart';
import 'mahsa_service.dart';

// --- VpnServer model ------------------------------------------
class VpnServer {
  final String  name;
  final String  link;                        // v2ray link (ss:// vless:// ...)
  final Map<String, dynamic>? rawOutbound;  // sing-box outbound مباشر

  // بيانات العرض (من servers.json)
  final int    ping;
  final String quality;
  final String flag;
  final String country;

  const VpnServer({
    required this.name,
    required this.link,
    this.rawOutbound,
    this.ping    = 0,
    this.quality = '',
    this.flag    = '🌐',
    this.country = '',
  });
}

class V2RayConfigs {

  // --- DNS --------------------------------------------------
  static Map<String, dynamic> _dns({bool blockAds = true}) => {
    'servers': [
      {
        'tag':              'dns-remote',
        'address':          'https://1.1.1.1/dns-query',
        'address_resolver': 'dns-local',
        'strategy':         'ipv4_only',
        'detour':           'proxy',
      },
      {
        'tag':      'dns-local',
        'address':  'https://223.5.5.5/dns-query',
        'strategy': 'ipv4_only',
        'detour':   'direct',
      },
      {
        'tag':     'dns-trick',
        'address': 'https://sky.rethinkdns.com/1:-Pf_____9_78YAA8AJ4BmAEA=',
        'detour':  'direct-fragment',
      },
      if (blockAds) {'tag': 'block', 'address': 'rcode://success'},
    ],
    'rules': [
      {'outbound': 'any',         'server': 'dns-local'},
      {'clash_mode': 'direct',    'server': 'dns-local'},
      {
        'domain': ['sky.rethinkdns.com'],
        'server': 'dns-trick',
      },
      if (blockAds) {
        'rule_set':  ['geosite-malware', 'geosite-phishing', 'geosite-ads'],
        'server':    'block',
        'disable_cache': true,
      },
    ],
    'final':             'dns-remote',
    'independent_cache': true,
    'strategy':          'ipv4_only',
    'static_ips': {
      'sky.rethinkdns.com': ['188.114.96.3', '188.114.97.3'],
    },
  };

  // --- Inbounds (TUN) ---------------------------------------
  static List<Map<String, dynamic>> _inbounds({List<String> excluded = const []}) => [
    {
      'type':           'tun',
      'tag':            'tun-in',
      'inet4_address':  '172.19.0.1/30',
      'inet6_address':  'fdfe:dcba:9876::1/126',
      'mtu':            9000,
      'auto_route':     true,
      'strict_route':   true,
      'sniff':          true,
      'sniff_override_destination': false,
      if (excluded.isNotEmpty) 'exclude_package': excluded,
    }
  ];

  // --- Rule Sets (remote from hiddify-geo) ------------------
  static List<Map<String, dynamic>> _ruleSets(String cc) => [
    {
      'type':            'remote',
      'tag':             'geoip-${cc.toLowerCase()}',
      'format':          'binary',
      'url':             'https://raw.githubusercontent.com/hiddify/hiddify-geo/rule-set/geo-ip/geoip-${cc.toLowerCase()}.srs',
      'download_detour': 'direct',
      'update_interval': '120h',
    },
    {
      'type':            'remote',
      'tag':             'geosite-${cc.toLowerCase()}',
      'format':          'binary',
      'url':             'https://raw.githubusercontent.com/hiddify/hiddify-geo/rule-set/geo-site/geosite-${cc.toLowerCase()}.srs',
      'download_detour': 'direct',
      'update_interval': '120h',
    },
    {
      'type':            'remote',
      'tag':             'geosite-malware',
      'format':          'binary',
      'url':             'https://raw.githubusercontent.com/hiddify/hiddify-geo/rule-set/geo-site/geosite-malware.srs',
      'download_detour': 'direct',
      'update_interval': '120h',
    },
    {
      'type':            'remote',
      'tag':             'geosite-phishing',
      'format':          'binary',
      'url':             'https://raw.githubusercontent.com/hiddify/hiddify-geo/rule-set/geo-site/geosite-phishing.srs',
      'download_detour': 'direct',
      'update_interval': '120h',
    },
    {
      'type':            'remote',
      'tag':             'geosite-ads',
      'format':          'binary',
      'url':             'https://raw.githubusercontent.com/hiddify/hiddify-geo/rule-set/geo-site/geosite-category-ads-all.srs',
      'download_detour': 'direct',
      'update_interval': '120h',
    },
  ];

  // --- Route ------------------------------------------------
  static Map<String, dynamic> _route({required String cc, bool blockAds = true}) => {
    'rules': [
      {'protocol': 'dns',   'outbound': 'dns-out'},
      {'port':     53,      'outbound': 'dns-out'},
      {'ip_is_private': true, 'outbound': 'direct'},
      if (blockAds) ...[
        {'rule_set': ['geosite-malware'],  'outbound': 'block'},
        {'rule_set': ['geosite-phishing'], 'outbound': 'block'},
        {'rule_set': ['geosite-ads'],      'outbound': 'block'},
      ],
      {'rule_set': ['geoip-${cc.toLowerCase()}'],   'outbound': 'direct'},
      {'rule_set': ['geosite-${cc.toLowerCase()}'], 'outbound': 'direct'},
    ],
    'rule_set':              _ruleSets(cc),
    'final':                 'proxy',
    'auto_detect_interface': true,
    'override_android_vpn':  true,
  };

  static List<Map<String, dynamic>> _base() => [
    {'type': 'direct',   'tag': 'direct'},
    {'type': 'direct',   'tag': 'direct-fragment',
      'tls_fragment': {'enabled': true, 'size': '10-30', 'sleep': '5-10'}},
    {'type': 'block',    'tag': 'block'},
    {'type': 'dns',      'tag': 'dns-out'},
  ];

  // ------------------------------------------------------------
  // ✅ WARP — WireGuard عبر Cloudflare
  // ------------------------------------------------------------
  static Future<String> warp({
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
    bool forceNewKeys = false,
  }) async {
    final keys = await WarpService.getKeys(forceRefresh: forceNewKeys);
    if (keys == null) throw StateError('WARP registration failed. Check your internet connection and try again.');
    final privateKey = keys.privateKey;
    final peerPub = keys.peerPublicKey;
    final reserved = keys.reserved;
    final v4 = keys.v4Address;
    final v6 = keys.v6Address;

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
          'type':                        'urltest',
          'tag':                         'proxy',
          'outbounds':                   ['warp-2408', 'warp-500', 'warp-1701', 'warp-4500'],
          'url':                         'https://www.gstatic.com/generate_204', // FIX: cp.cloudflare.com يحجب IPs عند الطلبات الكثيرة
          'interval':                    '10m',
          'tolerance':                   150,   // FIX: كان 1ms
          'interrupt_exist_connections': false,  // FIX: أضفنا هذا صراحةً
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

  // ------------------------------------------------------------
  // ✅ PSIPHON — native outbound مدمج في hiddify-core.aar
  // ------------------------------------------------------------
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

  // ------------------------------------------------------------
  // ✅ WARP via PSIPHON
  // المنهجية: Psiphon يتصل أولاً → WARP يمشي من فوقه
  //
  // الكور (hiddify-core v4.x) يحتاج:
  //   1. كونفيغ فيه WARP WireGuard outbounds (نفس warp() العادي)
  //   2. parameter منفصل 'warpOverProxy: true' عبر MethodChannel
  //      → الكور يضيف Psiphon كـ detour تحت WireGuard تلقائياً
  //
  // لو أرسلنا Psiphon فقط بدون WARP keys → الكور ما يعرف يربط الاتصال
  // ------------------------------------------------------------
  static Future<String> warpViaPsiphon({
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
    bool forceNewKeys = false,
  }) async {
    // نحتاج WARP keys — الكور يستخدمها مع Psiphon كـ detour
    final keys = await WarpService.getKeys(forceRefresh: forceNewKeys);
    if (keys == null) {
      // fallback: Psiphon وحده لو ما حصلنا على keys
      debugPrint('warpViaPsiphon: no WARP keys, falling back to Psiphon only');
      return jsonEncode({
        'log':      {'level': 'warn'},
        'dns':      _dns(blockAds: blockAds),
        'inbounds': _inbounds(excluded: excludedApps),
        'outbounds': [
          {'type': 'psiphon', 'tag': 'proxy'},
          ..._base(),
        ],
        'route': _route(cc: countryCode, blockAds: blockAds),
      });
    }

    final privateKey = keys.privateKey;
    final peerPub    = keys.peerPublicKey;
    final reserved   = keys.reserved;
    final v4         = keys.v4Address;
    final v6         = keys.v6Address;

    // نفس بنية warp() — الكور يضيف Psiphon كـ detour عند warpOverProxy: true
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
          'type':                        'urltest',
          'tag':                         'proxy',
          'outbounds':                   ['warp-2408', 'warp-500', 'warp-1701', 'warp-4500'],
          'url':                         'https://www.gstatic.com/generate_204',
          'interval':                    '10m',
          'tolerance':                   150,
          'interrupt_exist_connections': false,
        },
        wg('warp-2408', 2408),
        wg('warp-500',  500),
        wg('warp-1701', 1701),
        wg('warp-4500', 4500),
        // Psiphon موجود كـ outbound منفصل — الكور يربطه مع WARP عبر warpOverProxy
        {'type': 'psiphon', 'tag': 'psiphon-out'},
        ..._base(),
      ],
      'route': _route(cc: countryCode, blockAds: blockAds),
    });
  }

  // ------------------------------------------------------------
  // ✅ MAHSA — سيرفرات من GitHub
  // ------------------------------------------------------------
  static Future<String?> mahsa({
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
  }) async {
    final links = await MahsaService.getLinks();
    if (links.isEmpty) return null;

    final outbounds = <Map<String, dynamic>>[];
    for (final link in links) {
      final o = _parseLink(link);
      if (o != null) outbounds.add(o);
      if (outbounds.length >= 20) break;
    }
    if (outbounds.isEmpty) return null;

    return _buildFromOutbounds(
      outbounds: outbounds,
      countryCode: countryCode,
      excludedApps: excludedApps,
      blockAds: blockAds,
    );
  }

  // ------------------------------------------------------------
  // ✅ CUSTOM — subscription URL
  // ------------------------------------------------------------
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

      final body = res.body.trim();
      if (body.startsWith('{')) {
        final servers = _serversFromSingboxJson(body);
        final outbounds = servers
            .where((server) => server.rawOutbound != null)
            .map((server) => server.rawOutbound!)
            .take(20)
            .toList();
        if (outbounds.isEmpty) return null;
        return _buildFromOutbounds(
          outbounds: outbounds,
          countryCode: countryCode,
          excludedApps: excludedApps,
          blockAds: blockAds,
        );
      }

      final links = _extractSubscriptionLinks(body);
      if (links.isEmpty) return null;

      final outbounds = <Map<String, dynamic>>[];
      for (final link in links) {
        final o = _parseLink(link);
        if (o != null) outbounds.add(o);
        if (outbounds.length >= 20) break;
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

  // ------------------------------------------------------------
  // ✅ PARSE SUBSCRIPTION
  // ------------------------------------------------------------
  static Future<List<VpnServer>> parseSubscription(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':    'hiddify/2.0 (sing-box compatible)',
          'Accept':        'application/json, text/plain, */*',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return [];

      final body = res.body.trim();
      if (body.isEmpty) return [];

      if (body.startsWith('{')) {
        return _serversFromSingboxJson(body);
      }

      final links = _extractSubscriptionLinks(body);

      return links.map((link) {
        final uri  = Uri.tryParse(link);
        final name = (uri?.fragment.isNotEmpty == true)
            ? Uri.decodeComponent(uri!.fragment)
            : '${uri?.scheme.toUpperCase() ?? 'SERVER'} · ${uri?.host ?? 'Server'}';
        final countryInfo = _extractCountryFromName(name);
        return VpnServer(
          name:    name,
          link:    link,
          flag:    countryInfo.$1,
          country: countryInfo.$2,
        );
      }).toList();

    } catch (_) {
      return [];
    }
  }

  // --- Country / Flag extractor from server name -----------
  static (String, String) _extractCountryFromName(String name) {
    final lower = name.toLowerCase();
    const map = <String, (String, String)>{
      'afghanistan':    ('🇦🇫', 'Afghanistan'),
      'albania':        ('🇦🇱', 'Albania'),
      'algeria':        ('🇩🇿', 'Algeria'),
      'argentina':      ('🇦🇷', 'Argentina'),
      'armenia':        ('🇦🇲', 'Armenia'),
      'australia':      ('🇦🇺', 'Australia'),
      'austria':        ('🇦🇹', 'Austria'),
      'azerbaijan':     ('🇦🇿', 'Azerbaijan'),
      'bahrain':        ('🇧🇭', 'Bahrain'),
      'bangladesh':     ('🇧🇩', 'Bangladesh'),
      'belarus':        ('🇧🇾', 'Belarus'),
      'belgium':        ('🇧🇪', 'Belgium'),
      'brazil':         ('🇧🇷', 'Brazil'),
      'bulgaria':       ('🇧🇬', 'Bulgaria'),
      'cambodia':       ('🇰🇭', 'Cambodia'),
      'canada':         ('🇨🇦', 'Canada'),
      'chile':          ('🇨🇱', 'Chile'),
      'china':          ('🇨🇳', 'China'),
      'colombia':       ('🇨🇴', 'Colombia'),
      'croatia':        ('🇭🇷', 'Croatia'),
      'cyprus':         ('🇨🇾', 'Cyprus'),
      'czech':          ('🇨🇿', 'Czech'),
      'denmark':        ('🇩🇰', 'Denmark'),
      'egypt':          ('🇪🇬', 'Egypt'),
      'estonia':        ('🇪🇪', 'Estonia'),
      'finland':        ('🇫🇮', 'Finland'),
      'france':         ('🇫🇷', 'France'),
      'georgia':        ('🇬🇪', 'Georgia'),
      'germany':        ('🇩🇪', 'Germany'),
      'greece':         ('🇬🇷', 'Greece'),
      'hong kong':      ('🇭🇰', 'Hong Kong'),
      'hungary':        ('🇭🇺', 'Hungary'),
      'india':          ('🇮🇳', 'India'),
      'indonesia':      ('🇮🇩', 'Indonesia'),
      'iran':           ('🇮🇷', 'Iran'),
      'iraq':           ('🇮🇶', 'Iraq'),
      'ireland':        ('🇮🇪', 'Ireland'),
      'israel':         ('🇮🇱', 'Israel'),
      'italy':          ('🇮🇹', 'Italy'),
      'japan':          ('🇯🇵', 'Japan'),
      'jordan':         ('🇯🇴', 'Jordan'),
      'kazakhstan':     ('🇰🇿', 'Kazakhstan'),
      'kuwait':         ('🇰🇼', 'Kuwait'),
      'latvia':         ('🇱🇻', 'Latvia'),
      'lebanon':        ('🇱🇧', 'Lebanon'),
      'lithuania':      ('🇱🇹', 'Lithuania'),
      'luxembourg':     ('🇱🇺', 'Luxembourg'),
      'malaysia':       ('🇲🇾', 'Malaysia'),
      'mexico':         ('🇲🇽', 'Mexico'),
      'moldova':        ('🇲🇩', 'Moldova'),
      'mongolia':       ('🇲🇳', 'Mongolia'),
      'morocco':        ('🇲🇦', 'Morocco'),
      'netherlands':    ('🇳🇱', 'Netherlands'),
      'new zealand':    ('🇳🇿', 'New Zealand'),
      'nigeria':        ('🇳🇬', 'Nigeria'),
      'norway':         ('🇳🇴', 'Norway'),
      'oman':           ('🇴🇲', 'Oman'),
      'pakistan':       ('🇵🇰', 'Pakistan'),
      'palestine':      ('🇵🇸', 'Palestine'),
      'philippines':    ('🇵🇭', 'Philippines'),
      'poland':         ('🇵🇱', 'Poland'),
      'portugal':       ('🇵🇹', 'Portugal'),
      'qatar':          ('🇶🇦', 'Qatar'),
      'romania':        ('🇷🇴', 'Romania'),
      'russia':         ('🇷🇺', 'Russia'),
      'saudi':          ('🇸🇦', 'Saudi Arabia'),
      'serbia':         ('🇷🇸', 'Serbia'),
      'singapore':      ('🇸🇬', 'Singapore'),
      'slovakia':       ('🇸🇰', 'Slovakia'),
      'south africa':   ('🇿🇦', 'South Africa'),
      'south korea':    ('🇰🇷', 'South Korea'),
      'spain':          ('🇪🇸', 'Spain'),
      'sweden':         ('🇸🇪', 'Sweden'),
      'switzerland':    ('🇨🇭', 'Switzerland'),
      'syria':          ('🇸🇾', 'Syria'),
      'taiwan':         ('🇹🇼', 'Taiwan'),
      'thailand':       ('🇹🇭', 'Thailand'),
      'tunisia':        ('🇹🇳', 'Tunisia'),
      'turkey':         ('🇹🇷', 'Turkey'),
      'turkiye':        ('🇹🇷', 'Turkey'),
      'ukraine':        ('🇺🇦', 'Ukraine'),
      'united arab':    ('🇦🇪', 'UAE'),
      'uae':            ('🇦🇪', 'UAE'),
      'united kingdom': ('🇬🇧', 'UK'),
      'united states':  ('🇺🇸', 'USA'),
      'uzbekistan':     ('🇺🇿', 'Uzbekistan'),
      'venezuela':      ('🇻🇪', 'Venezuela'),
      'vietnam':        ('🇻🇳', 'Vietnam'),
      'yemen':          ('🇾🇪', 'Yemen'),
      ' af ':  ('🇦🇫', 'Afghanistan'),
      ' al ':  ('🇦🇱', 'Albania'),
      ' am ':  ('🇦🇲', 'Armenia'),
      ' at ':  ('🇦🇹', 'Austria'),
      ' au ':  ('🇦🇺', 'Australia'),
      ' az ':  ('🇦🇿', 'Azerbaijan'),
      ' be ':  ('🇧🇪', 'Belgium'),
      ' bg ':  ('🇧🇬', 'Bulgaria'),
      ' br ':  ('🇧🇷', 'Brazil'),
      ' by ':  ('🇧🇾', 'Belarus'),
      ' ca ':  ('🇨🇦', 'Canada'),
      ' ch ':  ('🇨🇭', 'Switzerland'),
      ' cn ':  ('🇨🇳', 'China'),
      ' cy ':  ('🇨🇾', 'Cyprus'),
      ' cz ':  ('🇨🇿', 'Czech'),
      ' de ':  ('🇩🇪', 'Germany'),
      ' dk ':  ('🇩🇰', 'Denmark'),
      ' ee ':  ('🇪🇪', 'Estonia'),
      ' eg ':  ('🇪🇬', 'Egypt'),
      ' es ':  ('🇪🇸', 'Spain'),
      ' fi ':  ('🇫🇮', 'Finland'),
      ' fr ':  ('🇫🇷', 'France'),
      ' gb ':  ('🇬🇧', 'UK'),
      ' ge ':  ('🇬🇪', 'Georgia'),
      ' gr ':  ('🇬🇷', 'Greece'),
      ' hk ':  ('🇭🇰', 'Hong Kong'),
      ' hr ':  ('🇭🇷', 'Croatia'),
      ' hu ':  ('🇭🇺', 'Hungary'),
      ' id ':  ('🇮🇩', 'Indonesia'),
      ' ie ':  ('🇮🇪', 'Ireland'),
      ' il ':  ('🇮🇱', 'Israel'),
      ' in ':  ('🇮🇳', 'India'),
      ' iq ':  ('🇮🇶', 'Iraq'),
      ' ir ':  ('🇮🇷', 'Iran'),
      ' it ':  ('🇮🇹', 'Italy'),
      ' jo ':  ('🇯🇴', 'Jordan'),
      ' jp ':  ('🇯🇵', 'Japan'),
      ' kr ':  ('🇰🇷', 'South Korea'),
      ' kw ':  ('🇰🇼', 'Kuwait'),
      ' kz ':  ('🇰🇿', 'Kazakhstan'),
      ' lb ':  ('🇱🇧', 'Lebanon'),
      ' lt ':  ('🇱🇹', 'Lithuania'),
      ' lu ':  ('🇱🇺', 'Luxembourg'),
      ' lv ':  ('🇱🇻', 'Latvia'),
      ' ma ':  ('🇲🇦', 'Morocco'),
      ' md ':  ('🇲🇩', 'Moldova'),
      ' mx ':  ('🇲🇽', 'Mexico'),
      ' my ':  ('🇲🇾', 'Malaysia'),
      ' ng ':  ('🇳🇬', 'Nigeria'),
      ' nl ':  ('🇳🇱', 'Netherlands'),
      ' no ':  ('🇳🇴', 'Norway'),
      ' nz ':  ('🇳🇿', 'New Zealand'),
      ' om ':  ('🇴🇲', 'Oman'),
      ' ph ':  ('🇵🇭', 'Philippines'),
      ' pk ':  ('🇵🇰', 'Pakistan'),
      ' pl ':  ('🇵🇱', 'Poland'),
      ' ps ':  ('🇵🇸', 'Palestine'),
      ' pt ':  ('🇵🇹', 'Portugal'),
      ' qa ':  ('🇶🇦', 'Qatar'),
      ' ro ':  ('🇷🇴', 'Romania'),
      ' rs ':  ('🇷🇸', 'Serbia'),
      ' ru ':  ('🇷🇺', 'Russia'),
      ' sa ':  ('🇸🇦', 'Saudi Arabia'),
      ' se ':  ('🇸🇪', 'Sweden'),
      ' sg ':  ('🇸🇬', 'Singapore'),
      ' sk ':  ('🇸🇰', 'Slovakia'),
      ' sy ':  ('🇸🇾', 'Syria'),
      ' th ':  ('🇹🇭', 'Thailand'),
      ' tn ':  ('🇹🇳', 'Tunisia'),
      ' tr ':  ('🇹🇷', 'Turkey'),
      ' tw ':  ('🇹🇼', 'Taiwan'),
      ' ua ':  ('🇺🇦', 'Ukraine'),
      ' uk ':  ('🇬🇧', 'UK'),
      ' us ':  ('🇺🇸', 'USA'),
      ' uz ':  ('🇺🇿', 'Uzbekistan'),
      ' vn ':  ('🇻🇳', 'Vietnam'),
      ' ye ':  ('🇾🇪', 'Yemen'),
      ' za ':  ('🇿🇦', 'South Africa'),
    };

    final padded = ' $lower ';
    for (final entry in map.entries) {
      if (padded.contains(entry.key)) return entry.value;
    }
    return ('🌐', '');
  }

  static List<VpnServer> _serversFromSingboxJson(String raw) {
    try {
      final config     = jsonDecode(raw) as Map<String, dynamic>;
      final outbounds  = config['outbounds'] as List<dynamic>? ?? [];
      final skipTypes  = {'selector', 'urltest', 'direct', 'block', 'dns'};
      final servers    = <VpnServer>[];

      for (final ob in outbounds) {
        final m    = ob as Map<String, dynamic>;
        final type = m['type'] as String? ?? '';
        final tag  = m['tag']  as String? ?? '';
        if (skipTypes.contains(type) || !_supportedOutboundTypes.contains(type)) continue;

        final server = m['server'] as String? ?? '';
        final port   = m['server_port']?.toString() ?? '';
        if (server.isEmpty) continue;
        final label       = tag.isNotEmpty ? tag : '$type · $server:$port';
        final countryInfo = _extractCountryFromName(label);
        servers.add(VpnServer(
          name:        label,
          link:        '',
          rawOutbound: m,
          flag:        countryInfo.$1,
          country:     countryInfo.$2,
        ));
      }
      return servers;
    } catch (_) {
      return [];
    }
  }

  // بناء config لسيرفر واحد محدد
  static Future<String?> buildForServer({
    required String url,
    required VpnServer server,
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
  }) async {
    if (server.rawOutbound != null) {
      return _buildFromOutbounds(
        outbounds:    [server.rawOutbound!],
        countryCode:  countryCode,
        excludedApps: excludedApps,
        blockAds:     blockAds,
      );
    }

    if (server.link.isNotEmpty) {
      final ob = _parseLink(server.link);
      if (ob == null) return null;
      return _buildFromOutbounds(
        outbounds:    [ob],
        countryCode:  countryCode,
        excludedApps: excludedApps,
        blockAds:     blockAds,
      );
    }

    return custom(
      url:          url,
      countryCode:  countryCode,
      excludedApps: excludedApps,
      blockAds:     blockAds,
    );
  }

  // --- Build from server list (GitHub JSON) -----------------
  static Future<String?> buildFromServerList({
    required List<VpnServer> servers,
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
  }) async {
    final outbounds = <Map<String, dynamic>>[];
    for (final s in servers) {
      if (s.rawOutbound != null) {
        outbounds.add(s.rawOutbound!);
      } else if (s.link.isNotEmpty) {
        final ob = _parseLink(s.link);
        if (ob != null) outbounds.add(ob);
      }
      if (outbounds.length >= 12) break;
    }
    if (outbounds.isEmpty) return null;
    return _buildFromOutbounds(
      outbounds:    outbounds,
      countryCode:  countryCode,
      excludedApps: excludedApps,
      blockAds:     blockAds,
    );
  }

  // --- Build from outbounds ---------------------------------
  static String _buildFromOutbounds({
    required List<Map<String, dynamic>> outbounds,
    String countryCode = 'iq',
    List<String> excludedApps = const [],
    bool blockAds = true,
  }) {
    final safeOutbounds = <Map<String, dynamic>>[];
    final usedTags = <String>{};
    for (var i = 0; i < outbounds.length; i++) {
      final outbound = Map<String, dynamic>.from(outbounds[i]);
      final originalTag = outbound['tag'] as String?;
      var tag = originalTag?.trim().isNotEmpty == true
          ? originalTag!.trim()
          : 'server-${i + 1}';
      var suffix = 2;
      while (!usedTags.add(tag)) {
        tag = '${originalTag ?? 'server-${i + 1}'}-${suffix++}';
      }
      outbound['tag'] = tag;
      safeOutbounds.add(outbound);
    }
    if (safeOutbounds.isEmpty) {
      throw const FormatException('No supported VPN servers were found.');
    }
    final tags = safeOutbounds.map((o) => o['tag'] as String).toList();
    return jsonEncode({
      'log':      {'level': 'warn'},
      'dns':      _dns(blockAds: blockAds),
      'inbounds': _inbounds(excluded: excludedApps),
      'outbounds': [
        {
          'type':                        'urltest',
          'tag':                         'proxy',
          'outbounds':                   tags,
          'url':                         'https://www.gstatic.com/generate_204',
          'interval':                    '10m',
          'tolerance':                   150,   // FIX: كان 1ms → يسبب تبديل سيرفر عند كل اختبار
          'idle_timeout':                '30m',
          'interrupt_exist_connections': false,  // FIX: كان true → يقطع الاتصال عند كل تبديل
        },
        // FIX: حذف proxy-fallback — كان يختبر كل 30 ثانية ويقطع الاتصال باستمرار
        // sing-box يتعامل مع الفشل تلقائياً عبر proxy الرئيسي
        ...safeOutbounds,
        ..._base(),
      ],
      'route': _route(cc: countryCode, blockAds: blockAds),
    });
  }

  // --- Link Parser ------------------------------------------
  static Map<String, dynamic>? _parseLink(String link) {
    try {
      final normalizedLink = link.trim().replaceFirst('﻿', '');
      final uri = Uri.parse(normalizedLink);
      final tag = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'srv-${link.hashCode.abs() % 9999}';

      if (uri.scheme == 'vless') {
        final p = uri.queryParameters;
        return {
          'type':        'vless',
          'tag':         tag,
          'server':      uri.host,
          'server_port': uri.port,
          'uuid':        Uri.decodeComponent(uri.userInfo),
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

      if (uri.scheme == 'trojan') {
        final p = uri.queryParameters;
        return {
          'type':        'trojan',
          'tag':         tag,
          'server':      uri.host,
          'server_port': uri.port,
          'password':    Uri.decodeComponent(uri.userInfo),
          'tls': {
            'enabled':     true,
            'server_name': p['sni'] ?? uri.host,
            'utls': {'enabled': true, 'fingerprint': p['fp'] ?? 'chrome'},
          },
          if (p['type'] != null && p['type'] != 'tcp')
            'transport': _parseTransport(p),
        };
      }

      if (uri.scheme == 'vmess') {
        final raw     = normalizedLink.substring(normalizedLink.indexOf('://') + 3);
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
          'tls': {
            'enabled': decoded['tls'] == 'tls',
            if ((decoded['sni'] ?? '').toString().isNotEmpty)
              'server_name': decoded['sni'],
            if (decoded['tls'] == 'tls')
              'utls': {
                'enabled': true,
                'fingerprint': (decoded['fp'] ?? 'chrome').toString(),
              },
          },
          if (decoded['net'] != null && decoded['net'] != 'tcp')
            'transport': {
              'type': decoded['net'],
              if (decoded['path'] != null && decoded['path'].toString().isNotEmpty)
                'path': decoded['path'],
              if (decoded['host'] != null && decoded['host'].toString().isNotEmpty)
                'headers': {'Host': decoded['host']},
            },
        };
      }

      // ✅ FIX: ss:// يدعم الصيغتين: base64 القديمة و SIP002 الجديدة
      if (uri.scheme == 'ss') {
        return _parseShadowsocks(uri, tag);
      }

      if (uri.scheme == 'hysteria2' || uri.scheme == 'hy2') {
        final p = uri.queryParameters;
        final upMbps = int.tryParse(p['upmbps'] ?? '');
        final downMbps = int.tryParse(p['downmbps'] ?? '');
        final tls = <String, dynamic>{
          'enabled': true,
          'server_name': p['sni'] ?? uri.host,
          if (p['insecure'] == '1' || p['insecure'] == 'true') 'insecure': true,
          if (p['alpn']?.isNotEmpty == true) 'alpn': p['alpn']!.split(','),
          'utls': {'enabled': true, 'fingerprint': p['fp'] ?? 'chrome'},
        };
        final obfs = p['obfs'];
        return {
          'type': 'hysteria2',
          'tag': tag,
          'server': uri.host,
          'server_port': uri.port,
          'password': Uri.decodeComponent(uri.userInfo),
          'tls': tls,
          if (obfs?.isNotEmpty == true)
            'obfs': {
              'type': obfs,
              if (p['obfs-password']?.isNotEmpty == true)
                'password': p['obfs-password'],
            },
          if (upMbps != null) 'up_mbps': upMbps,
          if (downMbps != null) 'down_mbps': downMbps,
        };
      }

      if (uri.scheme == 'tuic') {
        final p = uri.queryParameters;
        final credentials = Uri.decodeComponent(uri.userInfo).split(':');
        if (credentials.length < 2) return null;
        return {
          'type': 'tuic',
          'tag': tag,
          'server': uri.host,
          'server_port': uri.port,
          'uuid': credentials.first,
          'password': credentials.skip(1).join(':'),
          'congestion_control': p['congestion_control'] ?? p['cc'] ?? 'bbr',
          'udp_relay_mode': p['udp_relay_mode'] ?? 'native',
          'tls': {
            'enabled': true,
            'server_name': p['sni'] ?? uri.host,
            if (p['insecure'] == '1' || p['insecure'] == 'true') 'insecure': true,
            'alpn': p['alpn']?.split(',') ?? ['h3'],
            'utls': {'enabled': true, 'fingerprint': p['fp'] ?? 'chrome'},
          },
        };
      }

      if (uri.scheme == 'anytls') {
        final p = uri.queryParameters;
        return {
          'type': 'anytls',
          'tag': tag,
          'server': uri.host,
          'server_port': uri.port,
          'password': Uri.decodeComponent(uri.userInfo),
          'tls': {
            'enabled': true,
            'server_name': p['sni'] ?? uri.host,
            if (p['insecure'] == '1' || p['insecure'] == 'true') 'insecure': true,
            'utls': {'enabled': true, 'fingerprint': p['fp'] ?? 'chrome'},
          },
        };
      }

      if (uri.scheme == 'socks' || uri.scheme == 'socks5') {
        final credentials = uri.userInfo.isEmpty
            ? const <String>[]
            : Uri.decodeComponent(uri.userInfo).split(':');
        return {
          'type': 'socks',
          'tag': tag,
          'server': uri.host,
          'server_port': uri.port,
          'version': '5',
          if (credentials.isNotEmpty) 'username': credentials.first,
          if (credentials.length > 1) 'password': credentials.skip(1).join(':'),
        };
      }
    } catch (_) {}
    return null;
  }

  // ✅ FIX: parser لـ ss:// يدعم SIP002 (method:pass@host:port) + base64 القديمة
  static Map<String, dynamic>? _parseShadowsocks(Uri uri, String tag) {
    try {
      // SIP002: ss://method:password@host:port
      // userInfo يكون مباشرة method:password (مو base64)
      if (uri.host.isNotEmpty && uri.port > 0) {
        final userInfo = Uri.decodeComponent(uri.userInfo);
        // لو فيه @ في الـ userInfo → base64 قديمة
        // لو ما فيه → SIP002 مباشرة
        if (!userInfo.contains('@')) {
          // حاول فك base64 أول
          try {
            final padded  = userInfo + '=' * ((4 - userInfo.length % 4) % 4);
            final decoded = utf8.decode(base64.decode(padded));
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
          } catch (_) {}
          // فشل base64 → SIP002 مباشرة
          final idx = userInfo.indexOf(':');
          if (idx > 0) {
            return {
              'type':        'shadowsocks',
              'tag':         tag,
              'server':      uri.host,
              'server_port': uri.port,
              'method':      userInfo.substring(0, idx),
              'password':    userInfo.substring(idx + 1),
            };
          }
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

  static const _supportedOutboundTypes = {
    'vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria2', 'tuic', 'anytls',
    'socks', 'http', 'wireguard',
  };

  static List<String> _extractSubscriptionLinks(String body) {
    final text = _tryBase64(body.trim()).replaceFirst('﻿', '');
    const schemes = {
      'vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic',
      'anytls', 'socks', 'socks5',
    };
    return text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) {
          if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) return false;
          final scheme = Uri.tryParse(line)?.scheme.toLowerCase();
          return scheme != null && schemes.contains(scheme);
        })
        .toSet()
        .toList();
  }
}
