import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/vpn_mode.dart';
import 'v2ray_configs.dart';
import 'warp_service.dart';
import 'mahsa_service.dart';
import 'geo_service.dart';
import 'ads_service.dart';
import 'patterniha_service.dart';

export 'v2ray_configs.dart';

enum VpnState { disconnected, connecting, connected, failed }

// ─── منطقية هايدفاي الكاملة ────────────────────────────────────────
// ① Auto-reconnect: لو الاتصال انقطع نُعيد تلقائياً (max 3 محاولات)
// ② Fallback chain: Mahsa → Patterniha → WARP → WarpPsiphon
// ③ Connection timeout: 30 ثانية ثم نجرب الـ fallback
// ④ Network change detection: لو تغيّر الـ network نُعيد الاتصال
// ────────────────────────────────────────────────────────────────────

class SingboxProvider extends ChangeNotifier {

  // ─── Channels ────────────────────────────────────────────────────
  static const _method = MethodChannel('com.onyxvpn/vpn');
  static const _events = EventChannel('com.onyxvpn/status');

  // ─── State ───────────────────────────────────────────────────────
  VpnState     _state        = VpnState.disconnected;
  VpnMode      _mode         = VpnMode.mahsa;
  String       _status       = '';
  String       _downSpeed    = '0 B/s';
  String       _upSpeed      = '0 B/s';
  String?      _customUrl;
  Duration     _duration     = Duration.zero;
  List<String> _excludedApps = [];
  bool         _blockAds     = true;
  bool         _autoSpeedTest = false;

  // ─── Connected Country ───────────────────────────────────────────
  String _connectedCountry = '';
  String _connectedFlag    = '';
  String _connectedIp      = '';

  String get connectedCountry => _connectedCountry;
  String get connectedFlag    => _connectedFlag;
  String get connectedIp      => _connectedIp;

  // ─── Custom Subscription ─────────────────────────────────────────
  List<VpnServer> _servers        = [];
  VpnServer?      _selectedServer;
  bool            _loadingServers = false;

  bool _userChangedMode    = false;
  bool _pendingAdReconnect = false;

  // ─── Hiddify-style: Reconnect & Fallback ─────────────────────────
  int      _reconnectAttempts  = 0;
  static const _maxReconnect   = 3;           // هايدفاي: 3 محاولات
  static const _reconnectDelay = Duration(seconds: 2);
  bool     _isAutoReconnecting = false;

  // Fallback chain — نفس ترتيب هايدفاي
  static const _fallbackChain = [
    VpnMode.mahsa,
    VpnMode.patterniha,
    VpnMode.warp,
    VpnMode.warpPsiphon,
  ];
  int _fallbackIndex = 0;

  // Connection timeout — FIX: 30 ثانية (15 كانت تسبب false timeout بالعراق)
  Timer? _connectTimeoutTimer;
  static const _connectTimeout = Duration(seconds: 30);

  // ─── Getters ─────────────────────────────────────────────────────
  VpnState        get state          => _state;
  VpnMode         get mode           => _mode;
  String          get status         => _status;
  String          get downSpeed      => _downSpeed;
  String          get upSpeed        => _upSpeed;
  String?         get customUrl      => _customUrl;
  Duration        get duration       => _duration;
  List<String>    get excludedApps   => _excludedApps;
  bool            get blockAds       => _blockAds;
  bool            get autoSpeedTest  => _autoSpeedTest;
  List<VpnServer> get servers        => _servers;
  VpnServer?      get selectedServer => _selectedServer;
  bool            get loadingServers => _loadingServers;

  bool get isConnected  => _state == VpnState.connected;
  bool get isConnecting => _state == VpnState.connecting;
  bool get isFailed     => _state == VpnState.failed;

  Timer?              _durationTimer;
  Timer?              _statsTimer;
  DateTime?           _connectedAt;
  StreamSubscription? _statusSub;
  int _connectionRevision = 0;

  // ─── Network Change Detection (هايدفاي) ──────────────────────────
  StreamSubscription? _connectivitySub;
  List<ConnectivityResult> _lastConnectivity = [];

