// ─── Subscription Service (نفس منهجية Hiddify) ─────────────────
// Hiddify يعتمد على subscription URLs — المستخدم يضيف رابط
// والتطبيق يجيب منه configs بصيغة V2ray/Sing-box/Clash
//
// هنا نفس الطريقة بالضبط:
// ① نجيب محتوى الـ URL (قد يكون base64 أو plain text أو JSON)
// ② نحدد الصيغة ونحللها (V2ray lines / Clash YAML / Sing-box JSON)
// ③ كاش ذكي بطابع زمني حقيقي

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// بيانات subscription واحدة
class SubscriptionInfo {
  final List<String>   links;        // vless:// vmess:// trojan:// ss://
  final String?        title;
  final DateTime       fetchedAt;
  final int?           uploadBytes;
  final int?           downloadBytes;
  final int?           totalBytes;
  final DateTime?      expireDate;

  const SubscriptionInfo({
    required this.links,
    required this.fetchedAt,
    this.title,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expireDate,
  });
}

class MahsaService {
  static const _prefKey     = 'subscription_cache_v3';
  static const _cacheHours  = 6; // نفس Hiddify — يجدد كل 6 ساعات

  // مصادر مدمجة (fallback لما المستخدم ما يضيف رابط)
  static const _builtinSources = [
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/main/mci/sub_1.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/main/mtn/sub_1.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/main/mci/sub_2.txt',
    'https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/splitted/mixed',
    'https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge_base64.txt',
    'https://raw.githubusercontent.com/freefq/free/master/v2',
  ];

  // كاش في الذاكرة
  static List<String>? _cachedLinks;
  static DateTime?     _cacheTime;

  // ─── واجهة رئيسية ─────────────────────────────────────────

  /// جلب links — من subscription URL مخصص أو المصادر المدمجة
  static Future<List<String>> getLinks({
    String? subscriptionUrl,
    int maxCount = 8,
    bool forceRefresh = false,
  }) async {
    // 1. كاش الذاكرة (فقط لو ما طلبنا refresh ونفس الـ URL)
    if (!forceRefresh && subscriptionUrl == null &&
        _cachedLinks != null && _cacheTime != null) {
      final age = DateTime.now().difference(_cacheTime!);
      if (age.inHours < _cacheHours && _cachedLinks!.isNotEmpty) {
        debugPrint('MahsaService: from memory cache (${_cachedLinks!.length})');
        return _cachedLinks!.take(maxCount).toList();
      }
    }

    // 2. كاش SharedPreferences (للمصادر المدمجة فقط)
    if (!forceRefresh && subscriptionUrl == null) {
      final saved = await _loadFromPrefs();
      if (saved != null && saved.isNotEmpty) {
        _cachedLinks = saved;
        _cacheTime   = DateTime.now();
        debugPrint('MahsaService: from prefs cache (${saved.length})');
        return saved.take(maxCount).toList();
      }
    }

    // 3. جلب من الشبكة
    final links = subscriptionUrl != null
        ? await _fetchSubscription(subscriptionUrl)
        : await _fetchBuiltinSources(maxCount: maxCount * 3);

    if (links.isNotEmpty) {
      if (subscriptionUrl == null) {
        // نخزن فقط المصادر المدمجة
        _cachedLinks = links;
        _cacheTime   = DateTime.now();
        await _saveToPrefs(links);
      }
      debugPrint('MahsaService: fetched ${links.length} links');
      return links.take(maxCount).toList();
    }

    return [];
  }

  // ─── جلب Subscription URL مخصص (نفس منهجية Hiddify) ─────────

