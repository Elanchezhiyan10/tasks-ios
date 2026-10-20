import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskWidgetService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.flutter_pgi/task_widget',
  );

  static Future<void> refresh([List<dynamic>? tasksList]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('task_widget_token');
      final baseUrl = prefs.getString('task_widget_base_url');

      final Map<String, dynamic> payload = {
        'token': token ?? '',
        'baseUrl': baseUrl ?? '',
      };

      if (tasksList != null) {
        payload['tasksJson'] = jsonEncode(tasksList);
      }

      await _channel.invokeMethod('refreshTaskWidget', payload);
    } on PlatformException catch (e) {
      debugPrint('Widget refresh failed: ${e.message}');
    } on MissingPluginException catch (e) {
      debugPrint('Widget bridge unavailable: $e');
    } catch (e) {
      debugPrint('Widget refresh error: $e');
    }
  }
}
