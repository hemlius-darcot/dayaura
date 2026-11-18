import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'routine_history.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

const String _profileServerUrl = String.fromEnvironment(
  'ROUTINE_PROFILE_SERVER_URL',
);
bool get _profileServerConfigured =>
    _profileServerUrl.startsWith('http://') ||
    _profileServerUrl.startsWith('https://');
const String _adsSupabaseUrl = String.fromEnvironment('ADS_SUPABASE_URL');
const String _adsSupabasePublishableKey = String.fromEnvironment(
  'ADS_SUPABASE_PUBLISHABLE_KEY',
);
bool get _adsBackendConfigured =>
    _adsSupabaseUrl.startsWith('https://') &&
    _adsSupabasePublishableKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_adsBackendConfigured) {
    try {
      await Supabase.initialize(
        url: _adsSupabaseUrl,
        publishableKey: _adsSupabasePublishableKey,
      );
    } catch (error) {
      debugPrint('Advertisement backend initialization failed: $error');
    }
  }
  runApp(const RoutineApp());
}

const Color kGreen = Color(0xFF20B77A);
const Color kCandleRed = Color(0xFFE65A52);
const Color kCandleYellow = Color(0xFFF2C94C);

Widget _candleThresholdLegend(BuildContext context) {
  final theme = Theme.of(context);
  final textStyle = theme.textTheme.labelSmall?.copyWith(
    fontSize: 10,
    color: theme.colorScheme.onSurfaceVariant,
  );

  Widget item(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: textStyle),
    ],
  );

  Widget modeRow(String mode, List<Widget> items) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Wrap(
      spacing: 9,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$mode:', style: textStyle?.copyWith(fontWeight: FontWeight.w800)),
        ...items,
      ],
    ),
  );

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 2),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        modeRow('Auto', [
          item(kCandleRed, '<40% Red'),
          item(kCandleYellow, '40–<60% Yellow'),
          item(kGreen, '60–100% Green'),
        ]),
        modeRow('Manual', [
          item(kCandleRed, '<50% Red'),
          item(kCandleYellow, '50–<70% Yellow'),
          item(kGreen, '70–100% Green'),
        ]),
      ],
    ),
  );
}

Future<File> _routineSettingsFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/routine_settings.json');
}

Future<Map<String, dynamic>> _readRoutineSettings() async {
  try {
    final file = await _routineSettingsFile();
    if (!await file.exists()) return <String, dynamic>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (error) {
    debugPrint('Could not read routine settings: $error');
  }
  return <String, dynamic>{};
}

Future<void> _writeRoutineSettings(Map<String, dynamic> values) async {
  try {
    final file = await _routineSettingsFile();
    final existing = await _readRoutineSettings();
    await file.writeAsString(jsonEncode({...existing, ...values}), flush: true);
  } catch (error) {
    debugPrint('Could not save routine settings: $error');
  }
}

class RoutineApp extends StatefulWidget {
  const RoutineApp({super.key});
  @override
  State<RoutineApp> createState() => _RoutineAppState();
}

class _RoutineAppState extends State<RoutineApp> {
  bool isDark = true;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadThemeSetting();
  }

  Future<void> _loadThemeSetting() async {
    final settings = await _readRoutineSettings();
    if (!mounted) return;
    setState(() {
      isDark = settings['isDark'] is bool ? settings['isDark'] as bool : true;
      _settingsLoaded = true;
    });
  }

  void _setTheme(bool value) {
    setState(() => isDark = value);
    _writeRoutineSettings({'isDark': value});
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Routine Tracker',
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kGreen),
        scaffoldBackgroundColor: const Color(0xFFF5F7F8),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kGreen,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101411),
        cardTheme: const CardThemeData(color: Color(0xFF1A211D), elevation: 0),
      ),
      home: _ProfileGate(isDark: isDark, onThemeChanged: _setTheme),
    );
  }
}

/// First-launch profile gate. The profile is stored on-device before the main
/// dashboard is shown; this works without adding another package or network.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate({required this.isDark, required this.onThemeChanged});
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  bool _loading = true;
  Map<String, dynamic>? _profile;
  Timer? _profileRetryTimer;
  bool _syncInProgress = false;

  Future<File> get _profileFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/routine_profile.json');
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final file = await _profileFile;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic> && decoded['schemaVersion'] == 1) {
          _profile = Map<String, dynamic>.from(decoded);
          // Migrate profiles created by earlier local-only builds.
          if (_profile!['installationId'] is! String ||
              (_profile!['installationId'] as String).length != 36) {
            _profile!['installationId'] = _newInstallationId();
            _profile!['syncStatus'] = 'pending';
            final migrated = File('${file.path}.tmp');
            if (await migrated.exists()) await migrated.delete();
            await migrated.writeAsString(jsonEncode(_profile), flush: true);
            await migrated.rename(file.path);
          }
        }
      }
    } catch (error) {
      debugPrint('Could not load local profile: $error');
    }
    if (mounted) setState(() => _loading = false);
    if (_profile != null) {
      _syncProfileIfConfigured();
      _profileRetryTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _syncProfileIfConfigured(),
      );
    }
  }

  Future<void> _saveProfile(Map<String, dynamic> profile) async {
    final file = await _profileFile;
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) await temp.delete();
    await temp.writeAsString(jsonEncode(profile), flush: true);
    await temp.rename(file.path);
    if (!mounted) return;
    setState(() => _profile = profile);
    _syncProfileIfConfigured();
    _profileRetryTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _syncProfileIfConfigured(),
    );
  }

  String _isoCountryCode(String country) {
    const codes = <String, String>{
      'Bangladesh': 'BD',
      'India': 'IN',
      'Pakistan': 'PK',
      'Nepal': 'NP',
      'Sri Lanka': 'LK',
      'China': 'CN',
      'Malaysia': 'MY',
      'Indonesia': 'ID',
      'Saudi Arabia': 'SA',
      'United Arab Emirates': 'AE',
      'United Kingdom': 'GB',
      'United States': 'US',
      'Canada': 'CA',
      'Australia': 'AU',
      'Germany': 'DE',
      'Italy': 'IT',
      'France': 'FR',
      'Japan': 'JP',
      'South Korea': 'KR',
      'Other': 'BD',
    };
    return codes[country] ?? 'BD';
  }

  String _statusCode(String status) => switch (status) {
    'Student' => 'student',
    'Employed' => 'employed',
    'Job seeker' => 'job_seeker',
    'Self-employed' => 'self_employed',
    _ => 'other',
  };

  String _categorySlug(String goal) {
    final slug = goal
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return (slug.isEmpty ? 'general' : slug).substring(
      0,
      (slug.isEmpty ? 'general' : slug).length.clamp(1, 60),
    );
  }

  Future<void> _syncProfileIfConfigured() async {
    if (_syncInProgress || _profile == null || !_profileServerConfigured)
      return;
    final current = Map<String, dynamic>.from(_profile!);
    final installationId = current['installationId'];
    if (installationId is! String || installationId.length != 36) return;
    _syncInProgress = true;
    try {
      final status = current['status']?.toString() ?? 'Other';
      final goal = current['goal']?.toString() ?? 'General';
      final purposeParts = <String>[
        if (current['education'] != null) current['education'].toString(),
        if (current['workType'] != null) current['workType'].toString(),
        goal,
      ];
      final payload = <String, dynamic>{
        'installation_id': installationId,
        'country_code': _isoCountryCode(
          current['country']?.toString() ?? 'Other',
        ),
        'age': (current['age'] as num?)?.toInt() ?? 21,
        'current_status': _statusCode(status),
        'primary_goal_category': _categorySlug(goal),
        'routine_purpose': purposeParts.join(' — '),
        'answers': <String, dynamic>{
          'education': current['education'],
          'work_type': current['workType'],
          'goal': goal,
        },
      };
      final response = await http
          .post(
            Uri.parse(
              '${_profileServerUrl.replaceAll(RegExp(r'/+$'), '')}/profiles',
            ),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        current['syncStatus'] = 'synced';
        current['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
        final file = await _profileFile;
        final temp = File('${file.path}.tmp');
        if (await temp.exists()) await temp.delete();
        await temp.writeAsString(jsonEncode(current), flush: true);
        await temp.rename(file.path);
        if (mounted) setState(() => _profile = current);
      } else {
        debugPrint(
          'Profile sync pending: server returned HTTP ${response.statusCode}',
        );
      }
    } catch (error) {
      // Keep the local profile and retry on the next timer tick / app launch.
      debugPrint('Profile sync pending; will retry: $error');
    } finally {
      _syncInProgress = false;
    }
  }

  @override
  void dispose() {
    _profileRetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profile == null) {
      return _ProfileOnboarding(onSave: _saveProfile);
    }
    return HomePage(
      isDark: widget.isDark,
      onThemeChanged: widget.onThemeChanged,
    );
  }
}

String _newInstallationId() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class _ProfileOnboarding extends StatefulWidget {
  const _ProfileOnboarding({required this.onSave});
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_ProfileOnboarding> createState() => _ProfileOnboardingState();
}

class _ProfileOnboardingState extends State<_ProfileOnboarding> {
  static const List<String> _countries = <String>[
    'Bangladesh',
    'India',
    'Pakistan',
    'Nepal',
    'Sri Lanka',
    'China',
    'Malaysia',
    'Indonesia',
    'Saudi Arabia',
    'United Arab Emirates',
    'United Kingdom',
    'United States',
    'Canada',
    'Australia',
    'Germany',
    'Italy',
    'France',
    'Japan',
    'South Korea',
    'Other',
  ];
  static const List<String> _statuses = <String>[
    'Student',
    'Employed',
    'Job seeker',
    'Self-employed',
    'Other',
  ];
  static const List<String> _bdEducation = <String>[
    'Primary',
    'JSC / equivalent',
    'SSC / equivalent',
    'HSC / equivalent',
    'Polytechnic / Diploma',
    'Bachelor',
    'Master or higher',
    'Other',
  ];
  static const List<String> _generalEducation = <String>[
    'Primary',
    'Secondary',
    'Higher secondary',
    'Diploma / vocational',
    'Bachelor',
    'Master or higher',
    'Other',
  ];
  static const List<String> _studentGoals = <String>[
    'School / college study',
    'Polytechnic / diploma study',
    'University admission preparation',
    'BCS / government job preparation',
    'Professional certification',
    'Language learning',
    'Other',
  ];
  static const List<String> _workGoals = <String>[
    'Career development',
    'Learn a new skill',
    'Professional certification',
    'Find a better job',
    'Start / grow a business',
    'Other',
  ];

  String _country = 'Bangladesh';
  String _status = 'Student';
  String _education = 'HSC / equivalent';
  String _goal = 'University admission preparation';
  String _workType = 'Private sector';
  int _age = 21;
  bool _saving = false;
  String? _error;

  List<String> get _educationOptions =>
      _country == 'Bangladesh' ? _bdEducation : _generalEducation;
  List<String> get _goalOptions => _status == 'Student'
      ? _studentGoals
      : _status == 'Employed' || _status == 'Self-employed'
      ? _workGoals
      : <String>[
          'Find education opportunities',
          'Prepare for an exam',
          'Find a job',
          'Learn a new skill',
          'Other',
        ];

