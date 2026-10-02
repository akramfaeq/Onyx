import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_v2ray/flutter_v2ray.dart';
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

// ─── VpnServer ────────────────────────────────────────────────
class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String config; // V2Ray config (vless:// vmess:// trojan://)
  final String protocol; // vless / vmess / trojan / ss
  final int numSessions;
  final bool isHardToBlock;
  int realPing;

  VpnServer({
    required this.countryName,
    required this.countryCode,
    required this.ip,
    required this.ping,
    required this.config,
    this.protocol = 'vless',
    this.numSessions = 0,
    this.isHardToBlock = false,
    this.realPing = -1,
  });

  int get effectivePing => realPing > 0 ? realPing : ping;

  int get score {
    final congestion = (numSessions / 10).clamp(0, 200).toInt();
    final hardBonus  = isHardToBlock ? -100 : 0;
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
    if (p < 60)  return 'Excellent';
    if (p < 120) return 'Good';
    if (p < 200) return 'Fair';
    return 'Slow';
  }

  int get bars {
    final p = effectivePing;
    if (p < 60)  return 4;
    if (p < 120) return 3;
    if (p < 200) return 2;
    return 1;
  }

  Map<String, dynamic> toMap() => {
    'country_name':     countryName,
    'country_code':     countryCode,
    'ip':               ip,
    'ping':             ping,
    'real_ping':        realPing,
    'config':           config,
    'protocol':         protocol,
    'num_sessions':     numSessions,
    'is_hard_to_block': isHardToBlock,
  };

  factory VpnServer.fromMap(Map<String, dynamic> m) => VpnServer(
    countryName:    cleanCountryName(m['country_name'] ?? ''),
    countryCode:    m['country_code'] ?? '',
    ip:             m['ip'] ?? '',
    ping:           (m['ping'] as num?)?.toInt() ?? 999,
    config:         m['config'] ?? m['ovpn_config'] ?? '',
    protocol:       m['protocol'] ?? 'vless',
    numSessions:    (m['num_sessions'] as num?)?.toInt() ?? 0,
    isHardToBlock:  m['is_hard_to_block'] == true,
    realPing:       (m['real_ping'] as num?)?.toInt() ?? -1,
  );
}

// ─── VpnProvider ──────────────────────────────────────────────
class VpnProvider extends ChangeNotifier {
  final List<VpnServer> _servers = [];
  List<VpnServer> get servers => _servers;

  List<VpnServer> get serversForRegion {
    if (_isRestrictedRegion) {
      final hard   = _servers.where((s) => s.isHardToBlock).toList();
      final normal = _servers.where((s) => !s.isHardToBlock).toList();
      return [...hard, ...normal];
    }
    return _servers;
  }

  bool _isRestrictedRegion = false;
  bool get isRestrictedRegion => _isRestrictedRegion;

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

  String _downloadSpeed = '0 B/s';
  String _uploadSpeed   = '0 B/s';
  String get downloadSpeed => _downloadSpeed;
  String get uploadSpeed   => _uploadSpeed;

  Duration connectionDuration = Duration.zero;
  DateTime? _connectedAt;
  Timer? _statsTimer;
  Timer? _connectionTimeout;
  Timer? _disconnectDebounce;

  // ─── flutter_v2ray ────────────────────────────────────────
  late final FlutterV2ray _v2ray = FlutterV2ray(
    onStatusChanged: (status) {
      _onV2RayStatus(status);
    },
  );

  bool _v2rayInitialized = false;
  bool _userDisconnected = false;
  bool _isSwitchingServer = false;
  final Set<String> _triedServers = {};
  final List<String> _trustedIps = [];

  static const int _timeoutSeconds = 30;

  VpnProvider() {
    _initV2Ray();
    _detectRegion();
  }

  // ─── Init V2Ray ───────────────────────────────────────────
  Future<void> _initV2Ray() async {
    await _v2ray.initializeV2Ray(
      notificationIconResourceType: 'drawable',
      notificationIconResourceName: 'ic_vpn_notification',
    );
    _v2rayInitialized = true;
  }

