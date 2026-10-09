import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeoService {
  static String _countryCode = '';
  static String _countryName = '';

  static String get userCountryCode => _countryCode;
  static String get userCountryName => _countryName;

  // الدول المحجوبة — Psiphon أولاً لهذي
  static const _restrictedCountries = {
    'IR', // إيران
    'CN', // الصين
    'RU', // روسيا
    'BY', // بيلاروسيا
    'KP', // كوريا الشمالية
    'TM', // تركمانستان
    'CU', // كوبا
    'SY', // سوريا
  };

  // العراق محجوب جزئياً — Warp يكفي
  static const _partialCountries = {'IQ', 'SA', 'AE', 'EG', 'TR'};

  static bool get isRestrictedCountry =>
      _restrictedCountries.contains(_countryCode);

  static bool get isPartialCountry =>
      _partialCountries.contains(_countryCode);

  /// الـ Mode الأفضل حسب الدولة
  static String get recommendedMode {
    if (isRestrictedCountry) return 'psiphon';
    if (isPartialCountry)    return 'warp';
    return 'warp';
  }

  /// تحميل الدولة — من الكاش أول، وإلا من الإنترنت
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final cached    = prefs.getString('geo_country_code');
    final cachedAt  = prefs.getInt('geo_cached_at') ?? 0;
    final now       = DateTime.now().millisecondsSinceEpoch;
    const oneDay    = 86400000;

    // لو الكاش أقل من يوم → نستخدمه
    if (cached != null && (now - cachedAt) < oneDay) {
      _countryCode = cached;
      _countryName = prefs.getString('geo_country_name') ?? '';
      debugPrint('GeoService: loaded from cache → $_countryCode');
      return;
    }

    // وإلا نجيبه من الإنترنت
    await _fetchFromNetwork(prefs);
  }

  static Future<void> _fetchFromNetwork(SharedPreferences prefs) async {
    const apis = [
      'https://ipapi.co/json/',
      'https://ip-api.com/json/?fields=countryCode,country',
      'https://ipwho.is/?fields=country_code,country',
    ];

    for (final url in apis) {
      try {
        final res = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          final code = (json['country_code'] ?? json['countryCode'] ?? '').toString().toUpperCase();
          final name = (json['country'] ?? json['country_name'] ?? '').toString();

          if (code.isNotEmpty) {
            _countryCode = code;
            _countryName = name;
            await prefs.setString('geo_country_code', code);
            await prefs.setString('geo_country_name', name);
            await prefs.setInt('geo_cached_at', DateTime.now().millisecondsSinceEpoch);
            debugPrint('GeoService: fetched → $code ($name)');
            return;
          }
        }
      } catch (e) {
        debugPrint('GeoService: $url failed → $e');
        continue;
      }
    }

    debugPrint('GeoService: all APIs failed, defaulting to unknown');
    _countryCode = '';
    _countryName = '';
  }
}
