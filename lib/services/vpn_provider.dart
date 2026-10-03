import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ads_service.dart';
import 'cache_service.dart';

const _notifChannel = MethodChannel('com.onyxvpn.notification');

Future<void> _showNotification(String serverName, int ping) async {
  try { await _notifChannel.invokeMethod('show', {'server_name': serverName, 'ping': ping}); } catch (_) {}
}
Future<void> _hideNotification() async {
  try { await _notifChannel.invokeMethod('hide'); } catch (_) {}
}

String cleanCountryName(String raw) =>
    raw.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

// flutter_v2ray يرجع String للسرعة
String formatSpeed(dynamic raw) {
  if (raw == null) return '0 B/s';
  final s = raw.toString().trim();
  if (s.isEmpty || s == '0') return '0 B/s';
  // لو رجع رقم int أو double
  final n = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
  if (n == null || n == 0) return s.contains('/') ? s : '0 B/s';
  if (n >= 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  if (n >= 1024) return '${(n / 1024).toStringAsFixed(1)} KB/s';
  return '${n.toStringAsFixed(0)} B/s';
}

enum ConnectionState { disconnected, loading, connected, failed }

class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String config;
  final String protocol;
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

  int get effectivePing => realPing > 0 && realPing < 9999 ? realPing : ping;

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
    // Supabase يخزن الـ config بعمود ovpn_config
    config:         m['config'] ?? m['ovpn_config'] ?? '',
    protocol:       m['protocol'] ?? 'vless',
    numSessions:    (m['num_sessions'] as num?)?.toInt() ?? 0,
    isHardToBlock:  m['is_hard_to_block'] == true,
    realPing:       (m['real_ping'] as num?)?.toInt() ?? -1,
  );
}

class VpnProvider extends ChangeNotifier {
  final List<VpnServer> _servers = [];
  List<VpnServer> get servers => _servers;

  // السيرفرات المفلترة للعرض
  List<VpnServer> get serversPort443 => _servers.where((s) => s.isHardToBlock).toList();
  List<VpnServer> get serversFast    => _servers.where((s) => s.effectivePing < 120).toList();

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

  late final V2ray _v2ray = V2ray(
    onStatusChanged: _onV2RayStatus,
  );

  bool _v2rayInitialized = false;
  bool _userDisconnected = false;
  bool _isSwitchingServer = false;
  final Set<String> _triedServers = {};
  final List<String> _trustedIps = [];

  static const int _timeoutSeconds = 30;

  VpnProvider() {
    _initV2Ray();
  }

  Future<void> _initV2Ray() async {
    await _v2ray.initialize(
      notificationIconResourceType: 'drawable',
      notificationIconResourceName: 'ic_vpn_notification',
      providerBundleIdentifier: 'dev.amirzr.flutterV2rayMobile',
      groupIdentifier: 'group.dev.amirzr.flutterV2rayMobile',
    );
    _v2rayInitialized = true;
  }