  // ─── Status Handler ───────────────────────────────────────
  void _onV2RayStatus(V2RayStatus status) {
    final state = status.state;

    if (state == 'CONNECTED') {
      _disconnectDebounce?.cancel();
      _connectionTimeout?.cancel();
      _connState     = ConnectionState.connected;
      _statusMessage = '';
      _triedServers.clear();
      _downloadSpeed = formatSpeed(status.download);
      _uploadSpeed   = formatSpeed(status.upload);

      if (_selected != null && !_trustedIps.contains(_selected!.ip)) {
        _trustedIps.insert(0, _selected!.ip);
        if (_trustedIps.length > 10) _trustedIps.removeLast();
      }

      _connectedAt = DateTime.now();
      _startStats();
      AdsService.showInterstitialAfterSuccess(1);
      _showNotification(
        _selected?.countryName ?? 'VPN',
        _selected?.effectivePing ?? -1,
      );
      notifyListeners();

    } else if (state == 'DISCONNECTED') {
      _disconnectDebounce?.cancel();
      _disconnectDebounce = Timer(
        const Duration(milliseconds: 1500),
        () {
          if (_isSwitchingServer) return;
          _connectionTimeout?.cancel();
          _stopStats();
          if (_userDisconnected) {
            _connState     = ConnectionState.disconnected;
            _statusMessage = '';
          } else if (_connState == ConnectionState.loading) {
            _connState     = ConnectionState.failed;
            _statusMessage = 'Trying next server...';
            notifyListeners();
            Timer(const Duration(seconds: 2), () {
              if (_connState == ConnectionState.failed) {
                connectFastest();
              }
            });
          } else {
            _connState     = ConnectionState.disconnected;
            _statusMessage = '';
          }
          notifyListeners();
        },
      );

    } else if (state == 'CONNECTING') {
      _disconnectDebounce?.cancel();
      _connState     = ConnectionState.loading;
      _statusMessage = 'Connecting...';
      _downloadSpeed = formatSpeed(status.download);
      _uploadSpeed   = formatSpeed(status.upload);
      notifyListeners();

    } else {
      // حدّث السرعة حتى في الحالات الأخرى
      _downloadSpeed = formatSpeed(status.download);
      _uploadSpeed   = formatSpeed(status.upload);
      notifyListeners();
    }
  }