  // ─── SharedPreferences keys ──────────────────────────────────────
  static const _prefCustomUrl      = 'custom_url';
  static const _prefExcludedApps   = 'excluded_apps';
  static const _prefBlockAds       = 'block_ads';
  static const _prefAutoSpeedTest  = 'auto_speed_test';
  static const _prefLastConfig     = 'last_config_v2';
  static const _prefLastConfigAt   = 'last_config_saved_at';
  static const _prefLastConfigMode = 'last_config_mode';
  static const _configMaxAgeHours  = 6;

  SingboxProvider() { _init(); }

  Future<void> _init() async {
    final prefs    = await SharedPreferences.getInstance();
    _customUrl     = prefs.getString(_prefCustomUrl);
    _blockAds      = prefs.getBool(_prefBlockAds) ?? true;
    _autoSpeedTest = prefs.getBool(_prefAutoSpeedTest) ?? false;
    final saved    = prefs.getStringList(_prefExcludedApps);
    if (saved != null) _excludedApps = saved;

    try {
      await _method.invokeMethod('setup', {'grpcPort': 9090});
    } catch (e) {
      debugPrint('setup error: $e');
    }

    _statusSub = _events.receiveBroadcastStream().listen(_onNativeStatus);

    // ─── Network Change Detection ─────────────────────────────────
    _startNetworkMonitoring();

    await GeoService.load();
    _mode = _bestMode();

    // ─── تحميل صامت في الخلفية ───────────────────────────────────
    WarpService.getKeys();
    MahsaService.backgroundRefresh();
    PatternihaService.backgroundRefresh();
    loadOnyxServers();

    notifyListeners();
  }

  // ─── Network Monitoring — نفس ConnectivityController في هايدفاي ────
  void _startNetworkMonitoring() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final hasConnection = results.any((r) => r != ConnectivityResult.none);
        final hadConnection = _lastConnectivity.any((r) => r != ConnectivityResult.none);

        debugPrint('SingboxProvider: network changed → $results');

