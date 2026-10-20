import 'dart:convert';
import 'screens/task_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/task_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/task_widget_service.dart';

// Keep this URL for your current Chrome development setup.
const String baseUrl = 'https://tasks-reminder.onrender.com';

const Color primaryColor = Color(0xFF34465E);
const Color backgroundColor = Color(0xFFF5F7FA);
const Color surfaceColor = Color(0xFFFFFFFF);
const Color textColor = Color(0xFF253247);
const Color secondaryTextColor = Color(0xFF778397);
const Color borderColor = Color(0xFFE3E8EF);
const Color successColor = Color(0xFF467766);
const Color mutedGreen = Color(0xFFEDF5F0);
const Color mutedRed = Color(0xFFFAEEEE);

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();
const MethodChannel _deepLinkChannel =
    MethodChannel('com.example.flutter_pgi/deep_link');

void _setupDeepLinkListener() {
  _deepLinkChannel.setMethodCallHandler((call) async {
    if (call.method == 'onDeepLink') {
      final String? url = call.arguments as String?;
      if (url != null && (url.contains('dashboard') || url.contains('mytasks'))) {
        await _navigateToDashboardIfLoggedIn();
      }
    }
  });
}

Future<void> _navigateToDashboardIfLoggedIn() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('task_widget_token');
    final fullName = prefs.getString('task_widget_full_name') ?? 'Employee';
    if (token != null && token.isNotEmpty) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => TaskDashboard(token: token, fullName: fullName),
        ),
        (_) => false,
      );
    }
  } catch (e) {
    debugPrint('Navigation to dashboard error: $e');
  }
}

