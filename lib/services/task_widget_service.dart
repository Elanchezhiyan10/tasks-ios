import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TaskWidgetService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.flutter_pgi/task_widget',
  );

  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod('refreshTaskWidget');
    } on PlatformException catch (e) {
      debugPrint('Widget refresh failed: ${e.message}');
    } on MissingPluginException catch (e) {
      debugPrint('Widget bridge unavailable: $e');
    }
  }
}
