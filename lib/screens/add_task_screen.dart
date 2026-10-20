import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/task_notification_service.dart';

const String taskServerUrl = 'https://tasks-reminder.onrender.com';

class AddTaskScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? task;

  const AddTaskScreen({super.key, required this.token, this.task});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  String recurrenceFrequency = 'none';
  int recurrenceInterval = 1;
  List<int> selectedWeekdays = [];
  DateTime? recurrenceEndDate;

  final List<Map<String, dynamic>> weekdays = [
    {'label': 'Mon', 'value': 1},
    {'label': 'Tue', 'value': 2},
    {'label': 'Wed', 'value': 3},
    {'label': 'Thu', 'value': 4},
    {'label': 'Fri', 'value': 5},
    {'label': 'Sat', 'value': 6},
    {'label': 'Sun', 'value': 7},
  ];

  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();

  DateTime? parseTaskDate(dynamic value) {
    if (value == null) return null;

    final text = value.toString().replaceFirst(' ', 'T');
    return DateTime.tryParse(text);
  }

  DateTime scheduledDate = DateTime.now().add(const Duration(hours: 1));

  TimeOfDay scheduledTime = TimeOfDay.now();
  TimeOfDay? reminderTime;

  String priority = 'medium';
  bool saving = false;

  @override
  void initState() {
    super.initState();

    final task = widget.task;
    if (task == null) return;

    titleController.text = task['title']?.toString() ?? '';
    descriptionController.text = task['description']?.toString() ?? '';

    final existingPriority = task['priority']?.toString();
    if (['low', 'medium', 'high'].contains(existingPriority)) {
      priority = existingPriority!;
    }

    final scheduledText = task['scheduled_at']?.toString();
    if (scheduledText != null) {
      final scheduled = DateTime.tryParse(scheduledText.replaceFirst(' ', 'T'));

      if (scheduled != null) {
        scheduledDate = DateTime(
          scheduled.year,
          scheduled.month,
          scheduled.day,
        );
        scheduledTime = TimeOfDay.fromDateTime(scheduled);
      }
    }

    final reminderText = (task['remind_at'] ?? task['reminder_at'])?.toString();

    if (reminderText != null) {
      final reminder = DateTime.tryParse(reminderText.replaceFirst(' ', 'T'));

      if (reminder != null) {
        reminderTime = TimeOfDay.fromDateTime(reminder);
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  DateTime get scheduledAt => DateTime(
    scheduledDate.year,
    scheduledDate.month,
    scheduledDate.day,
    scheduledTime.hour,
    scheduledTime.minute,
  );

  DateTime? get reminderAt {
    if (reminderTime == null) return null;

    return DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
      reminderTime!.hour,
      reminderTime!.minute,
    );
  }

  String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Future<void> chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: scheduledDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (selected != null && mounted) {
      setState(() => scheduledDate = selected);
    }
  }

  Future<void> chooseTaskTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: scheduledTime,
    );

    if (selected != null && mounted) {
      setState(() => scheduledTime = selected);
    }
  }

  Future<void> chooseReminderTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: reminderTime ?? scheduledTime,
    );

    if (selected != null && mounted) {
      setState(() => reminderTime = selected);
    }
  }

  Future<void> saveTask() async {
    if (!formKey.currentState!.validate()) return;

    if (!scheduledAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future date and time.')),
      );
      return;
    }

    if (reminderAt != null && !reminderAt!.isBefore(scheduledAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder must be before the task time.')),
      );
      return;
    }

    setState(() => saving = true);

    try {
      final task = widget.task;
      final editing = task != null;

      final body = <String, dynamic>{
        'title': titleController.text.trim(),
        'description': descriptionController.text.trim().isEmpty
            ? null
            : descriptionController.text.trim(),
        'priority': priority,
        'scheduled_at':
            '${scheduledAt.year}-'
            '${scheduledAt.month.toString().padLeft(2, '0')}-'
            '${scheduledAt.day.toString().padLeft(2, '0')} '
            '${scheduledAt.hour.toString().padLeft(2, '0')}:'
            '${scheduledAt.minute.toString().padLeft(2, '0')}:00',
        'timezone': 'Asia/Kolkata',
      };

      // Recurrence is supported when creating a new task.
      if (!editing && recurrenceFrequency != 'none') {
        if (recurrenceFrequency == 'weekly' && selectedWeekdays.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one weekday.')),
          );
          return;
        }

        body['recurrence'] = {
          'frequency': recurrenceFrequency,
          'interval_value': recurrenceInterval,
          'days_of_week': recurrenceFrequency == 'weekly'
              ? selectedWeekdays
              : null,
          'end_date': recurrenceEndDate == null
              ? null
              : '${recurrenceEndDate!.year}-'
                    '${recurrenceEndDate!.month.toString().padLeft(2, '0')}-'
                    '${recurrenceEndDate!.day.toString().padLeft(2, '0')}',
        };
      }

      if (reminderAt != null) {
        final reminder = reminderAt!;
        body['reminder_at'] =
            '${reminder.year}-'
            '${reminder.month.toString().padLeft(2, '0')}-'
            '${reminder.day.toString().padLeft(2, '0')} '
            '${reminder.hour.toString().padLeft(2, '0')}:'
            '${reminder.minute.toString().padLeft(2, '0')}:00';
      }

      late final http.Response response;

      if (editing) {
        body['occurrence_id'] = task['occurrence_id'];

        response = await http
            .patch(
              Uri.parse('$taskServerUrl/tasks/${task['task_id']}'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${widget.token}',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15));
      } else {
        response = await http
            .post(
              Uri.parse('$taskServerUrl/tasks'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${widget.token}',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15));
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      final success = editing
          ? response.statusCode >= 200 && response.statusCode < 300
          : response.statusCode == 201;

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ?? 'Could not save task.',
            ),
          ),
        );
        return;
      }

      final occurrenceId = editing
          ? (task['occurrence_id'] as num).toInt()
          : (data['occurrence_id'] as num).toInt();

      try {
        if (editing) {
          await TaskNotificationService.cancelReminder(occurrenceId);
        }

        if (reminderAt != null) {
          await TaskNotificationService.scheduleReminder(
            id: occurrenceId,
            title: titleController.text.trim(),
            reminderAt: reminderAt!,
          );
        }
      } catch (e) {
        debugPrint('Reminder scheduling error: $e');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editing
                ? 'Task updated successfully!'
                : 'Task created successfully!',
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving task: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save task. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add task')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'What do you need to do?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Plan it now. Get it done on time.'),
            const SizedBox(height: 24),

            TextFormField(
              controller: titleController,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Task title',
                hintText: 'e.g. Complete project report',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a task title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Add some details',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 22),

            const Text(
              'Schedule',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: chooseDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(formatDate(scheduledDate)),
            ),

            OutlinedButton.icon(
              onPressed: chooseTaskTime,
              icon: const Icon(Icons.access_time),
              label: Text('Task time: ${scheduledTime.format(context)}'),
            ),

            const SizedBox(height: 22),

            const Text(
              'Priority',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              initialValue: priority,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => priority = value);
                }
              },
            ),

            const SizedBox(height: 22),

            const Text(
              'Reminder (optional)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: chooseReminderTime,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                reminderTime == null
                    ? 'Choose reminder time'
                    : 'Reminder: ${reminderTime!.format(context)}',
              ),
            ),

            if (reminderTime != null)
              TextButton(
                onPressed: () {
                  setState(() => reminderTime = null);
                },
                child: const Text('Remove reminder'),
              ),

            const SizedBox(height: 22),

            const Text(
              'Repeat task',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              initialValue: recurrenceFrequency,
              decoration: const InputDecoration(
                labelText: 'Repeat frequency',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    recurrenceFrequency = value;
                    selectedWeekdays.clear();
                  });
                }
              },
            ),

            if (recurrenceFrequency != 'none') ...[
              const SizedBox(height: 12),

              DropdownButtonFormField<int>(
                initialValue: recurrenceInterval,
                decoration: const InputDecoration(
                  labelText: 'Repeat every',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  4,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text(
                      '${index + 1} ${recurrenceFrequency == 'daily' ? 'day(s)' : 'week(s)'}',
                    ),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => recurrenceInterval = value);
                  }
                },
              ),
            ],

            if (recurrenceFrequency == 'weekly') ...[
              const SizedBox(height: 12),
              const Text('Repeat on'),

              Wrap(
                spacing: 6,
                children: weekdays.map((day) {
                  final value = day['value'] as int;

                  return FilterChip(
                    label: Text(day['label'] as String),
                    selected: selectedWeekdays.contains(value),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          selectedWeekdays.add(value);
                        } else {
                          selectedWeekdays.remove(value);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 22),

            const Text(
              'Reminder (optional)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: chooseReminderTime,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                reminderTime == null
                    ? 'Choose reminder time'
                    : 'Reminder: ${reminderTime!.format(context)}',
              ),
            ),

            if (reminderTime != null)
              TextButton(
                onPressed: () {
                  setState(() => reminderTime = null);
                },
                child: const Text('Remove reminder'),
              ),

            const SizedBox(height: 28),

            FilledButton.icon(
              onPressed: saving ? null : saveTask,
              icon: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_task),
              label: Text(saving ? 'Saving...' : 'Create task'),
            ),
          ],
        ),
      ),
    );
  }
}