        // لو كان في اتصال شبكة وتغيّر النوع (WiFi ↔ Data)
        if (hasConnection && _lastConnectivity.isNotEmpty) {
          final changed = !results.toSet().containsAll(_lastConnectivity) ||
                          !_lastConnectivity.toSet().containsAll(results);
          if (changed && isConnected) {
            debugPrint('SingboxProvider: network type changed → reconnecting');
            Future.delayed(const Duration(milliseconds: 800), () {
              if (isConnected) {
                disconnect().then((_) {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    connect();
                  });
                });
              }
            });
          }
        }

        // لو رجع الإنترنت بعد ما كان مقطوع
        if (hasConnection && !hadConnection) {
          debugPrint('SingboxProvider: internet restored → reconnecting');
          Future.delayed(const Duration(seconds: 1), () {
            if (_state == VpnState.failed || _state == VpnState.disconnected) {
              _reconnectAttempts = 0;
              _fallbackIndex     = 0;
              connect();
            }
          });
        }

        _lastConnectivity = results;
      },
    );
  }

  VpnMode _bestMode() {
    if (GeoService.isRestrictedCountry) return VpnMode.warpPsiphon;
    return VpnMode.mahsa;
  }

  // ─── Native Status Handler ────────────────────────────────────────
  void _onNativeStatus(dynamic event) {
    final s = event.toString();
    debugPrint('native status: $s');

    if (s == 'connected') {
      // ─── اتصل بنجاح → صفّر عداد الـ reconnect ───────────────────
      _reconnectAttempts  = 0;
      _fallbackIndex      = 0;
      _isAutoReconnecting = false;
      _connectTimeoutTimer?.cancel();

      _state       = VpnState.connected;
      _status      = '';
      _connectedAt ??= DateTime.now();
      _startTimer();
      _startStatsTimer();
      _fetchConnectedCountry();

      AdsService.startHourlyAdTimer(
        onDisconnect: disconnect,
        onReconnect: () async { _pendingAdReconnect = true; },
      );

    } else if (s == 'disconnected') {
      if (_state == VpnState.connecting) {
        debugPrint('_onNativeStatus: ignoring stale "disconnected" — already connecting');
        return;
      }

      _state            = VpnState.disconnected;
      _status           = '';
      _stopTimers();
      _connectedAt      = null;
      _downSpeed        = '0 B/s';
      _upSpeed          = '0 B/s';
      _connectedCountry = '';
      _connectedFlag    = '';
      _connectedIp      = '';

      AdsService.stopHourlyAdTimer();

      // ─── Ad reconnect ─────────────────────────────────────────────
      if (_pendingAdReconnect) {
        _pendingAdReconnect = false;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (_state == VpnState.disconnected) connect();
        });
      }

    } else if (s.startsWith('failed')) {
      _connectTimeoutTimer?.cancel();
      final msg = s.contains(':') ? s.split(':').skip(1).join(':') : 'Connection failed';
      debugPrint('native failed: $msg');

      // ─── هايدفاي Fallback Logic ───────────────────────────────────
      if (!_userChangedMode && _fallbackIndex < _fallbackChain.length) {
        _tryFallback(msg.trim());
      } else if (_reconnectAttempts < _maxReconnect && !_userChangedMode) {
        _scheduleReconnect(msg.trim());
      } else {
        _setFailed(_friendlyConnectionError(msg.trim()));
        AdsService.stopHourlyAdTimer();
      }
      return; // لا تُعلّم حتى نقرر

    } else if (s == 'permission_requested') {
      _status = 'Waiting for permission...';
    } else if (s.startsWith('stats:')) {
      _parseStats(s.substring(6));
    }

    notifyListeners();
  }

  // ─── ① Fallback Chain (هايدفاي) ──────────────────────────────────
  // عند الفشل: نجرب المصدر الثاني تلقائياً بدون ما يشوف المستخدم أي شيء
  void _tryFallback(String reason) {
    // تخطى الـ mode الحالي في الـ chain
    while (_fallbackIndex < _fallbackChain.length &&
           _fallbackChain[_fallbackIndex] == _mode) {
      _fallbackIndex++;
    }

    if (_fallbackIndex >= _fallbackChain.length) {
      // استنفدنا كل الخيارات → أظهر الخطأ
      _setFailed(_friendlyConnectionError(reason));
      AdsService.stopHourlyAdTimer();
      notifyListeners();
      return;
    }

    final nextMode = _fallbackChain[_fallbackIndex];
    _fallbackIndex++;

    debugPrint('SingboxProvider: fallback → $nextMode (was $_mode)');
    _status = 'Trying another server...';
    _mode   = nextMode;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (_state != VpnState.failed && _state != VpnState.disconnected) return;
      _clearConfigCache().then((_) => _connect(++_connectionRevision));
    });
  }

  // ─── ② Auto-Reconnect (هايدفاي) ──────────────────────────────────
  // نفس ConnectivityController في هايدفاي: يُعيد الاتصال تلقائياً
  void _scheduleReconnect(String reason) {
    _reconnectAttempts++;
    _isAutoReconnecting = true;
    _status = 'Reconnecting... ($_reconnectAttempts/$_maxReconnect)';
    notifyListeners();

    debugPrint('SingboxProvider: auto-reconnect #$_reconnectAttempts in ${_reconnectDelay.inSeconds}s');

    Future.delayed(_reconnectDelay * _reconnectAttempts, () {
      if (!_isAutoReconnecting) return;
      if (_state == VpnState.connected) return;
      _connect(++_connectionRevision);
    });
  }

  // ─── Connected Country Lookup ─────────────────────────────────────
  Future<void> _fetchConnectedCountry() async {
    const apis = [
      'https://ipapi.co/json/',
      'https://ip-api.com/json/?fields=countryCode,country,query',
      'https://ipwho.is/?fields=country_code,country,ip',
    ];
    for (final url in apis) {
      try {
        final res = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final j    = jsonDecode(res.body) as Map<String, dynamic>;
          final code = (j['country_code'] ?? j['countryCode'] ?? '').toString().toUpperCase();
          final name = (j['country'] ?? j['country_name'] ?? '').toString();
          final ip   = (j['ip'] ?? j['query'] ?? '').toString();
          if (code.isNotEmpty) {
            _connectedCountry = name.isNotEmpty ? name : code;
            _connectedFlag    = _codeToFlag(code);
            _connectedIp      = ip;
            notifyListeners();
            return;
          }
        }
      } catch (_) { continue; }
    }
  }

  static String _codeToFlag(String code) {
    if (code.length != 2) return '🌐';
    final base  = 0x1F1E6 - 0x41;
    final chars = code.toUpperCase().codeUnits;
    return String.fromCharCode(base + chars[0]) + String.fromCharCode(base + chars[1]);
  }

  // ─── Stats ────────────────────────────────────────────────────────
  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!isConnected) { _statsTimer?.cancel(); return; }
      try {
        final result = await _method.invokeMethod('getStats');
        if (result is Map) {
          _downSpeed = _formatSpeed(result['down'] as int? ?? 0);
          _upSpeed   = _formatSpeed(result['up']   as int? ?? 0);
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void _parseStats(String raw) {
    try {
      final parts = raw.split(':');
      if (parts.length >= 2) {
        _downSpeed = _formatSpeed(int.tryParse(parts[0]) ?? 0);
        _upSpeed   = _formatSpeed(int.tryParse(parts[1]) ?? 0);
      }
    } catch (_) {}
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024)         return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024)  return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  // ─── Connect ──────────────────────────────────────────────────────
  Future<void> connectWithMode(
    VpnMode mode, {
    VpnServer? onyxServer,
    VpnServer? customServer,
  }) async {
    final request = ++_connectionRevision;
    if (_state != VpnState.disconnected) await _stopConnection();
    if (request != _connectionRevision) return;

    // ─── إعادة تعيين الـ fallback عند اختيار يدوي ────────────────
    _mode               = mode;
    _userChangedMode    = true;
    _fallbackIndex      = 0;
    _reconnectAttempts  = 0;
    _isAutoReconnecting = false;

    if (mode == VpnMode.pythonServers) _selectedOnyxServer = onyxServer;
    if (mode == VpnMode.custom)        _selectedServer     = customServer;

    await _clearConfigCache();
    if (request != _connectionRevision) return;
    notifyListeners();
    await _connect(request);
  }

  Future<void> connect() async {
    if (_state == VpnState.connecting || _state == VpnState.connected) {
      _pendingAdReconnect = false;
      _isAutoReconnecting = false;
      await disconnect();
      return;
    }
    // ─── إعادة تعيين الـ fallback عند ضغطة يدوية ─────────────────
    _fallbackIndex     = 0;
    _reconnectAttempts = 0;
    _userChangedMode   = false;  // FIX: يسمح للـ fallback chain يشتغل من جديد
    if (_state == VpnState.failed) await _clearConfigCache();
    await _connect(++_connectionRevision);
  }

  Future<void> _connect(int request) async {
    if (!_userChangedMode) {
      final auto = _bestMode();
      if (_mode != auto && _fallbackIndex == 0) {
        _mode = auto;
        debugPrint('SingboxProvider: auto-selected mode → $auto');
      }
    }

    _state  = VpnState.connecting;
    _status = 'Preparing...';
    notifyListeners();

    // ─── ③ Connection Timeout — هايدفاي 15 ثانية ─────────────────
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(_connectTimeout, () {
      if (_state == VpnState.connecting) {
        debugPrint('SingboxProvider: connection timeout → trying fallback');
        _tryFallback('Connection timeout');
      }
    });

    try {
      final cc = GeoService.userCountryCode.toLowerCase().isNotEmpty
          ? GeoService.userCountryCode.toLowerCase()
          : 'iq';

      String? config = await _loadCachedConfig();

      if (config != null) {
        debugPrint('SingboxProvider: using cached config');
        _status = 'Connecting...';
        notifyListeners();
      } else {
        debugPrint('SingboxProvider: building fresh config');
        _status = 'Fetching servers...';
        notifyListeners();
        config = await _buildConfig(cc);

        if (request != _connectionRevision) { _connectTimeoutTimer?.cancel(); return; }

        if (config == null || config.isEmpty) {
          _connectTimeoutTimer?.cancel();
          if (!_userChangedMode && _fallbackIndex < _fallbackChain.length) {
            _tryFallback('No servers available');
          } else {
            _setFailed('No servers available');
          }
          return;
        }
        await _saveCachedConfig(config);
      }

      if (request != _connectionRevision) { _connectTimeoutTimer?.cancel(); return; }

      _status = 'Connecting...';
      notifyListeners();

      await _method.invokeMethod('start', {
        'config':        config,
        'warpOverProxy': _mode == VpnMode.warpPsiphon,
      });
      debugPrint('start result: ok');

      _scheduleBackgroundRefresh(cc);

    } on PlatformException catch (e) {
      _connectTimeoutTimer?.cancel();
      if (request != _connectionRevision) return;
      debugPrint('PlatformException: ${e.code} — ${e.message}');
      if (e.code == 'INVALID_CONFIG') await _clearConfigCache();

      if (!_userChangedMode && _fallbackIndex < _fallbackChain.length) {
        _tryFallback(e.message ?? 'Connection failed');
      } else {
        _setFailed(_friendlyConnectionError(e.message ?? 'Connection failed'));
      }
    } catch (e) {
      _connectTimeoutTimer?.cancel();
      if (request != _connectionRevision) return;
      debugPrint('connect error: $e');
      if (!_userChangedMode && _fallbackIndex < _fallbackChain.length) {
        _tryFallback('$e');
      } else {
        _setFailed('Error: $e');
      }
    }
  }

  Future<void> disconnect() async {
    _connectTimeoutTimer?.cancel();
    _isAutoReconnecting = false;
    ++_connectionRevision;
    await _stopConnection();
  }

  Future<void> _stopConnection() async {
    _stopTimers();
    _connectedAt = null;
    _duration    = Duration.zero;
    _downSpeed   = '0 B/s';
    _upSpeed     = '0 B/s';

    try {
      await _method.invokeMethod('stop');
    } catch (e) {
      debugPrint('disconnect error: $e');
    }

    await Future.delayed(const Duration(milliseconds: 300));

    if (_state != VpnState.disconnected) {
      _state  = VpnState.disconnected;
      _status = '';
      notifyListeners();
    }
  }

  // ─── Config Cache ────────────────────────────────────────────────
  Future<String?> _loadCachedConfig() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final config    = prefs.getString(_prefLastConfig);
      final savedAt   = prefs.getString(_prefLastConfigAt);
      final savedMode = prefs.getString(_prefLastConfigMode);
      if (config == null || savedAt == null || savedMode != _mode.name) return null;

      final age = DateTime.now().difference(DateTime.parse(savedAt));
      if (age.inHours >= _configMaxAgeHours) return null;
      return config;
    } catch (_) { return null; }
  }

  Future<void> _saveCachedConfig(String config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastConfig,     config);
      await prefs.setString(_prefLastConfigAt,   DateTime.now().toIso8601String());
      await prefs.setString(_prefLastConfigMode, _mode.name);
    } catch (_) {}
  }

  Future<void> _clearConfigCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefLastConfig);
    await prefs.remove(_prefLastConfigAt);
    await prefs.remove(_prefLastConfigMode);
  }

  // ─── Background Refresh ──────────────────────────────────────────
  // FIX: نأخر الـ refresh لـ 30 ثانية بعد الاتصال بدل 3 ثواني
  // الـ 3 ثواني كانت تسبب network requests أثناء تأسيس الاتصال → انقطاع
  void _scheduleBackgroundRefresh(String cc) {
    Future.delayed(const Duration(seconds: 30), () async {
      if (!isConnected) return;
      try {
        final newConfig = await _buildConfig(cc);
        if (newConfig != null && newConfig.isNotEmpty && isConnected) {
          await _saveCachedConfig(newConfig);
          debugPrint('SingboxProvider: background config refreshed');
        }
      } catch (e) {
        debugPrint('SingboxProvider: background refresh failed — $e');
      }
    });
  }

  // ─── Build Config ────────────────────────────────────────────────
  Future<String?> _buildConfig(String cc) async {
    switch (_mode) {
      case VpnMode.warp:
        _status = 'Fetching Warp keys...';
        notifyListeners();
        return await V2RayConfigs.warp(
          countryCode:  cc,
          excludedApps: _excludedApps,
          blockAds:     _blockAds,
        );

      case VpnMode.psiphon:
        _status = 'Building Psiphon config...';
        notifyListeners();
        return await V2RayConfigs.psiphon(
          countryCode:  cc,
          excludedApps: _excludedApps,
          blockAds:     _blockAds,
        );

      case VpnMode.warpPsiphon:
        _status = 'Fetching Warp keys...';
        notifyListeners();
        return await V2RayConfigs.warpViaPsiphon(
          countryCode:  cc,
          excludedApps: _excludedApps,
          blockAds:     _blockAds,
        );

      case VpnMode.mahsa:
        _status = 'Finding the fastest Mahsa server...';
        notifyListeners();
        return await V2RayConfigs.mahsa(
          countryCode:  cc,
          excludedApps: _excludedApps,
          blockAds:     _blockAds,
        );

      // ─── Patterniha — مصدر جديد في الـ fallback chain ────────────
      case VpnMode.patterniha:
        _status = 'Finding the fastest Patterniha server...';
        notifyListeners();
        final servers = await PatternihaService.getServers();
        if (servers.isEmpty) return null;
        return await V2RayConfigs.buildFromServerList(
          servers:      servers,
          countryCode:  cc,
          excludedApps: _excludedApps,
          blockAds:     _blockAds,
        );

      case VpnMode.pythonServers:
        if (_onyxServers.isEmpty) {
          _status = 'Loading Python servers...';
          notifyListeners();
          await loadOnyxServers(forceRefresh: true);
        }
        if (_onyxServers.isEmpty) return null;
        final selected  = _selectedOnyxServer;
        final allRanked = _rankedOnyxServers();
        final servers   = selected == null
            ? allRanked
            : allRanked.where((s) => s.country == selected.country).toList();
        _status = selected == null
            ? 'Selecting the fastest Python server...'
            : 'Connecting to ${selected.country.isNotEmpty ? selected.country : selected.name}...';
        notifyListeners();
        return await V2RayConfigs.buildFromServerList(
          servers:      servers,
          countryCode:  cc,
          excludedApps: _excludedApps,
          blockAds:     _blockAds,
        );

      case VpnMode.custom:
        if (_customUrl == null || _customUrl!.isEmpty) return null;
        if (_selectedServer != null) {
          _status = 'Connecting to ${_selectedServer!.name}...';
          notifyListeners();
          return await V2RayConfigs.buildForServer(
            url:          _customUrl!,
            server:       _selectedServer!,
            countryCode:  cc,
            excludedApps: _excludedApps,
            blockAds:     _blockAds,
          );
        }
        _status = 'Fetching servers...';
        notifyListeners();
        return await V2RayConfigs.custom(
          url:          _customUrl!,
          countryCode:  cc,
          excludedApps: _excludedApps,
          blockAds:     _blockAds,
        );
    }
  }

  // ─── OnyxServers ────────────────────────────────────────────────
  List<VpnServer> _onyxServers       = [];
  VpnServer?      _selectedOnyxServer;
  bool            _loadingOnyx       = false;
  List<VpnServer> get onyxServers    => _onyxServers;
  VpnServer?  get selectedOnyxServer => _selectedOnyxServer;
  bool            get loadingOnyx    => _loadingOnyx;

  List<VpnServer> _rankedOnyxServers() =>
      List<VpnServer>.unmodifiable(_onyxServers);

  Future<void> loadOnyxServers({bool forceRefresh = false}) async {
    _loadingOnyx = true;
    notifyListeners();
    try {
      _onyxServers = await PatternihaService.getServers(forceRefresh: forceRefresh);
      if (_selectedOnyxServer != null &&
          !_onyxServers.any((s) => s.link == _selectedOnyxServer!.link)) {
        _selectedOnyxServer = null;
      }
    } catch (e) {
      debugPrint('SingboxProvider: OnyxServers error — $e');
    }
    _loadingOnyx = false;
    notifyListeners();
  }

  void selectOnyxServer(VpnServer? server) {
    _selectedOnyxServer = server;
    _clearConfigCache();
    notifyListeners();
  }

  void selectMode(VpnMode m) {
    if (_state != VpnState.disconnected) return;
    _mode             = m;
    _userChangedMode  = true;
    _fallbackIndex    = 0;
    _reconnectAttempts = 0;
    _clearConfigCache();
    notifyListeners();
  }

  Future<void> setCustomUrl(String url) async {
    _customUrl      = url.trim();
    _selectedServer = null;
    _servers        = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomUrl, _customUrl!);
    await _clearConfigCache();
    notifyListeners();
    await fetchServers();
    await connectWithMode(VpnMode.custom);
  }

  Future<void> fetchServers() async {
    if (_customUrl == null || _customUrl!.isEmpty) return;
    _loadingServers = true;
    notifyListeners();
    try {
      final list  = await V2RayConfigs.parseSubscription(_customUrl!);
      _servers    = list;
      if (_selectedServer != null &&
          !list.any((s) => s.name == _selectedServer!.name)) {
        _selectedServer = null;
      }
    } catch (_) {
      _servers = [];
    }
    _loadingServers = false;
    notifyListeners();
  }

  void selectServer(VpnServer server) {
    _selectedServer = server;
    _clearConfigCache();
    notifyListeners();
  }

  void clearSelectedServer() {
    _selectedServer = null;
    _clearConfigCache();
    notifyListeners();
  }

  Future<void> addExcludedApp(String pkg) async {
    if (!_excludedApps.contains(pkg)) {
      _excludedApps = [..._excludedApps, pkg];
      await _saveExcluded();
      notifyListeners();
    }
  }

  Future<void> removeExcludedApp(String pkg) async {
    _excludedApps = _excludedApps.where((a) => a != pkg).toList();
    await _saveExcluded();
    notifyListeners();
  }

  Future<void> _saveExcluded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefExcludedApps, _excludedApps);
  }

  Future<void> setBlockAds(bool v) async {
    _blockAds = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBlockAds, v);
    await _clearConfigCache();
    notifyListeners();
  }

  Future<void> setAutoSpeedTest(bool v) async {
    _autoSpeedTest = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoSpeedTest, v);
    notifyListeners();
  }

  Future<void> refreshWarpKeys() async {
    await WarpService.clearKeys();
    await WarpService.getKeys(forceRefresh: true);
    await _clearConfigCache();
  }

  Future<void> refreshMahsa() async {
    await MahsaService.clearCache();
    await MahsaService.backgroundRefresh();
    await _clearConfigCache();
  }

  // ─── Timers ──────────────────────────────────────────────────────
  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        _duration = DateTime.now().difference(_connectedAt!);
        notifyListeners();
      }
    });
  }

  void _stopTimers() {
    _durationTimer?.cancel();
    _statsTimer?.cancel();
    _durationTimer = null;
    _statsTimer    = null;
    _duration      = Duration.zero;
  }

  void _setFailed(String msg) {
    _state  = VpnState.failed;
    _status = msg;
    _stopTimers();
    notifyListeners();
  }

  String _friendlyConnectionError(String message) {
    if (message.toLowerCase().contains('unknown outbound type: psiphon')) {
      return 'The bundled core rejected Psiphon (unknown outbound type).';
    }
    if (message.toLowerCase().contains('timeout')) {
      return 'Connection timed out. Please try again.';
    }
    if (message.toLowerCase().contains('no servers')) {
      return 'No servers available. Check your internet connection.';
    }
    return message;
  }

  String get formattedTime {
    final h = _duration.inHours.toString().padLeft(2, '0');
    final m = _duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _connectivitySub?.cancel();
    _connectTimeoutTimer?.cancel();
    _stopTimers();
    super.dispose();
  }
}
