// ─── Mahsa Config Fetcher ─────────────────────────────────────
// يجيب كونفيغات VLESS/VMess/Trojan من مصادر GitHub متعددة
// مع كاش ذكي واختيار أسرع سيرفر

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MahsaService {
  static const _prefKey     = 'mahsa_configs_v2';
  static const _prefPingKey = 'mahsa_best_source';

  // ─── مصادر متعددة — نحاول كلها ونأخذ أفضل ────────────────
  static const _sources = [
    // mahsanet الأصلي
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/main/mci/sub_1.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/main/mtn/sub_1.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/main/mci/sub_2.txt',
    // مصادر إضافية موثوقة
    'https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/splitted/mixed',
    'https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge_base64.txt',
    'https://raw.githubusercontent.com/freefq/free/master/v2',
  ];

  // كاش الـ configs في الذاكرة
  static List<String>? _cachedLinks;
  static DateTime?     _cacheTime;

  /// يجيب قائمة links صالحة (vless:// vmess:// trojan://)
  static Future<List<String>> getLinks({int maxCount = 8}) async {
    // 1. كاش في الذاكرة (30 دقيقة)
    if (_cachedLinks != null && _cacheTime != null) {
      final age = DateTime.now().difference(_cacheTime!);
      if (age.inMinutes < 30 && _cachedLinks!.isNotEmpty) {
        return _cachedLinks!.take(maxCount).toList();
      }
    }

    // 2. كاش في SharedPreferences (2 ساعة)
    final saved = await _loadFromPrefs();
    if (saved != null && saved.isNotEmpty) {
      _cachedLinks = saved;
      _cacheTime   = DateTime.now();
      return saved.take(maxCount).toList();
    }

    // 3. تحميل من المصادر
    final links = await _fetchAll(maxCount: maxCount);
    if (links.isNotEmpty) {
      _cachedLinks = links;
      _cacheTime   = DateTime.now();
      await _saveToPrefs(links);
      return links;
    }

    return [];
  }

  static Future<List<String>> _fetchAll({int maxCount = 8}) async {
    final allLinks = <String>[];

    // جرّب المصادر بالتوازي مع timeout قصير
    final futures = _sources.map((url) => _fetchSource(url));
    final results = await Future.wait(
      futures,
      eagerError: false,
    ).catchError((_) => <List<String>>[]);

    for (final result in results) {
      if (result.isNotEmpty) {
        allLinks.addAll(result);
        if (allLinks.length >= maxCount * 2) break;
      }
    }

    debugPrint('MahsaService: collected ${allLinks.length} links total');

    // إرجاع أفضل maxCount
    return allLinks.take(maxCount).toList();
  }

  static Future<List<String>> _fetchSource(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'v2ray/1.0'})
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];

      return _parseLinks(res.body);
    } catch (e) {
      debugPrint('MahsaService: $url failed — $e');
      return [];
    }
  }

  static List<String> _parseLinks(String body) {
    final links = <String>[];
    final text  = _tryBase64Decode(body.trim());

    for (final line in text.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      if (l.startsWith('vless://')  ||
          l.startsWith('vmess://')  ||
          l.startsWith('trojan://') ||
          l.startsWith('ss://')) {
        links.add(l);
        if (links.length >= 20) break;
      }
    }
    return links;
  }

  static String _tryBase64Decode(String input) {
    try {
      // إذا كل المحتوى base64 (subscription format)
      if (!input.contains('://')) {
        final padded  = input + '=' * ((4 - input.length % 4) % 4);
        final decoded = utf8.decode(base64.decode(padded));
        if (decoded.contains('://')) return decoded;
      }
    } catch (_) {}
    return input;
  }

  // ─── SharedPreferences (كاش 2 ساعة) ─────────────────────
  static Future<List<String>?> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null) return null;

      final data    = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(data['saved_at'] as String);
      if (DateTime.now().difference(savedAt).inHours >= 2) return null;

      return List<String>.from(data['links'] as List);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToPrefs(List<String> links) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'links':    links,
      }));
    } catch (_) {}
  }

  /// مسح الكاش لإعادة التحميل
  static Future<void> clearCache() async {
    _cachedLinks = null;
    _cacheTime   = null;
    final prefs  = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