Future<void> initializeNotifications() async {
  try {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await notificationsPlugin.initialize(settings: settings);

    final androidPlugin = notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();

    final darwinPlugin = notificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await darwinPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  } catch (e) {
    debugPrint('Notifications init error: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initializeNotifications();
  } catch (e) {
    debugPrint('initializeNotifications error: $e');
  }

  try {
    await TaskNotificationService.initialize();
  } catch (e) {
    debugPrint('TaskNotificationService error: $e');
  }

  try {
    _setupDeepLinkListener();
  } catch (e) {
    debugPrint('setupDeepLinkListener error: $e');
  }

  runApp(const AttendanceApp());
}

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  bool _loading = true;
  String? _token;
  String _fullName = 'Employee';

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('task_widget_token');
      final fullName = prefs.getString('task_widget_full_name') ?? 'Employee';

      try {
        final initialUrl =
            await _deepLinkChannel.invokeMethod<String>('getInitialUrl');
        debugPrint('Initial deep link URL: $initialUrl');
      } catch (_) {}

      if (mounted) {
        setState(() {
          _token = (token != null && token.isNotEmpty) ? token : null;
          _fullName = fullName;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Initial state check error: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    if (_token != null) {
      return TaskDashboard(token: _token!, fullName: _fullName);
    }

    return const LoginScreen();
  }
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Enterprise Attendance',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          surface: surfaceColor,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceColor,
          foregroundColor: textColor,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFAFBFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          labelStyle: const TextStyle(color: secondaryTextColor, fontSize: 14),
          prefixIconColor: secondaryTextColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryColor, width: 1.4),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFE5E9EF),
            disabledForegroundColor: secondaryTextColor,
            minimumSize: const Size.fromHeight(50),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            minimumSize: const Size.fromHeight(50),
            side: const BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(color: borderColor, thickness: 1),
      ),
      home: const AppEntryPoint(),
      routes: {
        '/login': (_) => const LoginScreen(),
      },
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => const AppEntryPoint(),
          settings: settings,
        );
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => const AppEntryPoint(),
          settings: settings,
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// LOGIN AND REGISTRATION
// -----------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employeeCode = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool isRegister = false;
  bool isLoading = false;
  bool hidePassword = true;
  String message = '';
  bool messageIsSuccess = false;

  @override
  void dispose() {
    _employeeCode.dispose();
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      message = '';
    });

    try {
      final endpoint = isRegister ? '/auth/register' : '/auth/login';

      final Map<String, dynamic> body = {
        'email': _email.text.trim(),
        'password': _password.text,
      };

      if (isRegister) {
        body['employee_code'] = _employeeCode.text.trim();
        body['full_name'] = _fullName.text.trim();
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};

      if (response.body.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {
          debugPrint('Invalid server response: ${response.body}');
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (isRegister) {
          setState(() {
            isRegister = false;
            _password.clear();
            message = 'Registration successful. Please log in.';
            messageIsSuccess = true;
          });
        } else {
          final token = data['token'] as String?;
          final user = data['user'] as Map<String, dynamic>?;

          if (token == null || user == null) {
            throw Exception('The server did not return login details.');
          }
          final fullName = user['full_name']?.toString() ?? 'Employee';
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('task_widget_token', token);
          await prefs.setString('task_widget_full_name', fullName);
          await prefs.setString('task_widget_base_url', baseUrl);

          await TaskWidgetService.refresh();
          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TaskDashboard(
                token: token,
                fullName: fullName,
              ),
            ),
          );
        }
      } else {
        setState(() {
          message = data['message']?.toString() ?? 'Request failed.';
          messageIsSuccess = false;
        });
      }
    } catch (error) {
      setState(() {
        message =
            'Could not connect to the server. Check your API address '
            'and make sure the backend is running.';
        messageIsSuccess = false;
      });

      debugPrint('Authentication error: $error');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),

                  // Brand header
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF0F6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.access_time_rounded,
                        size: 34,
                        color: primaryColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  const Text(
                    'Enterprise Attendance',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      letterSpacing: -0.6,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    isRegister
                        ? 'Create your employee account'
                        : 'Sign in to your employee workspace',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: secondaryTextColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Form card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.025),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            isRegister ? 'Create account' : 'Welcome back',
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            isRegister
                                ? 'Enter your details to get started.'
                                : 'Enter your credentials to continue.',
                            style: const TextStyle(
                              color: secondaryTextColor,
                              fontSize: 13,
                            ),
                          ),

                          const SizedBox(height: 24),

                          if (isRegister) ...[
                            _buildField(
                              controller: _employeeCode,
                              label: 'Employee code',
                              icon: Icons.badge_outlined,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Enter your employee code'
                                  : null,
                            ),

                            const SizedBox(height: 16),

                            _buildField(
                              controller: _fullName,
                              label: 'Full name',
                              icon: Icons.person_outline_rounded,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Enter your full name'
                                  : null,
                            ),

                            const SizedBox(height: 16),
                          ],

                          _buildField(
                            controller: _email,
                            label: 'Work email',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null ||
                                  !RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(value.trim())) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _password,
                            obscureText: hidePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    hidePassword = !hidePassword;
                                  });
                                },
                                icon: Icon(
                                  hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: secondaryTextColor,
                                  size: 20,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your password';
                              }

                              if (isRegister && value.length < 12) {
                                return 'Use at least 12 characters';
                              }

                              return null;
                            },
                          ),

                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _MessageBanner(
                              message: message,
                              isSuccess: messageIsSuccess,
                            ),
                          ],

                          const SizedBox(height: 22),

                          FilledButton(
                            onPressed: isLoading ? null : submit,
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primaryColor,
                                    ),
                                  )
                                : Text(
                                    isRegister ? 'Create account' : 'Sign in',
                                  ),
                          ),

                          const SizedBox(height: 12),

                          Center(
                            child: TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        isRegister = !isRegister;
                                        message = '';
                                        messageIsSuccess = false;
                                      });
                                    },
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                              ),
                              child: Text(
                                isRegister
                                    ? 'Already registered? Sign in'
                                    : 'New employee? Create account',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: secondaryTextColor,
                        size: 16,
                      ),
                      SizedBox(width: 7),
                      Text(
                        'Secure employee access',
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: validator,
    );
  }
}

// -----------------------------------------------------------------------------
// ATTENDANCE DASHBOARD
// -----------------------------------------------------------------------------

class AttendanceScreen extends StatefulWidget {
  final String token;
  final String fullName;