  /// يجيب SubscriptionInfo كاملة مع بيانات الاستخدام من الهيدرات
  static Future<SubscriptionInfo?> fetchSubscriptionFull(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':     'Hiddify/2.0 (compatible; sing-box)',
          'Accept':         '*/*',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return null;

      // قراءة بيانات الاستخدام من headers (نفس Hiddify)
      final subInfo     = res.headers['subscription-userinfo'] ?? '';
      final profileTitle= res.headers['profile-title'];
      int? upload, download, total;
      DateTime? expire;

      if (subInfo.isNotEmpty) {
        final parts = Map.fromEntries(
          subInfo.split(';').map((p) => p.trim().split('=')).where((p) => p.length == 2)
              .map((p) => MapEntry(p[0].trim(), p[1].trim())),
        );
        upload   = int.tryParse(parts['upload']   ?? '');
        download = int.tryParse(parts['download'] ?? '');
        total    = int.tryParse(parts['total']    ?? parts['totl'] ?? '');
        final exp = int.tryParse(parts['expire'] ?? '');
        if (exp != null) expire = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      }

      // قراءة profile-title من header أو base64
      String? title = profileTitle;
      if (title != null && title.startsWith('base64:')) {
        try {
          final b64 = title.substring(7);
          title = utf8.decode(base64.decode(b64 + '=' * ((4 - b64.length % 4) % 4)));
        } catch (_) {}
      }

      final links = _parseBody(res.body.trim());

      return SubscriptionInfo(
        links:         links,
        title:         title,
        fetchedAt:     DateTime.now(),
        uploadBytes:   upload,
        downloadBytes: download,
        totalBytes:    total,
        expireDate:    expire,
      );
    } catch (e) {
      debugPrint('MahsaService: fetchSubscriptionFull error — $e');
      return null;
    }
  }

  // ─── داخلي ───────────────────────────────────────────────────

  static Future<List<String>> _fetchSubscription(String url) async {
    final info = await fetchSubscriptionFull(url);
    return info?.links ?? [];
  }

  static Future<List<String>> _fetchBuiltinSources({int maxCount = 30}) async {
    final all = <String>[];
    final futures = _builtinSources.map(_fetchSingleSource);
    final results = await Future.wait(futures, eagerError: false)
        .catchError((_) => <List<String>>[]);

    for (final r in results) {
      all.addAll(r);
      if (all.length >= maxCount) break;
    }
    return all.take(maxCount).toList();
  }

  static Future<List<String>> _fetchSingleSource(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Hiddify/2.0'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];
      return _parseBody(res.body.trim());
    } catch (e) {
      debugPrint('MahsaService: $url — $e');
      return [];
    }
  }

  /// محلّل موحّد — يتعامل مع:
  ///   • Plain text lines (vless:// vmess:// ...)
  ///   • Base64 encoded subscription
  ///   • Sing-box JSON  → يستخرج outbound configs
  static List<String> _parseBody(String body) {
    if (body.isEmpty) return [];

    // محاولة Sing-box JSON
    if (body.startsWith('{')) {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final obs  = json['outbounds'] as List<dynamic>? ?? [];
        final links = <String>[];
        for (final ob in obs) {
          final m = ob as Map<String, dynamic>;
          final type = m['type'] as String? ?? '';
          if (['vless','vmess','trojan','shadowsocks'].contains(type)) {
            // نحوّل للصيغة النصية القياسية
            final link = _outboundToLink(m);
            if (link != null) links.add(link);
          }
        }
        if (links.isNotEmpty) return links;
      } catch (_) {}
    }

    // base64 subscription
    final decoded = _tryBase64Decode(body);
    final text    = decoded ?? body;

    // plain text lines
    final links = <String>[];
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.startsWith('vless://')  ||
          line.startsWith('vmess://')  ||
          line.startsWith('trojan://') ||
          line.startsWith('ss://')) {
        links.add(line);
        if (links.length >= 50) break;
      }
    }
    return links;
  }

  static String? _tryBase64Decode(String input) {
    if (input.contains('://')) return null; // ليس base64
    try {
      final padded  = input + '=' * ((4 - input.length % 4) % 4);
      final decoded = utf8.decode(base64.decode(padded));
      if (decoded.contains('://')) return decoded;
    } catch (_) {}
    return null;
  }

  /// تحويل sing-box outbound → رابط قياسي (تقريبي)
  static String? _outboundToLink(Map<String, dynamic> ob) {
    try {
      final type = ob['type'] as String;
      final tag  = ob['tag']  as String? ?? 'node';
      final host = ob['server'] as String? ?? '';
      final port = ob['server_port'] as int? ?? 443;
      if (host.isEmpty) return null;

      if (type == 'shadowsocks') {
        final method = ob['method'] as String? ?? 'none';
        final pass   = ob['password'] as String? ?? '';
        final up     = base64Url.encode(utf8.encode('$method:$pass')).replaceAll('=', '');
        return 'ss://$up@$host:$port#${Uri.encodeComponent(tag)}';
      }
      if (type == 'trojan') {
        final pass = ob['password'] as String? ?? '';
        return 'trojan://$pass@$host:$port#${Uri.encodeComponent(tag)}';
      }
      if (type == 'vless') {
        final uuid = ob['uuid'] as String? ?? '';
        return 'vless://$uuid@$host:$port#${Uri.encodeComponent(tag)}';
      }
    } catch (_) {}
    return null;
  }

  // ─── SharedPreferences (كاش 6 ساعات بطابع زمني حقيقي) ──────

  static Future<List<String>?> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_prefKey);
      if (raw == null) return null;

      final data    = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(data['saved_at'] as String);
      // فحص العمر الحقيقي للكاش
      if (DateTime.now().difference(savedAt).inHours >= _cacheHours) return null;

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

  static Future<void> clearCache() async {
    _cachedLinks = null;
    _cacheTime   = null;
    final prefs  = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
