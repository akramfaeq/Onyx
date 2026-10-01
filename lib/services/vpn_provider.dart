import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'ads_service.dart';
import 'cache_service.dart';

const _notifChannel = MethodChannel('com.onyxvpn.notification');

Future<void> _showNotification(String serverName, int ping) async {
  try { await _notifChannel.invokeMethod('show', {'server_name': serverName, 'ping': ping}); } catch (_) {}
}
Future<void> _hideNotification() async {
  try { await _notifChannel.invokeMethod('hide'); } catch (_) {}
}

String cleanCountryName(String raw) => raw.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

String formatSpeed(String raw) {
  final num = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
  if (num == null || num == 0) return '0 B/s';
  if (num >= 1024 * 1024) return '${(num / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  if (num >= 1024) return '${(num / 1024).toStringAsFixed(1)} KB/s';
  return '${num.toStringAsFixed(0)} B/s';
}

enum ConnectionState { disconnected, loading, connected, failed }

// ─── نوع السيرفر ──────────────────────────────────────────────
enum ServerType {
  openVpn,   // OpenVPN Gate — الأساس الشغّال
  v2ray,     // V2Ray/VLESS/Trojan — للمستقبل مع Cloudflare
  cloudflare // Cloudflare WARP — قريباً
}

class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String ovpnConfig;
  final int numSessions;
  final ServerType serverType;
  final String protocol;
  int realPing;

  VpnServer({
    required this.countryName,
    required this.countryCode,
    required this.ip,
    required this.ping,
    required this.ovpnConfig,
    this.numSessions = 0,
    this.serverType = ServerType.openVpn,
    this.protocol = 'openvpn',
    this.realPing = -1,
  });

  int get effectivePing => realPing > 0 ? realPing : ping;

  int get score {
    final congestion = (numSessions / 10).clamp(0, 200).toInt();
    // V2Ray وCloudflare يأخذون أولوية أعلى
    final typeBonus = serverType == ServerType.cloudflare ? -200
        : serverType == ServerType.v2ray ? -100 : 0;
    return effectivePing + congestion + typeBonus;
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

  // badge يبيّن نوع السيرفر
  String get typeBadge {
    switch (serverType) {
      case ServerType.cloudflare: return '☁️';
      case ServerType.v2ray:      return '⚡';
      case ServerType.openVpn:    return '';
    }
  }

  Map<String, dynamic> toMap() => {
    'country_name': countryName,
    'country_code': countryCode,
    'ip': ip,
    'ping': ping,
    'real_ping': realPing,
    'ovpn_config': ovpnConfig,
    'num_sessions': numSessions,
    'protocol': protocol,
    'server_type': serverType.index,
  };

  factory VpnServer.fromMap(Map<String, dynamic> m) {
    final proto = m['protocol'] ?? 'openvpn';
    final typeIndex = m['server_type'] as int?;
    ServerType type;
    if (typeIndex != null) {
      type = ServerType.values[typeIndex.clamp(0, ServerType.values.length - 1)];
    } else {
      // تخمين النوع من البروتوكول
      if (['vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria2'].contains(proto)) {
        type = ServerType.v2ray;
      } else {
        type = ServerType.openVpn;
      }
    }
    return VpnServer(
      countryName: cleanCountryName(m['country_name'] ?? ''),
      countryCode: m['country_code'] ?? 'XX',
      ip: m['ip'] ?? '',
      ping: (m['ping'] as num?)?.toInt() ?? 999,
      ovpnConfig: m['ovpn_config'] ?? '',
      numSessions: (m['num_sessions'] as num?)?.toInt() ?? 0,
      serverType: type,
      protocol: proto,
      realPing: (m['real_ping'] as num?)?.toInt() ?? -1,
    );
  }
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

  // ─── OpenVPN ──────────────────────────────────────────────
  OpenVPN? _vpn;

  // ─── V2Ray ────────────────────────────────────────────────
  FlutterV2ray? _v2ray;

  final List<String> _trustedIps = [];
  bool _userDisconnected = false;
  bool _isSwitchingServer = false;
  Timer? _disconnectDebounce;
  VPNStage? _lastStage;
  static const int _timeoutSeconds = 25;
  final Set<String> _triedServers = {};

  VpnProvider() {
    _initOpenVpn();
    _initV2Ray();
  }

  // ─── Init OpenVPN ─────────────────────────────────────────
  void _initOpenVpn() {
    _vpn = OpenVPN(
      onVpnStageChanged: (stage, _) {
        if (stage == _lastStage) return;
        _lastStage = stage;

        if (stage == VPNStage.connected) {
          _disconnectDebounce?.cancel();
          _connectionTimeout?.cancel();
          _connState = ConnectionState.connected;
          _statusMessage = '';
          _currentSource = 'OpenVPN';
          _triedServers.clear();
          if (_selected != null && !_trustedIps.contains(_selected!.ip)) {
            _trustedIps.insert(0, _selected!.ip);
            if (_trustedIps.length > 10) _trustedIps.removeLast();
          }
          _connectedAt = DateTime.now();
          _startStats();
          AdsService.showInterstitialAfterSuccess(1);
          _showNotification(_selected?.countryName ?? 'VPN', _selected?.effectivePing ?? -1);
          notifyListeners();

        } else if (stage == VPNStage.disconnected) {
          _disconnectDebounce?.cancel();
          _disconnectDebounce = Timer(const Duration(milliseconds: 1500), () {
            if (_isSwitchingServer) return;
            _connectionTimeout?.cancel();
            _stopStats();
            if (_userDisconnected) {
              _connState = ConnectionState.disconnected;
              _statusMessage = '';
            } else if (_connState == ConnectionState.loading) {
              _connState = ConnectionState.failed;
              _statusMessage = 'Trying next server...';
              notifyListeners();
              Timer(const Duration(seconds: 2), () {
                if (_connState == ConnectionState.failed) connectFastest();
              });
            } else {
              _connState = ConnectionState.disconnected;
              _statusMessage = '';
            }
            notifyListeners();
          });
        } else if ([VPNStage.connecting, VPNStage.authenticating,
                     VPNStage.vpn_generate_config, VPNStage.prepare].contains(stage)) {
          _disconnectDebounce?.cancel();
          _connState = ConnectionState.loading;
          _statusMessage = stage == VPNStage.authenticating ? 'Authenticating...' : 'Connecting...';
          notifyListeners();
        }
      },
      onVpnStatusChanged: (status) {
        if (status != null) {
          _downloadSpeed = formatSpeed(status.byteIn ?? '0');
          _uploadSpeed   = formatSpeed(status.byteOut ?? '0');
          notifyListeners();
        }
      },
    );
    _vpn!.initialize(
      groupIdentifier: 'com.onyxvpn.onyx_vpn',
      providerBundleIdentifier: 'com.onyxvpn.onyx_vpn',
      localizedDescription: 'OnyxVPN',
    );
  }

  // ─── Init V2Ray ───────────────────────────────────────────
  void _initV2Ray() {
    _v2ray = FlutterV2ray(
      onStatusChanged: (status) {
        if (status.state == 'CONNECTED') {
          _connectionTimeout?.cancel();
          _connState = ConnectionState.connected;
          _statusMessage = '';
          _currentSource = '⚡ V2Ray';
          _triedServers.clear();
          _connectedAt = DateTime.now();
          _startStats();
          AdsService.showInterstitialAfterSuccess(1);
          _showNotification(_selected?.countryName ?? 'VPN', _selected?.effectivePing ?? -1);
          notifyListeners();
        } else if (status.state == 'DISCONNECTED') {
          _stopStats();
          if (!_userDisconnected && _connState == ConnectionState.loading) {
            _connState = ConnectionState.failed;
            _statusMessage = 'Trying next server...';
            notifyListeners();
            Timer(const Duration(seconds: 2), () {
              if (_connState == ConnectionState.failed) connectFastest();
            });
          } else if (_userDisconnected) {
            _connState = ConnectionState.disconnected;
            _statusMessage = '';
            notifyListeners();
          }
        }
      },
    );
    _v2ray!.initializeV2Ray();
  }

  // ─── Connect To ───────────────────────────────────────────
  Future<void> connectTo(VpnServer server) async {
    if (_selected?.ip == server.ip && isConnected) return;

    _connectionTimeout?.cancel();
    _disconnectDebounce?.cancel();

    if (isConnected || isConnecting) {
      _isSwitchingServer = true;
      await _disconnectCurrent();
      await Future.delayed(const Duration(milliseconds: 800));
      _isSwitchingServer = false;
    }

    if (server.ovpnConfig.isEmpty) return;

    _userDisconnected = false;
    _lastStage = null;
    _selected = server;
    _connState = ConnectionState.loading;
    _statusMessage = 'Connecting...';
    notifyListeners();

    _connectionTimeout = Timer(const Duration(seconds: _timeoutSeconds), () {
      if (isConnecting) {
        _disconnectCurrent();
        _connState = ConnectionState.failed;
        _statusMessage = 'Trying next server...';
        notifyListeners();
        Timer(const Duration(seconds: 2), () {
          if (_connState == ConnectionState.failed) connectFastest();
        });
      }
    });

    try {
      if (server.serverType == ServerType.v2ray) {
        // ─── V2Ray connection ──────────────────────────────
        await _v2ray!.requestPermission();
        await _v2ray!.startV2Ray(
          remark: server.countryName,
          config: server.ovpnConfig,
          blockedApps: null,
          bypassSubnets: null,
          proxyOnly: false,
        );
      } else {
        // ─── OpenVPN connection ────────────────────────────
        _vpn?.connect(
          server.ovpnConfig,
          server.countryName,
          username: 'vpn',
          password: 'vpn',
          certIsRequired: false,
        );
      }
    } catch (_) {
      _connState = ConnectionState.failed;
      _connectionTimeout?.cancel();
      _statusMessage = 'Connection failed';
      notifyListeners();
    }
  }

  Future<void> _disconnectCurrent() async {
    try {
      if (_selected?.serverType == ServerType.v2ray) {
        await _v2ray?.stopV2Ray();
      } else {
        _vpn?.disconnect();
      }
    } catch (_) {}
    _stopStats();
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
    _isSwitchingServer = false;
    _disconnectDebounce?.cancel();
    _connectionTimeout?.cancel();
    _lastStage = null;
    _triedServers.clear();
    await _disconnectCurrent();
    _connState = ConnectionState.disconnected;
    _selected = null;
    _statusMessage = '';
    _currentSource = '';
    _hideNotification();
    notifyListeners();
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

    final list = await _fetchSupabase();

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
      final list = await _fetchSupabase();
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
      if (seen.contains(key)) continue;
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

  // ─── Fetch Supabase ───────────────────────────────────────
  Future<List<VpnServer>> _fetchSupabase() async {
    try {
      final res = await Supabase.instance.client
          .from('servers').select().eq('is_active', true)
          .order('ping', ascending: true).limit(80);
      final list = (res as List)
          .map((r) => VpnServer.fromMap(Map<String, dynamic>.from(r)))
          .where((s) => s.ovpnConfig.isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}

    try {
      const url = 'https://rtobllrfgmnlsxixmfwj.supabase.co';
      const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0b2JsbHJmZ21ubHN4aXhtZndqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1MDQ1MzYsImV4cCI6MjEwNTA4MDUzNn0.5AuNxLLbHByGGBVxbvkujHJ5VhUkFbNxRCkGW3ix3Y4';
      final uri = Uri.parse('$url/rest/v1/servers?is_active=eq.true&order=ping.asc&limit=80');
      final res = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        return (jsonDecode(res.body) as List)
            .map((r) => VpnServer.fromMap(Map<String, dynamic>.from(r)))
            .where((s) => s.ovpnConfig.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  // ─── Ping ─────────────────────────────────────────────────
  Future<int> _measurePing(String ip) async {
    for (final port in [443, 1194, 80]) {
      try {
        final start = DateTime.now();
        final s = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
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
    for (int i = 0; i < batch.length; i++) batch[i].realPing = pings[i];
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
    _disconnectDebounce?.cancel();
    super.dispose();
  }
}
