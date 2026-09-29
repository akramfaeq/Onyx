import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ads_service.dart';
import 'cache_service.dart';

// ─── Channels ─────────────────────────────────────────────────
const _notifChannel  = MethodChannel('com.onyxvpn.notification');
const _v2rayChannel  = MethodChannel('com.onyxvpn.v2ray');
const _eventChannel  = EventChannel('com.onyxvpn.v2ray.status');

// ─── Helpers ──────────────────────────────────────────────────
String cleanCountryName(String raw) =>
    raw.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

// IP → country via ip-api.com (مجاني بدون مفتاح)
Future<Map<String, String>> _lookupCountry(String ip) async {
  try {
    final res = await http
        .get(Uri.parse('http://ip-api.com/json/$ip?fields=country,countryCode'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'country': j['country'] as String? ?? 'Unknown',
        'code': j['countryCode'] as String? ?? 'XX',
      };
    }
  } catch (_) {}
  return {'country': 'Unknown', 'code': 'XX'};
}

// ─── Connection State ─────────────────────────────────────────
enum ConnectionState { disconnected, loading, connected, failed }

// ─── VpnServer ────────────────────────────────────────────────
class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String ovpnConfig;
  final int numSessions;
  final String protocol;
  final String source;
  final bool isHardToBlock;
  int realPing;

  VpnServer({
    required this.countryName,
    required this.countryCode,
    required this.ip,
    required this.ping,
    required this.ovpnConfig,
    this.numSessions = 0,
    this.protocol = 'unknown',
    this.source = 'supabase',
    this.isHardToBlock = false,
    this.realPing = -1,
  });

  int get effectivePing => realPing > 0 ? realPing : ping;

  int get score {
    final hardBonus = isHardToBlock ? -100 : 0;
    final congestion = (numSessions / 10).clamp(0, 200).toInt();
    return effectivePing + congestion + hardBonus;
  }

  String get flag {
    if (countryCode.length != 2 || countryCode == 'XX') return '🌐';
    return countryCode.toUpperCase().split('').map(
      (c) => String.fromCharCode(c.codeUnitAt(0) + 127397),
    ).join();
  }

  String get pingLabel {
    final p = effectivePing;
    if (p < 60) return 'Excellent';
    if (p < 120) return 'Good';
    if (p < 200) return 'Fair';
    return 'Slow';
  }

  int get bars {
    final p = effectivePing;
    if (p < 60) return 4;
    if (p < 120) return 3;
    if (p < 200) return 2;
    return 1;
  }

  bool get isV2Ray => [
    'vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria2', 'vless-reality'
  ].contains(protocol);

  Map<String, dynamic> toMap() => {
    'country_name': countryName,
    'country_code': countryCode,
    'ip': ip,
    'ping': ping,
    'real_ping': realPing,
    'ovpn_config': ovpnConfig,
    'num_sessions': numSessions,
    'protocol': protocol,
    'source': source,
    'is_hard_to_block': isHardToBlock,
  };

  VpnServer copyWith({String? countryName, String? countryCode}) => VpnServer(
    countryName: countryName ?? this.countryName,
    countryCode: countryCode ?? this.countryCode,
    ip: ip,
    ping: ping,
    ovpnConfig: ovpnConfig,
    numSessions: numSessions,
    protocol: protocol,
    source: source,
    isHardToBlock: isHardToBlock,
    realPing: realPing,
  );

  factory VpnServer.fromMap(Map<String, dynamic> m) => VpnServer(
    countryName: cleanCountryName(m['country_name'] ?? ''),
    countryCode: m['country_code'] ?? 'XX',
    ip: m['ip'] ?? '',
    ping: (m['ping'] as num?)?.toInt() ?? 999,
    ovpnConfig: m['ovpn_config'] ?? '',
    numSessions: (m['num_sessions'] as num?)?.toInt() ?? 0,
    protocol: m['protocol'] ?? 'unknown',
    source: m['source'] ?? 'supabase',
    isHardToBlock: m['is_hard_to_block'] == true,
    realPing: (m['real_ping'] as num?)?.toInt() ?? -1,
  );
}

