import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BiometricVault {
  static const _channel = MethodChannel('primitive_accumulation/biometric');
  static bool get mobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool> enabled() async {
    if (!mobile) return false;
    return await _channel.invokeMethod<bool>('enabled') == true;
  }

  static Future<bool> available() async =>
      mobile && await _channel.invokeMethod<bool>('available') == true;

  static Future<void> enable(String password) =>
      _channel.invokeMethod<void>('enable', password);

  static Future<void> disable() => _channel.invokeMethod<void>('disable');

  static Future<String?> unlock() => _channel.invokeMethod<String>('unlock');
}
