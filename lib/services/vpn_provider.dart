import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ads_service.dart';
import 'cache_service.dart';

// ─── Notification Channel ─────────────────────────────────────
const _notifChannel = MethodChannel('com.onyxvpn.notification');

Future<void> _showNotification(String serverName, int ping) async {
  try {
    await _notifChannel.invokeMethod('show', {
      'server_name': serverName,
      'ping': ping,
    });
  } catch (_) {}
}

Future<void> _hideNotification() async {
  try {
    await _notifChannel.invokeMethod('hide');
  } catch (_) {}
}

// ─── helpers ──────────────────────────────────────────────────
String cleanCountryName(String raw) =>
    raw.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

String formatSpeed(String raw) {
  final num = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
  if (num == null || num == 0) return '0 B/s';
  if (num >= 1024 * 1024) return '${(num / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  if (num >= 1024) return '${(num / 1024).toStringAsFixed(1)} KB/s';
  return '${num.toStringAsFixed(0)} B/s';
}

// ─── Connection State ─────────────────────────────────────────
enum ConnectionState {
  disconnected,
  loading,
  connected,
  failed,
}

// ─── Source Priority ──────────────────────────────────────────
// ترتيب المصادر من الأصعب حجباً للأسهل
enum ServerSource {
  source2Hard,      // Hysteria2 + REALITY — الأصعب حجباً
  source3Cloudflare,// Cloudflare CDN — صعب جداً
  source4Tested,    // morpheusadam — مختبر فعلياً
  source1All,       // كل البروتوكولات — احتياطي
  supabase,         // Supabase — الكاش الرئيسي
}