// ─── VpnProvider ──────────────────────────────────────────────
class VpnProvider extends ChangeNotifier {
  final List<VpnServer> _servers = [];
  List<VpnServer> get servers => _servers;

  VpnServer? _selected;
  VpnServer? get selectedServer => _selected;

  bool _loadingServers = false;
  bool get loadingServers => _loadingServers;

  bool _measuringPing = false;
  bool get measuringPing => _measuringPing;

  String? _serversError;
  String? get serversError => _serversError;

  ConnectionState _connState = ConnectionState.disconnected;
  ConnectionState get connState => _connState;

  bool get isConnected  => _connState == ConnectionState.connected;
  bool get isConnecting => _connState == ConnectionState.loading;
  bool get isFailed     => _connState == ConnectionState.failed;

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  String _currentSource = '';
  String get currentSource => _currentSource;

  String _downloadSpeed = '0 B/s';
  String _uploadSpeed   = '0 B/s';
  String get downloadSpeed => _downloadSpeed;
  String get uploadSpeed   => _uploadSpeed;

  Duration connectionDuration = Duration.zero;
  DateTime? _connectedAt;
  Timer? _statsTimer;
  Timer? _connectionTimeout;

  bool _userDisconnected = false;
  static const int _timeoutSeconds = 30;
  final Set<String> _triedServers = {};
  final List<String> _trustedIps  = [];

  // StreamSubscription للـ status events من Android
  StreamSubscription? _statusSub;

  // ─── روابط المصادر ────────────────────────────────────────
  static const _source1Urls = [
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/vless.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/trojan.txt',
  ];
  static const _source2Urls = [
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/reality.txt',
  ];
  static const _source3Urls = [
    'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub1.txt',
    'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub2.txt',
  ];
  static const _source4Urls = [
    'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/mix',
    'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/hysteria2',
  ];

  // ─── Parse ────────────────────────────────────────────────
  String _detectProtocol(String c) {
    if (c.startsWith('vless://')) {
      return (c.toLowerCase().contains('reality') ||
              c.toLowerCase().contains('xtls'))
          ? 'vless-reality'
          : 'vless';
    }
    if (c.startsWith('vmess://'))    return 'vmess';
    if (c.startsWith('trojan://'))   return 'trojan';
    if (c.startsWith('ss://'))       return 'shadowsocks';
    if (c.startsWith('hysteria2://') || c.startsWith('hy2://')) return 'hysteria2';
    return 'unknown';
  }

  bool _isHardToBlock(String p) =>
      ['hysteria2', 'vless-reality', 'vless'].contains(p);

  String _decodeIfBase64(String text) {
    try {
      final d = utf8.decode(base64.decode(base64.normalize(text)));
      if (['vless://', 'vmess://', 'trojan://', 'ss://', 'hysteria2://']
          .any((p) => d.contains(p))) return d;
    } catch (_) {}
    return text;
  }

  List<String> _parseConfigs(String raw) {
    final text = _decodeIfBase64(raw.trim());
    const px = ['vless://', 'vmess://', 'trojan://', 'ss://', 'hysteria2://', 'hy2://'];
    return text.split('\n').map((l) => l.trim()).where((l) => px.any(l.startsWith)).toList();
  }

  String _extractHost(String config) {
    try {
      final after = config.split('://').skip(1).join('://');
      if (config.startsWith('vmess://')) {
        final d = utf8.decode(base64.decode(base64.normalize(after)));
        return (jsonDecode(d) as Map<String, dynamic>)['add'] ?? '';
      }
      final at = after.contains('@') ? after.split('@').last : after;
      return at.split(':').first.split('?').first.split('#').first;
    } catch (_) {
      return '';
    }
  }

  VpnServer? _configToServer(String config, String src) {
    final proto = _detectProtocol(config);
    if (proto == 'unknown') return null;
    final host = _extractHost(config);
    if (host.isEmpty) return null;
    return VpnServer(
      ip: host,
      countryName: 'Unknown',
      countryCode: 'XX',
      ping: _isHardToBlock(proto) ? 80 : 180,
      ovpnConfig: config,
      protocol: proto,
      source: src,
      isHardToBlock: _isHardToBlock(proto),
    );
  }

