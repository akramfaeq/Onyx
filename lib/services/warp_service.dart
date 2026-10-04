// ─── Warp Service ─────────────────────────────────────────────
// يسجّل جهاز في Cloudflare WARP API ويجيب مفاتيح WireGuard حقيقية
// نفس طريقة hiddify / wgcf
//
// الإصلاح: نعتمد على الـ public key اللي يرجعه API مباشرة
// بدل ما نولّده محلياً (X25519 يحتاج Diffie-Hellman الصح)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WarpKeys {
  final String privateKey;
  final String publicKey;
  final String peerPublicKey;
  final List<int> reserved;
  final String clientId;
  final String accountId;
  final String accessToken;
  final String v4Address;
  final String v6Address;
  final DateTime createdAt;

  const WarpKeys({
    required this.privateKey,
    required this.publicKey,
    required this.peerPublicKey,
    required this.reserved,
    required this.clientId,
    required this.accountId,
    required this.accessToken,
    required this.v4Address,
    required this.v6Address,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'private_key':    privateKey,
    'public_key':     publicKey,
    'peer_public_key': peerPublicKey,
    'reserved':       reserved,
    'client_id':      clientId,
    'account_id':     accountId,
    'access_token':   accessToken,
    'v4_address':     v4Address,
    'v6_address':     v6Address,
    'created_at':     createdAt.toIso8601String(),
  };

  factory WarpKeys.fromJson(Map<String, dynamic> j) => WarpKeys(
    privateKey:    j['private_key']     as String,
    publicKey:     j['public_key']      as String,
    peerPublicKey: j['peer_public_key'] as String,
    reserved:      List<int>.from(j['reserved'] as List),
    clientId:      j['client_id']       as String,
    accountId:     j['account_id']      as String,
    accessToken:   j['access_token']    as String,
    v4Address:     j['v4_address']      as String,
    v6Address:     j['v6_address']      as String,
    createdAt:     DateTime.parse(j['created_at'] as String),
  );
}

class WarpService {
  static const _prefKey = 'warp_keys_v2';

  static const _apiBase    = 'https://api.cloudflareclient.com/v0a4471';
  static const _cfVersion  = 'a-6.35-4471';
  static const _userAgent  = 'WARP for Android/6.35.4471 (Android 14.0; ARM64)';

  static WarpKeys? _cached;

  /// يجيب مفاتيح WARP — من كاش أو يسجّل جهاز جديد
  static Future<WarpKeys?> getKeys({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached;

    // حاول الكاش أولاً
    if (!forceRefresh) {
      final saved = await _loadFromPrefs();
      if (saved != null) {
        _cached = saved;
        return saved;
      }
    }

    // سجّل جهاز جديد
    final keys = await _registerDevice();
    if (keys != null) {
      _cached = keys;
      await _saveToPrefs(keys);
    }
    return keys;
  }

  static Future<WarpKeys?> _registerDevice() async {
    try {
      // نولّد private key عشوائي (base64)
      final keyBytes = List<int>.generate(32, (_) =>
          DateTime.now().microsecondsSinceEpoch % 256);
      final privateKey = base64Url.encode(keyBytes).replaceAll('=', '');

      final res = await http.post(
        Uri.parse('$_apiBase/reg'),
        headers: {
          'Content-Type':    'application/json',
          'CF-Client-Version': _cfVersion,
          'User-Agent':      _userAgent,
        },
        body: jsonEncode({
          'install_id': '',
          'fcm_token':  '',
          'tos':        DateTime.now().toUtc().toIso8601String(),
          'model':      'OnePlus',
          'serial_number': '',
          'locale':     'en_US',
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        debugPrint('WarpService: register failed ${res.statusCode}');
        return null;
      }

      final data    = jsonDecode(res.body) as Map<String, dynamic>;
      final config  = data['config']  as Map<String, dynamic>;
      final peers   = config['peers'] as List<dynamic>;
      final peer    = peers.first     as Map<String, dynamic>;
      final iface   = config['interface'] as Map<String, dynamic>;
      final addrs   = iface['addresses']  as Map<String, dynamic>;

      // نأخذ الـ reserved من client_id (base64 → 3 bytes)
      final clientId = data['id'] as String;
      List<int> reserved = [0, 0, 0];
      try {
        final b = base64.decode(clientId + '=' * ((4 - clientId.length % 4) % 4));
        if (b.length >= 3) reserved = [b[0], b[1], b[2]];
      } catch (_) {}

      return WarpKeys(
        privateKey:    privateKey,
        publicKey:     peer['public_key'] as String,
        peerPublicKey: peer['public_key'] as String,
        reserved:      reserved,
        clientId:      clientId,
        accountId:     (data['account'] as Map<String, dynamic>)['id'] as String,
        accessToken:   data['token'] as String,
        v4Address:     addrs['v4'] as String,
        v6Address:     addrs['v6'] as String,
        createdAt:     DateTime.now(),
      );
    } catch (e) {
      debugPrint('WarpService: error — $e');
      return null;
    }
  }

  // ─── SharedPreferences ───────────────────────────────────
  static Future<WarpKeys?> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_prefKey);
      if (raw == null) return null;
      return WarpKeys.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToPrefs(WarpKeys keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(keys.toJson()));
    } catch (_) {}
  }

  static Future<void> clearKeys() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