  // ─── Connect To ───────────────────────────────────────────
  Future<void> connectTo(VpnServer server) async {
    if (!_v2rayInitialized) return;
    if (_selected?.ip == server.ip && isConnected) return;

    _connectionTimeout?.cancel();
    _disconnectDebounce?.cancel();

    if (isConnected || isConnecting) {
      _isSwitchingServer = true;
      await _v2ray.stopV2Ray();
      _stopStats();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 800));
      _isSwitchingServer = false;
    }

    if (server.config.isEmpty) return;

    // طلب إذن VPN من المستخدم
    final hasPermission = await FlutterV2ray.requestPermission();
    if (!hasPermission) {
      _connState     = ConnectionState.failed;
      _statusMessage = 'VPN permission denied';
      notifyListeners();
      return;
    }

    _userDisconnected = false;
    _selected         = server;
    _connState        = ConnectionState.loading;
    _statusMessage    = 'Connecting...';
    notifyListeners();

    _connectionTimeout = Timer(
      const Duration(seconds: _timeoutSeconds),
      () {
        if (isConnecting) {
          _v2ray.stopV2Ray();
          _connState     = ConnectionState.failed;
          _statusMessage = 'Connection failed. Trying another server...';
          notifyListeners();
          Timer(const Duration(seconds: 2), () {
            if (_connState == ConnectionState.failed) {
              if (_selected != null) _triedServers.add(_selected!.ip);
              connectFastest();
            }
          });
        }
      },
    );

    try {
      // حوّل الـ config لـ V2Ray JSON
      final v2rayURL = V2RayURL.parseURL(server.config);
      await _v2ray.startV2Ray(
        remark:          server.countryName,
        config:          v2rayURL.getFullConfiguration(),
        blockedApps:     null,
        bypassSubnets:   null,
        proxyOnly:       false,
        notificationDisconnectButtonName: 'Disconnect',
      );
    } catch (e) {
      _connState     = ConnectionState.failed;
      _connectionTimeout?.cancel();
      _statusMessage = 'Connection failed';
      debugPrint('V2Ray connect error: $e');
      notifyListeners();
    }
  }

  // ─── Connect Fastest ──────────────────────────────────────
  Future<void> connectFastest() async {
    if (_servers.isEmpty) await fetchServers();

    final available = serversForRegion
        .where((s) => s.config.isNotEmpty)
        .toList();

    if (available.isEmpty) return;

    final untried = available
        .where((s) => !_triedServers.contains(s.ip))
        .toList();

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
    _userDisconnected  = true;
    _isSwitchingServer = false;
    _disconnectDebounce?.cancel();
    _connectionTimeout?.cancel();
    _triedServers.clear();

    await _v2ray.stopV2Ray();
    _connState     = ConnectionState.disconnected;
    _selected      = null;
    _statusMessage = '';
    _stopStats();
    _hideNotification();
    notifyListeners();
  }

  // ─── Ping ─────────────────────────────────────────────────
  Future<int> _measurePing(VpnServer server) async {
    try {
      final delay = await _v2ray.getServerDelay(config: V2RayURL.parseURL(server.config).getFullConfiguration());
      return delay;
    } catch (_) {
      return 9999;
    }
  }

  Future<void> measureAllPings() async {
    if (_measuringPing || _servers.isEmpty) return;
    _measuringPing = true;
    notifyListeners();

    final batch = _servers.take(20).toList();
    final pings = await Future.wait(
      batch.map((s) => _measurePing(s)),
    );

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
    _connectedAt       = null;
    connectionDuration = Duration.zero;
    _downloadSpeed     = '0 B/s';
    _uploadSpeed       = '0 B/s';
  }

  String get formattedTime {
    final h = connectionDuration.inHours.toString().padLeft(2, '0');
    final m = connectionDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = connectionDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ─── Detect Region ────────────────────────────────────────
  Future<void> _detectRegion() async {
    const restrictedCountries = {
      'IR', 'CN', 'RU', 'TR', 'PK', 'BD',
      'EG', 'SA', 'AE', 'QA', 'KW', 'OM', 'BH',
    };
    try {
      final res = await http.get(
        Uri.parse('https://ip-api.com/json/?fields=countryCode'),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data        = jsonDecode(res.body);
        final countryCode = data['countryCode'] as String? ?? '';
        _isRestrictedRegion = restrictedCountries.contains(countryCode);
        debugPrint('📍 البلد: $countryCode | محجوب: $_isRestrictedRegion');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ تعذّر اكتشاف البلد: $e');
    }
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
        measureAllPings();
        return;
      }
    }

    _loadingServers = true;
    _servers.clear();
    notifyListeners();

    final list = await _fetchAllSources();

    if (list.isNotEmpty) {
      _applyServers(list);
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
      final list = await _fetchAllSources();
      if (list.isNotEmpty) {
        _applyServers(list);
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
      if (s.config.isEmpty) continue;
      _servers.add(s);
    }
    _sortServers();
  }

  void _applyServers(List<VpnServer> list) {
    _servers.clear();
    final seen = <String>{};
    for (final s in list) {
      if (seen.contains(s.ip)) continue;
      seen.add(s.ip);
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

  // ─── Fetch All Sources ────────────────────────────────────
  // المصادر بالترتيب: Cloudflare Worker ← Supabase ← GitHub
  Future<List<VpnServer>> _fetchAllSources() async {
    // ① Cloudflare Worker (Supabase mirror)
    try {
      final res = await http.get(
        Uri.parse('https://vpn.akramfaeq523.workers.dev/servers'),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List)
            .map((r) => VpnServer.fromMap(Map<String, dynamic>.from(r)))
            .where((s) => s.config.isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          debugPrint('✅ Servers via Worker: ${list.length}');
          return list;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Worker failed: $e');
    }

    // ② Supabase
    try {
      final res = await Supabase.instance.client
          .from('servers')
          .select()
          .eq('is_active', true)
          .order('ping', ascending: true)
          .limit(80);

      final list = (res as List)
          .map((r) => VpnServer.fromMap(Map<String, dynamic>.from(r)))
          .where((s) => s.config.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}

    // ③ GitHub — مصادر V2Ray مجانية محدّثة كل 15 دقيقة
    return await _fetchFromGitHub();
  }

  // ─── GitHub Free V2Ray Sources ────────────────────────────
  // هذي المصادر تشتغل بإيران وتتحدث تلقائياً
  static const _githubSources = [
    // top100 — مفلترة ومتحقق منها
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/top100.txt',
    // verified — كل config اختبرها 3 مرات
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs.txt',
    // fast — أسرع السيرفرات
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/fast/configs.txt',
    // مصدر ثاني — يتحدث كل 5 دقائق
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/Sub1.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/Sub2.txt',
  ];

  Future<List<VpnServer>> _fetchFromGitHub() async {
    final allConfigs = <String>[];

    for (final url in _githubSources) {
      try {
        final res = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;

        String body = res.body;
        // لو base64 فك التشفير
        if (!body.contains('://')) {
          try { body = utf8.decode(base64.decode(body.trim())); } catch (_) {}
        }

        final lines = body.split('\n')
            .map((l) => l.trim())
            .where((l) =>
                l.startsWith('vless://') ||
                l.startsWith('vmess://') ||
                l.startsWith('trojan://') ||
                l.startsWith('ss://'))
            .toList();

        allConfigs.addAll(lines);
        debugPrint('✅ GitHub ${url.split('/').last}: ${lines.length} configs');

        if (allConfigs.length >= 200) break;
      } catch (e) {
        debugPrint('⚠️ GitHub source failed: $e');
      }
    }

    if (allConfigs.isEmpty) return [];

    // حوّل الـ configs لـ VpnServer
    final servers = <VpnServer>[];
    final seen    = <String>{};
    final rng     = Random();

    for (final configStr in allConfigs) {
      try {
        final parsed = V2RayURL.parseURL(configStr);
        final ip     = parsed.address;
        if (ip.isEmpty || seen.contains(ip)) continue;
        seen.add(ip);

        final protocol = configStr.split('://').first.toLowerCase();
        final isTls    = configStr.contains('tls') || configStr.contains(':443');

        servers.add(VpnServer(
          countryName:    parsed.remark.isNotEmpty ? parsed.remark : 'Unknown',
          countryCode:    _guessCountryCode(parsed.remark),
          ip:             ip,
          ping:           rng.nextInt(150) + 50, // ping مؤقت حتى نقيسه
          config:         configStr,
          protocol:       protocol,
          isHardToBlock:  isTls,
        ));

        if (servers.length >= 80) break;
      } catch (_) {
        continue;
      }
    }

    debugPrint('✅ GitHub total servers: ${servers.length}');
    return servers;
  }

  // ─── Guess Country Code from Remark ───────────────────────
  String _guessCountryCode(String remark) {
    final r = remark.toUpperCase();
    if (r.contains('US') || r.contains('UNITED STATES') || r.contains('AMERICA')) return 'US';
    if (r.contains('DE') || r.contains('GERMANY') || r.contains('DEUTSCH')) return 'DE';
    if (r.contains('NL') || r.contains('NETHERLANDS') || r.contains('HOLLAND')) return 'NL';
    if (r.contains('FR') || r.contains('FRANCE')) return 'FR';
    if (r.contains('GB') || r.contains('UK') || r.contains('BRITAIN')) return 'GB';
    if (r.contains('JP') || r.contains('JAPAN')) return 'JP';
    if (r.contains('SG') || r.contains('SINGAPORE')) return 'SG';
    if (r.contains('TR') || r.contains('TURKEY')) return 'TR';
    if (r.contains('CA') || r.contains('CANADA')) return 'CA';
    if (r.contains('AU') || r.contains('AUSTRALIA')) return 'AU';
    if (r.contains('FI') || r.contains('FINLAND')) return 'FI';
    if (r.contains('SE') || r.contains('SWEDEN')) return 'SE';
    return 'UN';
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _connectionTimeout?.cancel();
    _disconnectDebounce?.cancel();
    super.dispose();
  }
}
