import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class AdsService {
  static const _androidGameId = '6191272';
  static const _iosGameId = '6191273';
  static const _interstitialAndroid = 'Interstitial_Android';
  static const _interstitialIOS = 'Interstitial_iOS';
  static const _bannerAndroid = 'Banner_Android';
  static const _bannerIOS = 'Banner_iOS';

  static String get _gameId => Platform.isIOS ? _iosGameId : _androidGameId;
  static String get interstitialId =>
      Platform.isIOS ? _interstitialIOS : _interstitialAndroid;
  static String get bannerId => Platform.isIOS ? _bannerIOS : _bannerAndroid;

  static bool _ready = false;
  static bool _loading = false;
  static Timer? _hourlyTimer;
  static bool _hourlyCycleRunning = false;
  static Future<void> Function()? _onDisconnect;
  static Future<void> Function()? _onReconnect;

  static Future<void> initialize() async {
    await UnityAds.init(
      gameId: _gameId,
      testMode: false,
      onComplete: _loadInterstitial,
      onFailed: (error, message) {
        debugPrint('Ads init failed: $message');
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
        _ready = true;
        _loading = false;
        debugPrint('Interstitial loaded');
      },
      onFailed: (_, __, message) {
        _ready = false;
        _loading = false;
        debugPrint('Interstitial load failed: $message');
        Future.delayed(const Duration(seconds: 3), _loadInterstitial);
      },
    );
  }

  static void _show({required VoidCallback afterAd}) {
    if (!_ready) {
      _loadInterstitial();
      return;
    }
    _ready = false;
    var completed = false;
    Timer? recoveryTimer;

    void finish() {
      if (completed) return;
      completed = true;
      recoveryTimer?.cancel();
      _loadInterstitial();
      afterAd();
    }

    recoveryTimer = Timer(const Duration(seconds: 90), finish);
    UnityAds.showVideoAd(
      placementId: interstitialId,
      onComplete: (_) => finish(),
      onFailed: (_, __, message) {
        debugPrint('Interstitial show failed: $message');
        finish();
      },
      onSkipped: (_) => finish(),
    );
  }

  static void startHourlyAdTimer({
    required Future<void> Function() onDisconnect,
    required Future<void> Function() onReconnect,
  }) {
    stopHourlyAdTimer();
    _onDisconnect = onDisconnect;
    _onReconnect = onReconnect;
    _hourlyTimer = Timer(const Duration(hours: 1), () {
      unawaited(_triggerHourlyAd());
    });
    debugPrint('AdsService: hourly timer started after VPN connected');
  }

  static void stopHourlyAdTimer() {
    _hourlyTimer?.cancel();
    _hourlyTimer = null;
  }

  static Future<void> _triggerHourlyAd() async {
    final disconnect = _onDisconnect;
    final reconnect = _onReconnect;
    if (_hourlyCycleRunning || disconnect == null || reconnect == null) return;

    // Never disconnect when Unity has no ad ready to show.
    if (!_ready) {
      startHourlyAdTimer(onDisconnect: disconnect, onReconnect: reconnect);
      return;
    }

    _hourlyCycleRunning = true;
    stopHourlyAdTimer();
    try {
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
      _show(afterAd: () {
        unawaited(() async {
          try {
            await Future.delayed(const Duration(milliseconds: 400));
            await reconnect();
          } catch (error) {
            debugPrint('AdsService: reconnect after ad failed: $error');
          } finally {
            _hourlyCycleRunning = false;
          }
        }());
      });
    } catch (error) {
      debugPrint('AdsService: hourly ad cycle failed: $error');
      try {
        await reconnect();
      } finally {
        _hourlyCycleRunning = false;
      }
    }
  }
}

class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 50,
        child: UnityBannerAd(placementId: AdsService.bannerId),
      );
}
