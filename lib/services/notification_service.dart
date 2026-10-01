import 'package:flutter/services.dart';

/// يتحكم بالـ notification الدائمة عند الاتصال
class NotificationService {
  static const _channel = MethodChannel('com.onyxvpn/notification');

  // يستقبل أمر الفصل من زر الـ notification
  static void Function()? onDisconnect;

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'disconnect') {
        onDisconnect?.call();
      }
    });
  }

  static Future<void> show(String serverName) async {
    try {
      await _channel.invokeMethod('showNotification', {
        'serverName': serverName,
      });
    } catch (_) {}
  }

  static Future<void> hide() async {
    try {
      await _channel.invokeMethod('hideNotification');
    } catch (_) {}
  }
}
