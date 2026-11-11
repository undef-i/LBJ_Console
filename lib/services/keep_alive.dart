import 'package:flutter/services.dart';

class KeepAliveNative {
  static const MethodChannel _channel = MethodChannel(
    'org.noxylva.lbjconsole/keepalive',
  );

  static Future<bool> _call(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> acquireWakeLock() => _call('acquireWakeLock');

  static Future<bool> releaseWakeLock() => _call('releaseWakeLock');

  static Future<bool> isIgnoringBatteryOptimizations() =>
      _call('isIgnoringBatteryOptimizations');

  static Future<bool> requestIgnoreBatteryOptimizations() =>
      _call('requestIgnoreBatteryOptimizations');

  static Future<bool> setWatchdogEnabled(bool enabled) =>
      _call('setWatchdogEnabled', enabled);

  static Future<bool> isWatchdogEnabled() => _call('isWatchdogEnabled');
}
