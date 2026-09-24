import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
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
// حالة واحدة واضحة بدل حالات متعددة مشتتة
enum ConnectionState {
  disconnected,
  loading,    // connecting + authenticating = حالة واحدة
  connected,
  failed,
}

// ─── VpnServer ────────────────────────────────────────────────
class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String ovpnConfig;
  final int numSessions;
  // ✅ ping حقيقي مقاس من الجهاز
  int realPing;

  VpnServer({
    required this.countryName,
    required this.countryCode,
    required this.ip,
    required this.ping,
    required this.ovpnConfig,
    this.numSessions = 0,
    this.realPing = -1, // -1 يعني لم يُقس بعد
  });

  // ✅ الترتيب بالـ ping الحقيقي إذا متوفر، وإلا من القاعدة
  int get effectivePing => realPing > 0 ? realPing : ping;

  int get score {
    final congestion = (numSessions / 10).clamp(0, 200).toInt();
    return effectivePing + congestion;
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

  Map<String, dynamic> toMap() => {
    'country_name': countryName,
    'country_code': countryCode,
    'ip': ip,
    'ping': ping,
    'real_ping': realPing,
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

  // ✅ إصلاح ٣: حالة واحدة واضحة
  ConnectionState _connState = ConnectionState.disconnected;
  ConnectionState get connState => _connState;

  bool get isConnected => _connState == ConnectionState.connected;
  bool get isConnecting => _connState == ConnectionState.loading;
  bool get isFailed => _connState == ConnectionState.failed;

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

  // ✅ إصلاح ٢: فلتر الأحداث الخاطفة
  Timer? _disconnectDebounce;
  VPNStage? _lastStage;

  static const int _timeoutSeconds = 30;

  VpnProvider() {
    _initOpenVpn();
  }

  // ─── Init OpenVPN ─────────────────────────────────────────
  void _initOpenVpn() {
    _vpn = OpenVPN(
      onVpnStageChanged: (stage, _) {
        // ✅ إصلاح ٢: تجاهل نفس الحالة المتكررة
        if (stage == _lastStage) return;
        _lastStage = stage;

        if (stage == VPNStage.connected) {
          _disconnectDebounce?.cancel();
          _connectionTimeout?.cancel();
          _connState = ConnectionState.connected;
          _statusMessage = '';
          _triedServers.clear(); // ريست عند النجاح

          if (_selected != null && !_trustedIps.contains(_selected!.ip)) {
            _trustedIps.insert(0, _selected!.ip);
            if (_trustedIps.length > 10) _trustedIps.removeLast();
          }
          _connectedAt = DateTime.now();
          _startStats();
          AdsService.showInterstitialAfterSuccess(1);
          // ✅ أظهر إشعار مخصص
          _showNotification(
            _selected?.countryName ?? 'VPN',
            _selected?.effectivePing ?? -1,
          );
          notifyListeners();

        } else if (stage == VPNStage.disconnected) {
          // ✅ إصلاح ٢: انتظر 1.5 ثانية قبل ما تعتبرها فصل حقيقي
          // لأن المكتبة ترسل DISCONNECTED أثناء المصادقة أحياناً
          _disconnectDebounce?.cancel();
          _disconnectDebounce = Timer(
            const Duration(milliseconds: 1500),
            () {
              if (_isSwitchingServer) return;
              _connectionTimeout?.cancel();
              _stopStats();
              if (_userDisconnected) {
                _connState = ConnectionState.disconnected;
                _statusMessage = '';
              } else if (_connState == ConnectionState.loading) {
                // ✅ إصلاح ٤: حالة فشل صريحة ثم تجرب التالي تلقائياً
                _connState = ConnectionState.failed;
                _statusMessage = 'Trying next server...';
                notifyListeners();
                Timer(const Duration(seconds: 2), () {
                  if (_connState == ConnectionState.failed) {
                    connectFastest();
                  }
                });
              } else {
                _connState = ConnectionState.disconnected;
                _statusMessage = '';
              }
              notifyListeners();
            },
          );

        } else if (stage == VPNStage.connecting ||
                   stage == VPNStage.authenticating ||
                   stage == VPNStage.vpn_generate_config ||
                   stage == VPNStage.prepare) {
          // ✅ إصلاح ١ و ٣: كل مراحل الاتصال = loading واحد
          // نغير النص فقط بدون تغيير الحالة
          _disconnectDebounce?.cancel();
          _connState = ConnectionState.loading;
          _statusMessage = stage == VPNStage.authenticating
              ? 'Authenticating...'
              : 'Connecting...';
          notifyListeners();
        }
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

  // ─── Connect To ───────────────────────────────────────────
  Future<void> connectTo(VpnServer server) async {
    if (_selected?.ip == server.ip && isConnected) return;

    _connectionTimeout?.cancel();
    _disconnectDebounce?.cancel();

    if (isConnected || isConnecting) {
      _isSwitchingServer = true;
      _vpn?.disconnect();
      _stopStats();
      notifyListeners();
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

    _connectionTimeout = Timer(
      const Duration(seconds: _timeoutSeconds),
      () {
        if (isConnecting) {
          _vpn?.disconnect();
          _connState = ConnectionState.failed;
          _statusMessage = 'Trying next server...';
          notifyListeners();
          Timer(const Duration(seconds: 2), () {
            if (_connState == ConnectionState.failed) {
              connectFastest();
            }
          });
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
      _connState = ConnectionState.failed;
      _connectionTimeout?.cancel();
      _statusMessage = 'Connection failed';
      notifyListeners();
    }
  }

  // ─── Connect Fastest ──────────────────────────────────────
  // يجرب السيرفرات بالترتيب حتى يتصل بواحد
  Future<void> connectFastest() async {
    if (_servers.isEmpty) await fetchServers();
    final available = _servers.where((s) => s.ovpnConfig.isNotEmpty).toList();
    if (available.isEmpty) return;

    // جرب الأول — وإذا فشل خلال الـ timeout راح يظهر failed
    // المستخدم يقدر يضغط مرة ثانية يجرب التالي
    // نختار أفضل سيرفر لم يجرّب بعد
    final untried = available
        .where((s) => !_triedServers.contains(s.ip))
        .toList();

    if (untried.isEmpty) {
      // جرّب كلهم — ريست وابدأ من الأول
      _triedServers.clear();
      await connectTo(available.first);
    } else {
      _triedServers.add(untried.first.ip);
      await connectTo(untried.first);
    }
  }

  // سيرفرات جرّبناها في هذه الجلسة
  final Set<String> _triedServers = {};

  // ─── Disconnect ───────────────────────────────────────────
  Future<void> disconnect() async {
    _userDisconnected = true;
    _isSwitchingServer = false;
    _disconnectDebounce?.cancel();
    _connectionTimeout?.cancel();
    _lastStage = null;
    _triedServers.clear();

    _vpn?.disconnect();
    _connState = ConnectionState.disconnected;
    _selected = null;
    _statusMessage = '';
    _stopStats();
    _hideNotification(); // ✅ أخفِ الإشعار
    notifyListeners();
  }

  // ─── Measure Real Ping ────────────────────────────────────
  // ✅ قياس الـ ping الحقيقي من الجهاز
  Future<int> _measurePing(String ip) async {
    try {
      final start = DateTime.now();
      final socket = await Socket.connect(ip, 443,
          timeout: const Duration(seconds: 3));
      final ms = DateTime.now().difference(start).inMilliseconds;
      socket.destroy();
      return ms;
    } catch (_) {
      try {
        final start = DateTime.now();
        final socket = await Socket.connect(ip, 1194,
            timeout: const Duration(seconds: 3));
        final ms = DateTime.now().difference(start).inMilliseconds;
        socket.destroy();
        return ms;
      } catch (_) {
        return 9999;
      }
    }
  }

  Future<void> measureAllPings() async {
    if (_measuringPing || _servers.isEmpty) return;
    _measuringPing = true;
    notifyListeners();

    // قس الأول 20 سيرفر بالتوازي
    final batch = _servers.take(20).toList();
    final pings = await Future.wait(
      batch.map((s) => _measurePing(s.ip)),
    );

    for (int i = 0; i < batch.length; i++) {
      batch[i].realPing = pings[i];
    }

    // ✅ رتّب بعد القياس
    _sortServers();
    // احفظ الـ cache مع الـ ping الجديد
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
        // قس الـ ping بالخلفية
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
      // قس الـ ping بعد التحميل
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
    _disconnectDebounce?.cancel();
    super.dispose();
  }
}
