import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ads_service.dart';
import 'cache_service.dart';

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

// ─── VpnServer ────────────────────────────────────────────────
class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String ovpnConfig;
  final int numSessions;

  const VpnServer({
    required this.countryName,
    required this.countryCode,
    required this.ip,
    required this.ping,
    required this.ovpnConfig,
    this.numSessions = 0,
  });

  int get score {
    final congestion = (numSessions / 10).clamp(0, 200).toInt();
    return ping + congestion;
  }

  String get flag {
    if (countryCode.length != 2) return '🌐';
    return countryCode.toUpperCase().split('').map(
      (c) => String.fromCharCode(c.codeUnitAt(0) + 127397),
    ).join();
  }

  String get pingLabel {
    if (ping < 60) return 'Excellent';
    if (ping < 120) return 'Good';
    if (ping < 200) return 'Fair';
    return 'Slow';
  }

  int get bars {
    if (ping < 60) return 4;
    if (ping < 120) return 3;
    if (ping < 200) return 2;
    return 1;
  }

  Map<String, dynamic> toMap() => {
    'country_name': countryName,
    'country_code': countryCode,
    'ip': ip,
    'ping': ping,
    'ovpn_config': ovpnConfig,
    'num_sessions': numSessions,
  };

  factory VpnServer.fromMap(Map<String, dynamic> m) => VpnServer(
    countryName: cleanCountryName(m['country_name'] ?? ''),
    countryCode: m['country_code'] ?? '',
    ip: m['ip'] ?? '',
    ping: (m['ping'] as num?)?.toInt() ?? 999,
    ovpnConfig: m['ovpn_config'] ?? '',
    numSessions: (m['num_sessions'] as num?)?.toInt() ?? 0,
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

  String? _serversError;
  String? get serversError => _serversError;

  VPNStage _stage = VPNStage.disconnected;

  bool get isConnected => _stage == VPNStage.connected;
  bool get isConnecting =>
      _stage == VPNStage.connecting ||
      _stage == VPNStage.authenticating ||
      _stage == VPNStage.vpn_generate_config ||
      _stage == VPNStage.prepare;

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  String _downloadSpeed = '0 B/s';
  String _uploadSpeed = '0 B/s';
  String get downloadSpeed => _downloadSpeed;
  String get uploadSpeed => _uploadSpeed;

  Duration connectionDuration = Duration.zero;
  DateTime? _connectedAt;
  Timer? _statsTimer;
  Timer? _connectionTimeout;

  OpenVPN? _vpn;
  final List<String> _trustedIps = [];

  bool _userDisconnected = false;
  bool _isSwitchingServer = false;

  static const int _timeoutSeconds = 25;

  VpnProvider() {
    _initOpenVpn();
  }

  // ─── Init OpenVPN ─────────────────────────────────────────
  void _initOpenVpn() {
    _vpn = OpenVPN(
      onVpnStageChanged: (stage, _) {
        _stage = stage;

        if (stage == VPNStage.connected) {
          _connectionTimeout?.cancel();
          _statusMessage = '';
          if (_selected != null && !_trustedIps.contains(_selected!.ip)) {
            _trustedIps.insert(0, _selected!.ip);
            if (_trustedIps.length > 10) _trustedIps.removeLast();
          }
          _connectedAt = DateTime.now();
          _startStats();
          AdsService.showInterstitialAfterSuccess(1);

        } else if (stage == VPNStage.disconnected) {
          _connectionTimeout?.cancel();
          _stopStats();
          // لا نعيد الاتصال تلقائياً — المستخدم هو من يختار
          if (!_isSwitchingServer) {
            _statusMessage = '';
            _isReconnecting = false;
          }

        } else if (stage == VPNStage.connecting) {
          _statusMessage = 'Connecting...';
        } else if (stage == VPNStage.authenticating) {
          _statusMessage = 'Authenticating...';
        } else if (stage == VPNStage.prepare) {
          _statusMessage = 'Connecting...';
        }

        notifyListeners();
      },
      onVpnStatusChanged: (status) {
        if (status != null) {
          _downloadSpeed = formatSpeed(status.byteIn ?? '0');
          _uploadSpeed = formatSpeed(status.byteOut ?? '0');
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

  bool _isReconnecting = false;
  bool get isReconnecting => _isReconnecting;

  // ─── Connect To ───────────────────────────────────────────
  Future<void> connectTo(VpnServer server) async {
    // إذا متصل أو يتصل — افصل أولاً بشكل نظيف
    if (isConnected || isConnecting) {
      _isSwitchingServer = true;
      _vpn?.disconnect();
      _stage = VPNStage.disconnected;
      _stopStats();
      _connectionTimeout?.cancel();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
      _isSwitchingServer = false;
    }

    if (server.ovpnConfig.isEmpty) return;

    _userDisconnected = false;
    _selected = server;
    _stage = VPNStage.prepare;
    _statusMessage = 'Connecting...';
    notifyListeners();

    // timeout — إذا ما اتصل بـ 25 ثانية يوقف بدون ما يجرب سيرفر ثاني
    _connectionTimeout?.cancel();
    _connectionTimeout = Timer(
      const Duration(seconds: _timeoutSeconds),
      () {
        if (isConnecting) {
          _vpn?.disconnect();
          _stage = VPNStage.disconnected;
          _statusMessage = 'Connection timed out';
          notifyListeners();
        }
      },
    );

    try {
      _vpn?.connect(
        server.ovpnConfig,
        server.countryName,
        username: 'vpn',
        password: 'vpn',
        certIsRequired: false,
      );
    } catch (_) {
      _stage = VPNStage.disconnected;
      _connectionTimeout?.cancel();
      _statusMessage = 'Connection failed';
      notifyListeners();
    }
  }

  // ─── Connect Fastest ──────────────────────────────────────
  Future<void> connectFastest() async {
    if (_servers.isEmpty) {
      await fetchServers();
    }
    final available = _servers.where((s) => s.ovpnConfig.isNotEmpty).toList();
    if (available.isEmpty) return;
    available.sort((a, b) => a.score.compareTo(b.score));
    await connectTo(available.first);
  }

  // ─── Disconnect ───────────────────────────────────────────
  Future<void> disconnect() async {
    _userDisconnected = true;
    _isSwitchingServer = false;
    _isReconnecting = false;
    _connectionTimeout?.cancel();

    _vpn?.disconnect();
    _stage = VPNStage.disconnected;
    _selected = null;
    _statusMessage = '';
    _stopStats();
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

  // ─── Fetch Servers (Supabase فقط) ─────────────────────────
  Future<void> fetchServers({bool forceRefresh = false}) async {
    _serversError = null;

    if (!forceRefresh) {
      final cached = CacheService.getCachedServers();
      if (cached != null && cached.isNotEmpty) {
        _applyCached(cached);
        _loadingServers = false;
        notifyListeners();
        if (!CacheService.isCacheValid) _backgroundRefresh();
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
      }
    } catch (_) {}
  }

  void _applyCached(List<Map<String, dynamic>> cached) {
    _servers.clear();
    for (final m in cached) {
      final s = VpnServer.fromMap(m);
      if (s.ovpnConfig.isEmpty || s.ping > 300) continue;
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

  // ─── Fetch Supabase ───────────────────────────────────────
  Future<List<VpnServer>> _fetchSupabase() async {
    // طريقة ١: SDK
    try {
      final res = await Supabase.instance.client
          .from('servers')
          .select()
          .eq('is_active', true)
          .lte('ping', 300)
          .order('ping', ascending: true)
          .limit(80);

      final list = (res as List)
          .map((r) => VpnServer.fromMap(Map<String, dynamic>.from(r)))
          .where((s) => s.ovpnConfig.isNotEmpty)
          .toList();

      if (list.isNotEmpty) return list;
    } catch (_) {}

    // طريقة ٢: HTTP مباشر
    try {
      const url = 'https://rtobllrfgmnlsxixmfwj.supabase.co';
      const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0b2JsbHJmZ21ubHN4aXhtZndqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1MDQ1MzYsImV4cCI6MjEwNTA4MDUzNn0.5AuNxLLbHByGGBVxbvkujHJ5VhUkFbNxRCkGW3ix3Y4';

      final uri = Uri.parse('$url/rest/v1/servers?is_active=eq.true&ping=lte.300&order=ping.asc&limit=80');
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

  @override
  void dispose() {
    _statsTimer?.cancel();
    _connectionTimeout?.cancel();
    super.dispose();
  }
}
