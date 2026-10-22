import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'add_task_screen.dart';
import '../services/task_widget_service.dart';
import '../main.dart' show LoginScreen, notificationsPlugin;

const String taskApiBaseUrl = 'https://tasks-reminder.onrender.com';

class TaskDashboard extends StatefulWidget {
  final String token;
  final String fullName;

  const TaskDashboard({super.key, required this.token, required this.fullName});

  @override
  State<TaskDashboard> createState() => _TaskDashboardState();
}

class _TaskDashboardState extends State<TaskDashboard> {
  List<dynamic> tasks = [];
  bool loading = true;
  String error = '';

  static const Color bg = Color(0xFF0F172A);
  static const Color panel = Color(0xFF1E293B);
  static const Color panelBorder = Color(0xFF334155);
  static const Color primary = Color(0xFF60A5FA);
  static const Color mainText = Color(0xFFF8FAFC);
  static const Color mutedText = Color(0xFF94A3B8);

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${widget.token}',
  };

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('task_widget_token');
    await prefs.remove('task_widget_full_name');
    await prefs.remove('task_widget_base_url');
    await prefs.remove('task_widget_tasks');
    await TaskWidgetService.refresh([]);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> loadTasks() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = '';
      });
    }

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      final end = today.add(const Duration(days: 7));

      final uri = Uri.parse('$taskApiBaseUrl/tasks').replace(
        queryParameters: {
          'from': weekStart.toIso8601String(),
          'to': end.toIso8601String(),
          'includeOverdue': 'true',
        },
      );

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      final dynamic decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (!mounted) return;

        final list = decoded is Map<String, dynamic>
            ? (decoded['tasks'] as List<dynamic>? ?? <dynamic>[])
            : <dynamic>[];

        setState(() => tasks = list);
        await TaskWidgetService.refresh(tasks);
      } else {
        if (!mounted) return;

        setState(() {
          error =
              'Tasks failed (${response.statusCode}): '
              '${decoded is Map ? decoded['message'] ?? response.body : response.body}';
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Task loading error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          error = 'Could not load tasks. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  DateTime? _scheduledDate(dynamic task) {
    final value = task['scheduled_at'];
    if (value == null) return null;

    return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));
  }

  DateTime? _reminderDate(dynamic task) {
    final value = task['remind_at'] ?? task['reminder_at'];
    if (value == null) return null;

    return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));
  }

  bool _completed(dynamic task) {
    final status = task['occurrence_status']?.toString().toLowerCase();
    return status == 'completed';
  }

  bool _pending(dynamic task) => !_completed(task);

  bool _sameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> updateTask(Map<String, dynamic> task) async {
    final id = task['occurrence_id'];
    final completed = task['occurrence_status'] == 'completed';
    final action = completed ? 'reopen' : 'complete';

    try {
      final response = await http.patch(
        Uri.parse('$taskApiBaseUrl/tasks/occurrences/$id/$action'),
        headers: headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await loadTasks();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not update task.')));
      }
    } catch (e) {
      debugPrint('Task update error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to connect to the server.')),
        );
      }
    }
  }

  Future<void> editTask(Map<String, dynamic> task) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(token: widget.token, task: task),
      ),
    );

    if (mounted && updated == true) await loadTasks();
  }

  Future<void> deleteTask(Map<String, dynamic> task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: panelBorder),
        ),
        title: const Text(
          'Delete task?',
          style: TextStyle(color: mainText, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${task['title']}"?',
          style: const TextStyle(color: mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: mutedText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFF87171)),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$taskApiBaseUrl/tasks/${task['task_id']}'),
        headers: headers,
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted successfully')),
        );
        await loadTasks();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not delete task')));
      }
    } catch (e) {
      debugPrint('Delete task error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to connect to the server')),
        );
      }
    }
  }

  Future<void> addTask() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddTaskScreen(token: widget.token)),
    );

    if (mounted && created == true) await loadTasks();
  }

  String formatTime(dynamic value) {
    if (value == null) return 'Time not set';

    final date = value is DateTime
        ? value
        : DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));

    if (date == null) return value.toString();

    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:${date.minute.toString().padLeft(2, '0')} $period';
  }

  String formatDate(DateTime date) => '${date.day}/${date.month}';

  void _showProfileSheet(BuildContext context) {
    final initials = widget.fullName.trim().isNotEmpty
        ? widget.fullName
              .trim()
              .split(RegExp(r'\s+'))
              .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
              .take(2)
              .join()
        : 'TR';

    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: panelBorder),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: panelBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: panelBorder),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: primary,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.fullName,
                            style: const TextStyle(
                              color: mainText,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Tasks Reminder · Employee Workspace',
                              style: TextStyle(
                                color: primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: panelBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF34D399,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.cloud_done_rounded,
                          color: Color(0xFF34D399),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connected to Render Cloud',
                              style: TextStyle(
                                color: mainText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Backend synchronization active',
                              style: TextStyle(color: mutedText, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications_active_outlined,
                      color: primary,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Test Notification',
                    style: TextStyle(
                      color: mainText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Verify local reminders on this iPhone',
                    style: TextStyle(color: mutedText, fontSize: 11),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await notificationsPlugin.show(
                      id: 100,
                      title: 'Tasks Reminder',
                      body: 'Notifications are working perfectly!',
                      notificationDetails: const NotificationDetails(
                        android: AndroidNotificationDetails(
                          'task_reminders',
                          'Task reminders',
                          channelDescription:
                              'Notifications for scheduled tasks',
                          importance: Importance.max,
                          priority: Priority.high,
                        ),
                        iOS: DarwinNotificationDetails(
                          presentAlert: true,
                          presentBadge: true,
                          presentSound: true,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          loadTasks();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Refresh'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: const BorderSide(color: panelBorder),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _logout();
                        },
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Logout'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEndExclusive = weekStart.add(const Duration(days: 7));

    final todayTasks = tasks
        .where((t) => _sameDay(_scheduledDate(t), today))
        .toList();

    final overdueTasks =
        tasks.where((t) {
          final date = _scheduledDate(t);
          return date != null && date.isBefore(today) && _pending(t);
        }).toList()..sort(
          (a, b) => (_scheduledDate(a) ?? today).compareTo(
            _scheduledDate(b) ?? today,
          ),
        );

    final upcomingTasks =
        tasks.where((t) {
          final date = _reminderDate(t);
          return _pending(t) && date != null && date.isAfter(now);
        }).toList()..sort(
          (a, b) =>
              (_reminderDate(a) ?? now).compareTo(_reminderDate(b) ?? now),
        );

    final weekTasks = tasks.where((t) {
      final date = _scheduledDate(t);

      return date != null &&
          !date.isBefore(weekStart) &&
          date.isBefore(weekEndExclusive);
    }).toList();

    final todayCompleted = todayTasks.where(_completed).length;
    final weekCompleted = weekTasks.where(_completed).length;

    final todayProgress = todayTasks.isEmpty
        ? 0.0
        : todayCompleted / todayTasks.length;

    final weekProgress = weekTasks.isEmpty
        ? 0.0
        : weekCompleted / weekTasks.length;

    final priorityTasks = tasks.where((t) {
      final date = _scheduledDate(t);
      return date != null && !date.isBefore(today) && _pending(t);
    }).toList();

    int priorityCount(String priority) => priorityTasks
        .where(
          (t) =>
              (t['priority']?.toString().toLowerCase() ?? 'medium') == priority,
        )
        .length;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 64,
        actions: [
          IconButton(
            onPressed: loading ? null : loadTasks,
            icon: const Icon(Icons.refresh_rounded, color: mutedText),
            tooltip: 'Refresh tasks',
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => _showProfileSheet(context),
            style: IconButton.styleFrom(
              backgroundColor: panel,
              foregroundColor: primary,
              minimumSize: const Size(42, 42),
            ),
            icon: const Icon(Icons.person_rounded, size: 20),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            style: IconButton.styleFrom(
              backgroundColor: panel,
              foregroundColor: primary,
              minimumSize: const Size(42, 42),
            ),
            icon: const Icon(Icons.logout_rounded, size: 20),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: primary))
          : RefreshIndicator(
              onRefresh: loadTasks,
              color: primary,
              backgroundColor: panel,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                children: [
                  _buildWelcomeHeader(now),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF451F2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF7F1D1D)),
                      ),
                      child: Text(
                        error,
                        style: const TextStyle(color: Color(0xFFFCA5A5)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _darkSummary(
                          'Today\'s tasks',
                          '${todayTasks.length}',
                          Icons.calendar_month_rounded,
                          primary,
                          'Stay on track',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _darkSummary(
                          'Upcoming',
                          upcomingTasks.length.toString().padLeft(2, '0'),
                          Icons.notifications_active_outlined,
                          const Color(0xFFFBBF24),
                          'Reminders ahead',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _darkProgressCard(
                    'Daily progress',
                    "You're making progress.",
                    todayCompleted,
                    todayTasks.length,
                    todayProgress,
                    primary,
                  ),
                  const SizedBox(height: 12),
                  _darkProgressCard(
                    'Weekly progress',
                    'Your Monday–Sunday overview.',
                    weekCompleted,
                    weekTasks.length,
                    weekProgress,
                    const Color(0xFFA78BFA),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Priority overview',
                        style: TextStyle(
                          color: mainText,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Pending tasks',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _darkPriority(
                          'High',
                          priorityCount('high'),
                          const Color(0xFFF87171),
                          const Color(0xFF3F2029),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _darkPriority(
                          'Medium',
                          priorityCount('medium'),
                          const Color(0xFFFBBF24),
                          const Color(0xFF3D3020),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _darkPriority(
                          'Low',
                          priorityCount('low'),
                          const Color(0xFF4ADE80),
                          const Color(0xFF163326),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _darkSectionTitle('Overdue tasks', overdueTasks.length),
                  const SizedBox(height: 10),
                  if (overdueTasks.isEmpty)
                    _darkEmpty(
                      'You are all caught up!',
                      'No overdue tasks right now.',
                      Icons.check_circle_outline_rounded,
                    )
                  else
                    ...overdueTasks.map(
                      (task) => _darkTaskCard(task, overdue: true),
                    ),
                  const SizedBox(height: 22),
                  _darkSectionTitle("Today's tasks", todayTasks.length),
                  const SizedBox(height: 10),
                  if (todayTasks.isEmpty)
                    _darkEmpty(
                      'A fresh start',
                      'Add a task to plan your day.',
                      Icons.event_available_rounded,
                    )
                  else
                    ...todayTasks.map((task) => _darkTaskCard(task)),
                  const SizedBox(height: 22),
                  _darkSectionTitle('Coming up next', upcomingTasks.length),
                  const SizedBox(height: 10),
                  if (upcomingTasks.isEmpty)
                    _darkEmpty(
                      'Nothing coming up yet',
                      'Future reminders will appear here.',
                      Icons.notifications_none_rounded,
                    )
                  else
                    _darkUpcomingList(upcomingTasks),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addTask,
        backgroundColor: primary,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 5,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Quick Add Task',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(DateTime now) {
    final firstName = widget.fullName.trim().isEmpty
        ? 'there'
        : widget.fullName.trim().split(RegExp(r'\s+')).first;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_weekday(now.weekday).toUpperCase()} · '
                '${_month(now.month).toUpperCase()} ${now.day}',
                style: const TextStyle(
                  color: Color(0xFF93A4BF),
                  fontSize: 11,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Let's get it done, $firstName.",
                style: const TextStyle(
                  color: mainText,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your day, organized in one place.',
                style: TextStyle(color: mutedText, fontSize: 13),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => _showProfileSheet(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: panelBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/task_reminder_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.person_rounded, color: primary, size: 24),
            ),
          ),
        ),
      ],
    );
  }

  String _weekday(int day) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][day - 1];

  String _month(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];

  Widget _darkSummary(
    String label,
    String value,
    IconData icon,
    Color accent,
    String hint,
  ) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: mainText,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: mutedText, fontSize: 12)),
          const SizedBox(height: 7),
          Text(
            hint,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkProgressCard(
    String title,
    String subtitle,
    int completed,
    int total,
    double progress,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: mainText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(color: mutedText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 3),
                ),
                child: Center(
                  child: Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                      color: mainText,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: panelBorder,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '$completed of $total tasks completed',
            style: const TextStyle(color: mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _darkPriority(
    String label,
    int count,
    Color accent,
    Color background,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_outlined, color: accent, size: 16),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: const TextStyle(
              color: mainText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkSectionTitle(String title, int count) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: mainText,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: panelBorder),
          ),
          child: Text(
            '$count',
            style: const TextStyle(color: mutedText, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _darkEmpty(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: panelBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: primary,
            size: 27,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: mainText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkTaskCard(dynamic rawTask, {bool overdue = false}) {
    final task = Map<String, dynamic>.from(rawTask as Map);
    final completed = _completed(task);
    final priority = (task['priority']?.toString() ?? 'medium').toLowerCase();

    final accent = priority == 'high'
        ? const Color(0xFFF87171)
        : priority == 'low'
        ? const Color(0xFF4ADE80)
        : const Color(0xFFFBBF24);

    final priorityLabel = priority.isEmpty
        ? 'Medium'
        : '${priority[0].toUpperCase()}${priority.substring(1)}';

    final subtitle =
        '${formatTime(task['scheduled_at'])} · $priorityLabel priority';

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: overdue ? const Color(0xFF7F1D1D) : panelBorder,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: completed,
            activeColor: primary,
            onChanged: (_) => updateTask(task),
            side: const BorderSide(color: Color(0xFF94A3B8)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task['title']?.toString() ?? 'Untitled task',
                    style: TextStyle(
                      color: completed ? const Color(0xFF94A3B8) : mainText,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    overdue ? 'Overdue · $subtitle' : subtitle,
                    style: TextStyle(
                      color: overdue ? const Color(0xFFFCA5A5) : mutedText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.flag_rounded, color: accent, size: 19),
            color: panel,
            onSelected: (value) {
              if (value == 'edit') editTask(task);
              if (value == 'delete') deleteTask(task);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit', style: TextStyle(color: mainText)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFF87171)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _darkUpcomingList(List<dynamic> upcomingTasks) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < upcomingTasks.length; i++) ...[
            _darkUpcomingRow(upcomingTasks[i]),
            if (i < upcomingTasks.length - 1)
              const Divider(height: 1, color: panelBorder),
          ],
        ],
      ),
    );
  }

  Widget _darkUpcomingRow(dynamic rawTask) {
    final task = Map<String, dynamic>.from(rawTask as Map);
    final priority = (task['priority']?.toString() ?? 'medium').toLowerCase();

    final date = _reminderDate(task);

    final color = priority == 'high'
        ? const Color(0xFFFBBF24)
        : priority == 'low'
        ? const Color(0xFF4ADE80)
        : const Color(0xFF93C5FD);

    final icon = priority == 'high'
        ? Icons.bolt_rounded
        : priority == 'low'
        ? Icons.checklist_rounded
        : Icons.description_outlined;

    final priorityLabel = priority.isEmpty
        ? 'Medium'
        : '${priority[0].toUpperCase()}${priority.substring(1)}';

    final subtitle = date == null
        ? 'Reminder set'
        : '${formatDate(date)} · ${formatTime(date)} · $priorityLabel priority';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['title']?.toString() ?? 'Untitled task',
                  style: const TextStyle(
                    color: mainText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(color: mutedText, fontSize: 11),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.chevron_right_rounded, color: mutedText),
            color: panel,
            onSelected: (action) {
              if (action == 'edit') editTask(task);
              if (action == 'delete') deleteTask(task);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit', style: TextStyle(color: mainText)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFF87171)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