// ─── VpnServer ────────────────────────────────────────────────
class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String ovpnConfig; // يحتوي كونفيغ V2Ray أو OpenVPN
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
    // الأصعب حجباً يأخذ أولوية عالية
    final hardBonus = isHardToBlock ? -100 : 0;
    final congestion = (numSessions / 10).clamp(0, 200).toInt();
    return effectivePing + congestion + hardBonus;
  }

  String get flag {
    if (countryCode.length != 2) return '🌐';
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

  factory VpnServer.fromMap(Map<String, dynamic> m) => VpnServer(
    countryName: cleanCountryName(m['country_name'] ?? ''),
    countryCode: m['country_code'] ?? '',
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

  bool get isConnected => _connState == ConnectionState.connected;
  bool get isConnecting => _connState == ConnectionState.loading;
  bool get isFailed => _connState == ConnectionState.failed;

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  String _currentSource = '';
  String get currentSource => _currentSource;

  String _downloadSpeed = '0 B/s';
  String _uploadSpeed = '0 B/s';
  String get downloadSpeed => _downloadSpeed;
  String get uploadSpeed => _uploadSpeed;

  Duration connectionDuration = Duration.zero;
  DateTime? _connectedAt;
  Timer? _statsTimer;
  Timer? _connectionTimeout;

  // V2Ray channel — للتواصل مع native Android
  static const _v2rayChannel = MethodChannel('com.onyxvpn.v2ray');

  bool _userDisconnected = false;
  bool _isSwitchingServer = false;
  Timer? _disconnectDebounce;
  String? _lastStage;

  static const int _timeoutSeconds = 25;
  final Set<String> _triedServers = {};
  final List<String> _trustedIps = [];

  // ─── روابط المصادر ────────────────────────────────────────

  // المصدر 1 — 0xRadikal كل البروتوكولات
  static const _source1Urls = [
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/vless.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/trojan.txt',
  ];

  // المصدر 2 — 0xRadikal Hysteria2 + REALITY فقط
  static const _source2Urls = [
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/reality.txt',
  ];

  // المصدر 3 — Cloudflare CDN
  static const _source3Urls = [
    'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub1.txt',
    'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub2.txt',
  ];

  // المصدر 4 — morpheusadam مختبر فعلياً
  static const _source4Urls = [
    'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/mix',
    'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/hysteria2',
  ];

  // ─── Parse Config ─────────────────────────────────────────
  String _detectProtocol(String config) {
    if (config.startsWith('vless://')) {
      if (config.toLowerCase().contains('reality') ||
          config.toLowerCase().contains('xtls')) return 'vless-reality';
      return 'vless';
    }
    if (config.startsWith('vmess://')) return 'vmess';
    if (config.startsWith('trojan://')) return 'trojan';
    if (config.startsWith('ss://')) return 'shadowsocks';
    if (config.startsWith('hysteria2://') || config.startsWith('hy2://')) return 'hysteria2';
    return 'unknown';
  }

  bool _isHardToBlock(String protocol) =>
      ['hysteria2', 'vless-reality', 'vless'].contains(protocol);

  String _decodeIfBase64(String text) {
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(text)));
      if (['vless://', 'vmess://', 'trojan://', 'ss://', 'hysteria2://']
          .any((p) => decoded.contains(p))) return decoded;
    } catch (_) {}
    return text;
  }

  List<String> _parseConfigs(String raw) {
    final text = _decodeIfBase64(raw.trim());
    const prefixes = ['vless://', 'vmess://', 'trojan://', 'ss://', 'hysteria2://', 'hy2://'];
    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => prefixes.any((p) => l.startsWith(p)))
        .toList();
  }

  String _extractHost(String config) {
    try {
      final afterProto = config.split('://').skip(1).join('://');
      if (config.startsWith('vmess://')) {
        final decoded = utf8.decode(base64.decode(base64.normalize(afterProto)));
        final data = jsonDecode(decoded) as Map<String, dynamic>;
        return data['add'] ?? '';
      }
      final atPart = afterProto.contains('@')
          ? afterProto.split('@').last
          : afterProto;
      return atPart.split(':').first.split('?').first.split('#').first;
    } catch (_) {
      return '';
    }
  }

  VpnServer? _configToServer(String config, String sourceName) {
    final protocol = _detectProtocol(config);
    if (protocol == 'unknown') return null;
    final host = _extractHost(config);
    if (host.isEmpty) return null;

    return VpnServer(
      ip: host,
      countryName: 'Auto',
      countryCode: 'XX',
      ping: _isHardToBlock(protocol) ? 80 : 180,
      ovpnConfig: config,
      protocol: protocol,
      source: sourceName,
      isHardToBlock: _isHardToBlock(protocol),
    );
  }

  // ─── Fetch من URL ─────────────────────────────────────────
  Future<String> _fetchText(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return res.body;
    } catch (_) {}
    return '';
  }

  // ─── المصدر 1 — كل البروتوكولات ──────────────────────────
  Future<List<VpnServer>> _fetchSource1() async {
    final result = <VpnServer>[];
    for (final url in _source1Urls) {
      final raw = await _fetchText(url);
      if (raw.isEmpty) continue;
      for (final c in _parseConfigs(raw).take(40)) {
        final s = _configToServer(c, 'source_1_all');
        if (s != null) result.add(s);
      }
    }
    return result;
  }

  // ─── المصدر 2 — Hysteria2 + REALITY فقط ──────────────────
  Future<List<VpnServer>> _fetchSource2() async {
    final result = <VpnServer>[];
    for (final url in _source2Urls) {
      final raw = await _fetchText(url);
      if (raw.isEmpty) continue;
      final configs = _parseConfigs(raw)
          .where((c) => ['hysteria2', 'vless-reality'].contains(_detectProtocol(c)))
          .take(30);
      for (final c in configs) {
        final s = _configToServer(c, 'source_2_hard');
        if (s != null) result.add(s);
      }
    }
    return result;
  }

  // ─── المصدر 3 — Cloudflare CDN ────────────────────────────
  Future<List<VpnServer>> _fetchSource3() async {
    final result = <VpnServer>[];
    for (final url in _source3Urls) {
      final raw = await _fetchText(url);
      if (raw.isEmpty) continue;
      final configs = _parseConfigs(raw)
          .where((c) => ['vless', 'trojan'].contains(_detectProtocol(c)))
          .take(25);
      for (final c in configs) {
        final s = _configToServer(c, 'source_3_cloudflare');
        if (s != null) {
          // أعطي Cloudflare أولوية أعلى
          result.add(VpnServer(
            ip: s.ip,
            countryName: s.countryName,
            countryCode: s.countryCode,
            ping: 60,
            ovpnConfig: s.ovpnConfig,
            protocol: s.protocol,
            source: s.source,
            isHardToBlock: true,
          ));
        }
      }
    }
    return result;
  }

  // ─── المصدر 4 — morpheusadam مختبر ───────────────────────
  Future<List<VpnServer>> _fetchSource4() async {
    final result = <VpnServer>[];
    for (final url in _source4Urls) {
      final raw = await _fetchText(url);
      if (raw.isEmpty) continue;
      for (final c in _parseConfigs(raw).take(40)) {
        final s = _configToServer(c, 'source_4_tested');
        if (s != null) {
          // مختبر فعلياً = أولوية أعلى
          result.add(VpnServer(
            ip: s.ip,
            countryName: s.countryName,
            countryCode: s.countryCode,
            ping: s.ping - 30,
            ovpnConfig: s.ovpnConfig,
            protocol: s.protocol,
            source: s.source,
            isHardToBlock: s.isHardToBlock,
          ));
        }
      }
    }
    return result;
  }

  // ─── Fetch Servers الرئيسي ────────────────────────────────
  Future<void> fetchServers({bool forceRefresh = false}) async {
    _serversError = null;

    // جرب الكاش أول
    if (!forceRefresh) {
      final cached = CacheService.getCachedServers();
      if (cached != null && cached.isNotEmpty) {
        _applyCached(cached);
        _loadingServers = false;
        notifyListeners();
        if (!CacheService.isCacheValid) _backgroundRefresh();
        measureAllPings();
        return;
      }
    }

    _loadingServers = true;
    _servers.clear();
    notifyListeners();

    // جيب من المصادر الأربعة + Supabase بالتوازي
    final results = await Future.wait([
      _fetchSource2(),       // الأولوية الأولى — Hysteria2 + REALITY
      _fetchSource3(),       // الأولوية الثانية — Cloudflare
      _fetchSource4(),       // الأولوية الثالثة — مختبر
      _fetchSource1(),       // الأولوية الرابعة — كل البروتوكولات
      _fetchSupabase(),      // Supabase — احتياطي
    ]);

    final allServers = <VpnServer>[
      ...results[0], // source2
      ...results[1], // source3
      ...results[2], // source4
      ...results[3], // source1
      ...results[4], // supabase
    ];

    if (allServers.isNotEmpty) {
      _applyServers(allServers);
      await CacheService.saveServers(_servers.map((s) => s.toMap()).toList());
      measureAllPings();
    } else {
      _serversError = 'Could not fetch servers. Pull down to retry.';
    }

    _loadingServers = false;
    notifyListeners();
  }

  Future<void> _backgroundRefresh() async {
    try {
      final results = await Future.wait([
        _fetchSource2(),
        _fetchSource3(),
        _fetchSource4(),
        _fetchSource1(),
        _fetchSupabase(),
      ]);
      final all = [...results[0], ...results[1], ...results[2], ...results[3], ...results[4]];
      if (all.isNotEmpty) {
        _applyServers(all);
        await CacheService.saveServers(_servers.map((s) => s.toMap()).toList());
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
      final aTrusted = _trustedIps.contains(a.ip);
      final bTrusted = _trustedIps.contains(b.ip);
      if (aTrusted && !bTrusted) return -1;
      if (!aTrusted && bTrusted) return 1;
      return a.score.compareTo(b.score);
    });
  }

  // ─── Fetch Supabase ───────────────────────────────────────
  Future<List<VpnServer>> _fetchSupabase() async {
    try {
      final res = await Supabase.instance.client
          .from('servers')
          .select()
          .eq('is_active', true)
          .order('ping', ascending: true)
          .limit(80);

      return (res as List)
          .map((r) => VpnServer.fromMap(Map<String, dynamic>.from(r)))
          .where((s) => s.ovpnConfig.isNotEmpty)
          .toList();
    } catch (_) {}

    try {
      const url = 'https://rtobllrfgmnlsxixmfwj.supabase.co';
      const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0b2JsbHJmZ21ubHN4aXhtZndqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1MDQ1MzYsImV4cCI6MjEwNTA4MDUzNn0.5AuNxLLbHByGGBVxbvkujHJ5VhUkFbNxRCkGW3ix3Y4';
      final uri = Uri.parse('$url/rest/v1/servers?is_active=eq.true&order=ping.asc&limit=80');
      final res = await http.get(uri, headers: {
        'apikey': key,
        'Authorization': 'Bearer $key',
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        return (jsonDecode(res.body) as List)
            .map((r) => VpnServer.fromMap(Map<String, dynamic>.from(r)))
            .where((s) => s.ovpnConfig.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    return [];
  }

  // ─── Connect ──────────────────────────────────────────────
  Future<void> connectTo(VpnServer server) async {
    if (_selected?.ip == server.ip && isConnected) return;

    _connectionTimeout?.cancel();
    _disconnectDebounce?.cancel();

    if (isConnected || isConnecting) {
      _isSwitchingServer = true;
      await _disconnect();
      await Future.delayed(const Duration(milliseconds: 800));
      _isSwitchingServer = false;
    }

    if (server.ovpnConfig.isEmpty) return;

    _userDisconnected = false;
    _lastStage = null;
    _selected = server;
    _connState = ConnectionState.loading;
    _statusMessage = 'Connecting...';
    _currentSource = _sourceLabel(server.source);
    notifyListeners();

    _connectionTimeout = Timer(
      const Duration(seconds: _timeoutSeconds),
      () {
        if (isConnecting) {
          _disconnect();
          _connState = ConnectionState.failed;
          _statusMessage = 'Trying next server...';
          notifyListeners();
          Timer(const Duration(seconds: 2), () {
            if (_connState == ConnectionState.failed) connectFastest();
          });
        }
      },
    );

    try {
      // V2Ray أو OpenVPN؟
      if (server.isV2Ray) {
        await _connectV2Ray(server);
      } else {
        await _connectOpenVPN(server);
      }
    } catch (_) {
      _connState = ConnectionState.failed;
      _connectionTimeout?.cancel();
      _statusMessage = 'Connection failed';
      notifyListeners();
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'source_2_hard': return '🔒 Hard-to-Block';
      case 'source_3_cloudflare': return '☁️ Cloudflare';
      case 'source_4_tested': return '✅ Tested';
      case 'source_1_all': return '🌐 Multi-Protocol';
      default: return '🛡️ Secure';
    }
  }

  // ─── V2Ray Connect ────────────────────────────────────────
  Future<void> _connectV2Ray(VpnServer server) async {
    try {
      final result = await _v2rayChannel.invokeMethod('connect', {
        'config': server.ovpnConfig,
        'name': server.countryName,
      });

      if (result == true) {
        _connState = ConnectionState.connected;
        _statusMessage = '';
        _triedServers.clear();
        if (!_trustedIps.contains(server.ip)) {
          _trustedIps.insert(0, server.ip);
          if (_trustedIps.length > 10) _trustedIps.removeLast();
        }
        _connectedAt = DateTime.now();
        _startStats();
        _connectionTimeout?.cancel();
        AdsService.showInterstitialAfterSuccess(1);
        _showNotification(server.countryName, server.effectivePing);
        notifyListeners();
      } else {
        // فشل — جرب التالي
        _connState = ConnectionState.failed;
        _statusMessage = 'Trying next server...';
        _connectionTimeout?.cancel();
        notifyListeners();
        Timer(const Duration(seconds: 2), () {
          if (_connState == ConnectionState.failed) connectFastest();
        });
      }
    } catch (_) {
      _connState = ConnectionState.failed;
      _connectionTimeout?.cancel();
      _statusMessage = 'V2Ray error — trying next...';
      notifyListeners();
      Timer(const Duration(seconds: 2), () {
        if (_connState == ConnectionState.failed) connectFastest();
      });
    }
  }

  // ─── OpenVPN Connect (احتياطي) ────────────────────────────
  Future<void> _connectOpenVPN(VpnServer server) async {
    // نفس منطق OpenVPN القديم — يستخدم فقط للسيرفرات القديمة بـ Supabase
    _connState = ConnectionState.failed;
    _statusMessage = 'OpenVPN not supported for this server';
    notifyListeners();
  }

  // ─── Connect Fastest ──────────────────────────────────────
  Future<void> connectFastest() async {
    if (_servers.isEmpty) await fetchServers();

    // رتب: الأصعب حجباً أولاً، ثم ما لم يجرب
    final available = _servers
        .where((s) => s.ovpnConfig.isNotEmpty)
        .toList();
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
    _isSwitchingServer = false;
    _disconnectDebounce?.cancel();
    _connectionTimeout?.cancel();
    _lastStage = null;
    _triedServers.clear();
    await _disconnect();
    _connState = ConnectionState.disconnected;
    _selected = null;
    _statusMessage = '';
    _currentSource = '';
    _stopStats();
    _hideNotification();
    notifyListeners();
  }

  Future<void> _disconnect() async {
    try {
      await _v2rayChannel.invokeMethod('disconnect');
    } catch (_) {}
    _stopStats();
  }

  // ─── Ping ─────────────────────────────────────────────────
  Future<int> _measurePing(String ip) async {
    for (final port in [443, 80, 1080]) {
      try {
        final start = DateTime.now();
        final socket = await Socket.connect(ip, port,
            timeout: const Duration(seconds: 3));
        final ms = DateTime.now().difference(start).inMilliseconds;
        socket.destroy();
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
    _uploadSpeed = '0 B/s';
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
    _disconnectDebounce?.cancel();
    super.dispose();
  }
}
