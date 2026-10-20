import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'add_task_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart' show notificationsPlugin;
import '../services/task_widget_service.dart';

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

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${widget.token}',
  };

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  Future<void> loadTasks() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 7));

      final uri = Uri.parse('$taskApiBaseUrl/tasks').replace(
        queryParameters: {
          'from': start.toIso8601String(),
          'to': end.toIso8601String(),
        },
      );

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (!mounted) return;

        setState(() {
          tasks = data['tasks'] as List<dynamic>? ?? [];
        });

        await TaskWidgetService.refresh();
      } else {
        debugPrint('Tasks API status: ${response.statusCode}');
        debugPrint('Tasks API response: ${response.body}');

        setState(() {
          error =
              'Tasks failed (${response.statusCode}): '
              '${data['message'] ?? response.body}';
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Task loading error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          error = 'Could not load tasks: $e';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not update task.')));
      }
    } catch (e) {
      debugPrint('Task update error: $e');
    }
  }

  Future<void> editTask(Map<String, dynamic> task) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(token: widget.token, task: task),
      ),
    );

    if (!mounted) return;

    if (updated == true) {
      await loadTasks();
    }
  }

  Future<void> deleteTask(Map<String, dynamic> task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Are you sure you want to delete "${task['title']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to connect to the server')),
      );
    }
  }

  String formatTime(dynamic value) {
    if (value == null) return 'Time not set';

    final text = value.toString();

    // MySQL DATETIME: YYYY-MM-DD HH:mm:ss
    final match = RegExp(
      r'^\d{4}-\d{2}-\d{2}[ T](\d{2}):(\d{2})',
    ).firstMatch(text);

    if (match == null) return text;

    final hour24 = int.parse(match.group(1)!);
    final minute = match.group(2)!;

    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final period = hour24 >= 12 ? 'PM' : 'AM';

    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final todayTasks = tasks.where((task) {
      final date = DateTime.tryParse(task['scheduled_at'].toString());
      return date != null &&
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    }).toList();

    final tomorrowTasks = tasks.where((task) {
      final date = DateTime.tryParse(task['scheduled_at'].toString());
      return date != null &&
          date.year == tomorrow.year &&
          date.month == tomorrow.month &&
          date.day == tomorrow.day;
    }).toList();

    final completedCount = tasks
        .where((task) => task['occurrence_status'] == 'completed')
        .length;

    final progress = tasks.isEmpty ? 0.0 : completedCount / tasks.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Tasks',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: loadTasks,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh tasks',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadTasks,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await notificationsPlugin.show(
                        id: 100,
                        title: 'Task reminder test',
                        body: 'Bro, your notifications are working!',
                        notificationDetails: const NotificationDetails(
                          android: AndroidNotificationDetails(
                            'task_reminders',
                            'Task reminders',
                            channelDescription:
                                'Notifications for scheduled tasks',
                            importance: Importance.max,
                            priority: Priority.high,
                          ),
                        ),
                      );
                    },
                    child: const Text('Test notification'),
                  ),

                  Text(
                    'Hello, ${widget.fullName.split(' ').first}!',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Plan your next seven days.'),
                  const SizedBox(height: 22),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Task progress',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 14),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 8),
                          Text(
                            '$completedCount of ${tasks.length} tasks completed',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (error.isNotEmpty)
                    Text(error, style: const TextStyle(color: Colors.red)),
                  _section('Today', todayTasks),
                  const SizedBox(height: 20),
                  _section('Tomorrow', tomorrowTasks),
                  const SizedBox(height: 20),
                  _section('Next 7 days', tasks),
                ],
              ),
            ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => AddTaskScreen(token: widget.token),
            ),
          );

          if (created == true) {
            await loadTasks();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add task'),
      ),
    );
  }

  Widget _section(String title, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No tasks scheduled.'),
          )
        else
          ...items.map((item) {
            final task = Map<String, dynamic>.from(item);
            final completed = task['occurrence_status'] == 'completed';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: CheckboxListTile(
                value: completed,
                onChanged: (_) => updateTask(task),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  task['title']?.toString() ?? 'Untitled task',
                  style: TextStyle(
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  '${formatTime(task['scheduled_at'])} • '
                  '${task['priority'] ?? 'medium'} priority',
                ),

                secondary: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit task',
                      onPressed: () => editTask(task),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Delete task',
                      onPressed: () => deleteTask(task),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
