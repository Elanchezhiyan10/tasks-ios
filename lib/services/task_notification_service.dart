import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class TaskNotificationService {
  static Future<void> cancelReminder(int id) async {
    await _plugin.cancel(id: id);
  }

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(settings: settings);

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required DateTime reminderAt,
  }) async {
    if (!reminderAt.isAfter(DateTime.now())) {
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders',
        'Task reminders',
        channelDescription: 'Reminders for your scheduled tasks',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: 'Task reminder',
      body: title,
      scheduledDate: tz.TZDateTime.from(reminderAt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