  void _onV2RayStatus(V2RayStatus status) {
    final state = status.state;

    if (state == 'CONNECTED') {
      _disconnectDebounce?.cancel();
      _connectionTimeout?.cancel();
      _connState     = ConnectionState.connected;
      _statusMessage = '';
      _triedServers.clear();
      _downloadSpeed = formatSpeed(status.downloadSpeed);
      _uploadSpeed   = formatSpeed(status.uploadSpeed);

      if (_selected != null && !_trustedIps.contains(_selected!.ip)) {
        _trustedIps.insert(0, _selected!.ip);
        if (_trustedIps.length > 10) _trustedIps.removeLast();
      }

      _connectedAt = DateTime.now();
      _startStats();
      AdsService.showInterstitialAfterSuccess(1);
      _showNotification(_selected?.countryName ?? 'VPN', _selected?.effectivePing ?? -1);
      notifyListeners();

    } else if (state == 'DISCONNECTED') {
      _disconnectDebounce?.cancel();
      _disconnectDebounce = Timer(const Duration(milliseconds: 1500), () {
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
            if (_connState == ConnectionState.failed) connectFastest();
          });
        } else {
          _connState     = ConnectionState.disconnected;
          _statusMessage = '';
        }
        notifyListeners();
      });

    } else if (state == 'CONNECTING') {
      _disconnectDebounce?.cancel();
      _connState     = ConnectionState.loading;
      _statusMessage = 'Connecting...';
      notifyListeners();

    } else {
      _downloadSpeed = formatSpeed(status.downloadSpeed);
      _uploadSpeed   = formatSpeed(status.uploadSpeed);
      notifyListeners();
    }
  }

  Future<void> connectTo(VpnServer server) async {
    if (!_v2rayInitialized) return;
    if (_selected?.ip == server.ip && isConnected) return;
    if (server.config.isEmpty) return;

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

    final hasPermission = await _v2ray.requestPermission();
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

    _connectionTimeout = Timer(const Duration(seconds: _timeoutSeconds), () {
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
    });

    try {
      final parsed = V2ray.parseFromURL(server.config);
      await _v2ray.startV2Ray(
        remark:          server.countryName,
        config:          parsed.getFullConfiguration(),
        blockedApps:     null,
        bypassSubnets:   null,
        proxyOnly:       false,
        notificationDisconnectButtonName: 'Disconnect',
      );
    } catch (e) {
      _connState     = ConnectionState.failed;
      _connectionTimeout?.cancel();
      _statusMessage = 'Connection failed';
      debugPrint('V2Ray error: $e');
      notifyListeners();
    }
  }

  Future<void> connectFastest() async {
    if (_servers.isEmpty) await fetchServers();
    final available = _servers.where((s) => s.config.isNotEmpty).toList();
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

  Future<int> _measurePing(VpnServer server) async {
    try {
      final parsed = V2ray.parseFromURL(server.config);
      return await _v2ray.getServerDelay(config: parsed.getFullConfiguration() );
    } catch (_) { return 9999; }
  }

  Future<void> measureAllPings() async {
    if (_measuringPing || _servers.isEmpty) return;
    _measuringPing = true;
    notifyListeners();

    final batch = _servers.where((s) => s.config.isNotEmpty).take(20).toList();
    final pings  = await Future.wait(batch.map((s) => _measurePing(s)));
    for (int i = 0; i < batch.length; i++) batch[i].realPing = pings[i];

    _sortServers();
    await CacheService.saveServers(_servers.map((s) => s.toMap()).toList());
    _measuringPing = false;
    notifyListeners();
  }

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
      if (seen.contains(s.ip) || s.config.isEmpty) continue;
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

  Future<List<VpnServer>> _fetchAllSources() async {
    // ① Supabase
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

    // ② GitHub مباشرة
    return await _fetchFromGitHub();
  }

  static const _githubSources = [
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/top100.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/fast/configs.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/Sub1.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/Sub2.txt',
  ];

  Future<List<VpnServer>> _fetchFromGitHub() async {
    final allConfigs = <String>[];

    for (final url in _githubSources) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;

        String body = res.body;
        if (!body.contains('://')) {
          try { body = utf8.decode(base64.decode(body.trim())); } catch (_) {}
        }

        final lines = body.split('\n').map((l) => l.trim()).where((l) =>
            l.startsWith('vless://') || l.startsWith('vmess://') ||
            l.startsWith('trojan://') || l.startsWith('ss://')).toList();

        allConfigs.addAll(lines);
        if (allConfigs.length >= 200) break;
      } catch (_) {}
    }

    if (allConfigs.isEmpty) return [];

    final servers = <VpnServer>[];
    final seen    = <String>{};
    final rng     = Random();

    for (final configStr in allConfigs) {
      try {
        final parsed = V2ray.parseFromURL(configStr);
        final ip     = parsed.address;
        if (ip.isEmpty || seen.contains(ip)) continue;
        seen.add(ip);

        final protocol = configStr.split('://').first.toLowerCase();
        final isTls    = configStr.contains('tls') || configStr.contains(':443');

        servers.add(VpnServer(
          countryName:    parsed.remark.isNotEmpty ? parsed.remark : 'Unknown',
          countryCode:    _guessCountryCode(parsed.remark),
          ip:             ip,
          ping:           rng.nextInt(150) + 50,
          config:         configStr,
          protocol:       protocol,
          isHardToBlock:  isTls,
        ));

        if (servers.length >= 80) break;
      } catch (_) { continue; }
    }

    return servers;
  }

  String _guessCountryCode(String remark) {
    final r = remark.toUpperCase();
    if (r.contains('US') || r.contains('UNITED STATES')) return 'US';
    if (r.contains('DE') || r.contains('GERMANY')) return 'DE';
    if (r.contains('NL') || r.contains('NETHERLANDS')) return 'NL';
    if (r.contains('FR') || r.contains('FRANCE')) return 'FR';
    if (r.contains('GB') || r.contains('UK')) return 'GB';
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
