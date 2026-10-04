import 'package:flutter/services.dart';

class NotificationService {
  static const _channel = MethodChannel('com.onyxvpn.notification');

  static Future<void> showConnected({
    required String modeName,
    required String modeEmoji,
  }) async {
    try {
      await _channel.invokeMethod('show', {
        'title': 'OnyxVPN Connected',
        'body': '$modeEmoji $modeName — Tap to disconnect',
      });
    } catch (_) {}
  }

  static Future<void> hide() async {
    try {
      await _channel.invokeMethod('hide');
    } catch (_) {}
  }
}
