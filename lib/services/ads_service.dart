import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class AdsService {
  static const _androidGameId       = '6191272';
  static const _iosGameId           = '6191273';
  static const _interstitialAndroid = 'Interstitial_Android';
  static const _interstitialIOS     = 'Interstitial_iOS';
  static const _bannerAndroid       = 'Banner_Android';
  static const _bannerIOS           = 'Banner_iOS';

  static String get _gameId        => Platform.isIOS ? _iosGameId : _androidGameId;
  static String get interstitialId => Platform.isIOS ? _interstitialIOS : _interstitialAndroid;
  static String get bannerId       => Platform.isIOS ? _bannerIOS : _bannerAndroid;

  static bool _ready        = false;
  static bool _loading      = false;
  static bool _pendingShow  = false;

  // عداد الاتصالات الناجحة — الإعلان يطلع كل اتصالين
  static int _successCount  = 0;
  static const int _showEvery = 2;

  static Future<void> initialize() async {
    await UnityAds.init(
      gameId: _gameId,
      testMode: false,
      onComplete: _loadInterstitial,
      onFailed: (e, m) {
        debugPrint('Ads init failed: $m');
        Future.delayed(const Duration(seconds: 5), initialize);
      },
    );
  }

  static void _loadInterstitial() {
    if (_loading) return;
    _loading = true;
    UnityAds.load(
      placementId: interstitialId,
      onComplete: (_) {
        _ready   = true;
        _loading = false;
        debugPrint('✅ Interstitial loaded');
        if (_pendingShow) {
          _pendingShow = false;
          _show();
        }
      },
      onFailed: (_, __, msg) {
        _ready   = false;
        _loading = false;
        debugPrint('❌ Interstitial load failed: $msg');
        Future.delayed(const Duration(seconds: 3), _loadInterstitial);
      },
    );
  }

  static void _show() {
    if (!_ready) {
      _pendingShow = true;
      _loadInterstitial();
      return;
    }
    _ready = false;
    UnityAds.showVideoAd(
      placementId: interstitialId,
      onComplete: (_) {
        debugPrint('✅ Ad completed');
        _loadInterstitial();
      },
      onFailed: (_, __, msg) {
        debugPrint('❌ Ad show failed: $msg');
        _loadInterstitial();
      },
      onSkipped: (_) {
        debugPrint('⏭️ Ad skipped');
        _loadInterstitial();
      },
    );
  }

  /// استدعيها بعد كل اتصال ناجح — الإعلان يطلع كل اتصالين
  static void showInterstitialAfterSuccess(int successCount) {
    _successCount++;
    debugPrint('📢 Success #$_successCount — show every $_showEvery');
    if (_successCount % _showEvery == 0) {
      debugPrint('🎯 Showing ad now!');
      _show();
    }
  }
}

class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: UnityBannerAd(placementId: AdsService.bannerId),
    );
  }
}