  // ─── Fetch ────────────────────────────────────────────────
  Future<String> _fetchText(String url) async {
    try {
      final r = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) return r.body;
    } catch (_) {}
    return '';
  }

  Future<List<VpnServer>> _fetchSource1() async {
    final out = <VpnServer>[];
    for (final u in _source1Urls) {
      final raw = await _fetchText(u);
      if (raw.isEmpty) continue;
      for (final c in _parseConfigs(raw).take(40)) {
        final s = _configToServer(c, 'source_1_all');
        if (s != null) out.add(s);
      }
    }
    return out;
  }

  Future<List<VpnServer>> _fetchSource2() async {
    final out = <VpnServer>[];
    for (final u in _source2Urls) {
      final raw = await _fetchText(u);
      if (raw.isEmpty) continue;
      for (final c in _parseConfigs(raw)
          .where((c) => ['hysteria2', 'vless-reality'].contains(_detectProtocol(c)))
          .take(30)) {
        final s = _configToServer(c, 'source_2_hard');
        if (s != null) out.add(s);
      }
    }
    return out;
  }

  Future<List<VpnServer>> _fetchSource3() async {
    final out = <VpnServer>[];
    for (final u in _source3Urls) {
      final raw = await _fetchText(u);
      if (raw.isEmpty) continue;
      for (final c in _parseConfigs(raw)
          .where((c) => ['vless', 'trojan'].contains(_detectProtocol(c)))
          .take(25)) {
        final s = _configToServer(c, 'source_3_cloudflare');
        if (s != null) out.add(VpnServer(
          ip: s.ip, countryName: s.countryName, countryCode: s.countryCode,
          ping: 60, ovpnConfig: s.ovpnConfig, protocol: s.protocol,
          source: s.source, isHardToBlock: true,
        ));
      }
    }
    return out;
  }

  Future<List<VpnServer>> _fetchSource4() async {
    final out = <VpnServer>[];
    for (final u in _source4Urls) {
      final raw = await _fetchText(u);
      if (raw.isEmpty) continue;
      for (final c in _parseConfigs(raw).take(40)) {
        final s = _configToServer(c, 'source_4_tested');
        if (s != null) out.add(VpnServer(
          ip: s.ip, countryName: s.countryName, countryCode: s.countryCode,
          ping: s.ping - 30, ovpnConfig: s.ovpnConfig, protocol: s.protocol,
          source: s.source, isHardToBlock: s.isHardToBlock,
        ));
      }
    }
    return out;
  }

  Future<List<VpnServer>> _fetchSupabase() async {
    try {
      final res = await Supabase.instance.client
          .from('servers').select().eq('is_active', true)
          .order('ping', ascending: true).limit(80);
      return (res as List)
          .map((r) => VpnServer.fromMap(Map<String, dynamic>.from(r)))
          .where((s) => s.ovpnConfig.isNotEmpty).toList();
    } catch (_) {}
    return [];
  }

  // ─── Fetch Servers ────────────────────────────────────────
  Future<void> fetchServers({bool forceRefresh = false}) async {
    _serversError = null;

    if (!forceRefresh) {
      final cached = CacheService.getCachedServers();
      if (cached != null && cached.isNotEmpty) {
        _applyCached(cached);
        _loadingServers = false;
        notifyListeners();
        if (!CacheService.isCacheValid) _backgroundRefresh();
        _enrichCountries();
        measureAllPings();
        return;
      }
    }

    _loadingServers = true;
    _servers.clear();
    notifyListeners();

    final results = await Future.wait([
      _fetchSource2(),
      _fetchSource3(),
      _fetchSource4(),
      _fetchSource1(),
      _fetchSupabase(),
    ]);

    final all = <VpnServer>[
      ...results[0], ...results[1], ...results[2], ...results[3], ...results[4],
    ];

    if (all.isNotEmpty) {
      _applyServers(all);
      await CacheService.saveServers(_servers.map((s) => s.toMap()).toList());
      _enrichCountries();
      measureAllPings();
    } else {
      _serversError = 'Could not fetch servers. Pull down to retry.';
    }

    _loadingServers = false;
    notifyListeners();
  }

  // ─── Enrich Countries — يجيب اسم الدولة والعلم من IP ─────
  Future<void> _enrichCountries() async {
    // خذ أول 30 سيرفر ما عندهم دولة
    final toEnrich = _servers
        .where((s) => s.countryCode == 'XX' || s.countryName == 'Unknown')
        .take(30)
        .toList();

    for (final server in toEnrich) {
      final info = await _lookupCountry(server.ip);
      final idx = _servers.indexWhere((s) => s.ip == server.ip && s.protocol == server.protocol);
      if (idx >= 0) {
        _servers[idx] = _servers[idx].copyWith(
          countryName: info['country'],
          countryCode: info['code'],
        );
      }
    }

    // احفظ بالكاش
    await CacheService.saveServers(_servers.map((s) => s.toMap()).toList());
    notifyListeners();
  }

  Future<void> _backgroundRefresh() async {
    try {
      final results = await Future.wait([
        _fetchSource2(), _fetchSource3(), _fetchSource4(),
        _fetchSource1(), _fetchSupabase(),
      ]);
      final all = [...results[0], ...results[1], ...results[2], ...results[3], ...results[4]];
      if (all.isNotEmpty) {
        _applyServers(all);
        await CacheService.saveServers(_servers.map((s) => s.toMap()).toList());
        _enrichCountries();
        notifyListeners();
        measureAllPings();
      }
    } catch (_) {}
  }

  void _applyCached(List<Map<String, dynamic>> cached) {
    _servers.clear();
    for (final m in cached) {
      final s = VpnServer.fromMap(m);
      if (s.ovpnConfig.isEmpty) continue;
      _servers.add(s);
    }
    _sortServers();
  }

  void _applyServers(List<VpnServer> list) {
    _servers.clear();
    final seen = <String>{};
    for (final s in list) {
      final key = '${s.ip}_${s.protocol}';
      if (seen.contains(key) || s.ovpnConfig.isEmpty) continue;
      seen.add(key);
      _servers.add(s);
    }
    _sortServers();
  }

  void _sortServers() {
    _servers.sort((a, b) {
      final at = _trustedIps.contains(a.ip);
      final bt = _trustedIps.contains(b.ip);
      if (at && !bt) return -1;
      if (!at && bt) return 1;
      return a.score.compareTo(b.score);
    });
  }

  // ─── Connect ──────────────────────────────────────────────
  Future<void> connectTo(VpnServer server) async {
    if (_selected?.ip == server.ip && isConnected) return;
    _connectionTimeout?.cancel();
    if (isConnected || isConnecting) {
      await _doDisconnect();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (server.ovpnConfig.isEmpty) return;

    _userDisconnected = false;
    _selected = server;
    _connState = ConnectionState.loading;
    _statusMessage = 'Connecting...';
    _currentSource = _sourceLabel(server.source);
    notifyListeners();

    // Timeout — لو ما اتصل خلال 30 ثانية جرب التالي
    _connectionTimeout = Timer(const Duration(seconds: _timeoutSeconds), () {
      if (isConnecting) {
        _doDisconnect();
        _connState = ConnectionState.failed;
        _statusMessage = 'Timeout — trying next...';
        notifyListeners();
        Timer(const Duration(seconds: 2), () {
          if (_connState == ConnectionState.failed && !_userDisconnected) {
            connectFastest();
          }
        });
      }
    });

    try {
      // شغّل xray عبر Kotlin
      final result = await _v2rayChannel.invokeMethod<bool>('connect', {
        'config': server.ovpnConfig,
        'name': server.countryName.isNotEmpty ? server.countryName : 'VPN',
      });

      if (result == true) {
        // انتظر ثانية وتحقق إن xray شغّال فعلاً
        await Future.delayed(const Duration(seconds: 2));
        final running = await _checkIfRunning();

        if (running) {
          _onConnected(server);
        } else {
          _onFailed();
        }
      } else {
        _onFailed();
      }
    } catch (e) {
      _onFailed();
    }
  }

  // تحقق إن xray شغّال فعلاً بتجربة اتصال بـ SOCKS port
  Future<bool> _checkIfRunning() async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1', 10808,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onConnected(VpnServer server) {
    _connState = ConnectionState.connected;
    _statusMessage = '';
    _connectionTimeout?.cancel();
    _triedServers.clear();
    if (!_trustedIps.contains(server.ip)) {
      _trustedIps.insert(0, server.ip);
      if (_trustedIps.length > 10) _trustedIps.removeLast();
    }
    _connectedAt = DateTime.now();
    _startStats();
    AdsService.showInterstitialAfterSuccess(1);
    _notifChannel.invokeMethod('show', {
      'server_name': server.countryName.isNotEmpty ? server.countryName : 'VPN',
      'ping': server.effectivePing,
    });
    notifyListeners();
  }

  void _onFailed() {
    _connectionTimeout?.cancel();
    _connState = ConnectionState.failed;
    _statusMessage = 'Failed — trying next...';
    notifyListeners();
    Timer(const Duration(seconds: 2), () {
      if (_connState == ConnectionState.failed && !_userDisconnected) {
        connectFastest();
      }
    });
  }

  String _sourceLabel(String src) {
    switch (src) {
      case 'source_2_hard':        return '🔒 Hard-to-Block';
      case 'source_3_cloudflare':  return '☁️ Cloudflare';
      case 'source_4_tested':      return '✅ Tested';
      case 'source_1_all':         return '🌐 Multi-Protocol';
      default:                     return '🛡️ Secure';
    }
  }

  // ─── Connect Fastest ──────────────────────────────────────
  Future<void> connectFastest() async {
    if (_servers.isEmpty) await fetchServers();
    final available = _servers.where((s) => s.ovpnConfig.isNotEmpty).toList();
    if (available.isEmpty) return;
    final untried = available.where((s) => !_triedServers.contains(s.ip)).toList();
    if (untried.isEmpty) {
      _triedServers.clear();
      await connectTo(available.first);
    } else {
      _triedServers.add(untried.first.ip);
      await connectTo(untried.first);
    }
  }

  // ─── Disconnect ───────────────────────────────────────────
  Future<void> disconnect() async {
    _userDisconnected = true;
    _connectionTimeout?.cancel();
    _triedServers.clear();
    await _doDisconnect();
    _connState = ConnectionState.disconnected;
    _selected = null;
    _statusMessage = '';
    _currentSource = '';
    _stopStats();
    _notifChannel.invokeMethod('hide');
    notifyListeners();
  }

  Future<void> _doDisconnect() async {
    try {
      await _v2rayChannel.invokeMethod('disconnect');
    } catch (_) {}
    _stopStats();
  }

  // ─── Listen for disconnect from notification button ───────
  void listenToNativeEvents() {
    // يستقبل "disconnect" من زر الـ notification
    _notifChannel.setMethodCallHandler((call) async {
      if (call.method == 'disconnect') {
        await disconnect();
      }
    });
  }

  // ─── Ping ─────────────────────────────────────────────────
  Future<int> _measurePing(String ip) async {
    for (final port in [443, 80, 8080]) {
      try {
        final start = DateTime.now();
        final s = await Socket.connect(ip, port,
            timeout: const Duration(seconds: 3));
        final ms = DateTime.now().difference(start).inMilliseconds;
        s.destroy();
        return ms;
      } catch (_) {}
    }
    return 9999;
  }

  Future<void> measureAllPings() async {
    if (_measuringPing || _servers.isEmpty) return;
    _measuringPing = true;
    notifyListeners();
    final batch = _servers.take(20).toList();
    final pings = await Future.wait(batch.map((s) => _measurePing(s.ip)));
    for (int i = 0; i < batch.length; i++) {
      batch[i].realPing = pings[i];
    }
    _sortServers();
    await CacheService.saveServers(_servers.map((s) => s.toMap()).toList());
    _measuringPing = false;
    notifyListeners();
  }

  // ─── Stats ────────────────────────────────────────────────
  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        connectionDuration = DateTime.now().difference(_connectedAt!);
        notifyListeners();
      }
    });
  }

  void _stopStats() {
    _statsTimer?.cancel();
    _connectedAt = null;
    connectionDuration = Duration.zero;
    _downloadSpeed = '0 B/s';
    _uploadSpeed   = '0 B/s';
  }

  String get formattedTime {
    final h = connectionDuration.inHours.toString().padLeft(2, '0');
    final m = connectionDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = connectionDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _connectionTimeout?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