  @override
  void initState() {
    super.initState();
    _education = _educationOptions.firstWhere(
      (item) => item == _education,
      orElse: () => _educationOptions.first,
    );
    _goal = _goalOptions.firstWhere(
      (item) => item == _goal,
      orElse: () => _goalOptions.first,
    );
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(<String, dynamic>{
        'schemaVersion': 1,
        'installationId': _newInstallationId(),
        'country': _country,
        'age': _age,
        'status': _status,
        'education': _status == 'Student' ? _education : null,
        'workType': _status == 'Employed' || _status == 'Self-employed'
            ? _workType
            : null,
        'goal': _goal,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'syncStatus': 'pending',
      });
    } catch (error) {
      if (mounted)
        setState(
          () => _error = 'Could not save on this device. Please try again.',
        );
      debugPrint('Local profile save failed: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Icon(Icons.person_outline_rounded, size: 48, color: kGreen),
            const SizedBox(height: 12),
            Text(
              'Make Routine Tracker fit your goals',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a few categories. Your answers are saved on this device first.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            DropdownButtonFormField<String>(
              value: _country,
              decoration: const InputDecoration(
                labelText: 'Country / region',
                border: OutlineInputBorder(),
              ),
              items: _countries
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                      _country = v ?? _country;
                      _education = _educationOptions.first;
                    }),
            ),
            const SizedBox(height: 14),
            Text('Age: $_age', style: theme.textTheme.titleMedium),
            Slider(
              value: _age.toDouble(),
              min: 13,
              max: 100,
              divisions: 87,
              label: '$_age',
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _age = v.round()),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(
                labelText: 'Current status',
                border: OutlineInputBorder(),
              ),
              items: _statuses
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                      _status = v ?? _status;
                      _goal = _goalOptions.first;
                    }),
            ),
            if (_status == 'Student') ...<Widget>[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _educationOptions.contains(_education)
                    ? _education
                    : _educationOptions.first,
                decoration: const InputDecoration(
                  labelText: 'Education level',
                  border: OutlineInputBorder(),
                ),
                items: _educationOptions
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _education = v ?? _education),
              ),
            ],
            if (_status == 'Employed' ||
                _status == 'Self-employed') ...<Widget>[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _workType,
                decoration: const InputDecoration(
                  labelText: 'Work area',
                  border: OutlineInputBorder(),
                ),
                items:
                    const <String>[
                          'Private sector',
                          'Public sector',
                          'Freelance',
                          'Business owner',
                          'Other',
                        ]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _workType = v ?? _workType),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _goalOptions.contains(_goal) ? _goal : _goalOptions.first,
              decoration: const InputDecoration(
                labelText: 'Main goal',
                border: OutlineInputBorder(),
              ),
              items: _goalOptions
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _goal = v ?? _goal),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _saving ? 'Saving on device…' : 'Save profile and continue',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No name, phone number, or email is requested. This build saves your profile and tasks on this device; server sync and category-targeted ads are not connected in this build.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class TaskNode {
  TaskNode({
    required this.title,
    required this.startMinute,
    required this.endMinute,
    this.done = false,
    this.alarmEnabled = false,
    this.alarmLeadSeconds = 300,
    List<TaskNode>? children,
  }) : children = children ?? <TaskNode>[];

  String title;
  int startMinute;
  int endMinute; // 1440 represents midnight at the end of the day.
  bool done;
  bool alarmEnabled;
  int alarmLeadSeconds;
  final List<TaskNode> children;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'done': done,
    'alarmEnabled': alarmEnabled,
    'alarmLeadSeconds': alarmLeadSeconds,
    'children': children.map((child) => child.toJson()).toList(),
  };

  factory TaskNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    return TaskNode(
      title: json['title']?.toString() ?? 'Untitled task',
      startMinute: (json['startMinute'] as num?)?.toInt() ?? 0,
      endMinute: (json['endMinute'] as num?)?.toInt() ?? 60,
      done: json['done'] == true,
      alarmEnabled: json['alarmEnabled'] == true,
      alarmLeadSeconds: (json['alarmLeadSeconds'] as num?)?.toInt() ?? 300,
      children: rawChildren is List
          ? rawChildren
                .whereType<Map>()
                .map(
                  (child) =>
                      TaskNode.fromJson(Map<String, dynamic>.from(child)),
                )
                .toList()
          : <TaskNode>[],
    );
  }

  int get durationMinutes => endMinute - startMinute;
  String get startLabel => _formatMinute(startMinute);
  String get endLabel => _formatMinute(endMinute == 1440 ? 0 : endMinute);
  String get durationLabel {
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

String _formatMinute(int minute, {bool use24Hour = true}) {
  final safe = minute % 1440;
  final hour = safe ~/ 60;
  final min = safe % 60;
  final minuteText = min.toString().padLeft(2, '0');
  if (use24Hour) return '${hour.toString().padLeft(2, '0')}:$minuteText';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  final suffix = hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minuteText $suffix';
}

String _formatClock(DateTime value, bool use24Hour) =>
    _formatMinute(value.hour * 60 + value.minute, use24Hour: use24Hour);

String _formatClockWithSeconds(DateTime value, bool use24Hour) {
  final minutePart = '${_two(value.minute)}:${_two(value.second)}';
  if (use24Hour) return '${_two(value.hour)}:$minutePart';
  final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '$hour12:$minutePart ${value.hour < 12 ? 'AM' : 'PM'}';
}

int? _parseTime(
  String raw, {
  required bool use24Hour,
  bool endTime = false,
  int? startMinute,
}) {
  final input = raw.trim();
  int? value;
  if (use24Hour) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(input);
    if (match != null) {
      value = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    }
  } else {
    final match = RegExp(
      r'^(0?[1-9]|1[0-2]):([0-5]\d)\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(input);
    if (match != null) {
      var hour = int.parse(match.group(1)!) % 12;
      final minute = int.parse(match.group(2)!);
      if (match.group(3)!.toUpperCase() == 'PM') hour += 12;
      value = hour * 60 + minute;
    }
  }
  if (value == null) return null;
  if (endTime && value == 0 && startMinute != null && startMinute > 0)
    return 1440;
  return value;
}

class SampleDay {
  const SampleDay(this.date, this.progress, this.mode);
  final DateTime date;
  final double progress;
  final String mode;
}

class TimeInterval {
  const TimeInterval(this.startSeconds, this.endSeconds);
  final int startSeconds;
  final int endSeconds;
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
  });
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool showCandles = true;
  bool showSetup = false;
  bool use24Hour = true;
  String activeMode = 'Auto';
  late DateTime now;
  Timer? clockTimer;

  final RoutineHistoryStore _historyStore = RoutineHistoryStore();
  List<RoutineDayRecord> _savedHistory = <RoutineDayRecord>[];
  bool _historyLoaded = false;
  bool _dateRolloverInProgress = false;

  Future<void> _loadRoutineHistory() async {
    try {
      final records = await _historyStore.load();
      if (!mounted) return;
      setState(() {
        _savedHistory = records;
        _historyLoaded = true;
      });
    } catch (error) {
      debugPrint('Could not load routine history: $error');
      if (mounted) {
        setState(() => _historyLoaded = true);
      }
    }
  }

  final GlobalKey<_InteractiveCumulativeChartState> _lifetimeChartKey =
      GlobalKey<_InteractiveCumulativeChartState>();
  // Each day starts with an empty task list. Users create that day's tasks;
  // Auto and Manual remain separate data spaces.
  final List<TaskNode> autoTasks = <TaskNode>[];
  final List<TaskNode> manualTasks = <TaskNode>[];

  Future<File> _routineTasksFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/routine_tasks.json');
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  double _progressForTasks(List<TaskNode> tasks) =>
      (_completedLeafSeconds(tasks) / 86400 * 100).clamp(0.0, 100.0);

  Future<void> _saveDayRecord(
    DateTime date, {
    required double progress,
    required String mode,
  }) async {
    await _historyStore.save(
      RoutineDayRecord(
        date: DateTime(date.year, date.month, date.day),
        progress: progress,
        mode: mode,
      ),
    );
  }

  Future<void> _recoverDays(
    DateTime firstDate,
    DateTime currentDate, {
    required double firstDayProgress,
    required String mode,
  }) async {
    var day = DateTime(firstDate.year, firstDate.month, firstDate.day);
    final today = DateTime(currentDate.year, currentDate.month, currentDate.day);

    // Never overwrite an already finalized day. This matters when the app is
    // reopened after a long gap or when rollover recovery runs more than once.
    final existingRecords = await _historyStore.load();
    final existingDateKeys = existingRecords.map((record) => record.dateKey).toSet();
    var isFirst = true;

    while (day.isBefore(today)) {
      final key = _dateKey(day);
      if (!existingDateKeys.contains(key)) {
        await _saveDayRecord(
          day,
          progress: isFirst ? firstDayProgress : 0.0,
          mode: mode,
        );
        existingDateKeys.add(key);
      }
      isFirst = false;
      day = day.add(const Duration(days: 1));
    }
  }

  Future<void> _refreshRoutineHistory() async {
    try {
      final records = await _historyStore.load();
      if (!mounted) return;
      setState(() {
        _savedHistory = records;
        _historyLoaded = true;
      });
    } catch (error) {
      debugPrint('Could not refresh routine history: $error');
    }
  }

  Future<void> _initializeRoutineData() async {
    await _loadRoutineHistory();
    await _loadRoutineTasks();
    await _refreshRoutineHistory();
  }

  void _resetTaskCompletion(List<TaskNode> tasks) {
    for (final task in tasks) {
      task.done = false;
      if (task.children.isNotEmpty) {
        _resetTaskCompletion(task.children);
      }
    }
  }

  void _resetAllDailyTaskCompletion() {
    _resetTaskCompletion(autoTasks);
    _resetTaskCompletion(manualTasks);
  }

  Future<void> _saveRoutineTasks() async {
    final file = await _routineTasksFile();
    final data = <String, dynamic>{
      'version': 1,
      'autoTasks': autoTasks.map((task) => task.toJson()).toList(),
      'manualTasks': manualTasks.map((task) => task.toJson()).toList(),
      'activeMode': activeMode,
      'routineDate': _dateKey(now),
    };
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> _loadRoutineTasks() async {
    try {
      final file = await _routineTasksFile();
      if (!await file.exists()) return;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;

      List<TaskNode>? parseTasks(dynamic value) {
        if (value is! List) return null;
        try {
          return value
              .whereType<Map>()
              .map((item) => TaskNode.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        } catch (_) {
          return null;
        }
      }

      final loadedAuto = parseTasks(decoded['autoTasks']);
      final loadedManual = parseTasks(decoded['manualTasks']);
      if (!mounted || loadedAuto == null || loadedManual == null) return;

      final savedMode = decoded['activeMode'];
      final resolvedMode = savedMode == 'Manual' ? 'Manual' : 'Auto';
      final savedRoutineDate = decoded['routineDate'];
      var crossedIntoNewDay = false;
      if (savedRoutineDate is String) {
        try {
          final parts = savedRoutineDate.split('-').map(int.parse).toList();
          if (parts.length == 3) {
            final savedDate = DateTime(parts[0], parts[1], parts[2]);
            final today = DateTime(now.year, now.month, now.day);
            if (savedDate.isBefore(today)) {
              final savedTasks =
                  resolvedMode == 'Manual' ? loadedManual : loadedAuto;
              // Finalize the last saved day before clearing any completion flags.
              await _recoverDays(
                savedDate,
                today,
                firstDayProgress: _progressForTasks(savedTasks),
                mode: resolvedMode,
              );
              crossedIntoNewDay = true;
            }
          }
        } catch (error) {
          debugPrint('Could not recover routine dates: $error');
        }
      }

      if (crossedIntoNewDay) {
        // Tasks belong to the day they were created for. Finalize yesterday's
        // progress first, then start today with no tasks in either mode.
        loadedAuto.clear();
        loadedManual.clear();
      }

      setState(() {
        autoTasks
          ..clear()
          ..addAll(loadedAuto);
        manualTasks
          ..clear()
          ..addAll(loadedManual);
        if (savedMode == 'Auto' || savedMode == 'Manual') {
          activeMode = savedMode as String;
        }
      });
      if (crossedIntoNewDay) {
        await _saveRoutineTasks();
        await _refreshRoutineHistory();
      }
    } catch (error) {
      debugPrint('Could not load routine tasks: $error');
    }
  }

  List<TaskNode> get currentTasks =>
      activeMode == 'Auto' ? autoTasks : manualTasks;
  int get _elapsedSeconds => now.hour * 3600 + now.minute * 60 + now.second;
  bool _isTimeExpired(TaskNode task) =>
      activeMode == 'Auto' && _elapsedSeconds >= task.endMinute * 60;

  // Upcoming Auto tasks can be pre-checked; their time only turns green as it elapses.
  bool _isUpcomingAuto(TaskNode task) =>
      activeMode == 'Auto' && _elapsedSeconds < task.startMinute * 60;

  // Do not let a parent cascade a tick into a future or already-locked child.
  bool _hasExpiredDescendant(TaskNode task) => task.children.any(
    (child) => _isTimeExpired(child) || _hasExpiredDescendant(child),
  );

  bool _isCheckboxLocked(TaskNode task) =>
      activeMode == 'Auto' &&
      (_isTimeExpired(task) || _hasExpiredDescendant(task));

  // A running parent may still be extended, even if one of its child intervals has ended.
  bool _isTaskLockedForChanges(TaskNode task) =>
      activeMode == 'Auto' && _isTimeExpired(task);

  bool _isDeleteLocked(TaskNode task) =>
      activeMode == 'Auto' &&
      (_isTimeExpired(task) || _hasExpiredDescendant(task));

  @override
  void initState() {
    super.initState();
    now = DateTime.now();
    _initializeRoutineData();
    _loadTimeFormatSetting();
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final actualNow = DateTime.now();
      if (_dateKey(actualNow) != _dateKey(now)) {
        if (!_dateRolloverInProgress) {
          _dateRolloverInProgress = true;
          _handleRoutineDateRollover(actualNow).whenComplete(() {
            _dateRolloverInProgress = false;
          });
        }
        return;
      }
      setState(() => now = actualNow);
    });
  }

  Future<void> _handleRoutineDateRollover(DateTime actualNow) async {
    final previousDate = DateTime(now.year, now.month, now.day);
    final currentDate = DateTime(
      actualNow.year,
      actualNow.month,
      actualNow.day,
    );
    final selectedTasks = activeMode == 'Manual' ? manualTasks : autoTasks;

    await _recoverDays(
      previousDate,
      currentDate,
      firstDayProgress: _progressForTasks(selectedTasks),
      mode: activeMode,
    );

    if (!mounted) return;
    // History is finalized first. Tasks are daily entries, so a new date
    // starts with empty Auto and Manual lists; yesterday remains in history.
    autoTasks.clear();
    manualTasks.clear();
    setState(() => now = actualNow);
    try {
      await _saveRoutineTasks();
      await _refreshRoutineHistory();
    } catch (error) {
      debugPrint('Could not finish daily rollover: $error');
    }
  }

  Future<void> _loadTimeFormatSetting() async {
    final settings = await _readRoutineSettings();
    if (!mounted) return;

    final savedValue = settings['use24Hour'];
    if (savedValue is bool) {
      setState(() => use24Hour = savedValue);
    }
  }

  @override
  void dispose() {
    clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // Android/system Back should return from Today Setup to the Dashboard.
      // The Dashboard remains the root page and may be left normally.
      canPop: !showSetup,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && showSetup && mounted) {
          setState(() => showSetup = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            showSetup ? 'Today Setup' : 'Routine Tracker',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          leading: showSetup
              ? IconButton(
                  onPressed: () => setState(() => showSetup = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'Today Setup',
              onPressed: () => setState(() => showSetup = !showSetup),
              icon: Icon(
                showSetup
                    ? Icons.dashboard_outlined
                    : Icons.calendar_month_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Time format settings',
              onPressed: _showTimeFormatSettings,
              icon: const Icon(Icons.schedule_rounded),
            ),
            IconButton(
              tooltip: 'Toggle theme',
              onPressed: () => widget.onThemeChanged(!widget.isDark),
              icon: Icon(
                widget.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: showSetup ? _buildTodaySetup() : _buildDashboard(),
      ),
    );
  }

  Widget _buildDashboard() {
    final sample = _savedHistory
        .map((record) => SampleDay(record.date, record.progress, record.mode))
        .toList();
    final completedSeconds = _completedLeafSeconds(currentTasks);
    final dailyPct = completedSeconds / 86400 * 100;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0x3320B77A),
                  child: Icon(Icons.timer_outlined, color: kGreen),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_month(now.month)} ${now.day}, ${now.year}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatClockWithSeconds(now, use24Hour),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Text('Active mode: $activeMode'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AdvertisementBanner(
                  onOpenGallery: (ads) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdvertisementGalleryScreen(ads: ads),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Lifetime Overview',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Candle')),
                ButtonSegment(value: false, label: Text('Line')),
              ],
              selected: {showCandles},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => showCandles = selection.first),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        showCandles
                            ? 'CUMULATIVE CANDLE CHART'
                            : 'CUMULATIVE LINE CHART',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open fullscreen chart',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _lifetimeChartKey.currentState?.openFullscreen(),
                      icon: const Icon(Icons.fullscreen_rounded),
                    ),
                    IconButton(
                      tooltip: 'Show recent 5 days',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _lifetimeChartKey.currentState?.showRecentFiveDays(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                if (showCandles) _candleThresholdLegend(context),
                const SizedBox(height: 10),
                _InteractiveCumulativeChart(
                  key: _lifetimeChartKey,
                  candles: showCandles,
                  days: sample,
                  labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  gridColor: Theme.of(context).dividerColor,
                  bodyColor: kGreen,
                  initialRecentFiveDays: true,
                ),
                const SizedBox(height: 8),
                Text(
                  _historyLoaded
                      ? 'Saved daily progress. Missing days detected after the last saved date are recorded as 0%. Drag to pan, pinch to zoom, or use refresh to return to the latest 5 days.'
                      : 'Loading saved daily progress…',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _metric(
                'Today',
                '${dailyPct.toStringAsFixed(2)}%',
                'Daily progress',
                Icons.today_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metric(
                'Completed',
                _formatDuration(completedSeconds),
                'Tracked time',
                Icons.check_circle_outline_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => setState(() => showSetup = true),
          icon: const Icon(Icons.add_task_rounded),
          label: const Padding(
            padding: EdgeInsets.all(13),
            child: Text('Open Today Setup'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _showHistoryNotice,
          icon: const Icon(Icons.history_rounded),
          label: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Historical Details'),
          ),
        ),
      ],
    );
  }

  Widget _metric(String title, String value, String subtitle, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(title),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySetup() {
    final elapsedSeconds = _elapsedSeconds;
    final completedSeconds = _completedLeafSeconds(currentTasks);
    final progress = (completedSeconds / 86400).clamp(0.0, 1.0);
    final completedIntervals = _checkedLeafIntervals(currentTasks);
    final activeElapsedSeconds = _activeElapsedSeconds(
      completedIntervals,
      elapsedSeconds,
    );
    final inactiveElapsedSeconds = math
        .max(0, elapsedSeconds - activeElapsedSeconds)
        .toInt();
    final activeRatio = elapsedSeconds == 0
        ? 0.0
        : activeElapsedSeconds / elapsedSeconds;
    final inactiveRatio = elapsedSeconds == 0
        ? 0.0
        : inactiveElapsedSeconds / elapsedSeconds;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${_month(now.month)} ${now.day}, ${now.year} • ${_formatClockWithSeconds(now, use24Hour)}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'Auto',
              label: Text('Auto Mode'),
              icon: Icon(Icons.lock_clock_rounded),
            ),
            ButtonSegment(
              value: 'Manual',
              label: Text('Manual Mode'),
              icon: Icon(Icons.tune_rounded),
            ),
          ],
          selected: {activeMode},
          showSelectedIcon: false,
          onSelectionChanged: (values) {
            setState(() => activeMode = values.first);
            _saveRoutineTasks().catchError((Object error) {
              debugPrint('Could not save active mode: $error');
            });
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Day timeline',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 76,
                  child: CustomPaint(
                    painter: DayTimelinePainter(
                      elapsedSeconds: elapsedSeconds,
                      activeIntervals: completedIntervals,
                      currentTimeLabel: _formatClock(now, use24Hour),
                      use24Hour: use24Hour,
                      inactiveColor: const Color(0xFFE65A52),
                      activeColor: kGreen,
                      futureColor: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.12),
                      markerColor: Theme.of(context).colorScheme.onSurface,
                      labelColor: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                      bubbleColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Active/inactive ratio is represented by the SAME 24-hour bar
                // above. Below it, show only numeric breakdowns (no second bar).
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _timelineLegend(
                      kGreen,
                      'Active ${_formatHms(activeElapsedSeconds)} (${(activeRatio * 100).toStringAsFixed(1)}%)',
                    ),
                    _timelineLegend(
                      const Color(0xFFE65A52),
                      'Inactive ${_formatHms(inactiveElapsedSeconds)} (${(inactiveRatio * 100).toStringAsFixed(1)}%)',
                    ),
                    _timelineLegend(
                      Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.30),
                      'Future time',
                    ),
                    _timelineLegend(
                      Theme.of(context).colorScheme.onSurface,
                      'Current time marker',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Completed time contribution',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text('${(progress * 100).toStringAsFixed(2)}%'),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress, minHeight: 8),
                const SizedBox(height: 5),
                Text(
                  '${_formatHms(completedSeconds)} completed • contribution updates immediately when a task is checked.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Timeline tasks',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: () => _openTaskDialog(),
              icon: const Icon(Icons.add_circle_rounded),
              tooltip: 'Add task',
            ),
          ],
        ),
        ..._sortedTasks(currentTasks)
            .map((task) => _buildTaskTree(task, 0, null)),
        const SizedBox(height: 10),
        Text(
          'Auto and Manual tasks are separate. The day timeline marks elapsed checked intervals green, elapsed unchecked intervals red, and future intervals neutral. The current-time marker moves every second. Checking a task adds its full duration to Completed Time Contribution immediately.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _timelineLegend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _showTimeFormatSettings() {
    var selectedUse24Hour = use24Hour;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          title: const Text('Time format'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                title: const Text('24-hour (17:30)'),
                value: true,
                groupValue: selectedUse24Hour,
                onChanged: (value) =>
                    refreshDialog(() => selectedUse24Hour = value ?? true),
              ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                title: const Text('12-hour (5:30 PM)'),
                value: false,
                groupValue: selectedUse24Hour,
                onChanged: (value) =>
                    refreshDialog(() => selectedUse24Hour = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => use24Hour = selectedUse24Hour);
                _writeRoutineSettings({'use24Hour': selectedUse24Hour});
                Navigator.pop(dialogContext);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTree(
    TaskNode task,
    int depth,
    TaskNode? parent, {
    String parentPath = '',
  }) {
    final hasChildren = task.children.isNotEmpty;
    final border = BorderRadius.circular(12);
    final breadcrumb = parentPath.isEmpty ? '' : '$parentPath → ${task.title}';
    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0, bottom: 7),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: border),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: task.done,
                        onChanged: _isCheckboxLocked(task)
                            ? null
                            : (value) {
                                setState(
                                  () => _setTaskDone(
                                    task,
                                    value ?? false,
                                    parent,
                                  ),
                                );
                                _saveRoutineTasks().catchError((Object error) {
                                  debugPrint(
                                    'Could not save routine tasks: $error',
                                  );
                                });
                              },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              softWrap: true,
                              style: TextStyle(
                                fontWeight: depth == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_formatMinute(task.startMinute, use24Hour: use24Hour)} – ${_formatMinute(task.endMinute, use24Hour: use24Hour)} • ${task.durationLabel}'
                              '${_isTimeExpired(task) ? (task.done ? ' • LOCKED' : ' • MISSED / LOCKED') : (_isUpcomingAuto(task) ? ' • UPCOMING' : (_isCheckboxLocked(task) ? ' • SUBTASK LOCKED' : ''))}',
                              softWrap: true,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 42),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        IconButton(
                          tooltip: 'Add subtask',
                          onPressed: _isTaskLockedForChanges(task)
                              ? null
                              : () => _openTaskDialog(parent: task),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                        IconButton(
                          tooltip: 'Edit task',
                          onPressed: _isTaskLockedForChanges(task)
                              ? null
                              : () => _openTaskDialog(
                                  existing: task,
                                  parent: parent,
                                ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete task',
                          onPressed: _isDeleteLocked(task)
                              ? null
                              : () => _confirmDeleteTask(task, parent),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (hasChildren)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
                child: Column(
                  children: _sortedTasks(task.children)
                      .map(
                        (child) => _buildTaskTree(
                          child,
                          depth + 1,
                          task,
                          parentPath: breadcrumb.isEmpty
                              ? task.title
                              : breadcrumb,
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTask(TaskNode task, TaskNode? parent) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Delete "${task.title}" and all of its subtasks?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                if (parent == null) {
                  currentTasks.remove(task);
                } else {
                  parent.children.remove(task);
                  _syncAncestors(parent);
                }
              });
              Navigator.pop(dialogContext);
              _saveRoutineTasks().catchError((Object error) {
                debugPrint('Could not save routine tasks: $error');
              });
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _setTaskDone(TaskNode task, bool value, TaskNode? parent) {
    task.done = value;
    for (final child in task.children) {
      _setSubtreeState(child, value);
    }
    if (parent != null) {
      _syncAncestors(parent);
    }
  }

  void _setSubtreeState(TaskNode task, bool value) {
    task.done = value;
    for (final child in task.children) {
      _setSubtreeState(child, value);
    }
  }

  void _syncAncestors(TaskNode node) {
    if (node.children.isNotEmpty) {
      node.done = node.children.every((child) => child.done);
    } else {
      node.done = false;
    }
    final parent = _findParent(currentTasks, node);
    if (parent != null) _syncAncestors(parent);
  }

  TaskNode? _findParent(List<TaskNode> nodes, TaskNode target) {
    for (final node in nodes) {
      if (node.children.contains(target)) return node;
      final found = _findParent(node.children, target);
      if (found != null) return found;
    }
    return null;
  }

  List<TaskNode> _ancestorChain(TaskNode? node) {
    if (node == null) return <TaskNode>[];
    final parentNode = _findParent(currentTasks, node);
    return [..._ancestorChain(parentNode), node];
  }

  Widget _buildTaskBreadcrumb(TaskNode? parent, {TaskNode? existing}) {
    final chain = _ancestorChain(parent);
    if (chain.isEmpty && existing == null) return const SizedBox.shrink();
    final isEditing = existing != null;
    final items = <String>[];
    for (var i = 0; i < chain.length; i++) {
      items.add('${i == 0 ? 'Task' : 'Subtask'}: ${chain[i].title}');
    }
    if (isEditing) {
      items.add('${chain.isEmpty ? 'Task' : 'Subtask'}: ${existing.title}');
    } else if (parent != null) {
      items.add('${chain.length == 1 ? 'Subtask' : 'Subtask'}: [new name]');
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  item,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _openTaskDialog({TaskNode? existing, TaskNode? parent}) {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final parentStartSeconds = (parent?.startMinute ?? 0) * 60;
    final parentEndSeconds = math.min((parent?.endMinute ?? 1440) * 60, 86399);
    final openingNow = DateTime.now();
    final openingNowSeconds =
        (openingNow.hour * 3600 + openingNow.minute * 60 + openingNow.second) ~/
            60 *
            60 +
        60;
    int startSeconds =
        (existing?.startMinute ?? parent?.startMinute ?? 720) * 60;
    if (existing == null && activeMode == 'Auto') {
      startSeconds = math.max(openingNowSeconds, parentStartSeconds);
    }
    int endSeconds = (existing?.endMinute ?? parent?.endMinute ?? 780) * 60;
    startSeconds = startSeconds
        .clamp(parentStartSeconds, (parentEndSeconds - 1).clamp(0, 86399))
        .toInt();
    if (endSeconds <= startSeconds) {
      endSeconds = (startSeconds + 3600)
          .clamp(startSeconds + 1, parentEndSeconds)
          .toInt();
    }
    if (activeMode == 'Auto' && existing == null) {
      final openingNextMinute =
          (openingNow.hour * 60 + openingNow.minute + 1) * 60;
      final earliestEnd = math
          .max((startSeconds ~/ 60 + 1) * 60, openingNextMinute)
          .clamp(startSeconds + 1, parentEndSeconds)
          .toInt();
      if (endSeconds < earliestEnd) endSeconds = earliestEnd;
    }
    endSeconds = endSeconds.clamp(startSeconds + 1, parentEndSeconds).toInt();
    // A duration may never run past the end of its containing interval or
    // past 23:59:59 on the current day.
    int maxDurationForStart(int start) =>
        math.max(1, math.min(parentEndSeconds, 86399) - start).toInt();
    final initialMaxDurationSeconds = maxDurationForStart(startSeconds);
    int durationSeconds = (endSeconds - startSeconds)
        .clamp(1, initialMaxDurationSeconds)
        .toInt();
    endSeconds = (startSeconds + durationSeconds)
        .clamp(startSeconds + 1, parentEndSeconds)
        .toInt();
    int alarmLeadSeconds = existing?.alarmLeadSeconds ?? 300;
    bool useEndTime = true;
    bool alarmEnabled = existing?.alarmEnabled ?? false;
    String? validationError;
    Timer? dialogClockTimer;

    int bounded(int value, int min, int max) => value.clamp(min, max).toInt();
    String two(int n) => n.toString().padLeft(2, '0');

    Widget wheel({
      required String label,
      required int value,
      required int max,
      required ValueChanged<int> onChanged,
      int min = 0,
    }) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            SizedBox(
              height: 104,
              child: CupertinoPicker(
                itemExtent: 34,
                scrollController: FixedExtentScrollController(
                  initialItem: bounded(value, min, max) - min,
                ),
                onSelectedItemChanged: (index) => onChanged(index + min),
                children: List<Widget>.generate(
                  max - min + 1,
                  (index) => Center(
                    child: Text(
                      two(index + min),
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget timePicker({
      required String label,
      required int seconds,
      required ValueChanged<int> onChanged,
      required int maxSeconds,
      int minSeconds = 0,
      bool isDuration = false,
    }) {
      // Duration is elapsed time, never a time-of-day. Use a dedicated picker
      // branch so AM/PM cannot appear even when the global clock format is 12h.
      // maxSeconds is already bounded by the time remaining until 23:59:59
      // (or the parent task's end), and the picker exposes only that range.
      if (isDuration) {
        final durationCap = maxSeconds.clamp(1, 86399).toInt();
        final safeDuration = bounded(seconds, minSeconds, durationCap);
        final durationHours = safeDuration ~/ 3600;
        final durationMinutes = (safeDuration % 3600) ~/ 60;
        final durationRemainderSeconds = safeDuration % 60;
        final maximumHours = durationCap ~/ 3600;
        final maximumMinutes = durationHours == maximumHours
            ? (durationCap % 3600) ~/ 60
            : 59;
        final maximumSeconds =
            durationHours == maximumHours && durationMinutes == maximumMinutes
            ? durationCap % 60
            : 59;
        final minimumSeconds = durationHours == 0 && durationMinutes == 0
            ? minSeconds.clamp(0, 59).toInt()
            : 0;

        int boundedDuration(int hours, int minutes, int seconds) =>
            (hours * 3600 + minutes * 60 + seconds)
                .clamp(minSeconds, durationCap)
                .toInt();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                wheel(
                  label: 'H',
                  value: durationHours,
                  max: maximumHours,
                  onChanged: (value) => onChanged(
                    boundedDuration(
                      value,
                      durationMinutes,
                      durationRemainderSeconds,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text(':'),
                ),
                wheel(
                  label: 'M',
                  value: durationMinutes,
                  max: maximumMinutes,
                  onChanged: (value) => onChanged(
                    boundedDuration(
                      durationHours,
                      value,
                      durationRemainderSeconds,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text(':'),
                ),
                wheel(
                  label: 'S',
                  value: durationRemainderSeconds,
                  min: minimumSeconds,
                  max: maximumSeconds,
                  onChanged: (value) => onChanged(
                    boundedDuration(durationHours, durationMinutes, value),
                  ),
                ),
              ],
            ),
          ],
        );
      }

      final safe = bounded(seconds, minSeconds, maxSeconds);
      final h24 = safe ~/ 3600;
      final m = (safe % 3600) ~/ 60;
      final sec = safe % 60;
      final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
      final isPm = h24 >= 12;
      final minHour24 = minSeconds ~/ 3600;
      final maxHour24 = maxSeconds ~/ 3600;
      final minMinute = h24 == minHour24 ? (minSeconds % 3600) ~/ 60 : 0;
      final maxMinute = h24 == maxHour24 ? (maxSeconds % 3600) ~/ 60 : 59;
      final minuteFloor = h24 * 3600 + m * 60;
      final minSecond = minuteFloor == (minSeconds ~/ 60) * 60
          ? minSeconds % 60
          : 0;
      final maxSecond = minuteFloor == (maxSeconds ~/ 60) * 60
          ? maxSeconds % 60
          : 59;
      void emitTime(int hour24, int minute, int second) {
        final candidate = hour24 * 3600 + minute * 60 + second;
        onChanged(candidate.clamp(minSeconds, maxSeconds).toInt());
      }

      // In 12-hour mode, show only hour choices whose corresponding 24-hour
      // time can fit within the allowed interval. Keep AM/PM as a separate wheel.
      // In 12-hour mode, build the hour wheel only from hours available in
      // the currently selected period. Do not merge AM and PM hours into one
      // list: that made a future 9 PM option appear as an invalid 9 AM option
      // before a 10 AM minimum.
      final validHours12 = <int>[];
      for (var hour24 = 0; hour24 < 24; hour24++) {
        if ((hour24 >= 12) != isPm) continue;
        final hourStart = hour24 * 3600;
        final hourEnd = hourStart + 3599;
        if (hourEnd >= minSeconds && hourStart <= maxSeconds) {
          final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
          if (!validHours12.contains(hour12)) validHours12.add(hour12);
        }
      }
      validHours12.sort((a, b) {
        final a24 = (a % 12) + (isPm ? 12 : 0);
        final b24 = (b % 12) + (isPm ? 12 : 0);
        return a24.compareTo(b24);
      });
      if (validHours12.isEmpty) validHours12.add(h12);
      final selectedHour12Index = validHours12
          .indexOf(h12)
          .clamp(0, validHours12.length - 1);

      // Show AM or PM if that period has any valid time in the complete
      // selectable range, not only when the *currently selected hour* is
      // valid in that period. This lets a user switch from a default 12 PM
      // end time to a valid 10:24 AM end time; emitTime clamps to the nearest
      // valid boundary and then the hour/minute wheels update to that value.
      final validPeriods = <bool>[]; // false = AM, true = PM
      for (final pm in [false, true]) {
        var periodHasAvailableTime = false;
        for (var hour24 = 0; hour24 < 24; hour24++) {
          if ((hour24 >= 12) != pm) continue;
          final hourStart = hour24 * 3600;
          final hourEnd = hourStart + 3599;
          if (hourEnd >= minSeconds && hourStart <= maxSeconds) {
            periodHasAvailableTime = true;
            break;
          }
        }
        if (periodHasAvailableTime) validPeriods.add(pm);
      }
      if (validPeriods.isEmpty) validPeriods.add(isPm);
      final selectedPeriodIndex = validPeriods
          .indexOf(isPm)
          .clamp(0, validPeriods.length - 1);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              // A duration is an elapsed amount, not a clock time. Always show
              // its hour component as 00–23 and never show AM/PM, regardless of
              // the user's preferred clock format.
              if (use24Hour || isDuration)
                wheel(
                  label: 'H',
                  value: h24,
                  min: minHour24,
                  max: maxHour24.clamp(minHour24, 23).toInt(),
                  onChanged: (v) => emitTime(v, m, sec),
                )
              else ...[
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('H', style: Theme.of(context).textTheme.labelMedium),
                      SizedBox(
                        height: 104,
                        child: CupertinoPicker(
                          itemExtent: 34,
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedHour12Index,
                          ),
                          onSelectedItemChanged: (index) {
                            final selected12 = validHours12[index];
                            final hour24 = (selected12 % 12) + (isPm ? 12 : 0);
                            emitTime(hour24, m, sec);
                          },
                          children: validHours12
                              .map(
                                (hour) => Center(
                                  child: Text(
                                    two(hour),
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text(':'),
              ),
              wheel(
                label: 'M',
                value: m,
                min: minMinute,
                max: maxMinute.clamp(minMinute, 59).toInt(),
                onChanged: (v) => emitTime(h24, v, sec),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text(':'),
              ),
              wheel(
                label: 'S',
                value: sec,
                min: minSecond,
                max: maxSecond.clamp(minSecond, 59).toInt(),
                onChanged: (v) => emitTime(h24, m, v),
              ),
              if (!use24Hour && !isDuration) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AM/PM',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      SizedBox(
                        height: 104,
                        child: CupertinoPicker(
                          itemExtent: 34,
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedPeriodIndex,
                          ),
                          onSelectedItemChanged: (index) => emitTime(
                            (h12 % 12) + (validPeriods[index] ? 12 : 0),
                            m,
                            sec,
                          ),
                          children: validPeriods
                              .map(
                                (pm) => Center(child: Text(pm ? 'PM' : 'AM')),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) {
          dialogClockTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted || !dialogContext.mounted) return;
            final freshNow = DateTime.now();
            final freshSeconds =
                freshNow.hour * 3600 + freshNow.minute * 60 + freshNow.second;
            final nextMinuteSeconds = (freshSeconds ~/ 60 + 1) * 60;
            refreshDialog(() {
              now = freshNow;
              if (activeMode == 'Auto' && existing == null) {
                final earliestStart = math
                    .max(nextMinuteSeconds, parentStartSeconds)
                    .clamp(parentStartSeconds, parentEndSeconds - 1)
                    .toInt();
                if (startSeconds < earliestStart) startSeconds = earliestStart;
                if (useEndTime) {
                  final earliestEnd = math
                      .max((startSeconds ~/ 60 + 1) * 60, nextMinuteSeconds)
                      .clamp(startSeconds + 1, parentEndSeconds)
                      .toInt();
                  if (endSeconds < earliestEnd) endSeconds = earliestEnd;
                  durationSeconds = (endSeconds - startSeconds)
                      .clamp(1, math.max(1, parentEndSeconds - startSeconds))
                      .toInt();
                } else {
                  final maxDuration = maxDurationForStart(startSeconds);
                  durationSeconds = durationSeconds
                      .clamp(1, maxDuration)
                      .toInt();
                  endSeconds = startSeconds + durationSeconds;
                }
              }
            });
          });
          return AlertDialog(
            title: Text(
              existing == null
                  ? (parent == null ? 'Add task' : 'Add subtask')
                  : 'Edit task',
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTaskBreadcrumb(parent, existing: existing),
                    _TaskTimePreview(
                      key: ValueKey(
                        'task-preview-${startSeconds}-${endSeconds}-${use24Hour}',
                      ),
                      title: parent == null
                          ? '24-hour task timeline'
                          : '${parent.title} timeline',
                      rangeStartSeconds: parent == null
                          ? 0
                          : parent.startMinute * 60,
                      rangeEndSeconds: parent == null
                          ? 86399
                          : math.min(parent.endMinute * 60, 86399),
                      selectedStartSeconds: startSeconds,
                      selectedEndSeconds: endSeconds,
                      occupied: (parent?.children ?? currentTasks)
                          .where((task) => !identical(task, existing))
                          .toList(),
                      use24Hour: use24Hour,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Topic / task name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    timePicker(
                      label: 'Start time',
                      seconds: startSeconds,
                      maxSeconds: parent == null ? 86399 : parentEndSeconds - 1,
                      minSeconds: activeMode == 'Auto' && existing == null
                          ? math.max(
                              parentStartSeconds,
                              ((DateTime.now().hour * 3600 +
                                              DateTime.now().minute * 60 +
                                              DateTime.now().second) ~/
                                          60 +
                                      1) *
                                  60,
                            )
                          : (parent == null ? 0 : parentStartSeconds),
                      onChanged: (v) => refreshDialog(() {
                        final freshNow = DateTime.now();
                        final currentSeconds =
                            freshNow.hour * 3600 +
                            freshNow.minute * 60 +
                            freshNow.second;
                        final minimumStart =
                            activeMode == 'Auto' && existing == null
                            ? math.max(
                                parentStartSeconds,
                                (currentSeconds ~/ 60 + 1) * 60,
                              )
                            : parentStartSeconds;
                        startSeconds = v
                            .clamp(minimumStart, parentEndSeconds - 1)
                            .toInt();
                        if (useEndTime) {
                          final nextMinute = (currentSeconds ~/ 60 + 1) * 60;
                          final minimumEnd =
                              activeMode == 'Auto' && existing == null
                              ? math
                                    .max(
                                      (startSeconds ~/ 60 + 1) * 60,
                                      nextMinute,
                                    )
                                    .clamp(startSeconds + 1, parentEndSeconds)
                                    .toInt()
                              : (startSeconds + 1)
                                    .clamp(startSeconds + 1, parentEndSeconds)
                                    .toInt();
                          if (endSeconds < minimumEnd) endSeconds = minimumEnd;
                          if (endSeconds > parentEndSeconds)
                            endSeconds = parentEndSeconds;
                          durationSeconds = (endSeconds - startSeconds)
                              .clamp(
                                1,
                                math.max(1, parentEndSeconds - startSeconds),
                              )
                              .toInt();
                        } else {
                          final maxDuration = maxDurationForStart(startSeconds);
                          durationSeconds = durationSeconds
                              .clamp(1, maxDuration)
                              .toInt();
                          endSeconds = startSeconds + durationSeconds;
                        }
                      }),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Set end time')),
                        ButtonSegment(
                          value: false,
                          label: Text('Set duration'),
                        ),
                      ],
                      selected: {useEndTime},
                      showSelectedIcon: false,
                      onSelectionChanged: (values) => refreshDialog(() {
                        useEndTime = values.first;
                        final maxDuration = maxDurationForStart(startSeconds);
                        if (!useEndTime) {
                          durationSeconds = (endSeconds - startSeconds)
                              .clamp(1, maxDuration)
                              .toInt();
                          endSeconds = startSeconds + durationSeconds;
                        } else {
                          durationSeconds = durationSeconds
                              .clamp(1, maxDuration)
                              .toInt();
                          endSeconds = (startSeconds + durationSeconds)
                              .clamp(startSeconds + 1, parentEndSeconds)
                              .toInt();
                          durationSeconds = endSeconds - startSeconds;
                        }
                      }),
                    ),
                    const SizedBox(height: 8),
                    if (useEndTime)
                      timePicker(
                        label: 'End time',
                        seconds: endSeconds,
                        maxSeconds: parent == null ? 86399 : parentEndSeconds,
                        minSeconds: activeMode == 'Auto' && existing == null
                            ? math
                                  .max(
                                    (startSeconds ~/ 60 + 1) * 60,
                                    (now.hour * 60 + now.minute + 1) * 60,
                                  )
                                  .clamp(startSeconds + 1, parentEndSeconds)
                                  .toInt()
                            : startSeconds + 1,
                        onChanged: (v) => refreshDialog(() {
                          final freshNow = DateTime.now();
                          final currentSeconds =
                              freshNow.hour * 3600 +
                              freshNow.minute * 60 +
                              freshNow.second;
                          final minimumEnd =
                              activeMode == 'Auto' && existing == null
                              ? math
                                    .max(
                                      (startSeconds ~/ 60 + 1) * 60,
                                      (currentSeconds ~/ 60 + 1) * 60,
                                    )
                                    .clamp(startSeconds + 1, parentEndSeconds)
                                    .toInt()
                              : (startSeconds + 1)
                                    .clamp(startSeconds + 1, parentEndSeconds)
                                    .toInt();
                          endSeconds = v
                              .clamp(minimumEnd, parentEndSeconds)
                              .toInt();
                          durationSeconds = (endSeconds - startSeconds)
                              .clamp(1, 86399)
                              .toInt();
                        }),
                      )
                    else
                      timePicker(
                        label: 'Duration (H:M:S)',
                        seconds: durationSeconds,
                        maxSeconds: maxDurationForStart(startSeconds),
                        minSeconds: 1,
                        isDuration: true,
                        onChanged: (v) => refreshDialog(() {
                          final maxDuration = maxDurationForStart(startSeconds);
                          durationSeconds = v.clamp(1, maxDuration).toInt();
                          endSeconds = (startSeconds + durationSeconds)
                              .clamp(startSeconds + 1, parentEndSeconds)
                              .toInt();
                          durationSeconds = endSeconds - startSeconds;
                        }),
                      ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Reminder / Alarm'),
                      subtitle: const Text('Notify before this task ends'),
                      value: alarmEnabled,
                      onChanged: (value) =>
                          refreshDialog(() => alarmEnabled = value),
                    ),
                    if (alarmEnabled) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Text('Notify before end')),
                          const SizedBox(width: 12),
                          DropdownButton<int>(
                            value: bounded(
                              (alarmLeadSeconds / 60).round(),
                              1,
                              10,
                            ),
                            items: List<DropdownMenuItem<int>>.generate(
                              10,
                              (index) => DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text('${index + 1} min'),
                              ),
                            ),
                            onChanged: (minutes) {
                              if (minutes != null) {
                                refreshDialog(
                                  () => alarmLeadSeconds = minutes * 60,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      Text(
                        'Notification name: ${titleController.text.trim().isEmpty ? 'Task / subtask' : titleController.text.trim()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  final start = startSeconds ~/ 60;
                  final maxDurationAtSave = maxDurationForStart(startSeconds);
                  if (!useEndTime && durationSeconds > maxDurationAtSave) {
                    refreshDialog(() {
                      durationSeconds = maxDurationAtSave;
                      endSeconds = startSeconds + durationSeconds;
                      validationError = 'Duration was limited to the time remaining before 23:59:59. Review and save again.';
                    });
                    return;
                  }
                  final endInSeconds = useEndTime
                      ? endSeconds
                      : startSeconds + durationSeconds;
                  final end = (endInSeconds / 60).ceil();
                  if (title.isEmpty) {
                    refreshDialog(() => validationError = 'Enter a task name.');
                    return;
                  }
                  if (durationSeconds <= 0 ||
                      endInSeconds <= startSeconds ||
                      endInSeconds > 86399) {
                    refreshDialog(
                      () => validationError =
                          'Choose a valid time range within this day.',
                    );
                    return;
                  }
                  if (activeMode == 'Auto') {
                    final saveNow = DateTime.now();
                    final saveNowSeconds =
                        saveNow.hour * 3600 +
                        saveNow.minute * 60 +
                        saveNow.second;
                    final earliestAllowedStart = math.max(
                      parentStartSeconds,
                      (saveNowSeconds ~/ 60 + 1) * 60,
                    );
                    if (existing == null &&
                        startSeconds < earliestAllowedStart) {
                      refreshDialog(() {
                        startSeconds = earliestAllowedStart
                            .clamp(parentStartSeconds, parentEndSeconds - 1)
                            .toInt();
                        final nextEndMinute = math
                            .max(
                              (startSeconds ~/ 60 + 1) * 60,
                              earliestAllowedStart,
                            )
                            .clamp(startSeconds + 1, parentEndSeconds)
                            .toInt();
                        if (endSeconds < nextEndMinute)
                          endSeconds = nextEndMinute;
                        durationSeconds = (endSeconds - startSeconds)
                            .clamp(1, 86399)
                            .toInt();
                        validationError = 'Start time must be at least the next full minute. It has been updated; review and save again.';
                      });
                      return;
                    }
                    if (existing == null && useEndTime) {
                      final earliestAllowedEndMinute = math.max(
                        startSeconds ~/ 60 + 1,
                        saveNowSeconds ~/ 60 + 1,
                      );
                      if (end < earliestAllowedEndMinute) {
                        refreshDialog(() {
                          endSeconds = (earliestAllowedEndMinute * 60)
                              .clamp(startSeconds + 1, parentEndSeconds)
                              .toInt();
                          durationSeconds = (endSeconds - startSeconds)
                              .clamp(1, 86399)
                              .toInt();
                          validationError = 'End time must be in a future minute and after the start time. It has been updated; review and save again.';
                        });
                        return;
                      }
                    }
                    if (existing != null && _isTaskLockedForChanges(existing)) {
                      refreshDialog(
                        () => validationError = 'This task is locked in Auto Mode because its time has ended.',
                      );
                      return;
                    }
                    if (existing != null &&
                        existing.startMinute * 60 < _elapsedSeconds &&
                        start != existing.startMinute) {
                      refreshDialog(
                        () => validationError = 'In Auto Mode, a running task start time cannot be changed. Extend only its future end time.',
                      );
                      return;
                    }
                    if (existing != null &&
                        existing.startMinute * 60 < _elapsedSeconds &&
                        endInSeconds <= _elapsedSeconds) {
                      refreshDialog(
                        () => validationError = 'A running task can only be extended to a future end time.',
                      );
                      return;
                    }
                  }
                  final siblings = parent?.children ?? currentTasks;
                  final overlaps = siblings.any((other) {
                    if (identical(other, existing)) return false;
                    return start < other.endMinute && other.startMinute < end;
                  });
                  if (overlaps) {
                    refreshDialog(
                      () => validationError =
                          'This time overlaps another task at the same level.',
                    );
                    return;
                  }
                  // Apply the same parent-boundary rule at every nesting level.
                  if (parent != null &&
                      (startSeconds < parent.startMinute * 60 ||
                          endInSeconds > parent.endMinute * 60)) {
                    refreshDialog(
                      () => validationError =
                          'Choose a time entirely within ${parent.title} (${_formatMinute(parent.startMinute, use24Hour: use24Hour)}–${_formatMinute(parent.endMinute, use24Hour: use24Hour)}).',
                    );
                    return;
                  }
                  if (parent != null &&
                      (start < parent.startMinute || end > parent.endMinute)) {
                    refreshDialog(
                      () => validationError =
                          'A subtask must fit within its parent task time.',
                    );
                    return;
                  }
                  bool descendantsFit(TaskNode node) {
                    for (final child in node.children) {
                      if (start > child.startMinute ||
                          end < child.endMinute ||
                          !descendantsFit(child)) {
                        return false;
                      }
                    }
                    return true;
                  }

                  if (existing != null && !descendantsFit(existing)) {
                    refreshDialog(
                      () => validationError = 'The parent time range must contain every subtask and nested subtask.',
                    );
                    return;
                  }
                  setState(() {
                    if (existing != null) {
                      existing.title = title;
                      existing.startMinute = start;
                      existing.endMinute = end;
                      existing.alarmEnabled = alarmEnabled;
                      existing.alarmLeadSeconds = alarmLeadSeconds;
                    } else {
                      siblings.add(
                        TaskNode(
                          title: title,
                          startMinute: start,
                          endMinute: end,
                          alarmEnabled: alarmEnabled,
                          alarmLeadSeconds: alarmLeadSeconds,
                        ),
                      );
                    }
                    if (parent != null) _syncAncestors(parent);
                  });
                  Navigator.pop(dialogContext);
                  _saveRoutineTasks().catchError((Object error) {
                    debugPrint('Could not save routine tasks: $error');
                  });
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() => dialogClockTimer?.cancel());
  }

  int _completedLeafSeconds(List<TaskNode> nodes) {
    var seconds = 0;
    for (final task in nodes) {
      if (task.children.isEmpty) {
        if (task.done) seconds += task.durationMinutes * 60;
      } else {
        seconds += _completedLeafSeconds(task.children);
      }
    }
    return seconds;
  }

  List<TimeInterval> _checkedLeafIntervals(List<TaskNode> nodes) {
    final intervals = <TimeInterval>[];
    for (final task in nodes) {
      if (task.children.isEmpty) {
        if (task.done && task.endMinute > task.startMinute) {
          intervals.add(
            TimeInterval(task.startMinute * 60, task.endMinute * 60),
          );
        }
      } else {
        intervals.addAll(_checkedLeafIntervals(task.children));
      }
    }
    intervals.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    return intervals;
  }

  int _activeElapsedSeconds(List<TimeInterval> intervals, int elapsedSeconds) {
    final cutoff = elapsedSeconds.clamp(0, 86400).toInt();
    var total = 0;
    var mergedStart = -1;
    var mergedEnd = -1;
    for (final interval in intervals) {
      final start = interval.startSeconds.clamp(0, cutoff).toInt();
      final end = interval.endSeconds.clamp(0, cutoff).toInt();
      if (end <= start) continue;
      if (mergedStart < 0) {
        mergedStart = start;
        mergedEnd = end;
      } else if (start <= mergedEnd) {
        mergedEnd = math.max(mergedEnd, end).toInt();
      } else {
        total += mergedEnd - mergedStart;
        mergedStart = start;
        mergedEnd = end;
      }
    }
    if (mergedStart >= 0) total += mergedEnd - mergedStart;
    return total;
  }

  void _showHistoryNotice() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Historical Details'),
        content: SizedBox(
          width: double.maxFinite,
          child: _savedHistory.isEmpty
              ? const Text('No saved daily records yet.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _savedHistory.length,
                  itemBuilder: (context, index) {
                    final record = _savedHistory[_savedHistory.length - 1 - index];
                    final dateLabel =
                        '${record.date.year.toString().padLeft(4, '0')}-'
                        '${record.date.month.toString().padLeft(2, '0')}-'
                        '${record.date.day.toString().padLeft(2, '0')}';
                    return ListTile(
                      dense: true,
                      title: Text(dateLabel),
                      subtitle: Text('Mode: ${record.mode}'),
                      trailing: Text('${record.progress.toStringAsFixed(2)}%'),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// Sort only the displayed list by start time; preserve original data and mode isolation.
List<TaskNode> _sortedTasks(List<TaskNode> tasks) {
  final sorted = List<TaskNode>.of(tasks);
  sorted.sort((a, b) {
    final byStart = a.startMinute.compareTo(b.startMinute);
    if (byStart != 0) return byStart;
    return a.endMinute.compareTo(b.endMinute);
  });
  return sorted;
}

List<SampleDay> _buildSampleHistory(DateTime today) {
  // Illustrative 42-day history so chart navigation can be exercised before
  // real persisted history is connected.
  const progress = <double>[
    18,
    42,
    30,
    55,
    0,
    65,
    48,
    25,
    72,
    36,
    51,
    14,
    63,
    44,
    28,
    80,
    33,
    57,
    21,
    68,
    40,
    12,
    75,
    47,
    31,
    59,
    23,
    85,
    38,
    53,
    16,
    66,
    45,
    27,
    70,
    34,
    62,
    19,
    49,
    76,
    41,
    58,
  ];
  return List<SampleDay>.generate(progress.length, (i) {
    final day = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: progress.length - 1 - i));
    final mode = i % 4 == 2 || i % 7 == 5 ? 'Manual' : 'Auto';
    return SampleDay(day, progress[i], mode);
  });
}

class _TaskTimePreview extends StatefulWidget {
  const _TaskTimePreview({
    super.key,
    required this.title,
    required this.rangeStartSeconds,
    required this.rangeEndSeconds,
    required this.selectedStartSeconds,
    required this.selectedEndSeconds,
    required this.occupied,
    required this.use24Hour,
  });

  final String title;
  final int rangeStartSeconds;
  final int rangeEndSeconds;
  final int selectedStartSeconds;
  final int selectedEndSeconds;
  final List<TaskNode> occupied;
  final bool use24Hour;

  @override
  State<_TaskTimePreview> createState() => _TaskTimePreviewState();
}

class _TaskTimePreviewState extends State<_TaskTimePreview> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _rangeEndLabel(int seconds) {
    if (seconds >= 86399) return widget.use24Hour ? '23:59:59' : '11:59:59 PM';
    return _clock(seconds);
  }

  String _clock(int seconds) {
    final safe = seconds.clamp(0, 86400);
    final h24 = (safe ~/ 3600) % 24;
    final minute = (safe % 3600) ~/ 60;
    final second = safe % 60;
    if (widget.use24Hour) {
      return '${h24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
    }
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '${h12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')} ${h24 >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final rangeStartSeconds = widget.rangeStartSeconds;
    final rangeEndSeconds = widget.rangeEndSeconds;
    final span = math.max(1, rangeEndSeconds - rangeStartSeconds);
    final start = widget.selectedStartSeconds
        .clamp(rangeStartSeconds, rangeEndSeconds)
        .toInt();
    final end = widget.selectedEndSeconds.clamp(start, rangeEndSeconds).toInt();
    final theme = Theme.of(context);
    const red = Color(0xFFE65A52);
    const pink = Color(0xFFE86AB3);
    final green = kGreen;
    final neutral = theme.colorScheme.onSurface.withValues(alpha: 0.12);
    double leftFor(int seconds) =>
        ((seconds - rangeStartSeconds) / span).clamp(0.0, 1.0);
    double widthFor(int a, int b) => ((b - a) / span).clamp(0.0, 1.0);
    final visibleOccupied = widget.occupied
        .where(
          (t) =>
              t.endMinute * 60 > rangeStartSeconds &&
              t.startMinute * 60 < rangeEndSeconds,
        )
        .toList();
    final nowSeconds = _now.hour * 3600 + _now.minute * 60 + _now.second;
    final showCurrentMarker =
        nowSeconds >= rangeStartSeconds && nowSeconds <= rangeEndSeconds;
    final markerFraction = leftFor(nowSeconds);
    final currentLabel = _formatClock(_now, widget.use24Hour);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _clock(rangeStartSeconds),
                style: theme.textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                _rangeEndLabel(rangeEndSeconds),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 65,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final markerX = (markerFraction * w).clamp(0.0, w).toDouble();
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 43,
                      height: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: neutral,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    if (end > start)
                      Positioned(
                        left: leftFor(start) * w,
                        width: math.max(2.0, widthFor(start, end) * w),
                        top: 43,
                        height: 18,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: pink,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ...visibleOccupied.map((task) {
                      final a = math
                          .max(rangeStartSeconds, task.startMinute * 60)
                          .toInt();
                      final b = math
                          .min(rangeEndSeconds, task.endMinute * 60)
                          .toInt();
                      if (b <= a) return const SizedBox.shrink();
                      return Positioned(
                        left: leftFor(a) * w,
                        width: math.max(2.0, widthFor(a, b) * w),
                        top: 43,
                        height: 18,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: red,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      );
                    }),
                    if (showCurrentMarker) ...[
                      Positioned(
                        left: (markerX - 1)
                            .clamp(0.0, math.max(0.0, w - 2))
                            .toDouble(),
                        top: 32,
                        bottom: 0,
                        width: 3,
                        child: ColoredBox(color: Colors.white),
                      ),
                      Positioned(
                        left: (markerX - (currentLabel.length * 3.1 + 8))
                            .clamp(
                              0.0,
                              math.max(
                                0.0,
                                w - (currentLabel.length * 6.2 + 16),
                              ),
                            )
                            .toDouble(),
                        top: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF414B46),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Text(
                            currentLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            children: [
              _previewLegend(red, 'Reserved'),
              _previewLegend(pink, 'Selected'),
              _previewLegend(green, 'Available'),
            ],
          ),
          if (visibleOccupied.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...visibleOccupied.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: red,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_clock(task.startMinute * 60)}–${_clock(task.endMinute * 60)}  ${task.title}',
                        style: theme.textTheme.labelSmall,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${_clock(start)}–${_clock(end)}  ${visibleOccupied.isEmpty ? 'Selected interval' : 'New interval'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: pink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewLegend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  );
}

class DayTimelinePainter extends CustomPainter {
  DayTimelinePainter({
    required this.elapsedSeconds,
    required this.activeIntervals,
    required this.currentTimeLabel,
    required this.use24Hour,
    required this.inactiveColor,
    required this.activeColor,
    required this.futureColor,
    required this.markerColor,
    required this.labelColor,
    required this.bubbleColor,
  });

  final int elapsedSeconds;
  final List<TimeInterval> activeIntervals;
  final String currentTimeLabel;
  final bool use24Hour;
  final Color inactiveColor;
  final Color activeColor;
  final Color futureColor;
  final Color markerColor;
  final Color labelColor;
  final Color bubbleColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const horizontalInset = 3.0;
    const bubbleTop = 1.0;
    const barTop = 27.0;
    const barHeight = 13.0;
    const labelsTop = 45.0;
    final barLeft = horizontalInset;
    final barWidth = math.max(1.0, size.width - horizontalInset * 2).toDouble();
    final barRight = barLeft + barWidth;
    final elapsed = elapsedSeconds.clamp(0, 86400).toInt();
    double xAt(int seconds) => barLeft + barWidth * seconds / 86400.0;
    final barRect = Rect.fromLTWH(barLeft, barTop, barWidth, barHeight);
    final radius = Radius.circular(barHeight / 2);

    // Future time is neutral. The elapsed portion starts red, then completed
    // intervals are overpainted green. This naturally updates as the clock moves.
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, radius),
      Paint()..color = futureColor,
    );
    if (elapsed > 0) {
      final elapsedRect = Rect.fromLTRB(
        barLeft,
        barTop,
        xAt(elapsed),
        barTop + barHeight,
      );
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(barRect, radius));
      canvas.drawRect(elapsedRect, Paint()..color = inactiveColor);
      for (final interval in activeIntervals) {
        final start = interval.startSeconds.clamp(0, elapsed).toInt();
        final end = interval.endSeconds.clamp(0, elapsed).toInt();
        if (end <= start) continue;
        canvas.drawRect(
          Rect.fromLTRB(xAt(start), barTop, xAt(end), barTop + barHeight),
          Paint()..color = activeColor,
        );
      }
      canvas.restore();
    }

    // Current time marker across the timeline, including a small pointer dot.
    final markerX = xAt(elapsed);
    canvas.drawLine(
      Offset(markerX, barTop - 5),
      Offset(markerX, barTop + barHeight + 8),
      Paint()
        ..color = markerColor
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(markerX, barTop + barHeight / 2),
      3.2,
      Paint()..color = markerColor,
    );

    final bubbleText = TextPainter(
      text: TextSpan(
        text: currentTimeLabel,
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const bubblePaddingX = 6.0;
    const bubblePaddingY = 3.0;
    final bubbleWidth = bubbleText.width + bubblePaddingX * 2;
    final bubbleHeight = bubbleText.height + bubblePaddingY * 2;
    final bubbleLeft = (markerX - bubbleWidth / 2)
        .clamp(0.0, math.max(0.0, size.width - bubbleWidth))
        .toDouble();
    final bubbleRect = Rect.fromLTWH(
      bubbleLeft,
      bubbleTop,
      bubbleWidth,
      bubbleHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect, const Radius.circular(5)),
      Paint()..color = bubbleColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect, const Radius.circular(5)),
      Paint()
        ..color = labelColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    bubbleText.paint(
      canvas,
      Offset(bubbleLeft + bubblePaddingX, bubbleTop + bubblePaddingY),
    );

    final ticks = <int>[0, 21600, 43200, 64800, 86400];
    for (int i = 0; i < ticks.length; i++) {
      final minute = ticks[i] ~/ 60;
      final tickLabel = _formatMinute(minute, use24Hour: use24Hour);
      final tp = TextPainter(
        text: TextSpan(
          text: tickLabel,
          style: TextStyle(color: labelColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var x = xAt(ticks[i]);
      if (i == 0) {
        x = barLeft;
      } else if (i == ticks.length - 1) {
        x = barRight - tp.width;
      } else {
        x -= tp.width / 2;
      }
      canvas.drawLine(
        Offset(xAt(ticks[i]), barTop + barHeight + 1),
        Offset(xAt(ticks[i]), barTop + barHeight + 5),
        Paint()
          ..color = labelColor.withValues(alpha: 0.55)
          ..strokeWidth = 0.8,
      );
      tp.paint(canvas, Offset(x, labelsTop));
    }
  }

  @override
  bool shouldRepaint(covariant DayTimelinePainter oldDelegate) => true;
}

class _InteractiveCumulativeChart extends StatefulWidget {
  const _InteractiveCumulativeChart({
    super.key,
    required this.candles,
    required this.days,
    required this.labelColor,
    required this.gridColor,
    required this.bodyColor,
    this.expandToParent = false,
    this.initialRecentFiveDays = false,
  });

  final bool candles;
  final List<SampleDay> days;
  final Color labelColor;
  final Color gridColor;
  final Color bodyColor;
  final bool expandToParent;
  final bool initialRecentFiveDays;

  @override
  State<_InteractiveCumulativeChart> createState() =>
      _InteractiveCumulativeChartState();
}

class _InteractiveCumulativeChartState
    extends State<_InteractiveCumulativeChart> {
  // Keep date and value axes outside the plot's pan/zoom transform.
  static const double _dayWidth = 38.0;
  static const double _yAxisWidth = 42.0;
  static const double _rightScaleWidth = 62.0;
  static const double _xAxisHeight = 30.0;
  static const double _minZoomX = 0.35;
  static const double _maxZoomX = 4.0;
  static const double _minZoomY = 0.50;
  static const double _maxZoomY = 32.0;

  double _zoomX = 1.0;
  double _zoomY = 1.0;
  double _panX = 0.0;
  double _panY = 0.0;
  double _lastPlotWidth = 0.0;
  double _lastPlotHeight = 0.0;
  bool _initialRecentApplied = false;

  @override
  void initState() {
    super.initState();
    _initialRecentApplied = !widget.initialRecentFiveDays;
  }

  double _clampPanX(double value, double viewportWidth) {
    final contentWidth = widget.days.length * _dayWidth * _zoomX;
    if (contentWidth <= viewportWidth) {
      return (viewportWidth - contentWidth) / 2;
    }
    return value.clamp(viewportWidth - contentWidth, 0.0).toDouble();
  }

  double _clampPanY(double value, double viewportHeight) {
    final contentHeight = viewportHeight * _zoomY;
    // The date strip is separate, so only the plot moves vertically.
    final panMargin = viewportHeight * 0.45;
    final minPan = math
        .min(viewportHeight - contentHeight, -panMargin)
        .toDouble();
    final maxPan = math.max(0.0, panMargin).toDouble();
    return value.clamp(minPan, maxPan).toDouble();
  }

  void showRecentFiveDays() {
    final viewportWidth = _lastPlotWidth;
    final viewportHeight = _lastPlotHeight;
    if (!mounted || viewportWidth <= 0 || viewportHeight <= 0) return;

    // Fit the visible five-day window vertically as well as horizontally.
    // The previous reset only changed X zoom and reset Y to 0..globalMax,
    // which left recent cumulative candles compressed near the top/bottom.
    final axis = _cumulativeAxisRange(widget.days);
    final firstVisibleIndex = math.max(0, widget.days.length - 5).toInt();
    var cumulative = 0.0;
    var visibleMin = double.infinity;
    var visibleMax = double.negativeInfinity;
    for (var i = 0; i < widget.days.length; i++) {
      final open = cumulative;
      final close = cumulative + widget.days[i].progress;
      final high = widget.candles ? open + 100.0 : close;
      if (i >= firstVisibleIndex) {
        visibleMin = math.min(visibleMin, math.min(open, close)).toDouble();
        visibleMax = math
            .max(visibleMax, math.max(high, math.max(open, close)))
            .toDouble();
      }
      cumulative = close;
    }
    if (!visibleMin.isFinite || !visibleMax.isFinite) {
      visibleMin = 0.0;
      visibleMax = axis.maxValue;
    }

    final rawSpan = math.max(1.0, visibleMax - visibleMin).toDouble();
    // Snap the fitted range to readable cumulative-point boundaries so the
    // candles, current-point line, grid, and Y-axis labels all share one scale.
    final fitTickStep = _niceTickStep(rawSpan / 5.0);
    final paddedMin = math
        .max(0.0, (visibleMin / fitTickStep).floor() * fitTickStep)
        .toDouble();
    var paddedMax = (visibleMax / fitTickStep).ceil() * fitTickStep;
    if (paddedMax <= paddedMin) paddedMax = paddedMin + fitTickStep;

    final baseTop = _baseChartY(paddedMax, axis.maxValue, viewportHeight);
    final baseBottom = _baseChartY(paddedMin, axis.maxValue, viewportHeight);
    final baseSpan = math.max(1.0, baseBottom - baseTop).toDouble();
    // Fit the snapped range into about 76% of the plot, with top/bottom margin.
    const targetTopFraction = 0.12;
    const targetBottomFraction = 0.88;
    final targetSpan =
        viewportHeight * (targetBottomFraction - targetTopFraction);
    final fittedZoomY = (targetSpan / baseSpan)
        .clamp(_minZoomY, _maxZoomY)
        .toDouble();
    final fittedPanY =
        viewportHeight * targetTopFraction - baseTop * fittedZoomY;

    setState(() {
      _zoomX = (viewportWidth / (5 * _dayWidth))
          .clamp(_minZoomX, _maxZoomX)
          .toDouble();
      _zoomY = fittedZoomY;
      _panY = _clampPanY(fittedPanY, viewportHeight);
      final contentWidth = widget.days.length * _dayWidth * _zoomX;
      _panX = _clampPanX(viewportWidth - contentWidth, viewportWidth);
    });
  }

  void openFullscreen() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _CumulativeChartFullscreenPage(
          candles: widget.candles,
          days: widget.days,
          labelColor: widget.labelColor,
          gridColor: widget.gridColor,
          bodyColor: widget.bodyColor,
        ),
      ),
    );
  }

  void _onChartGestureUpdate(
    _ChartGestureUpdate details, {
    required double viewportWidth,
    required double viewportHeight,
  }) {
    setState(() {
      // Dragging the right-side value strip changes the vertical scale, like a
      // trading chart's price axis. Dragging the plot pans it; pinching zooms.
      if (details.verticalScaleGesture && details.scaleFactor == 1.0) {
        final deltaY = details.focalPoint.dy - details.previousFocalPoint.dy;
        final previousZoomY = _zoomY;
        _zoomY = (_zoomY * math.exp(-deltaY * 0.008))
            .clamp(_minZoomY, _maxZoomY)
            .toDouble();
        final ratioY = _zoomY / previousZoomY;
        _panY =
            details.focalPoint.dy -
            (details.previousFocalPoint.dy - _panY) * ratioY;
        _panY = _clampPanY(_panY, viewportHeight);
      } else {
        final previousZoomX = _zoomX;
        final previousZoomY = _zoomY;
        _zoomX = (_zoomX * details.scaleFactor)
            .clamp(_minZoomX, _maxZoomX)
            .toDouble();
        _zoomY = (_zoomY * details.scaleFactor)
            .clamp(_minZoomY, _maxZoomY)
            .toDouble();

        final ratioX = _zoomX / previousZoomX;
        final ratioY = _zoomY / previousZoomY;
        // Focal X may be in the right value strip; anchor zoom to plot's edge.
        final oldX = details.previousFocalPoint.dx
            .clamp(0.0, viewportWidth)
            .toDouble();
        final newX = details.focalPoint.dx.clamp(0.0, viewportWidth).toDouble();
        _panX = newX - (oldX - _panX) * ratioX;
        _panY =
            details.focalPoint.dy -
            (details.previousFocalPoint.dy - _panY) * ratioY;
        _panX = _clampPanX(_panX, viewportWidth);
        _panY = _clampPanY(_panY, viewportHeight);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final axis = _cumulativeAxisRange(widget.days);
    return SizedBox(
      // In fullscreen mode the parent Expanded supplies the finite height.
      // Leaving this unconstrained lets the chart fill that slot beneath the
      // threshold legend without requesting an infinite height.
      height: widget.expandToParent ? null : 310,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 310.0;
          final plotHeight = math
              .max(1.0, chartHeight - _xAxisHeight)
              .toDouble();
          final bodyWidth = math
              .max(1.0, constraints.maxWidth - _yAxisWidth)
              .toDouble();
          final plotWidth = math
              .max(1.0, bodyWidth - _rightScaleWidth)
              .toDouble();
          _lastPlotWidth = plotWidth;
          _lastPlotHeight = plotHeight;
          if (!_initialRecentApplied) {
            _initialRecentApplied = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) showRecentFiveDays();
            });
          }
          final visibleY = _visibleAxisRange(
            axis.maxValue,
            _zoomY,
            _panY,
            plotHeight,
          );
          final visibleSpan = visibleY.maxValue - visibleY.minValue;
          final displayTickStep = visibleSpan > 0
              ? _niceTickStep(visibleSpan / 10.0)
              : axis.tickStep;
          final currentPoint = _latestCumulativePoint(widget.days);
          return Column(
            children: [
              SizedBox(
                height: plotHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _yAxisWidth,
                      child: ClipRect(
                        child: CustomPaint(
                          painter: CumulativeYAxisPainter(
                            maxAxis: axis.maxValue,
                            tickStep: displayTickStep,
                            zoomY: _zoomY,
                            panY: _panY,
                            labelColor: widget.labelColor,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: RawGestureDetector(
                          behavior: HitTestBehavior.opaque,
                          gestures: <Type, GestureRecognizerFactory>{
                            _ChartPanZoomRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  _ChartPanZoomRecognizer
                                >(
                                  () =>
                                      _ChartPanZoomRecognizer(debugOwner: this),
                                  (instance) {
                                    instance.viewportWidth = bodyWidth;
                                    instance.verticalScaleBandWidth =
                                        _rightScaleWidth;
                                    instance.onUpdate = (details) =>
                                        _onChartGestureUpdate(
                                          details,
                                          viewportWidth: plotWidth,
                                          viewportHeight: plotHeight,
                                        );
                                  },
                                ),
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                right: _rightScaleWidth,
                                child: CustomPaint(
                                  painter: CumulativeChartPainter(
                                    candles: widget.candles,
                                    days: widget.days,
                                    labelColor: widget.labelColor,
                                    gridColor: widget.gridColor,
                                    bodyColor: widget.bodyColor,
                                    zoomX: _zoomX,
                                    zoomY: _zoomY,
                                    panX: _panX,
                                    panY: _panY,
                                    maxAxis: axis.maxValue,
                                    tickStep: displayTickStep,
                                    currentPoint: currentPoint,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                width: _rightScaleWidth,
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: CumulativeCurrentPointPainter(
                                      currentPoint: currentPoint,
                                      maxAxis: axis.maxValue,
                                      zoomY: _zoomY,
                                      panY: _panY,
                                      bodyColor: widget.bodyColor,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: _xAxisHeight,
                child: Row(
                  children: [
                    const SizedBox(width: _yAxisWidth),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRect(
                              child: CustomPaint(
                                painter: CumulativeXAxisPainter(
                                  days: widget.days,
                                  zoomX: _zoomX,
                                  panX: _panX,
                                  labelColor: widget.labelColor,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                          const SizedBox(width: _rightScaleWidth),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CumulativeChartFullscreenPage extends StatefulWidget {
  const _CumulativeChartFullscreenPage({
    required this.candles,
    required this.days,
    required this.labelColor,
    required this.gridColor,
    required this.bodyColor,
  });

  final bool candles;
  final List<SampleDay> days;
  final Color labelColor;
  final Color gridColor;
  final Color bodyColor;

  @override
  State<_CumulativeChartFullscreenPage> createState() =>
      _CumulativeChartFullscreenPageState();
}

class _CumulativeChartFullscreenPageState
    extends State<_CumulativeChartFullscreenPage> {
  final GlobalKey<_InteractiveCumulativeChartState> _chartKey =
      GlobalKey<_InteractiveCumulativeChartState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.candles ? 'Cumulative Candle Chart' : 'Cumulative Line Chart',
        ),
        actions: [
          IconButton(
            tooltip: 'Show recent 5 days',
            onPressed: () => _chartKey.currentState?.showRecentFiveDays(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              if (widget.candles) _candleThresholdLegend(context),
              if (widget.candles) const SizedBox(height: 6),
              Expanded(
                child: _InteractiveCumulativeChart(
                  key: _chartKey,
                  candles: widget.candles,
                  days: widget.days,
                  labelColor: widget.labelColor,
                  gridColor: widget.gridColor,
                  bodyColor: widget.bodyColor,
                  expandToParent: true,
                  initialRecentFiveDays: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartGestureUpdate {
  const _ChartGestureUpdate({
    required this.previousFocalPoint,
    required this.focalPoint,
    required this.scaleFactor,
    required this.verticalScaleGesture,
  });

  final Offset previousFocalPoint;
  final Offset focalPoint;
  final double scaleFactor;
  final bool verticalScaleGesture;
}

/// Captures touches that begin on the chart before the parent ListView can
/// claim vertical motion. Implements one-finger pan and multi-finger pinch
/// without separate pan/zoom buttons.
class _ChartPanZoomRecognizer extends OneSequenceGestureRecognizer {
  _ChartPanZoomRecognizer({super.debugOwner});

  void Function(_ChartGestureUpdate details)? onUpdate;
  double viewportWidth = 0.0;
  double verticalScaleBandWidth = 0.0;

  final Map<int, Offset> _positions = <int, Offset>{};
  Offset? _previousFocalPoint;
  double _previousSpread = 0.0;
  int _previousPointerCount = 0;
  bool _verticalScaleGesture = false;

  Offset _focalPoint() {
    if (_positions.isEmpty) return Offset.zero;
    var total = Offset.zero;
    for (final point in _positions.values) {
      total += point;
    }
    return total / _positions.length.toDouble();
  }

  double _spread(Offset focalPoint) {
    if (_positions.length < 2) return 0.0;
    var total = 0.0;
    for (final point in _positions.values) {
      total += (point - focalPoint).distance;
    }
    return total / _positions.length;
  }

  void _resetBaseline() {
    _previousFocalPoint = _focalPoint();
    _previousSpread = _spread(_previousFocalPoint!);
    _previousPointerCount = _positions.length;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final isFirstPointer = _positions.isEmpty;
    startTrackingPointer(event.pointer, event.transform);
    _positions[event.pointer] = event.localPosition;
    if (isFirstPointer) {
      _verticalScaleGesture =
          event.localPosition.dx >= viewportWidth - verticalScaleBandWidth;
    } else {
      _verticalScaleGesture = false;
    }
    _resetBaseline();
    // Claim every touch that starts in the chart, including the right-side
    // scale strip, before the parent Dashboard ListView can steal the drag.
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final previousFocal = _previousFocalPoint;
      final previousSpread = _previousSpread;
      final previousCount = _previousPointerCount;
      _positions[event.pointer] = event.localPosition;
      final focal = _focalPoint();
      final spread = _spread(focal);
      var scaleFactor = 1.0;
      if (_positions.length >= 2 &&
          _positions.length == previousCount &&
          previousSpread > 0.0) {
        scaleFactor = spread / previousSpread;
      }
      if (previousFocal != null) {
        onUpdate?.call(
          _ChartGestureUpdate(
            previousFocalPoint: previousFocal,
            focalPoint: focal,
            scaleFactor: scaleFactor,
            verticalScaleGesture:
                _positions.length == 1 && _verticalScaleGesture,
          ),
        );
      }
      _previousFocalPoint = focal;
      _previousSpread = spread;
      _previousPointerCount = _positions.length;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _positions.remove(event.pointer);
      stopTrackingPointer(event.pointer);
      if (_positions.isEmpty) {
        _previousFocalPoint = null;
        _previousSpread = 0.0;
        _previousPointerCount = 0;
      } else {
        // A remaining finger after a pinch should pan, not keep scaling the axis.
        _verticalScaleGesture = false;
        _resetBaseline();
      }
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (_positions.containsKey(pointer)) {
      _positions.remove(pointer);
      stopTrackingPointer(pointer);
      if (_positions.isEmpty) {
        _previousFocalPoint = null;
        _previousSpread = 0.0;
        _previousPointerCount = 0;
        _verticalScaleGesture = false;
      } else {
        _verticalScaleGesture = false;
        _resetBaseline();
      }
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'chartPanZoom';
}

class _CumulativeAxisRange {
  const _CumulativeAxisRange(this.maxValue, this.tickStep);
  final double maxValue;
  final double tickStep;
}

_CumulativeAxisRange _cumulativeAxisRange(List<SampleDay> days) {
  var cumulative = 0.0;
  var maxValue = 100.0;
  for (final day in days) {
    maxValue = math.max(maxValue, cumulative + 100.0).toDouble();
    cumulative += day.progress;
    maxValue = math.max(maxValue, cumulative).toDouble();
  }
  var tickStep = 100.0;
  while (maxValue / tickStep > 8) {
    tickStep *= 2;
  }
  final axisMax = ((maxValue / tickStep).ceil() * tickStep).toDouble();
  return _CumulativeAxisRange(axisMax, tickStep);
}

double _latestCumulativePoint(List<SampleDay> days) {
  var total = 0.0;
  for (final day in days) {
    total += day.progress;
  }
  return total;
}

String _formatPointValue(double value) {
  final raw = value.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
    out.write(raw[i]);
  }
  return out.toString();
}

double _baseChartY(double value, double maxAxis, double height) {
  const topInset = 12.0;
  const bottomInset = 12.0;
  final drawableHeight = math
      .max(1.0, height - topInset - bottomInset)
      .toDouble();
  return height - bottomInset - (value / maxAxis) * drawableHeight;
}

class _VisibleAxisRange {
  const _VisibleAxisRange(this.minValue, this.maxValue);
  final double minValue;
  final double maxValue;
}

// Convert the current pan/zoom transform back into the cumulative values that
// are actually visible in the plot viewport. Axis labels and grid lines must
// use this range; scaling only the candle pixels makes labels disagree with data.
_VisibleAxisRange _visibleAxisRange(
  double maxAxis,
  double zoomY,
  double panY,
  double height,
) {
  const topInset = 12.0;
  const bottomInset = 12.0;
  final drawableHeight = math
      .max(1.0, height - topInset - bottomInset)
      .toDouble();
  final safeZoom = zoomY.clamp(0.01, 100.0).toDouble();

  double valueAt(double screenY) {
    final baseY = (screenY - panY) / safeZoom;
    return maxAxis * (height - bottomInset - baseY) / drawableHeight;
  }

  final atTop = valueAt(0.0);
  final atBottom = valueAt(height);
  final minValue = math.max(0.0, math.min(atTop, atBottom)).toDouble();
  final maxValue = math
      .max(minValue + 1.0, math.max(atTop, atBottom))
      .toDouble();
  return _VisibleAxisRange(minValue, maxValue);
}

double _niceTickStep(double rawStep) {
  if (!rawStep.isFinite || rawStep <= 0) return 1.0;
  final exponent = (math.log(rawStep) / math.ln10).floor();
  final magnitude = math.pow(10.0, exponent).toDouble();
  final normalized = rawStep / magnitude;
  const choices = <double>[1.0, 2.0, 2.5, 4.0, 5.0, 10.0];
  var selected = choices.last;
  for (final choice in choices) {
    if (normalized <= choice) {
      selected = choice;
      break;
    }
  }
  return selected * magnitude;
}

class CumulativeChartPainter extends CustomPainter {
  CumulativeChartPainter({
    required this.candles,
    required this.days,
    required this.labelColor,
    required this.gridColor,
    required this.bodyColor,
    required this.zoomX,
    required this.zoomY,
    required this.panX,
    required this.panY,
    required this.maxAxis,
    required this.tickStep,
    required this.currentPoint,
  });

  final bool candles;
  final List<SampleDay> days;
  final Color labelColor;
  final Color gridColor;
  final Color bodyColor;
  final double zoomX;
  final double zoomY;
  final double panX;
  final double panY;
  final double maxAxis;
  final double tickStep;
  final double currentPoint;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty || size.width <= 1 || size.height <= 1) return;
    final axisMax = maxAxis <= 0 ? 100.0 : maxAxis;
    double yFor(double value) =>
        _baseChartY(value, axisMax, size.height) * zoomY + panY;
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    // Draw only ticks whose actual cumulative values fall in the visible range.
    // This keeps the grid and labels consistent after Refresh auto-fit, vertical
    // scaling, and pan. Do not restart ticks at zero for a zoomed viewport.
    final visible = _visibleAxisRange(axisMax, zoomY, panY, size.height);
    final safeTickStep = tickStep.isFinite && tickStep > 0 ? tickStep : 100.0;
    final firstTick = (visible.minValue / safeTickStep).ceil() * safeTickStep;
    final lastTick = (visible.maxValue / safeTickStep).floor() * safeTickStep;
    var ticksDrawn = 0;
    for (
      var value = firstTick;
      value <= lastTick + safeTickStep * 0.0001 && ticksDrawn < 160;
      value += safeTickStep
    ) {
      final y = yFor(value);
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
      ticksDrawn++;
    }

    final step = 38.0 * zoomX;
    double xFor(int index) => panX + step * (index + 0.5);

    // Vertical date guides: one guide passes through each candle's center so
    // the candle can be matched to its fixed date label below the plot. These
    // guides share horizontal pan/zoom with the candles but are unaffected by
    // vertical pan/zoom, keeping candle/date alignment intuitive.
    final verticalGridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.14)
      ..strokeWidth = 0.7;
    for (var i = 0; i < days.length; i++) {
      final x = xFor(i);
      if (x < -step || x > size.width + step) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), verticalGridPaint);
    }
    var cumulative = 0.0;
    final opens = <double>[];
    final closes = <double>[];
    final highs = <double>[];
    for (final day in days) {
      opens.add(cumulative);
      highs.add(cumulative + 100.0);
      cumulative += day.progress;
      closes.add(cumulative);
    }

    if (candles) {
      final bodyWidth = (step * 0.76)
          .clamp(2.0, math.max(2.0, step * 0.88))
          .toDouble();
      for (var i = 0; i < days.length; i++) {
        final x = xFor(i);
        if (x < -step || x > size.width + step) continue;
        final yOpen = yFor(opens[i]);
        final yClose = yFor(closes[i]);
        final yHigh = yFor(highs[i]);
        final bodyTop = math.min(yOpen, yClose).toDouble();
        final bodyBottom = math.max(yOpen, yClose).toDouble();
        final bodyRect = Rect.fromLTRB(
          x - bodyWidth / 2,
          bodyTop,
          x + bodyWidth / 2,
          math.max(bodyTop + 2.0, bodyBottom).toDouble(),
        );
        // Mode-specific progress bands: Auto <40 red, 40..<60 yellow,
        // >=60 green; Manual <50 red, 50..<70 yellow, >=70 green.
        final isManual = days[i].mode.toLowerCase() == 'manual';
        final redThreshold = isManual ? 50.0 : 40.0;
        final greenThreshold = isManual ? 70.0 : 60.0;
        final progress = days[i].progress;
        final Color candleColor;
        if (progress < redThreshold) {
          candleColor = kCandleRed;
        } else if (progress < greenThreshold) {
          candleColor = kCandleYellow;
        } else {
          candleColor = bodyColor;
        }
        canvas.drawLine(
          Offset(x, yHigh),
          Offset(x, bodyTop),
          Paint()
            ..color = candleColor.withValues(alpha: 0.9)
            ..strokeWidth = math.max(1.2, zoomX * 1.2).toDouble(),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bodyRect, const Radius.circular(2)),
          Paint()..color = candleColor,
        );

        // Daily progress labels remain compact and only appear when there is
        // enough horizontal room, avoiding overlap between neighboring candles.
        if (step >= 29) {
          final modeCode = days[i].mode == 'Auto' ? 'A' : 'M';
          final labelWidth = math.max(10.0, step - 3).toDouble();
          final label = TextPainter(
            text: TextSpan(
              text: '${days[i].progress.toStringAsFixed(0)}%($modeCode)',
              style: TextStyle(
                color: candleColor,
                fontSize: (7.5 * zoomX.clamp(0.9, 1.2)).toDouble(),
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: labelWidth);
          final labelY = bodyTop - label.height - 2;
          if (labelY >= 0 && labelY + label.height <= size.height) {
            label.paint(canvas, Offset(x - label.width / 2, labelY));
          }
        }
      }
    } else {
      final path = Path();
      var pathStarted = false;
      for (var i = 0; i < days.length; i++) {
        final point = Offset(xFor(i), yFor(closes[i]));
        if (!pathStarted) {
          path.moveTo(point.dx, point.dy);
          pathStarted = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = bodyColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      for (var i = 0; i < days.length; i++) {
        final x = xFor(i);
        if (x >= -5 && x <= size.width + 5) {
          canvas.drawCircle(
            Offset(x, yFor(closes[i])),
            3.5,
            Paint()..color = bodyColor,
          );
        }
      }
    }

    // Dashed horizontal marker for the latest cumulative close, analogous to
    // the current-price line on a trading chart.
    final currentY = yFor(currentPoint);
    if (currentY >= 0 && currentY <= size.height) {
      final currentLinePaint = Paint()
        ..color = bodyColor.withValues(alpha: 0.82)
        ..strokeWidth = 1.2;
      for (var x = 0.0; x < size.width; x += 10.0) {
        canvas.drawLine(
          Offset(x, currentY),
          Offset(math.min(x + 5.0, size.width).toDouble(), currentY),
          currentLinePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CumulativeChartPainter oldDelegate) =>
      oldDelegate.candles != candles ||
      oldDelegate.days != days ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.bodyColor != bodyColor ||
      oldDelegate.zoomX != zoomX ||
      oldDelegate.zoomY != zoomY ||
      oldDelegate.panX != panX ||
      oldDelegate.panY != panY ||
      oldDelegate.maxAxis != maxAxis ||
      oldDelegate.tickStep != tickStep ||
      oldDelegate.currentPoint != currentPoint;
}

class CumulativeCurrentPointPainter extends CustomPainter {
  CumulativeCurrentPointPainter({
    required this.currentPoint,
    required this.maxAxis,
    required this.zoomY,
    required this.panY,
    required this.bodyColor,
  });

  final double currentPoint;
  final double maxAxis;
  final double zoomY;
  final double panY;
  final Color bodyColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1 || maxAxis <= 0) return;
    final rawY = _baseChartY(currentPoint, maxAxis, size.height) * zoomY + panY;
    final isAbove = rawY < 0;
    final isBelow = rawY > size.height;
    final y = rawY.clamp(0.0, size.height).toDouble();
    final prefix = isAbove ? '↑ ' : (isBelow ? '↓ ' : '');
    final labelText = '$prefix${_formatPointValue(currentPoint)} pts';
    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Color(0xFF0E1A13),
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width - 6);
    const horizontalPadding = 3.0;
    const verticalPadding = 3.0;
    final pillHeight = textPainter.height + verticalPadding * 2;
    final top = (y - pillHeight / 2)
        .clamp(0.0, math.max(0.0, size.height - pillHeight))
        .toDouble();
    final rect = Rect.fromLTWH(
      1,
      top,
      math
          .min(size.width - 2, textPainter.width + horizontalPadding * 2)
          .toDouble(),
      pillHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = bodyColor.withValues(alpha: 0.96),
    );
    textPainter.paint(
      canvas,
      Offset(rect.left + horizontalPadding, rect.top + verticalPadding),
    );
  }

  @override
  bool shouldRepaint(covariant CumulativeCurrentPointPainter oldDelegate) =>
      oldDelegate.currentPoint != currentPoint ||
      oldDelegate.maxAxis != maxAxis ||
      oldDelegate.zoomY != zoomY ||
      oldDelegate.panY != panY ||
      oldDelegate.bodyColor != bodyColor;
}

class CumulativeYAxisPainter extends CustomPainter {
  CumulativeYAxisPainter({
    required this.maxAxis,
    required this.tickStep,
    required this.zoomY,
    required this.panY,
    required this.labelColor,
  });

  final double maxAxis;
  final double tickStep;
  final double zoomY;
  final double panY;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1 || maxAxis <= 0 || tickStep <= 0)
      return;
    final visible = _visibleAxisRange(maxAxis, zoomY, panY, size.height);
    final safeTickStep = tickStep.isFinite && tickStep > 0 ? tickStep : 100.0;
    final firstTick = (visible.minValue / safeTickStep).ceil() * safeTickStep;
    final lastTick = (visible.maxValue / safeTickStep).floor() * safeTickStep;
    final style = TextStyle(color: labelColor, fontSize: 9);
    var ticksDrawn = 0;
    for (
      var value = firstTick;
      value <= lastTick + safeTickStep * 0.0001 && ticksDrawn < 160;
      value += safeTickStep
    ) {
      final y = _baseChartY(value, maxAxis, size.height) * zoomY + panY;
      final label = TextPainter(
        text: TextSpan(text: value.toStringAsFixed(0), style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 3);
      if (y - label.height / 2 >= 0 && y + label.height / 2 <= size.height) {
        label.paint(
          canvas,
          Offset(size.width - label.width - 3, y - label.height / 2),
        );
      }
      ticksDrawn++;
    }
  }

  @override
  bool shouldRepaint(covariant CumulativeYAxisPainter oldDelegate) =>
      oldDelegate.maxAxis != maxAxis ||
      oldDelegate.tickStep != tickStep ||
      oldDelegate.zoomY != zoomY ||
      oldDelegate.panY != panY ||
      oldDelegate.labelColor != labelColor;
}

class CumulativeXAxisPainter extends CustomPainter {
  CumulativeXAxisPainter({
    required this.days,
    required this.zoomX,
    required this.panX,
    required this.labelColor,
  });

  final List<SampleDay> days;
  final double zoomX;
  final double panX;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty || size.width <= 1 || size.height <= 1) return;
    final step = 38.0 * zoomX;
    // Keep dates readable. At close zoom show every day; when zoomed out,
    // increase the stride to avoid overlapping labels.
    final stride = math.max(1, ((44.0 / step).ceil())).toInt();
    final style = TextStyle(color: labelColor, fontSize: 10);
    for (var i = 0; i < days.length; i++) {
      if (i % stride != 0 && i != days.length - 1) continue;
      final date = days[i].date;
      final dateText = '${_shortMonth(date.month)} ${date.day}';
      final label = TextPainter(
        text: TextSpan(text: dateText, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = panX + step * (i + 0.5);
      if (x + label.width / 2 < 0 || x - label.width / 2 > size.width) continue;
      // This painter lives in a separate fixed-height strip, so vertical plot
      // movement cannot push date labels off screen. Horizontal pan is shared.
      label.paint(
        canvas,
        Offset(x - label.width / 2, (size.height - label.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CumulativeXAxisPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.zoomX != zoomX ||
      oldDelegate.panX != panX ||
      oldDelegate.labelColor != labelColor;
}

String _formatHms(int seconds) {
  final safe = seconds.clamp(0, 86400);
  final h = safe ~/ 3600;
  final m = (safe % 3600) ~/ 60;
  final s = safe % 60;
  return '${h}h ${m}m ${s}s';
}

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

String _two(int n) => n.toString().padLeft(2, '0');
String _month(int m) => const [
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
][m - 1];
String _shortMonth(int m) => const [
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
][m - 1];

// -----------------------------------------------------------------------------
// Advertisement module. Kept isolated from task, mode, settings, and chart logic.
// v34: image + video support. Configure only a separate Supabase ads project.
// Dashboard and fullscreen video audio are ALWAYS muted.
// -----------------------------------------------------------------------------

class Advertisement {
  const Advertisement({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.assetPath,
    required this.assetUrl,
    required this.localMediaPath,
    required this.targetUrl,
    required this.displayOrder,
  });

  final String id;
  final String title;
  final String mediaType; // 'video' or 'image'
  // Kept backed by the existing database column video_path for compatibility.
  final String assetPath;
  final String assetUrl;
  final String localMediaPath;
  final String targetUrl;
  final int displayOrder;

  bool get isImage => mediaType == 'image';

  factory Advertisement.fromJson(Map<String, dynamic> json) => Advertisement(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Advertisement',
    mediaType: json['mediaType'] as String? ?? 'video',
    assetPath:
        json['assetPath'] as String? ?? json['videoPath'] as String? ?? '',
    assetUrl: json['assetUrl'] as String? ?? json['videoUrl'] as String? ?? '',
    localMediaPath:
        json['localMediaPath'] as String? ?? json['localVideoPath'] as String,
    targetUrl: json['targetUrl'] as String? ?? '',
    displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'mediaType': mediaType,
    'assetPath': assetPath,
    'assetUrl': assetUrl,
    'localMediaPath': localMediaPath,
    'targetUrl': targetUrl,
    'displayOrder': displayOrder,
  };
}

class _AdvertisementService {
  _AdvertisementService._();
  static final _AdvertisementService instance = _AdvertisementService._();
  static const String _bucket = 'routine-ads';
  static const String _table = 'advertisements';
  static const Set<String> _allowedExtensions = {
    'mp4',
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  Future<Directory> _cacheDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/routine_ad_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _manifestFile() async {
    final directory = await _cacheDirectory();
    return File('${directory.path}/advertisements.json');
  }

  Future<List<Advertisement>> loadCached() async {
    try {
      final manifest = await _manifestFile();
      if (!await manifest.exists()) return <Advertisement>[];
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! List) return <Advertisement>[];
      final result = <Advertisement>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final ad = Advertisement.fromJson(item);
        if (await File(ad.localMediaPath).exists()) result.add(ad);
      }
      result.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      return result;
    } catch (error) {
      debugPrint('Could not read cached advertisements: $error');
      return <Advertisement>[];
    }
  }

  Future<void> _saveManifest(List<Advertisement> ads) async {
    final file = await _manifestFile();
    await file.writeAsString(jsonEncode(ads.map((ad) => ad.toJson()).toList()));
  }

  Future<List<Advertisement>> syncFromServer() async {
    final cached = await loadCached();
    if (!_adsBackendConfigured) return cached;

    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from(_table)
          .select('id,title,video_path,media_type,target_url,display_order')
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .order('created_at', ascending: true);
      final directory = await _cacheDirectory();
      final cachedById = <String, Advertisement>{
        for (final ad in cached) ad.id: ad,
      };
      final synced = <Advertisement>[];

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id'] as String;
        final assetPath = row['video_path'] as String;
        final mediaType = (row['media_type'] as String?) == 'image'
            ? 'image'
            : 'video';
        final targetUrl = row['target_url'] as String? ?? '';
        final title = row['title'] as String? ?? 'Advertisement';
        final order = (row['display_order'] as num?)?.toInt() ?? 0;
        final assetUrl = client.storage.from(_bucket).getPublicUrl(assetPath);
        final cachedAd = cachedById[id];
        final canReuseCachedPath =
            cachedAd != null &&
            cachedAd.mediaType == mediaType &&
            cachedAd.assetPath == assetPath &&
            await File(cachedAd.localMediaPath).exists();
        final localFile = canReuseCachedPath
            ? File(cachedAd.localMediaPath)
            : File('${directory.path}/${id}_${assetPath.split('/').last}');

        if (!await localFile.exists()) {
          try {
            final response = await http
                .get(Uri.parse(assetUrl))
                .timeout(const Duration(seconds: 25));
            if (response.statusCode < 200 || response.statusCode >= 300)
              continue;
            if (response.bodyBytes.isEmpty ||
                response.bodyBytes.length > 5 * 1024 * 1024)
              continue;
            await localFile.writeAsBytes(response.bodyBytes, flush: true);
          } catch (error) {
            debugPrint('Could not cache ad $id: $error');
            continue;
          }
        }

        synced.add(
          Advertisement(
            id: id,
            title: title,
            mediaType: mediaType,
            assetPath: assetPath,
            assetUrl: assetUrl,
            localMediaPath: localFile.path,
            targetUrl: targetUrl,
            displayOrder: order,
          ),
        );
      }

      // A successful online query is authoritative. Keep offline playback files only
      // for currently active ads; if the query fails, keep the previous cache.
      await _saveManifest(synced);
      final retainedPaths = synced.map((ad) => ad.localMediaPath).toSet();
      final manifestPath = (await _manifestFile()).path;
      for (final entity in directory.listSync()) {
        if (entity is! File || entity.path == manifestPath) continue;
        final name = entity.path.toLowerCase();
        final ext = name.contains('.') ? name.split('.').last : '';
        if (_allowedExtensions.contains(ext) &&
            !retainedPaths.contains(entity.path)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
      return synced;
    } catch (error) {
      debugPrint('Advertisement sync failed; keeping offline cache: $error');
      return cached;
    }
  }
}

bool get _canPlayCachedVideo =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
bool get _canShowCachedImage => !kIsWeb;

class AdvertisementBanner extends StatefulWidget {
  const AdvertisementBanner({super.key, required this.onOpenGallery});
  final ValueChanged<List<Advertisement>> onOpenGallery;

  @override
  State<AdvertisementBanner> createState() => _AdvertisementBannerState();
}

class _AdvertisementBannerState extends State<AdvertisementBanner>
    with WidgetsBindingObserver {
  List<Advertisement> _ads = <Advertisement>[];
  int _index = 0;
  VideoPlayerController? _controller;
  Timer? _syncTimer;
  Timer? _imageTimer;
  int _generation = 0;
  bool _switching = false;
  bool _syncing = false;
  String? _loadedAdId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAds();
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshAds(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAds();
  }

  Future<void> _loadAds() async {
    final cached = await _AdvertisementService.instance.loadCached();
    if (!mounted) return;
    setState(() {
      _ads = cached;
      _index = 0;
    });
    await _loadMedia();
    await _refreshAds();
  }

  String _sequence(List<Advertisement> ads) => ads
      .map(
        (ad) =>
            '${ad.id}:${ad.mediaType}:${ad.assetPath}:${ad.targetUrl}:${ad.displayOrder}',
      )
      .join('|');

  Future<void> _refreshAds() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final oldSequence = _sequence(_ads);
      final updated = await _AdvertisementService.instance.syncFromServer();
      if (!mounted) return;
      final changed = _sequence(updated) != oldSequence;
      setState(() {
        _ads = updated;
        if (_ads.isEmpty || _index >= _ads.length) _index = 0;
      });
      final currentId = _ads.isEmpty ? null : _ads[_index].id;
      if (changed || _loadedAdId != currentId) await _loadMedia();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _loadMedia() async {
    final generation = ++_generation;
    _imageTimer?.cancel();
    _imageTimer = null;
    final old = _controller;
    _controller = null;
    old?.removeListener(_onVideoTick);
    await old?.dispose();
    if (!mounted || _ads.isEmpty) {
      _loadedAdId = null;
      if (mounted) setState(() {});
      return;
    }
    final ad = _ads[_index % _ads.length];
    _loadedAdId = ad.id;
    final file = File(ad.localMediaPath);
    if (!await file.exists()) {
      if (mounted) setState(() {});
      return;
    }
    if (ad.isImage) {
      if (mounted) setState(() {});
      if (_canShowCachedImage) {
        _imageTimer = Timer(const Duration(seconds: 5), _advanceAd);
      }
      return;
    }
    if (!_canPlayCachedVideo) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(false);
      controller.addListener(_onVideoTick);
      setState(() => _controller = controller);
      await controller.play();
    } catch (error) {
      debugPrint('Advertisement playback failed: $error');
      await controller.dispose();
    }
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || _switching || !controller.value.isInitialized)
      return;
    final duration = controller.value.duration;
    if (duration > Duration.zero && controller.value.position >= duration)
      _advanceAd();
  }

  Future<void> _advanceAd() async {
    if (_switching || _ads.isEmpty) return;
    _switching = true;
    try {
      if (_ads.length == 1 && !_ads.first.isImage) {
        final current = _controller;
        if (current != null) {
          await current.seekTo(Duration.zero);
          await current.play();
        }
      } else if (_ads.length == 1 && _ads.first.isImage) {
        await _loadMedia();
      } else {
        if (mounted) setState(() => _index = (_index + 1) % _ads.length);
        await _loadMedia();
      }
    } finally {
      _switching = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _imageTimer?.cancel();
    _generation++;
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  Widget _placeholder(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.campaign_rounded,
              size: 19,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              'Advertisement',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ad = _ads.isEmpty ? null : _ads[_index % _ads.length];
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    Widget media = _placeholder(context);
    if (ad != null && ad.isImage && _canShowCachedImage) {
      media = Image.file(
        File(ad.localMediaPath),
        fit: BoxFit.cover,
        width: 104,
        height: 64,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    } else if (ad != null && !ad.isImage && ready && _canPlayCachedVideo) {
      media = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (_ads.isNotEmpty) {
            widget.onOpenGallery(List<Advertisement>.unmodifiable(_ads));
          } else {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('No active advertisements are available yet.'),
              ),
            );
          }
        },
        child: SizedBox(width: 104, height: 64, child: media),
      ),
    );
  }
}

class AdvertisementGalleryScreen extends StatefulWidget {
  const AdvertisementGalleryScreen({super.key, required this.ads});
  final List<Advertisement> ads;

  @override
  State<AdvertisementGalleryScreen> createState() =>
      _AdvertisementGalleryScreenState();
}

class _AdvertisementGalleryScreenState
    extends State<AdvertisementGalleryScreen> {
  int _index = 0;
  VideoPlayerController? _controller;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadPlayer(0);
  }

  Future<void> _loadPlayer(int index) async {
    final generation = ++_generation;
    final old = _controller;
    _controller = null;
    old?.removeListener(_onVideoTick);
    if (mounted) setState(() {});
    await old?.dispose();
    if (!mounted || index < 0 || index >= widget.ads.length) return;
    final ad = widget.ads[index];
    if (ad.isImage || !_canPlayCachedVideo) return;
    final file = File(ad.localMediaPath);
    if (!await file.exists()) return;
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(true);
      setState(() => _controller = controller);
      await controller.play();
    } catch (error) {
      debugPrint('Fullscreen advertisement playback failed: $error');
      await controller.dispose();
    }
  }

  void _onVideoTick() {}

  @override
  void dispose() {
    _generation++;
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openCurrentLink() async {
    if (_index < 0 || _index >= widget.ads.length) return;
    final uri = Uri.tryParse(widget.ads[_index].targetUrl);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This advertisement has an invalid destination link.'),
        ),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this advertisement link.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.ads.isEmpty ? null : widget.ads[_index];
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    current == null
                        ? 'Advertisements'
                        : '${current.title}  •  ${_index + 1}/${widget.ads.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: widget.ads.isEmpty
                  ? const Center(
                      child: Text(
                        'No advertisements available.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : PageView.builder(
                      scrollDirection: Axis.vertical,
                      itemCount: widget.ads.length,
                      onPageChanged: (index) {
                        setState(() => _index = index);
                        _loadPlayer(index);
                      },
                      itemBuilder: (context, index) {
                        final ad = widget.ads[index];
                        if (ad.isImage && _canShowCachedImage) {
                          return Center(
                            child: Image.file(
                              File(ad.localMediaPath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                size: 58,
                                color: Colors.white70,
                              ),
                            ),
                          );
                        }
                        if (index == _index && ready && _canPlayCachedVideo) {
                          return Center(
                            child: AspectRatio(
                              aspectRatio: controller.value.aspectRatio > 0
                                  ? controller.value.aspectRatio
                                  : 16 / 9,
                              child: VideoPlayer(controller),
                            ),
                          );
                        }
                        return Center(
                          child: Icon(
                            Icons.campaign_rounded,
                            size: 58,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        );
                      },
                    ),
            ),
            if (current != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  current.title,
                  style: const TextStyle(color: Colors.white, fontSize: 17),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openCurrentLink,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open Link'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
