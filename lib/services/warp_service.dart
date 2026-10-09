// ─── Warp Service ─────────────────────────────────────────────
// نفس طريقة Hiddify / wgcf بالضبط:
// 1. نولّد private key صحيح بـ Random.secure() + Curve25519 clamping
// 2. نسجّل جهاز في Cloudflare WARP API
// 3. نأخذ peer_public_key + reserved + addresses من الـ response مباشرة

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';

class WarpKeys {
  final String privateKey;
  final String peerPublicKey;
  final List<int> reserved;
  final String v4Address;
  final String v6Address;
  final DateTime createdAt;

  const WarpKeys({
    required this.privateKey,
    required this.peerPublicKey,
    required this.reserved,
    required this.v4Address,
    required this.v6Address,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'private_key':     privateKey,
    'peer_public_key': peerPublicKey,
    'reserved':        reserved,
    'v4_address':      v4Address,
    'v6_address':      v6Address,
    'created_at':      createdAt.toIso8601String(),
  };

  factory WarpKeys.fromJson(Map<String, dynamic> j) => WarpKeys(
    privateKey:    j['private_key']     as String,
    peerPublicKey: j['peer_public_key'] as String,
    reserved:      List<int>.from(j['reserved'] as List),
    v4Address:     j['v4_address']      as String,
    v6Address:     j['v6_address']      as String,
    createdAt:     DateTime.parse(j['created_at'] as String),
  );
}

class WarpService {
  static const _prefKey   = 'warp_keys_v3';
  static const _apiBase   = 'https://api.cloudflareclient.com/v0a5641';
  static const _cfVersion = 'a-6.38.9-5641';
  static const _userAgent = '1.1.1.1/6.38.9-5641 (Android 14.0.0)';

  static WarpKeys? _cached;

  static Future<WarpKeys?> getKeys({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached;

    if (!forceRefresh) {
      final saved = await _loadFromPrefs();
      if (saved != null) {
        _cached = saved;
        return saved;
      }
    }

    final keys = await _registerDevice();
    if (keys != null) {
      _cached = keys;
      await _saveToPrefs(keys);
    }
    return keys;
  }

  static Future<WarpKeys?> _registerDevice() async {
    try {
      // ① توليد private key صحيح — نفس طريقة wgcf/Hiddify
      final keyPair = await X25519().newKeyPair();
      final privateKey = base64Encode(await keyPair.extractPrivateKeyBytes());
      final publicKey = await keyPair.extractPublicKey();

      // ② تسجيل في Cloudflare WARP API
      final res = await http.post(
        Uri.parse('$_apiBase/reg'),
        headers: {
          'Content-Type':      'application/json',
          'CF-Client-Version': _cfVersion,
          'User-Agent':        _userAgent,
        },
        body: jsonEncode({
          'key':           base64Encode(publicKey.bytes),
          'key_type':      'curve25519',
          'tunnel_type':   'wireguard',
          'os_version':   '14.0.0',
          'install_id':    '',
          'fcm_token':     '',
          'tos':           DateTime.now().toUtc().toIso8601String(),
          'model':         'Samsung',
          'serial_number': '',
          'locale':        'en_US',
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 && res.statusCode != 201) {
        debugPrint('WarpService: register failed ${res.statusCode}');
        return null;
      }

      final data   = jsonDecode(res.body) as Map<String, dynamic>;
      final config = data['config'] as Map<String, dynamic>;
      final peers  = config['peers'] as List<dynamic>;
      if (peers.isEmpty) throw const FormatException('Cloudflare returned no WARP peer');
      final peer   = peers.first as Map<String, dynamic>;
      final iface  = config['interface'] as Map<String, dynamic>;
      final addrs  = iface['addresses'] as Map<String, dynamic>;

      // ③ الـ reserved يجيب من client_id (3 bytes أول من base64)
      final clientId = data['client_id'] as String? ??
                       (data['config'] as Map<String, dynamic>)['client_id'] as String? ?? '';
      List<int> reserved = [0, 0, 0];
      if (clientId.isNotEmpty) {
        try {
          final b = base64.decode(clientId + '=' * ((4 - clientId.length % 4) % 4));
          if (b.length >= 3) reserved = [b[0], b[1], b[2]];
        } catch (_) {}
      }

      return WarpKeys(
        privateKey:    privateKey,
        peerPublicKey: peer['public_key'] as String,
        reserved:      reserved,
        v4Address:     addrs['v4'] as String,
        v6Address:     addrs['v6'] as String,
        createdAt:     DateTime.now(),
      );
    } catch (e) {
      debugPrint('WarpService: error — $e');
      return null;
    }
  }

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