  const AttendanceScreen({
    super.key,
    required this.token,
    required this.fullName,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<dynamic> records = [];
  bool isLoading = true;
  bool isWorking = false;
  String message = '';
  bool messageIsSuccess = false;

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${widget.token}',
  };

  @override
  void initState() {
    super.initState();
    loadAttendance();
  }

  String dateOnly(dynamic value) {
    if (value == null) return '—';
    return value.toString().substring(0, 10);
  }

  String timeOnly(dynamic value) {
    if (value == null) return '—';

    final text = value.toString();

    if (text.length >= 16 && text.contains('T')) {
      return text.substring(11, 16);
    }

    if (text.length >= 16) {
      return text.substring(11, 16);
    }

    return text;
  }

  String formattedDate(String value) {
    try {
      final date = DateTime.parse(value);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];

      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return value;
    }
  }

  String formattedToday() {
    final now = DateTime.now();
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
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
    ];

    return '${weekdays[now.weekday - 1]}, ${now.day} '
        '${months[now.month - 1]} ${now.year}';
  }

  dynamic get todayRecord {
    final today = DateTime.now().toLocal().toIso8601String().substring(0, 10);

    for (final record in records) {
      if (dateOnly(record['attendance_date']) == today) {
        return record;
      }
    }

    return null;
  }

  Future<void> loadAttendance() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/attendance/weekly'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('Weekly API status: ${response.statusCode}');
      debugPrint('Weekly API body: ${response.body}');

      Map<String, dynamic> data = {};

      if (response.body.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {
          debugPrint('Invalid server response: ${response.body}');
        }
      }

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          records = data['attendance'] as List<dynamic>? ?? [];
          message = '';
        });
      } else {
        setState(() {
          message = data['message']?.toString() ?? 'Could not load attendance.';
          messageIsSuccess = false;
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Unable to load attendance. Check your connection.';
        messageIsSuccess = false;
      });

      debugPrint('Attendance loading error: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> markAttendance(String action) async {
    setState(() {
      isWorking = true;
      message = '';
    });

    try {
      final response = await http
          .post(Uri.parse('$baseUrl/attendance/$action'), headers: headers)
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};

      if (response.body.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {
          debugPrint('Invalid server response: ${response.body}');
        }
      }

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          message =
              data['message']?.toString() ??
              (action == 'check-in'
                  ? 'Check-in completed successfully.'
                  : 'Check-out completed successfully.');
          messageIsSuccess = true;
        });

        await loadAttendance();
      } else {
        setState(() {
          message = data['message']?.toString() ?? 'Request failed.';
          messageIsSuccess = false;
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Could not contact the server.';
        messageIsSuccess = false;
      });

      debugPrint('Attendance action error: $error');
    } finally {
      if (mounted) {
        setState(() => isWorking = false);
      }
    }
  }

  void logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = todayRecord;
    final hasCheckedIn = today != null && today['check_in_at'] != null;
    final hasCheckedOut = today != null && today['check_out_at'] != null;

    final statusText = !hasCheckedIn
        ? 'Not checked in'
        : hasCheckedOut
        ? 'Shift completed'
        : 'Currently working';

    final statusColor = !hasCheckedIn
        ? secondaryTextColor
        : hasCheckedOut
        ? successColor
        : primaryColor;

    final statusBackground = !hasCheckedIn
        ? const Color(0xFFF0F2F5)
        : hasCheckedOut
        ? mutedGreen
        : const Color(0xFFEDF1F6);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.access_time_rounded, size: 25, color: primaryColor),
            SizedBox(width: 10),
            Text(
              'Attendance',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh attendance',
            onPressed: isLoading ? null : loadAttendance,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 12),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
      ),
      body: RefreshIndicator(
        color: primaryColor,
        onRefresh: loadAttendance,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // Welcome section
            const Text(
              'EMPLOYEE WORKSPACE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: secondaryTextColor,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'Welcome, ${widget.fullName}',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: textColor,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              formattedToday(),
              style: const TextStyle(fontSize: 14, color: secondaryTextColor),
            ),

            const SizedBox(height: 26),

            // Today's attendance card
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Today's attendance",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: statusBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Check-in and check-out time cards
                  Row(
                    children: [
                      Expanded(
                        child: _TimeCard(
                          icon: Icons.login_rounded,
                          title: 'Check-in',
                          time: timeOnly(today?['check_in_at']),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeCard(
                          icon: Icons.logout_rounded,
                          title: 'Check-out',
                          time: timeOnly(today?['check_out_at']),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  if (!hasCheckedIn)
                    const Text(
                      'Start your workday by recording your check-in.',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    )
                  else if (!hasCheckedOut)
                    const Text(
                      'Your check-in is recorded. Remember to check out '
                      'when your workday is complete.',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    )
                  else
                    const Text(
                      'Your attendance for today is complete.',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Check-in button
                  FilledButton.icon(
                    onPressed: isWorking || hasCheckedIn
                        ? null
                        : () => markAttendance('check-in'),
                    icon: const Icon(Icons.login_rounded, size: 19),
                    label: Text(hasCheckedIn ? 'Checked in' : 'Check in'),
                  ),

                  const SizedBox(height: 10),

                  // Check-out button
                  OutlinedButton.icon(
                    onPressed: isWorking || !hasCheckedIn || hasCheckedOut
                        ? null
                        : () => markAttendance('check-out'),
                    icon: const Icon(Icons.logout_rounded, size: 19),
                    label: Text(hasCheckedOut ? 'Checked out' : 'Check out'),
                  ),

                  if (isWorking) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(
                      color: primaryColor,
                      backgroundColor: borderColor,
                      minHeight: 2,
                    ),
                  ],

                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _MessageBanner(
                      message: message,
                      isSuccess: messageIsSuccess,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Weekly attendance heading
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Attendance history',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                if (!isLoading)
                  Text(
                    '${records.length} records',
                    style: const TextStyle(
                      fontSize: 12,
                      color: secondaryTextColor,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 6),

            const Text(
              'Your recorded attendance for this week',
              style: TextStyle(fontSize: 13, color: secondaryTextColor),
            ),

            const SizedBox(height: 16),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(
                    color: primaryColor,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (records.isEmpty)
              _SectionCard(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.calendar_month_outlined,
                        color: secondaryTextColor,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No attendance records yet',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your attendance entries will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondaryTextColor, fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              _SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (int i = 0; i < records.length; i++) ...[
                      _AttendanceHistoryItem(
                        date: formattedDate(
                          dateOnly(records[i]['attendance_date']),
                        ),
                        checkIn: timeOnly(records[i]['check_in_at']),
                        checkOut: timeOnly(records[i]['check_out_at']),
                        completed: records[i]['check_out_at'] != null,
                      ),
                      if (i != records.length - 1)
                        const Divider(
                          height: 1,
                          indent: 18,
                          endIndent: 18,
                          color: borderColor,
                        ),
                    ],
                  ],
                ),
              ),

            const SizedBox(height: 24),

            const Center(
              child: Text(
                'Enterprise Attendance System',
                style: TextStyle(fontSize: 11, color: secondaryTextColor),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// REUSABLE UI COMPONENTS
// -----------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.018),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TimeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String time;

  const _TimeCard({
    required this.icon,
    required this.title,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: secondaryTextColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              time,
              style: const TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceHistoryItem extends StatelessWidget {
  final String date;
  final String checkIn;
  final String checkOut;
  final bool completed;

  const _AttendanceHistoryItem({
    required this.date,
    required this.checkIn,
    required this.checkOut,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 19,
              color: primaryColor,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.login_rounded,
                      size: 14,
                      color: secondaryTextColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      checkIn,
                      style: const TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.logout_rounded,
                      size: 14,
                      color: secondaryTextColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      checkOut,
                      style: const TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: completed ? mutedGreen : const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              completed ? 'Complete' : 'Open',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: completed ? successColor : secondaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final String message;
  final bool isSuccess;

  const _MessageBanner({required this.message, required this.isSuccess});

  @override
  Widget build(BuildContext context) {
    final color = isSuccess ? successColor : const Color(0xFF9D4848);
    final background = isSuccess ? mutedGreen : mutedRed;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSuccess
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
