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
import 'routine_template.dart';
import 'distraction_service.dart';
import 'journal_notepad_sheet.dart';
import 'consistency_tracker.dart';
import 'countries.dart';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'paper/paper_launcher.dart';

// Open-source Edition: 100% offline & local-first. Zero external cloud dependencies.
const String _supabaseAppsUrl = '';
const String _supabaseAppsAnonKey = '';

const String _profileServerUrl = '';
bool get _profileServerConfigured => false;

const String _adsSupabaseUrl = '';
const String _adsSupabasePublishableKey = '';
bool get _adsBackendConfigured => false;

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

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 2),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        item(kCandleRed, '<40% Red'),
        item(kCandleYellow, '40–<60% Yellow'),
        item(kGreen, '≥60% Green'),
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

String _isoCountryCode(String country) => isoCountryCode(country);

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

class RoutineApp extends StatefulWidget {
  const RoutineApp({super.key});
  @override
  State<RoutineApp> createState() => _RoutineAppState();
}

class _RoutineAppState extends State<RoutineApp> {
  bool isDark = true;
  double appScale = 1.0;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _readRoutineSettings();
    if (!mounted) return;
    setState(() {
      isDark = settings['isDark'] is bool ? settings['isDark'] as bool : true;
      if (settings['appScale'] is num) {
        appScale = (settings['appScale'] as num).toDouble().clamp(0.80, 1.30);
      }
      _settingsLoaded = true;
    });
  }

  void _setTheme(bool value) {
    setState(() => isDark = value);
    _writeRoutineSettings({'isDark': value});
  }

  void _setScale(double value) {
    final clamped = value.clamp(0.80, 1.30);
    setState(() => appScale = clamped);
    _writeRoutineSettings({'appScale': clamped});
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
      title: 'DayAura',
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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(appScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _ProfileGate(
        isDark: isDark,
        onThemeChanged: _setTheme,
        appScale: appScale,
        onScaleChanged: _setScale,
      ),
    );
  }
}

/// First-launch profile gate. The profile is stored on-device before the main
/// dashboard is shown; this works without adding another package or network.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate({
    required this.isDark,
    required this.onThemeChanged,
    required this.appScale,
    required this.onScaleChanged,
  });
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final double appScale;
  final ValueChanged<double> onScaleChanged;

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


  Future<void> _syncProfileIfConfigured() async {
    if (_syncInProgress || _profile == null) return;
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
      final headers = <String, String>{
        'apikey': _supabaseAppsAnonKey,
        'Authorization': 'Bearer $_supabaseAppsAnonKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      };

      bool profileUpdated = false;

      // 1. Sync Profile to Supabase Mailbox if not synced yet
      if (current['syncStatus'] != 'synced') {
        final payload = <String, dynamic>{
          'installation_id': installationId,
          'country_code': _isoCountryCode(
            current['country']?.toString() ?? 'Other',
          ),
          'age': (current['age'] as num?)?.toInt() ?? 21,
          'current_status': _statusCode(status),
          'primary_goal_category': _categorySlug(goal),
          'routine_purpose': purposeParts.join(' — '),
          'answers_json': <String, dynamic>{
            'education': current['education'],
            'work_type': current['workType'],
            'goal': goal,
          },
        };
        final response = await http
            .post(
              Uri.parse('$_supabaseAppsUrl/rest/v1/incoming_profiles'),
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          current['syncStatus'] = 'synced';
          current['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
          profileUpdated = true;
        }
      }

      // 2. Sync Daily Active Event to Supabase Mailbox
      final todayKey = DateTime.now().toIso8601String().substring(0, 10);
      if (current['lastActivePingDate'] != todayKey) {
        final pingPayload = <String, dynamic>{
          'installation_id': installationId,
          'activity_date': todayKey,
          'country_code': _isoCountryCode(
            current['country']?.toString() ?? 'Other',
          ),
          'current_status': _statusCode(status),
          'education': current['education']?.toString() ?? '',
          'goal': goal,
        };
        final pingRes = await http
            .post(
              Uri.parse('$_supabaseAppsUrl/rest/v1/incoming_activities'),
              headers: headers,
              body: jsonEncode(pingPayload),
            )
            .timeout(const Duration(seconds: 8));
        if (pingRes.statusCode >= 200 && pingRes.statusCode < 300) {
          current['lastActivePingDate'] = todayKey;
          profileUpdated = true;
        }
      }

      if (profileUpdated) {
        final file = await _profileFile;
        final temp = File('${file.path}.tmp');
        if (await temp.exists()) await temp.delete();
        await temp.writeAsString(jsonEncode(current), flush: true);
        await temp.rename(file.path);
        if (mounted) setState(() => _profile = current);
      }
    } catch (error) {
      debugPrint('Supabase profile/activity sync pending; will retry: $error');
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
      appScale: widget.appScale,
      onScaleChanged: widget.onScaleChanged,
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
            InkWell(
              onTap: _saving
                  ? null
                  : () async {
                      final selected = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: theme.colorScheme.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        builder: (_) => _CountrySearchSheet(
                          currentCountry: _country,
                          countries: kAllCountries,
                        ),
                      );
                      if (selected != null && mounted) {
                        setState(() {
                          _country = selected;
                          _education = _educationOptions.first;
                        });
                      }
                    },
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Country / region',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.public_rounded),
                  suffixIcon: Icon(Icons.search_rounded),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _country,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Tap to change',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
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

class _CountrySearchSheet extends StatefulWidget {
  const _CountrySearchSheet({
    required this.currentCountry,
    required this.countries,
  });

  final String currentCountry;
  final List<String> countries;

  @override
  State<_CountrySearchSheet> createState() => _CountrySearchSheetState();
}

class _CountrySearchSheetState extends State<_CountrySearchSheet> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _query = _searchController.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filteredList {
    if (_query.isEmpty) return widget.countries;
    final matches = widget.countries
        .where((c) => c.toLowerCase().contains(_query))
        .toList();
    // Prioritize prefix matches so typing 'in' puts India and Indonesia at the top!
    matches.sort((a, b) {
      final aStarts = a.toLowerCase().startsWith(_query);
      final bStarts = b.toLowerCase().startsWith(_query);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      return a.compareTo(b);
    });
    return matches;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredList;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.public_rounded, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Select Country / Region',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search country (e.g. India, Indonesia)...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No country found matching "$_query"',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final country = filtered[i];
                      final isSelected = country == widget.currentCountry;
                      return ListTile(
                        leading: const Icon(Icons.location_on_outlined, size: 20),
                        title: Text(
                          country,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? kGreen : null,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: kGreen)
                            : null,
                        onTap: () => Navigator.of(ctx).pop(country),
                      );
                    },
                  ),
          ),
        ],
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
  String get endLabel => _formatMinute(endMinute, isEndTime: true);
  String get durationLabel {
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

String _formatMinute(
  int minute, {
  bool use24Hour = true,
  bool isEndTime = false,
}) {
  if (minute >= 1440 || (isEndTime && minute >= 1439)) {
    return use24Hour ? '23:59' : '11:59 PM';
  }
  final safe = minute % 1440;
  final hour = safe ~/ 60;
  final min = safe % 60;
  final minuteText = min.toString().padLeft(2, '0');
  if (use24Hour) return '${hour.toString().padLeft(2, '0')}:$minuteText';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  final suffix = hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minuteText $suffix';
}

String formatMinute(
  int minute, {
  bool use24Hour = true,
  bool isEndTime = false,
}) =>
    _formatMinute(minute, use24Hour: use24Hour, isEndTime: isEndTime);

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
  const SampleDay(
    this.date,
    this.progress,
    this.mode, {
    this.tasks,
    this.emoji,
    this.memoryTitle,
    this.memoryNote,
    this.memoryImages,
    this.distractions,
  });
  final DateTime date;
  final double progress;
  final String mode;
  final List<Map<String, dynamic>>? tasks;
  final String? emoji;
  final String? memoryTitle;
  final String? memoryNote;
  final List<String>? memoryImages;
  final List<Map<String, dynamic>>? distractions;
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
    this.appScale = 1.0,
    this.onScaleChanged,
  });
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final double appScale;
  final ValueChanged<double>? onScaleChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool showCandles = true;
  bool showSetup = false;
  bool use24Hour = true;
  String activeMode = 'Auto';
  late DateTime now;
  Timer? clockTimer;
  String _currentRoutineDate = '';

  final RoutineHistoryStore _historyStore = RoutineHistoryStore();
  final RoutineTemplateStore _templateStore = RoutineTemplateStore();
  final TodayJournalStore _todayJournalStore = TodayJournalStore();
  TodayJournalEntry _todayJournal = const TodayJournalEntry();
  List<RoutineDayRecord> _savedHistory = <RoutineDayRecord>[];

  bool _distractionTrackerActive = false;
  List<DistractionItem> _todayDistractions = <DistractionItem>[];
  final Set<String> _firedAlarmKeys = <String>{};
  bool _isAlarmShowing = false;

  bool _isLockedInActive = false; // true if Time Lock is active
  int _lockedInUntilEpoch = 0;

  Future<void> _checkLockedInStatus() async {
    final state = await DistractionService.instance.getLockedInState();
    final isTime = state['isTimeLock'] as bool? ?? false;
    final until = state['untilEpoch'] as int? ?? 0;
    if (mounted) {
      setState(() {
        _isLockedInActive = isTime;
        _lockedInUntilEpoch = until;
      });
    }
  }

  String _formatLockedInRemaining() {
    final diff = DateTime.fromMillisecondsSinceEpoch(_lockedInUntilEpoch)
        .difference(DateTime.now());
    if (diff.isNegative) return 'Completed';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    if (days > 0) return '$days days, $hours hrs left';
    if (hours > 0) return '$hours hrs, $mins mins left';
    return '$mins mins left';
  }

  void _showAppVerificationNoticeDialog(AppVerificationNotice notice) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isApproved = notice.approved;
        final primaryColor = isApproved ? Colors.greenAccent : Colors.redAccent;
        final bgColor = isApproved ? const Color(0xFF071F10) : const Color(0xFF220808);
        final borderColor = isApproved
            ? Colors.greenAccent.withValues(alpha: 0.5)
            : Colors.redAccent.withValues(alpha: 0.6);

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderColor, width: 1.5),
          ),
          backgroundColor: bgColor,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isApproved ? Icons.verified_user_rounded : Icons.shield_rounded,
                        color: primaryColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isApproved ? 'Study App Approved' : 'Distraction App Detected',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isApproved ? 'Verified by DayAura AI' : 'Auto-Uninstalled via Device Owner',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Application: ',
                            style: TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                          Expanded(
                            child: Text(
                              notice.appName.isNotEmpty ? notice.appName : notice.packageName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Category: ',
                            style: TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                          Expanded(
                            child: Text(
                              notice.category,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primaryColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'AI VERDICT (ENGLISH):',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    notice.reason,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (!isApproved)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Package has been silently uninstalled to protect your focus.',
                            style: TextStyle(fontSize: 11, color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      DistractionService.instance.dismissVerificationNotice(notice.packageName);
                      Navigator.of(ctx).pop();
                    },
                    child: Text(
                      isApproved ? 'Continue' : 'Got it',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _checkPendingSmartGuardNotices() async {
    try {
      final notices = await DistractionService.instance.loadVerificationNotices();
      if (notices.isNotEmpty && mounted) {
        _showAppVerificationNoticeDialog(notices.first);
      }
      final pendingApps = await DistractionService.instance.getPendingInstalledApps();
      for (final app in pendingApps) {
        final pkg = app['packageName'] ?? '';
        final name = app['appName'] ?? pkg;
        if (pkg.isNotEmpty) {
          DistractionService.instance.verifyAndProcessInstalledApp(pkg, name);
        }
      }
    } catch (_) {}
  }

  Future<void> _openEmergencyUnlockDialog() async {
    final passCtrl = TextEditingController();
    String? errorText;
    final gracePasscode =
        await DistractionService.instance.getGracePeriodPasscode();
    if (!mounted) return;

    final unlocked = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final now = DateTime.now();
          final months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          final dateStr = '${months[now.month - 1]} ${now.day}';

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.vpn_key_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Developer Unlock'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter emergency unlock passcode for $dateStr:',
                  style: const TextStyle(fontSize: 13),
                ),
                if (gracePasscode != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.key_rounded, size: 16, color: Colors.orangeAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Emergency passcode: $gracePasscode',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Formula: First 6 digits of (567673 * 12h time). E.g. 3:43 -> 194711.',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Enter 6-digit passcode (e.g. 194711)',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.password_rounded),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF20B77A),
                ),
                onPressed: () {
                  final input = passCtrl.text.trim();
                  if (DistractionService.verifyUnlockPasscode(input)) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDialogState(() {
                      errorText = 'Invalid passcode for today!';
                    });
                  }
                },
                child: const Text('Unlock'),
              ),
            ],
          );
        },
      ),
    );

    if (unlocked == true && mounted) {
      await DistractionService.instance.setLockedInMode(
        mode: 'none',
        untilEpoch: 0,
      );
      await DistractionService.instance.releaseDeviceOwner();
      if (mounted) {
        setState(() {
          _isLockedInActive = false;
          _lockedInUntilEpoch = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF20B77A),
            content: Text('🔓 Time Lock successfully unlocked!'),
          ),
        );
      }
    }
  }

  void _onDistractionsUpdated() {
    _loadTodayDistractions();
    _loadRoutineHistory();
  }

  Future<void> _checkDistractionTrackerStatus() async {
    final active = await DistractionService.instance.isFloatingTrackerRunning();
    if (mounted) setState(() => _distractionTrackerActive = active);
  }

  Future<void> _loadTodayDistractions() async {
    final items = await DistractionService.instance.loadTodayDistractions();
    if (mounted) setState(() => _todayDistractions = items);
  }

  Future<void> _loadTodayJournal() async {
    final entry = await _todayJournalStore.load();
    if (mounted) setState(() => _todayJournal = entry);
  }

  Future<void> _loadRoutineHistory() async {
    try {
      final records = await _historyStore.load();
      final todayKey = _dateKey(now);
      // Remove any today record from past history so candle is never drawn before 11:59:59 PM
      final todayIndex = records.indexWhere((r) => r.dateKey == todayKey);
      if (todayIndex >= 0) {
        final r = records[todayIndex];
        if (r.hasMemorableNote && !_todayJournal.hasContent) {
          _todayJournal = TodayJournalEntry(
            emoji: r.emoji,
            title: r.memoryTitle,
            note: r.memoryNote,
            images: r.memoryImages ?? const [],
          );
          await _todayJournalStore.save(_todayJournal);
        }
        records.removeAt(todayIndex);
        await _historyStore.saveMultiple(records);
      }
      if (!mounted) return;
      setState(() {
        _savedHistory = records.where((r) => r.dateKey != todayKey).toList();
      });
    } catch (error) {
      debugPrint('Could not load routine history: $error');
    }
  }

  final GlobalKey<_InteractiveCumulativeChartState> _lifetimeChartKey =
      GlobalKey<_InteractiveCumulativeChartState>();
  // Auto mode is DayAura's unified standard routine mode.
  final List<TaskNode> autoTasks = <TaskNode>[];
  final List<TaskNode> tomorrowTasks = <TaskNode>[];
  final List<TaskNode> manualTasks = <TaskNode>[];
  String _planningTab = 'Today'; // 'Today' or 'Tomorrow'

  Future<File> _routineTasksFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/routine_tasks.json');
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  int _completedUnionSeconds(List<TaskNode> nodes) {
    final intervals = _checkedLeafIntervals(nodes);
    return _activeElapsedSeconds(intervals, 86400);
  }

  Future<void> _saveRoutineTasks() async {
    final file = await _routineTasksFile();
    final dateToSave =
        _currentRoutineDate.isNotEmpty ? _currentRoutineDate : _dateKey(now);
    final data = <String, dynamic>{
      'version': 2,
      'autoTasks': autoTasks.map((task) => task.toJson()).toList(),
      'tomorrowTasks': tomorrowTasks.map((task) => task.toJson()).toList(),
      'manualTasks': <dynamic>[],
      'activeMode': 'Auto',
      'routineDate': dateToSave,
    };
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> _reconcileRoutineDate() async {
    try {
      final todayKey = _dateKey(now);
      final file = await _routineTasksFile();
      if (!await file.exists()) {
        _currentRoutineDate = todayKey;
        await _saveRoutineTasks();
        return;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final decoded = jsonDecode(content);
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

      final savedAuto = parseTasks(decoded['autoTasks']) ?? <TaskNode>[];
      final savedTomorrow = parseTasks(decoded['tomorrowTasks']) ?? <TaskNode>[];
      final savedDateKey = decoded['routineDate'] as String?;

      if (savedDateKey == null || savedDateKey.isEmpty) {
        _currentRoutineDate = todayKey;
        await _saveRoutineTasks();
        return;
      }

      final savedParts = savedDateKey.split('-').map(int.parse).toList();
      final savedDate = DateTime(savedParts[0], savedParts[1], savedParts[2]);
      final todayDate = DateTime(now.year, now.month, now.day);
      final daysDiff = todayDate.difference(savedDate).inDays;

      if (daysDiff <= 0) {
        _currentRoutineDate = savedDateKey;
        if (mounted) {
          setState(() {
            autoTasks
              ..clear()
              ..addAll(savedAuto);
            tomorrowTasks
              ..clear()
              ..addAll(savedTomorrow);
            activeMode = 'Auto';
          });
        }
        return;
      }

      // One or more days have elapsed since routine tasks were recorded.
      // 1. Finalize the saved past day with its task snapshot (Path 2)
      final pastActiveTasks = savedAuto;
      final unionSecs = _completedUnionSeconds(pastActiveTasks);
      final pastProgress = (unionSecs / 86400 * 100).clamp(0.0, 100.0);
      final pastSnapshot = pastActiveTasks.map((t) => t.toJson()).toList();
      final pastDistractions =
          await DistractionService.instance.loadTodayDistractions();
      final todayJournal = await _todayJournalStore.load();

      final recordsToSave = <RoutineDayRecord>[
        RoutineDayRecord(
          date: savedDate,
          progress: pastProgress,
          mode: 'Auto',
          tasks: pastSnapshot,
          distractions: pastDistractions.map((d) => d.toJson()).toList(),
          emoji: todayJournal.emoji,
          memoryTitle: todayJournal.title,
          memoryNote: todayJournal.note,
          memoryImages: todayJournal.images,
        ),
      ];

      // 2. Fill any missed intermediate days with 0% (Red candle)
      for (var d = 1; d < daysDiff; d++) {
        final missedDate = savedDate.add(Duration(days: d));
        recordsToSave.add(
          RoutineDayRecord(
            date: missedDate,
            progress: 0.0,
            mode: 'Auto',
            tasks: null,
          ),
        );
      }

      await _historyStore.saveMultiple(recordsToSave);
      await DistractionService.instance.clearToday();
      await _todayJournalStore.clear();
      _todayJournal = const TodayJournalEntry();

      // 3. Midnight rollover: tomorrow tasks become today's active tasks, and tomorrow tasks is cleared!
      _currentRoutineDate = todayKey;
      if (mounted) {
        setState(() {
          autoTasks.clear();
          if (daysDiff == 1) {
            autoTasks.addAll(savedTomorrow);
          }
          tomorrowTasks.clear();
          manualTasks.clear();
          activeMode = 'Auto';
        });
      }

      await _saveRoutineTasks();
      await _loadRoutineHistory();
    } catch (error) {
      debugPrint('Error reconciling routine date: $error');
    }
  }

  List<TaskNode> get currentTasks => autoTasks;
  int get _elapsedSeconds => now.hour * 3600 + now.minute * 60 + now.second;
  bool _isTimeExpired(TaskNode task) =>
      activeMode == 'Auto' &&
      _elapsedSeconds >= (task.endMinute == 1440 ? 86400 : task.endMinute * 60);

  // In Auto Mode, upcoming tasks cannot be pre-checked; their checkbox unlocks when scheduled start arrives.
  bool _isUpcomingAuto(TaskNode task) =>
      activeMode == 'Auto' && _elapsedSeconds < task.startMinute * 60;

  bool _isActiveNowAuto(TaskNode task) =>
      activeMode == 'Auto' &&
      _elapsedSeconds >= task.startMinute * 60 &&
      _elapsedSeconds < (task.endMinute == 1440 ? 86400 : task.endMinute * 60);

  // Do not let a parent cascade a tick into a future or already-locked child.
  bool _hasExpiredDescendant(TaskNode task) => task.children.any(
    (child) => _isTimeExpired(child) || _hasExpiredDescendant(child),
  );

  bool _isCheckboxLocked(TaskNode task) =>
      activeMode == 'Auto' &&
      (_isTimeExpired(task) || _isUpcomingAuto(task) || _hasExpiredDescendant(task));

  // A running parent may still be extended, even if one of its child intervals has ended.
  bool _isTaskLockedForChanges(TaskNode task) =>
      activeMode == 'Auto' && _isTimeExpired(task);

  bool _isDeleteLocked(TaskNode task) =>
      activeMode == 'Auto' &&
      (_isTimeExpired(task) || _hasExpiredDescendant(task));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    now = DateTime.now();
    _currentRoutineDate = _dateKey(now);
    _reconcileRoutineDate();
    _loadTimeFormatSetting();
    _loadTodayJournal();
    _loadRoutineHistory();
    _checkDistractionTrackerStatus();
    _checkLockedInStatus();
    DistractionService.instance.registerEmergencyUnlockCallback(() {
      if (mounted) _openEmergencyUnlockDialog();
    });
    DistractionService.instance.onAppVerificationNotice = (notice) {
      if (mounted) _showAppVerificationNoticeDialog(notice);
    };
    _checkPendingSmartGuardNotices();
    DistractionService.instance.addListener(_onDistractionsUpdated);
    _loadTodayDistractions();
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final current = DateTime.now();
      final todayKey = _dateKey(current);
      if (todayKey != _currentRoutineDate) {
        setState(() => now = current);
        _reconcileRoutineDate();
      } else {
        setState(() => now = current);
      }
      _checkAndTriggerTaskAlarms(current);
    });
  }

  void _checkAndTriggerTaskAlarms(DateTime current) {
    if (_isAlarmShowing) return;
    final currentSecond =
        current.hour * 3600 + current.minute * 60 + current.second;
    final todayKey = _dateKey(current);

    void checkNode(TaskNode task) {
      if (task.alarmEnabled && !task.done) {
        final endSec = task.endMinute * 60;
        final alarmSec = endSec - task.alarmLeadSeconds;
        final alarmKey =
            '${todayKey}_${task.title}_${task.startMinute}_${task.endMinute}';
        if (currentSecond >= alarmSec && currentSecond < endSec + 60) {
          if (!_firedAlarmKeys.contains(alarmKey)) {
            _firedAlarmKeys.add(alarmKey);
            _fireTaskAlarm(task);
          }
        }
      }
      for (final child in task.children) {
        checkNode(child);
      }
    }

    for (final t in currentTasks) {
      checkNode(t);
    }
  }

  void _fireTaskAlarm(TaskNode task) {
    _isAlarmShowing = true;
    final leadMin = (task.alarmLeadSeconds / 60).round();
    final timeStr =
        _formatMinute(task.endMinute, use24Hour: use24Hour, isEndTime: true);
    DistractionService.instance.showAlarmNotification(
      title: task.title,
      timeLabel: timeStr,
      leadMinutes: leadMin,
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (alarmCtx) => AlertDialog(
        icon: const Icon(Icons.alarm_on, color: Colors.orange, size: 40),
        title: Text('Task Ending Soon: ${task.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ends at $timeStr.\nAlarm set for $leadMin min before end.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tick korun task complete korte, ba Dismiss korun.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              DistractionService.instance.stopAlarmNotification();
              _isAlarmShowing = false;
              Navigator.of(alarmCtx).pop();
            },
            child: const Text('Dismiss'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Mark Complete (Tick)'),
            onPressed: () {
              DistractionService.instance.stopAlarmNotification();
              _isAlarmShowing = false;
              Navigator.of(alarmCtx).pop();
              setState(() {
                _setTaskDone(task, true, null);
              });
              _saveRoutineTasks().catchError((Object error) {
                debugPrint('Could not save routine tasks: $error');
              });
            },
          ),
        ],
      ),
    ).then((_) {
      _isAlarmShowing = false;
      DistractionService.instance.stopAlarmNotification();
    });
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final current = DateTime.now();
      setState(() => now = current);
      _checkDistractionTrackerStatus();
      _loadTodayDistractions();
      _checkLockedInStatus();
      if (_dateKey(current) != _currentRoutineDate) {
        _reconcileRoutineDate();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DistractionService.instance.removeListener(_onDistractionsUpdated);
    DistractionService.instance.unregisterEmergencyUnlockCallback();
    DistractionService.instance.onAppVerificationNotice = null;
    clockTimer?.cancel();
    DistractionService.instance.stopAlarmSound();
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
          title: showSetup
              ? const Text(
                  'Today Setup',
                  style: TextStyle(fontWeight: FontWeight.w800),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_month(now.month)} ${now.day}, ${now.year}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatClockWithSeconds(now, use24Hour),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: (activeMode == 'Auto'
                                    ? kGreen
                                    : Colors.orangeAccent)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            activeMode,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: activeMode == 'Auto'
                                  ? kGreen
                                  : Colors.orangeAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          leading: showSetup
              ? IconButton(
                  tooltip: 'Back to Dashboard',
                  onPressed: () => setState(() => showSetup = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'Dashboard (Home)',
              icon: Icon(
                !showSetup ? Icons.home_rounded : Icons.home_outlined,
                color:
                    !showSetup ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: () {
                if (showSetup) setState(() => showSetup = false);
              },
            ),
            IconButton(
              tooltip: showSetup ? 'Add Task (+)' : 'Today Setup (+)',
              icon: Icon(
                showSetup
                    ? Icons.add_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: showSetup ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: () {
                if (!showSetup) {
                  setState(() => showSetup = true);
                } else {
                  _openTaskDialog(isTomorrow: _planningTab == 'Tomorrow');
                }
              },
            ),
            if (_isLockedInActive)
              IconButton(
                tooltip: 'Time Lock Active (Tap to Unlock)',
                icon: const Icon(Icons.lock_clock_rounded, color: Colors.redAccent),
                onPressed: _openEmergencyUnlockDialog,
              ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_rounded),
              onPressed: _showSettingsSheet,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: showSetup ? _buildTodaySetup() : _buildDashboard(),
      ),
    );
  }

  void _setUse24Hour(bool value) {
    setState(() => use24Hour = value);
    _writeRoutineSettings({'use24Hour': value});
  }

  void _openDayAuraPaper() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DayAuraPaperPage(),
      ),
    );
  }

  Future<void> _openManageDistractingAppsSheet() async {
    final hasUsageStats =
        await DistractionService.instance.canAccessUsageStats();
    if (!hasUsageStats && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Usage Access Permission Required'),
          content: const Text(
            'DayAura needs "Usage Access" permission to detect when your selected distracting apps are opened, so it can display the red screen focus warning.\n\nYour app usage data stays 100% private and offline on your device.\n\nWould you like to open Android Settings to grant permission?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not Now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (proceed == true) {
        await DistractionService.instance.requestUsageStatsPermission();
      }
    }

    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const _DistractingAppsSheet(
          initialTab: 0,
        ),
      ),
    );
    _checkLockedInStatus();
  }

  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final scale = widget.appScale;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings_rounded, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Settings',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isLockedInActive) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded, color: Colors.redAccent, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Time Lock Active (Hardcore)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Locked until ${_formatLockedInRemaining()}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _openEmergencyUnlockDialog();
                            },
                            child: const Text('Unlock', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // 1. Time format
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x2220B77A),
                      child: Icon(Icons.schedule_rounded, color: kGreen),
                    ),
                    title: const Text('Time format'),
                    subtitle: Text(
                      use24Hour ? '24-Hour (13:00)' : '12-Hour (1:00 PM)',
                    ),
                    trailing: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('12h')),
                        ButtonSegment(value: true, label: Text('24h')),
                      ],
                      selected: {use24Hour},
                      showSelectedIcon: false,
                      onSelectionChanged: (selected) {
                        _setUse24Hour(selected.first);
                        setSheetState(() {});
                      },
                    ),
                  ),
                  const Divider(height: 16),
                  // 2. Dark / Light Mode
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: CircleAvatar(
                      backgroundColor: const Color(0x2220B77A),
                      child: Icon(
                        widget.isDark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: kGreen,
                      ),
                    ),
                    title: const Text('Theme mode'),
                    subtitle:
                        Text(widget.isDark ? 'Dark theme' : 'Light theme'),
                    value: widget.isDark,
                    onChanged: (val) {
                      widget.onThemeChanged(val);
                      setSheetState(() {});
                    },
                  ),
                  const Divider(height: 16),
                  // Distraction Tracker Floating Button
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const CircleAvatar(
                      backgroundColor: Color(0x22E53935),
                      child: Icon(Icons.radar_rounded, color: Color(0xFFE53935)),
                    ),
                    title: const Text('Distraction Tracker'),
                    subtitle: const Text(
                      'Floating draggable button to track distractions over other apps',
                    ),
                    value: _distractionTrackerActive,
                    onChanged: (val) async {
                      if (val) {
                        final canDraw =
                            await DistractionService.instance.canDrawOverlays();
                        if (!canDraw && sheetContext.mounted) {
                          final proceed = await showDialog<bool>(
                            context: sheetContext,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Permission Required'),
                              content: const Text(
                                'Floating Distraction Tracker needs "Display over other apps" permission so the floating button stays visible while you study or work.\n\nOpen Android Settings to grant permission?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Open Settings'),
                                ),
                              ],
                            ),
                          );
                          if (proceed == true) {
                            await DistractionService.instance
                                .requestOverlayPermission();
                          }
                          return;
                        }
                        await DistractionService.instance
                            .startFloatingTracker();
                        setState(() => _distractionTrackerActive = true);
                        setSheetState(() {});
                      } else {
                        await DistractionService.instance
                            .stopFloatingTracker();
                        setState(() => _distractionTrackerActive = false);
                        setSheetState(() {});
                      }
                    },
                  ),
                  // Consistency Track (Above Locked In)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x2220B77A),
                      child: Icon(Icons.track_changes_rounded, color: kGreen),
                    ),
                    title: const Text('Consistency Track'),
                    subtitle: const Text(
                      'Track habits, streaks & relapses (days, hours, minutes)',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ConsistencyTrackScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 16),
                  // Locked In (Below Consistency Track)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: _isLockedInActive
                          ? const Color(0x33E53935)
                          : const Color(0x22E53935),
                      child: Icon(
                        _isLockedInActive
                            ? Icons.lock_clock_rounded
                            : Icons.lock_person_rounded,
                        color: const Color(0xFFE53935),
                      ),
                    ),
                    title: const Text('Locked In'),
                    subtitle: Text(
                      _isLockedInActive
                          ? 'Time Lock Active • ${_formatLockedInRemaining()}'
                          : 'Hardcore distraction blocking & website shields',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      // Do not pop sheetContext so back button returns to Settings
                      await _openManageDistractingAppsSheet();
                      if (mounted) setSheetState(() {});
                    },
                  ),
                  const Divider(height: 16),
                  // 3. Favorite Routines
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x22E91E63),
                      child: Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
                    ),
                    title: const Text('Favorite Routines'),
                    subtitle: const Text('Manage templates, apply & share with friends'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showFavoriteRoutinesSheet();
                    },
                  ),
                  const Divider(height: 16),
                  // 4. Historical Details
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x2220B77A),
                      child: Icon(Icons.history_rounded, color: kGreen),
                    ),
                    title: const Text('Historical details'),
                    subtitle: const Text('View past days & task snapshots'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showHistoricalDetailsList();
                    },
                  ),
                  const Divider(height: 16),
                  // 4. Backup & Restore (Export / Import)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x2220B77A),
                      child: Icon(Icons.sync_alt_rounded, color: kGreen),
                    ),
                    title: const Text('Backup & Restore'),
                    subtitle: const Text('Download or upload backup JSON'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showBackupRestoreSheet();
                    },
                  ),
                  const Divider(height: 16),
                  // DayAura Paper
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x2220B77A),
                      child: Icon(Icons.menu_book_rounded, color: kGreen),
                    ),
                    title: const Text('DayAura Paper'),
                    subtitle: const Text(
                      'Tutorials, video guides & documentation',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openDayAuraPaper();
                    },
                  ),
                  const Divider(height: 16),
                  // 5. App Zoom (Scale / Font & UI Size)
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0x2220B77A),
                            child: Icon(Icons.zoom_in_rounded,
                                size: 20, color: kGreen),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'App zoom & scale',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              Text(
                                'Fit small or large screens',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${(scale * 100).round()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Zoom Out (Smaller)',
                        icon: const Icon(Icons.remove_rounded),
                        onPressed: scale > 0.81
                            ? () {
                                final next =
                                    (scale - 0.05).clamp(0.80, 1.30);
                                widget.onScaleChanged?.call(
                                    double.parse(next.toStringAsFixed(2)));
                                setSheetState(() {});
                              }
                            : null,
                      ),
                      Expanded(
                        child: Slider(
                          value: scale.clamp(0.80, 1.30),
                          min: 0.80,
                          max: 1.30,
                          divisions: 10,
                          label: '${(scale * 100).round()}%',
                          onChanged: (val) {
                            widget.onScaleChanged?.call(
                                double.parse(val.toStringAsFixed(2)));
                            setSheetState(() {});
                          },
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Zoom In (Larger)',
                        icon: const Icon(Icons.add_rounded),
                        onPressed: scale < 1.29
                            ? () {
                                final next =
                                    (scale + 0.05).clamp(0.80, 1.30);
                                widget.onScaleChanged?.call(
                                    double.parse(next.toStringAsFixed(2)));
                                setSheetState(() {});
                              }
                            : null,
                      ),
                    ],
                  ),
                  Center(
                    child: TextButton.icon(
                      onPressed: scale != 1.0
                          ? () {
                              widget.onScaleChanged?.call(1.0);
                              setSheetState(() {});
                            }
                          : null,
                      icon: const Icon(Icons.restart_alt_rounded, size: 16),
                      label: const Text('Reset zoom to 100%'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDashboard() {
    final todayKey = _dateKey(now);
    final sample = _savedHistory
        .where((record) => record.dateKey != todayKey)
        .map((record) => SampleDay(
              record.date,
              record.progress,
              record.mode,
              tasks: record.tasks,
              emoji: record.emoji,
              memoryTitle: record.memoryTitle,
              memoryNote: record.memoryNote,
              memoryImages: record.memoryImages,
              distractions: record.distractions,
            ))
        .toList();
    final completedSeconds = _completedUnionSeconds(currentTasks);
    final dailyPct = (completedSeconds / 86400 * 100).clamp(0.0, 100.0);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isLockedInActive) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2C0A0A), Color(0xFF190505)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, color: Colors.redAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'HARDCORE TIME LOCK ACTIVE 🔒',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Anti-Uninstall & App Blocking ON • ${_formatLockedInRemaining()}',
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _openEmergencyUnlockDialog,
                  icon: const Icon(Icons.vpn_key_rounded, size: 14),
                  label: const Text(
                    'Unlock',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.today_rounded,
                            size: 15,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${dailyPct.toStringAsFixed(2)}%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'Daily progress',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 15,
                            color: kGreen,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Completed',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatDuration(completedSeconds),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'Tracked time',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_adsBackendConfigured) ...[
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Lifetime Overview',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
                  onDayTap: (index) {
                    if (index >= 0 && index < sample.length) {
                      _showDayDetailsSheet(sample[index], index, sample);
                    }
                  },
                  onOpenHistoricalList: _showHistoricalDetailsList,
                  onCandlesChanged: (val) {
                    if (mounted) setState(() => showCandles = val);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Drag the plot to pan. Drag the right-side point scale up or down to scale vertically. Pinch with two fingers to zoom. Tap any candle or date to view that day\'s details. Use the refresh icon to return to recent days.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: kGreen.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openDayAuraPaper,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF20B77A), Color(0xFF0F766E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF20B77A).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'DayAura Paper',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: kGreen.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'GUIDE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: kGreen,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Interactive documentation, tutorials & guides in 8 languages',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTodaySetup() {
    final isTomorrowTab = _planningTab == 'Tomorrow';
    final activeTabTasks = isTomorrowTab ? tomorrowTasks : autoTasks;

    final elapsedSeconds = isTomorrowTab ? 0 : _elapsedSeconds;
    final completedSeconds = _completedUnionSeconds(activeTabTasks);
    final progress = (completedSeconds / 86400).clamp(0.0, 1.0);
    final completedIntervals = _checkedLeafIntervals(activeTabTasks);
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

    final tomorrowDate = now.add(const Duration(days: 1));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          isTomorrowTab
              ? 'Planning for Tomorrow • ${_month(tomorrowDate.month)} ${tomorrowDate.day}, ${tomorrowDate.year}'
              : '${_month(now.month)} ${now.day}, ${now.year} • ${_formatClockWithSeconds(now, use24Hour)}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'Today',
              label: Text('Today Routine'),
              icon: Icon(Icons.today_rounded),
            ),
            ButtonSegment(
              value: 'Tomorrow',
              label: Text('Tomorrow Tasks'),
              icon: Icon(Icons.wb_twilight_rounded),
            ),
          ],
          selected: {_planningTab},
          showSelectedIcon: false,
          onSelectionChanged: (values) {
            setState(() => _planningTab = values.first);
          },
        ),
        if (isTomorrowTab) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
            margin: EdgeInsets.zero,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.wb_twilight_rounded, color: Colors.amber, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Plan your tomorrow routine in advance. At 12:00 AM midnight, these tasks will automatically move to Today and activate!',
                      style: TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (!isTomorrowTab)
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
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Tomorrow routine preview',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        'Total: ${_formatHms(_totalPlannedSeconds(tomorrowTasks))}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 20,
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final w = constraints.maxWidth;
                        final intervals = _allLeafIntervals(tomorrowTasks);
                        return Stack(
                          children: [
                            Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            ...intervals.map((it) {
                              final left = (it.startSeconds / 86400.0) * w;
                              final width = math.max(
                                2.0,
                                ((it.endSeconds - it.startSeconds) / 86400.0) * w,
                              );
                              return Positioned(
                                left: left,
                                width: width,
                                top: 0,
                                height: 16,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('00:00', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                      Text('06:00', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                      Text('12:00', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                      Text('18:00', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                      Text('23:59', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (!isTomorrowTab) ...[
          const SizedBox(height: 12),
          // Today's Memorable Day Journal & Distraction Quick Access
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.bookmark_added_rounded,
                                size: 20, color: Colors.amber),
                            const SizedBox(width: 8),
                            Text(
                              _todayMemoryLabel(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text('Journal Note'),
                        onPressed: _openJournalNotepadForToday,
                      ),
                    ],
                  ),
                  const Divider(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.radar_rounded,
                                size: 20, color: Color(0xFFE53935)),
                            const SizedBox(width: 8),
                            Text(
                              _todayDistractions.isEmpty
                                  ? 'No distractions logged today'
                                  : 'Distractions: ${_todayDistractions.length} times',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Log distraction now',
                        icon: const Icon(Icons.add_alert_rounded,
                            color: Color(0xFFE53935), size: 20),
                        onPressed: _promptAddDistractionManually,
                      ),
                    ],
                  ),
                  if (_todayDistractions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _todayDistractions.map((d) {
                        return Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor:
                              Colors.redAccent.withValues(alpha: 0.12),
                          side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.25)),
                          label: Text(
                            '${d.name} (${d.timeLabel})',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                isTomorrowTab ? 'Tomorrow tasks' : 'Timeline tasks',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Save routine as favorite',
              icon: const Icon(Icons.favorite_border_rounded, color: Colors.pinkAccent),
              onPressed: _promptSaveCurrentAsFavorite,
            ),
            IconButton(
              tooltip: 'Favorite Routines',
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: _showFavoriteRoutinesSheet,
            ),
            IconButton(
              onPressed: () => _openTaskDialog(isTomorrow: isTomorrowTab),
              icon: const Icon(Icons.add_circle_rounded),
              tooltip: isTomorrowTab ? 'Add task for tomorrow' : 'Add task for today',
            ),
          ],
        ),
        if (activeTabTasks.isEmpty)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      isTomorrowTab ? Icons.wb_twilight_rounded : Icons.playlist_add_check_circle_outlined,
                      size: 44,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isTomorrowTab
                          ? 'No tasks planned for tomorrow yet'
                          : 'No tasks created for today yet',
                      style:
                          const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTomorrowTab
                          ? 'Tap + above to schedule your routine for tomorrow in advance!'
                          : 'Tap the + button above to add your first task for today, or apply a saved favorite routine.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      onPressed: _showFavoriteRoutinesSheet,
                      icon: const Icon(Icons.favorite_rounded,
                          size: 18, color: Colors.pinkAccent),
                      label: const Text('Apply a Favorite Routine'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ..._sortedTasks(activeTabTasks)
              .map((task) => _buildTaskTree(task, 0, null)),
        const SizedBox(height: 10),
        Text(
          isTomorrowTab
              ? 'Tasks scheduled for tomorrow will automatically move to Today at 12:00 AM midnight. You can set any start and end time without past-time limits.'
              : 'The day timeline marks elapsed checked intervals green, elapsed unchecked intervals red, and future intervals neutral. Checking a task adds its duration to Completed Time Contribution immediately.',
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
                        value: _planningTab == 'Tomorrow' ? false : task.done,
                        onChanged: (_planningTab == 'Tomorrow' || _isCheckboxLocked(task))
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
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        '${_formatMinute(task.startMinute, use24Hour: use24Hour)} – ${_formatMinute(task.endMinute, use24Hour: use24Hour)} • ${task.durationLabel}',
                                  ),
                                  if (_planningTab == 'Tomorrow') ...[
                                    const TextSpan(
                                      text: ' • SCHEDULED FOR TOMORROW',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blueAccent,
                                      ),
                                    ),
                                  ] else ...[
                                    if (_isTimeExpired(task))
                                      TextSpan(
                                        text: task.done
                                            ? ' • LOCKED'
                                            : ' • MISSED / LOCKED',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: task.done
                                              ? Colors.grey
                                              : Colors.redAccent,
                                        ),
                                      )
                                    else if (_isUpcomingAuto(task))
                                      const TextSpan(
                                        text: ' • UPCOMING',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey,
                                        ),
                                      )
                                    else if (_isActiveNowAuto(task))
                                      const TextSpan(
                                        text: ' • ACTIVE NOW',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: kGreen,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
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
                          onPressed: (_planningTab != 'Tomorrow' && _isTaskLockedForChanges(task))
                              ? null
                              : () => _openTaskDialog(parent: task, isTomorrow: _planningTab == 'Tomorrow'),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                        IconButton(
                          tooltip: 'Edit task',
                          onPressed: (_planningTab != 'Tomorrow' && _isTaskLockedForChanges(task))
                              ? null
                              : () => _openTaskDialog(
                                  existing: task,
                                  parent: parent,
                                  isTomorrow: _planningTab == 'Tomorrow',
                                ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete task',
                          onPressed: (_planningTab != 'Tomorrow' && _isDeleteLocked(task))
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
                  if (_planningTab == 'Tomorrow') {
                    tomorrowTasks.remove(task);
                  } else {
                    autoTasks.remove(task);
                  }
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
      if (!_isCheckboxLocked(child)) {
        _setSubtreeState(child, value);
      }
    }
    if (parent != null) {
      _syncAncestors(parent);
    }
  }

  void _setSubtreeState(TaskNode task, bool value) {
    if (_isCheckboxLocked(task)) return;
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

  void _openTaskDialog({TaskNode? existing, TaskNode? parent, bool isTomorrow = false}) {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final parentStartSeconds = (parent?.startMinute ?? 0) * 60;
    final parentEndSeconds = parent == null
        ? 86399
        : math.min(
            (parent.endMinute >= 1440 ? 1439 : parent.endMinute) * 60 +
                (parent.endMinute >= 1440 ? 59 : 0),
            86399,
          );
    final openingNow = DateTime.now();
    final openingNowSeconds =
        ((openingNow.hour * 3600 + openingNow.minute * 60 + openingNow.second) ~/
                60 +
            1) *
        60;

    final bool isTaskActiveOrPast = !isTomorrow &&
        existing != null &&
        activeMode == 'Auto' &&
        (existing.startMinute * 60 < openingNowSeconds);

    int startSeconds;
    if (existing != null) {
      startSeconds = existing.startMinute * 60;
    } else if (!isTomorrow && activeMode == 'Auto') {
      startSeconds = math.max(openingNowSeconds, parentStartSeconds);
    } else {
      if (parent != null) {
        startSeconds = parentStartSeconds;
      } else if (isTomorrow && tomorrowTasks.isNotEmpty) {
        final lastEnd = tomorrowTasks.last.endMinute * 60;
        startSeconds = (lastEnd < 86340) ? lastEnd : 0;
      } else if (isTomorrow) {
        startSeconds = 6 * 3600;
      } else {
        startSeconds = 720 * 60;
      }
    }

    int endSeconds;
    if (existing != null) {
      endSeconds = math.min(
        (existing.endMinute >= 1440 ? 1439 : existing.endMinute) * 60 +
            (existing.endMinute >= 1440 ? 59 : 0),
        parentEndSeconds,
      );
    } else {
      endSeconds = (startSeconds + 3600)
          .clamp(startSeconds + 60, parentEndSeconds)
          .toInt();
    }

    startSeconds = startSeconds
        .clamp(parentStartSeconds, (parentEndSeconds - 60).clamp(0, 86399))
        .toInt();
    startSeconds = (startSeconds ~/ 60) * 60;
    if (endSeconds <= startSeconds) {
      endSeconds = (startSeconds + 3600)
          .clamp(startSeconds + 60, parentEndSeconds)
          .toInt();
    }
    if (!isTomorrow && activeMode == 'Auto') {
      final openingNextMinute = openingNowSeconds;
      final earliestEnd = math
          .max(startSeconds + 60, openingNextMinute)
          .clamp(startSeconds + 60, parentEndSeconds)
          .toInt();
      if (endSeconds < earliestEnd) endSeconds = earliestEnd;
    }
    endSeconds = (endSeconds ~/ 60) * 60;
    endSeconds = endSeconds.clamp(startSeconds + 60, parentEndSeconds).toInt();

    int maxDurationForStart(int start) =>
        math.max(60, math.min(parentEndSeconds, 86399) - start).toInt();
    final initialMaxDurationSeconds = maxDurationForStart(startSeconds);
    int durationSeconds = (endSeconds - startSeconds)
        .clamp(60, initialMaxDurationSeconds)
        .toInt();
    durationSeconds = (durationSeconds ~/ 60) * 60;
    endSeconds = (startSeconds + durationSeconds)
        .clamp(startSeconds + 60, parentEndSeconds)
        .toInt();

    int alarmLeadSeconds = existing?.alarmLeadSeconds ?? 300;
    bool useEndTime = true;
    bool alarmEnabled = existing?.alarmEnabled ?? false;
    String? validationError;
    Timer? dialogClockTimer;
    int trimRevision = 0;

    int bounded(int value, int min, int max) => value.clamp(min, max).toInt();
    String two(int n) => n.toString().padLeft(2, '0');

    Widget legendDot(Color color, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500),
          ),
        ],
      );
    }

    Widget compactWheel({
      required String label,
      required int value,
      required int max,
      required ValueChanged<int> onChanged,
      int min = 0,
    }) {
      final safeValue = bounded(value, min, max);
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 64,
              child: CupertinoPicker(
                key: ValueKey('$label-$min-$max-$trimRevision'),
                itemExtent: 22,
                scrollController: FixedExtentScrollController(
                  initialItem: safeValue - min,
                ),
                onSelectedItemChanged: (index) => onChanged(index + min),
                children: List<Widget>.generate(
                  max - min + 1,
                  (index) => Center(
                    child: Text(
                      two(index + min),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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
      if (isDuration) {
        final durationCap = maxSeconds.clamp(60, 86399).toInt();
        final safeDuration = bounded(seconds, minSeconds, durationCap);
        final durationHours = safeDuration ~/ 3600;
        final durationMinutes = (safeDuration % 3600) ~/ 60;
        final maximumHours = durationCap ~/ 3600;
        final maximumMinutes = durationHours == maximumHours
            ? (durationCap % 3600) ~/ 60
            : 59;
        final minimumMinutes = durationHours == 0
            ? math.max(1, (minSeconds % 3600) ~/ 60)
            : 0;

        int boundedDuration(int hours, int minutes) =>
            (hours * 3600 + minutes * 60)
                .clamp(minSeconds, durationCap)
                .toInt();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                compactWheel(
                  label: 'H',
                  value: durationHours,
                  max: maximumHours,
                  onChanged: (v) =>
                      onChanged(boundedDuration(v, durationMinutes)),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                compactWheel(
                  label: 'M',
                  value: durationMinutes,
                  min: minimumMinutes,
                  max: maximumMinutes,
                  onChanged: (v) =>
                      onChanged(boundedDuration(durationHours, v)),
                ),
              ],
            ),
          ],
        );
      }

      final safe = bounded(seconds, minSeconds, maxSeconds);
      final h24 = safe ~/ 3600;
      final m = (safe % 3600) ~/ 60;
      final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
      final isPm = h24 >= 12;
      final minHour24 = minSeconds ~/ 3600;
      final maxHour24 = maxSeconds ~/ 3600;
      final minMinute = h24 == minHour24 ? (minSeconds % 3600) ~/ 60 : 0;
      final maxMinute = h24 == maxHour24 ? (maxSeconds % 3600) ~/ 60 : 59;

      void emitTime(int hour24, int minute) {
        final candidate = hour24 * 3600 + minute * 60;
        onChanged(candidate.clamp(minSeconds, maxSeconds).toInt());
      }

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
      final selectedHour12Index =
          validHours12.indexOf(h12).clamp(0, validHours12.length - 1);

      final amAvailable = minSeconds < 43200;
      final pmAvailable = maxSeconds >= 43200;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!use24Hour)
                Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.2),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: amAvailable
                            ? () {
                                if (isPm) {
                                  trimRevision++;
                                  final targetH24 = (h12 % 12);
                                  emitTime(targetH24, m);
                                }
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: !isPm
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'AM',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: !isPm
                                  ? Colors.white
                                  : (amAvailable
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade400),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: pmAvailable
                            ? () {
                                if (!isPm) {
                                  trimRevision++;
                                  final targetH24 = (h12 % 12) + 12;
                                  emitTime(targetH24, m);
                                }
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isPm
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'PM',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isPm
                                  ? Colors.white
                                  : (pmAvailable
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade400),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (use24Hour)
                compactWheel(
                  label: 'H',
                  value: h24,
                  min: minHour24,
                  max: maxHour24.clamp(minHour24, 23).toInt(),
                  onChanged: (v) => emitTime(v, m),
                )
              else
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'H',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      SizedBox(
                        height: 64,
                        child: CupertinoPicker(
                          key: ValueKey(
                            'h12-$isPm-${validHours12.join("-")}-$trimRevision',
                          ),
                          itemExtent: 22,
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedHour12Index,
                          ),
                          onSelectedItemChanged: (index) {
                            final selected12 = validHours12[index];
                            final hour24 = (selected12 % 12) + (isPm ? 12 : 0);
                            emitTime(hour24, m);
                          },
                          children: validHours12
                              .map(
                                (hour) => Center(
                                  child: Text(
                                    two(hour),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  ':',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              compactWheel(
                label: 'M',
                value: m,
                min: minMinute,
                max: maxMinute.clamp(minMinute, 59).toInt(),
                onChanged: (v) => emitTime(h24, v),
              ),
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
              if (!isTomorrow && activeMode == 'Auto' && !isTaskActiveOrPast) {
                final earliestStart = math
                    .max(nextMinuteSeconds, parentStartSeconds)
                    .clamp(parentStartSeconds, parentEndSeconds - 60)
                    .toInt();
                if (startSeconds < earliestStart) {
                  startSeconds = earliestStart;
                  trimRevision++;
                }
                if (useEndTime) {
                  final earliestEnd = math
                      .max(startSeconds + 60, nextMinuteSeconds)
                      .clamp(startSeconds + 60, parentEndSeconds)
                      .toInt();
                  if (endSeconds < earliestEnd) {
                    endSeconds = earliestEnd;
                    trimRevision++;
                  }
                  durationSeconds = (endSeconds - startSeconds)
                      .clamp(
                        60,
                        math.max(60, parentEndSeconds - startSeconds),
                      )
                      .toInt();
                } else {
                  final maxDuration = maxDurationForStart(startSeconds);
                  durationSeconds = durationSeconds
                      .clamp(60, maxDuration)
                      .toInt();
                  endSeconds = startSeconds + durationSeconds;
                }
              }
            });
          });

          final siblings = parent?.children ?? (isTomorrow ? tomorrowTasks : autoTasks);
          final reservedTasks = siblings
              .where((task) => !identical(task, existing))
              .toList()
            ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.88,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Row 1: Title (left) + Legend (right)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isTomorrow
                              ? (existing == null
                                  ? (parent == null ? 'Add Tomorrow Task' : 'Add Tomorrow Subtask')
                                  : 'Edit Tomorrow Task')
                              : (existing == null
                                  ? (parent == null ? 'Add task' : 'Add subtask')
                                  : 'Edit task'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            legendDot(const Color(0xFFE65A52), 'Reserved'),
                            const SizedBox(width: 6),
                            legendDot(const Color(0xFFE86AB3), 'Selected'),
                            const SizedBox(width: 6),
                            legendDot(const Color(0xFF4CAF50), 'Available'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Row 2: Full-width Interactive Trim Timeline Bar!
                    _InteractiveTrimTimeline(
                      rangeStartSeconds: parentStartSeconds,
                      rangeEndSeconds: parentEndSeconds,
                      selectedStartSeconds: startSeconds,
                      selectedEndSeconds: endSeconds,
                      occupied: reservedTasks,
                      use24Hour: use24Hour,
                      isStartLocked: isTaskActiveOrPast,
                      isTomorrow: isTomorrow,
                      minAllowedStartSeconds: (!isTomorrow && activeMode == 'Auto')
                          ? math.max(
                              parentStartSeconds,
                              ((DateTime.now().hour * 3600 +
                                              DateTime.now().minute * 60 +
                                              DateTime.now().second) ~/
                                          60 +
                                      1) *
                                  60,
                            )
                          : parentStartSeconds,
                      minAllowedEndSeconds: (!isTomorrow && activeMode == 'Auto')
                          ? math.max(
                              startSeconds + 60,
                              ((DateTime.now().hour * 3600 +
                                              DateTime.now().minute * 60 +
                                              DateTime.now().second) ~/
                                          60 +
                                      1) *
                                  60,
                            )
                          : startSeconds + 60,
                      onRangeChanged: (newStart, newEnd) => refreshDialog(() {
                        trimRevision++;
                        startSeconds = newStart;
                        endSeconds = newEnd;
                        durationSeconds = (endSeconds - startSeconds)
                            .clamp(60, 86399)
                            .toInt();
                      }),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(height: 5),
                    if (parent != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Parent: ${parent.title} (${_formatMinute(parent.startMinute, use24Hour: use24Hour)}–${_formatMinute(parent.endMinute, use24Hour: use24Hour)})',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    // Task title input
                    TextField(
                      controller: titleController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        hintText: 'Topic / task name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onChanged: (_) => refreshDialog(() {}),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // 2:1 Split Body
                    Flexible(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left 2/3: Reserved List
                          Expanded(
                            flex: 2,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Selected interval card
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE86AB3)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFE86AB3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFE86AB3),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  titleController.text
                                                          .trim()
                                                          .isEmpty
                                                      ? 'Selected Time'
                                                      : titleController.text
                                                          .trim(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                Text(
                                                  '${_formatMinute(startSeconds ~/ 60, use24Hour: use24Hour)} - ${_formatMinute((endSeconds / 60).ceil(), use24Hour: use24Hour)} (${(endSeconds - startSeconds) ~/ 3600 > 0 ? '${(endSeconds - startSeconds) ~/ 3600}h ' : ''}${((endSeconds - startSeconds) % 3600) ~/ 60}m)',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Reserved Intervals Header
                                    Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFE65A52),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Reserved Intervals',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ...reservedTasks.isEmpty
                                        ? [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 12,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'No other tasks reserved\n(Time slot available)',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .outline,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ]
                                        : reservedTasks.map((sibling) {
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.red
                                                    .withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                border: Border.all(
                                                  color: Colors.red
                                                      .withValues(alpha: 0.2),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration:
                                                        const BoxDecoration(
                                                      color:
                                                          Color(0xFFE65A52),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          sibling.title,
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${_formatMinute(sibling.startMinute, use24Hour: use24Hour)} - ${_formatMinute(sibling.endMinute, use24Hour: use24Hour)}',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            color: Theme.of(
                                                              context,
                                                            )
                                                                .colorScheme
                                                                .outline,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const VerticalDivider(width: 1, thickness: 1),
                          const SizedBox(width: 8),
                          // Right 1/3: Time controls & buttons
                          Expanded(
                            flex: 1,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isTaskActiveOrPast)
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.amber
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.lock_clock,
                                            size: 14,
                                            color: Colors.amber,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Locked:\n${_formatMinute(existing.startMinute, use24Hour: use24Hour)}',
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    timePicker(
                                      label: 'Start time',
                                      seconds: startSeconds,
                                      maxSeconds: parent == null
                                          ? 86399
                                          : parentEndSeconds - 60,
                                      minSeconds: (!isTomorrow && activeMode == 'Auto')
                                          ? math.max(
                                              parentStartSeconds,
                                              ((DateTime.now().hour * 3600 +
                                                              DateTime.now()
                                                                      .minute *
                                                                  60 +
                                                              DateTime.now()
                                                                  .second) ~/
                                                          60 +
                                                      1) *
                                                  60,
                                            )
                                          : (parent == null
                                              ? 0
                                              : parentStartSeconds),
                                      onChanged: (v) => refreshDialog(() {
                                        final freshNow = DateTime.now();
                                        final currentSeconds =
                                            freshNow.hour * 3600 +
                                                freshNow.minute * 60 +
                                                freshNow.second;
                                        final minimumStart = (!isTomorrow && activeMode == 'Auto')
                                            ? math.max(
                                                parentStartSeconds,
                                                (currentSeconds ~/ 60 + 1) * 60,
                                              )
                                            : parentStartSeconds;
                                        startSeconds = v
                                            .clamp(
                                              minimumStart,
                                              parentEndSeconds - 60,
                                            )
                                            .toInt();
                                        if (useEndTime) {
                                          final nextMinute =
                                              (currentSeconds ~/ 60 + 1) * 60;
                                          final minimumEnd = (!isTomorrow && activeMode == 'Auto')
                                              ? math
                                                  .max(
                                                    startSeconds + 60,
                                                    nextMinute,
                                                  )
                                                  .clamp(
                                                    startSeconds + 60,
                                                    parentEndSeconds,
                                                  )
                                                  .toInt()
                                              : (startSeconds + 60)
                                                  .clamp(
                                                    startSeconds + 60,
                                                    parentEndSeconds,
                                                  )
                                                  .toInt();
                                          if (endSeconds < minimumEnd) {
                                            endSeconds = minimumEnd;
                                            trimRevision++;
                                          }
                                          if (endSeconds > parentEndSeconds) {
                                            endSeconds = parentEndSeconds;
                                          }
                                          durationSeconds =
                                              (endSeconds - startSeconds)
                                                  .clamp(
                                                    60,
                                                    math.max(
                                                      60,
                                                      parentEndSeconds -
                                                          startSeconds,
                                                    ),
                                                  )
                                                  .toInt();
                                        } else {
                                          final maxDuration =
                                              maxDurationForStart(startSeconds);
                                          durationSeconds = durationSeconds
                                              .clamp(60, maxDuration)
                                              .toInt();
                                          endSeconds =
                                              startSeconds + durationSeconds;
                                        }
                                      }),
                                    ),
                                  const SizedBox(height: 6),
                                  // End time / Duration toggle
                                  Container(
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.grey.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => refreshDialog(() {
                                              useEndTime = true;
                                              trimRevision++;
                                              final maxDuration =
                                                  maxDurationForStart(
                                                startSeconds,
                                              );
                                              durationSeconds = durationSeconds
                                                  .clamp(60, maxDuration)
                                                  .toInt();
                                              endSeconds = (startSeconds +
                                                      durationSeconds)
                                                  .clamp(
                                                    startSeconds + 60,
                                                    parentEndSeconds,
                                                  )
                                                  .toInt();
                                            }),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: useEndTime
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                'End time',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: useEndTime
                                                      ? Colors.white
                                                      : Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => refreshDialog(() {
                                              useEndTime = false;
                                              trimRevision++;
                                              final maxDuration =
                                                  maxDurationForStart(
                                                startSeconds,
                                              );
                                              durationSeconds =
                                                  (endSeconds - startSeconds)
                                                      .clamp(60, maxDuration)
                                                      .toInt();
                                              endSeconds = startSeconds +
                                                  durationSeconds;
                                            }),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: !useEndTime
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                'Duration',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: !useEndTime
                                                      ? Colors.white
                                                      : Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // End time or Duration picker
                                  if (useEndTime)
                                    timePicker(
                                      label: 'End time',
                                      seconds: endSeconds,
                                      maxSeconds: parent == null
                                          ? 86399
                                          : parentEndSeconds,
                                      minSeconds: (!isTomorrow && activeMode == 'Auto')
                                          ? math
                                              .max(
                                                startSeconds + 60,
                                                ((DateTime.now().hour * 3600 +
                                                            DateTime.now()
                                                                    .minute *
                                                                60 +
                                                            DateTime.now()
                                                                .second) ~/
                                                        60 +
                                                    1) *
                                                    60,
                                              )
                                              .clamp(
                                                startSeconds + 60,
                                                parentEndSeconds,
                                              )
                                              .toInt()
                                          : startSeconds + 60,
                                      onChanged: (v) => refreshDialog(() {
                                        final freshNow = DateTime.now();
                                        final currentSeconds =
                                            freshNow.hour * 3600 +
                                                freshNow.minute * 60 +
                                                freshNow.second;
                                        final minimumEnd = (!isTomorrow && activeMode == 'Auto')
                                            ? math
                                                .max(
                                                  startSeconds + 60,
                                                  (currentSeconds ~/ 60 + 1) *
                                                      60,
                                                )
                                                .clamp(
                                                  startSeconds + 60,
                                                  parentEndSeconds,
                                                )
                                                .toInt()
                                            : (startSeconds + 60)
                                                .clamp(
                                                  startSeconds + 60,
                                                  parentEndSeconds,
                                                )
                                                .toInt();
                                        endSeconds = v
                                            .clamp(minimumEnd, parentEndSeconds)
                                            .toInt();
                                        durationSeconds =
                                            (endSeconds - startSeconds)
                                                .clamp(60, 86399)
                                                .toInt();
                                      }),
                                    )
                                  else
                                    timePicker(
                                      label: 'Duration',
                                      seconds: durationSeconds,
                                      maxSeconds:
                                          maxDurationForStart(startSeconds),
                                      minSeconds: 60,
                                      isDuration: true,
                                      onChanged: (v) => refreshDialog(() {
                                        final maxDuration =
                                            maxDurationForStart(startSeconds);
                                        durationSeconds =
                                            v.clamp(60, maxDuration).toInt();
                                        endSeconds = (startSeconds +
                                                durationSeconds)
                                            .clamp(
                                              startSeconds + 60,
                                              parentEndSeconds,
                                            )
                                            .toInt();
                                        durationSeconds =
                                            endSeconds - startSeconds;
                                      }),
                                    ),
                                  const SizedBox(height: 6),
                                  // Alarm button
                                  InkWell(
                                    onTap: () async {
                                      if (!alarmEnabled) {
                                        final canNotify =
                                            await DistractionService.instance
                                                .canPostNotifications();
                                        if (!canNotify && context.mounted) {
                                          final ask = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                  'Notification Permission'),
                                              content: const Text(
                                                'System status bar-e alarm dekhar jonno Notification permission proyojon. Apni ki permission dite chan?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text('Later'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text(
                                                      'Allow Permission'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ask == true) {
                                            await DistractionService.instance
                                                .requestNotificationPermission();
                                          }
                                        }
                                      }
                                      refreshDialog(() {
                                        if (!alarmEnabled) {
                                          alarmEnabled = true;
                                          alarmLeadSeconds = 120;
                                        } else {
                                          if (alarmLeadSeconds <= 120) {
                                            alarmLeadSeconds = 300;
                                          } else if (alarmLeadSeconds == 300) {
                                            alarmLeadSeconds = 420;
                                          } else if (alarmLeadSeconds == 420) {
                                            alarmLeadSeconds = 600;
                                          } else {
                                            alarmEnabled = false;
                                            alarmLeadSeconds = 120;
                                          }
                                        }
                                      });
                                    },
                                    child: Container(
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: alarmEnabled
                                            ? Colors.orange
                                                .withValues(alpha: 0.15)
                                            : Colors.grey
                                                .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: alarmEnabled
                                              ? Colors.orange
                                              : Colors.grey.shade400,
                                          width: 0.8,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            alarmEnabled
                                                ? Icons.notifications_active
                                                : Icons.notifications_none,
                                            size: 13,
                                            color: alarmEnabled
                                                ? Colors.orange
                                                : Colors.grey,
                                          ),
                                          const SizedBox(width: 3),
                                          Flexible(
                                            child: Text(
                                              alarmEnabled
                                                  ? '${(alarmLeadSeconds / 60).round()}m'
                                                  : 'Alarm',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: alarmEnabled
                                                    ? Colors.orange.shade800
                                                    : Colors.grey.shade700,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Save button (no cancel button)
                                  SizedBox(
                                    height: 32,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                      ),
                                      onPressed: () {
                                        final title =
                                            titleController.text.trim();
                                        final start = startSeconds ~/ 60;
                                        final maxDurationAtSave =
                                            maxDurationForStart(startSeconds);
                                        if (!useEndTime &&
                                            durationSeconds >
                                                maxDurationAtSave) {
                                          refreshDialog(() {
                                            durationSeconds = maxDurationAtSave;
                                            endSeconds =
                                                startSeconds + durationSeconds;
                                            validationError =
                                                'Duration 23:59:59 porjonto simito kora hoyeche. Review kore abar Save korun.';
                                          });
                                          return;
                                        }
                                        final endInSeconds = useEndTime
                                            ? endSeconds
                                            : startSeconds + durationSeconds;
                                        final end = (endInSeconds / 60).ceil();
                                        if (title.isEmpty) {
                                          refreshDialog(
                                            () => validationError =
                                                'Topic / task name likhun.',
                                          );
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
                                        if (!isTomorrow && activeMode == 'Auto') {
                                          final saveNow = DateTime.now();
                                          final saveNowSeconds =
                                              saveNow.hour * 3600 +
                                                  saveNow.minute * 60 +
                                                  saveNow.second;
                                          final earliestAllowedStart = math.max(
                                            parentStartSeconds,
                                            (saveNowSeconds ~/ 60 + 1) * 60,
                                          );
                                          if (!isTaskActiveOrPast &&
                                              startSeconds <
                                                  earliestAllowedStart) {
                                            refreshDialog(() {
                                              startSeconds = earliestAllowedStart
                                                  .clamp(
                                                    parentStartSeconds,
                                                    parentEndSeconds - 60,
                                                  )
                                                  .toInt();
                                              final nextEndMinute = math
                                                  .max(
                                                    startSeconds + 60,
                                                    earliestAllowedStart,
                                                  )
                                                  .clamp(
                                                    startSeconds + 60,
                                                    parentEndSeconds,
                                                  )
                                                  .toInt();
                                              if (endSeconds < nextEndMinute) {
                                                endSeconds = nextEndMinute;
                                              }
                                              durationSeconds =
                                                  (endSeconds - startSeconds)
                                                      .clamp(60, 86399)
                                                      .toInt();
                                              validationError =
                                                  'Auto mode-e past time select kora jabe na. Start time update kora hoyeche; review kore abar Save korun.';
                                            });
                                            return;
                                          }
                                          if (useEndTime) {
                                            final earliestAllowedEndMinute =
                                                math.max(
                                              startSeconds ~/ 60 + 1,
                                              saveNowSeconds ~/ 60 + 1,
                                            );
                                            if (end <
                                                earliestAllowedEndMinute) {
                                              refreshDialog(() {
                                                endSeconds =
                                                    (earliestAllowedEndMinute *
                                                            60)
                                                        .clamp(
                                                          startSeconds + 60,
                                                          parentEndSeconds,
                                                        )
                                                        .toInt();
                                                durationSeconds =
                                                    (endSeconds - startSeconds)
                                                        .clamp(60, 86399)
                                                        .toInt();
                                                validationError =
                                                    'End time must be in a future minute. Review kore abar Save korun.';
                                              });
                                              return;
                                            }
                                          }
                                          if (existing != null &&
                                              _isTaskLockedForChanges(
                                                existing,
                                              )) {
                                            refreshDialog(
                                              () => validationError =
                                                  'This task is locked in Auto Mode because its time has ended.',
                                            );
                                            return;
                                          }
                                          if (existing != null &&
                                              existing.startMinute * 60 <
                                                  saveNowSeconds &&
                                              start != existing.startMinute) {
                                            refreshDialog(
                                              () => validationError =
                                                  'In Auto Mode, a running task start time cannot be changed.',
                                            );
                                            return;
                                          }
                                          if (existing != null &&
                                              existing.startMinute * 60 <
                                                  saveNowSeconds &&
                                              endInSeconds <= saveNowSeconds) {
                                            refreshDialog(
                                              () => validationError =
                                                  'A running task can only be extended to a future end time.',
                                            );
                                            return;
                                          }
                                        }

                                        final overlaps =
                                            reservedTasks.any((other) {
                                          return start < other.endMinute &&
                                              other.startMinute < end;
                                        });
                                        if (overlaps) {
                                          refreshDialog(
                                            () => validationError =
                                                'This time overlaps another task at the same level.',
                                          );
                                          return;
                                        }
                                        if (parent != null &&
                                            (startSeconds <
                                                    parent.startMinute * 60 ||
                                                endInSeconds >
                                                    parent.endMinute * 60)) {
                                          refreshDialog(
                                            () => validationError =
                                                'Choose a time entirely within ${parent.title} (${_formatMinute(parent.startMinute, use24Hour: use24Hour)}–${_formatMinute(parent.endMinute, use24Hour: use24Hour)}).',
                                          );
                                          return;
                                        }
                                        if (parent != null &&
                                            (start < parent.startMinute ||
                                                end > parent.endMinute)) {
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

                                        if (existing != null &&
                                            !descendantsFit(existing)) {
                                          refreshDialog(
                                            () => validationError =
                                                'Parent time range must contain every subtask.',
                                          );
                                          return;
                                        }
                                        setState(() {
                                          if (existing != null) {
                                            existing.title = title;
                                            existing.startMinute = start;
                                            existing.endMinute = end;
                                            existing.alarmEnabled =
                                                alarmEnabled;
                                            existing.alarmLeadSeconds =
                                                alarmLeadSeconds;
                                          } else {
                                            siblings.add(
                                              TaskNode(
                                                title: title,
                                                startMinute: start,
                                                endMinute: end,
                                                alarmEnabled: alarmEnabled,
                                                alarmLeadSeconds:
                                                    alarmLeadSeconds,
                                              ),
                                            );
                                          }
                                          if (parent != null) {
                                            _syncAncestors(parent);
                                          }
                                        });
                                        Navigator.pop(dialogContext);
                                        _saveRoutineTasks().catchError((
                                          Object error,
                                        ) {
                                          debugPrint(
                                            'Could not save routine tasks: $error',
                                          );
                                        });
                                      },
                                      child: const Text(
                                        'Save',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => dialogClockTimer?.cancel());
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

  List<TimeInterval> _allLeafIntervals(List<TaskNode> nodes) {
    final intervals = <TimeInterval>[];
    for (final task in nodes) {
      if (task.children.isEmpty) {
        if (task.endMinute > task.startMinute) {
          intervals.add(
            TimeInterval(task.startMinute * 60, task.endMinute * 60),
          );
        }
      } else {
        intervals.addAll(_allLeafIntervals(task.children));
      }
    }
    intervals.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    return intervals;
  }

  int _totalPlannedSeconds(List<TaskNode> nodes) {
    final intervals = _allLeafIntervals(nodes);
    var total = 0;
    var mergedStart = -1;
    var mergedEnd = -1;
    for (final interval in intervals) {
      if (mergedStart == -1) {
        mergedStart = interval.startSeconds;
        mergedEnd = interval.endSeconds;
      } else if (interval.startSeconds <= mergedEnd) {
        if (interval.endSeconds > mergedEnd) {
          mergedEnd = interval.endSeconds;
        }
      } else {
        total += (mergedEnd - mergedStart);
        mergedStart = interval.startSeconds;
        mergedEnd = interval.endSeconds;
      }
    }
    if (mergedStart != -1) {
      total += (mergedEnd - mergedStart);
    }
    return total;
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

  void _openJournalNotepadForDay(SampleDay day) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => JournalNotepadSheet(
          date: day.date,
          initialEmoji: day.emoji,
          initialTitle: day.memoryTitle,
          initialNote: day.memoryNote,
          initialImages: day.memoryImages,
          onSave: ({
            required String? emoji,
            required String? title,
            required String? note,
            required List<String> images,
          }) async {
            final record = RoutineDayRecord(
              date: day.date,
              progress: day.progress,
              mode: day.mode,
              tasks: day.tasks,
              emoji: emoji,
              memoryTitle: title,
              memoryNote: note,
              memoryImages: images,
              distractions: day.distractions,
            );
            await _historyStore.save(record);
            await _loadRoutineHistory();
          },
        ),
      ),
    );
  }

  void _openJournalNotepadForToday() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => JournalNotepadSheet(
          date: now,
          initialEmoji: _todayJournal.emoji,
          initialTitle: _todayJournal.title,
          initialNote: _todayJournal.note,
          initialImages: _todayJournal.images,
          onSave: ({
            required String? emoji,
            required String? title,
            required String? note,
            required List<String> images,
          }) async {
            final updated = TodayJournalEntry(
              emoji: emoji,
              title: title,
              note: note,
              images: images,
            );
            await _todayJournalStore.save(updated);
            if (mounted) {
              setState(() {
                _todayJournal = updated;
              });
            }
          },
        ),
      ),
    );
  }

  String _todayMemoryLabel() {
    if (_todayJournal.hasContent) {
      final emoji = _todayJournal.emoji ?? '⭐';
      final title = _todayJournal.title?.isNotEmpty == true
          ? _todayJournal.title!
          : 'Memorable Day';
      return '$emoji $title';
    }
    return "Today's Memory Journal";
  }

  Future<void> _promptAddDistractionManually() async {
    final customController = TextEditingController();
    final pinnedChips = await DistractionService.instance.getPinnedChips();
    final recentChips = await DistractionService.instance.getRecentChips();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text('Log Distraction'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: customController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Reason + emoji (e.g. Reels 📱)...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () async {
                          final text = customController.text.trim();
                          if (text.isNotEmpty) {
                            if (!pinnedChips.any(
                                (c) => c.toLowerCase() == text.toLowerCase())) {
                              pinnedChips.insert(0, text);
                              await DistractionService.instance
                                  .savePinnedChips(pinnedChips);
                              customController.clear();
                              setDialogState(() {});
                            }
                          }
                        },
                        child: const Text('📌 Pin',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  if (pinnedChips.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '📌 Pinned (Tap to track • Long-press to unpin)',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: pinnedChips
                          .map(
                            (c) => InkWell(
                              onTap: () async {
                                Navigator.pop(ctx);
                                await DistractionService.instance
                                    .recordDistraction(c);
                                if (!recentChips.any((r) =>
                                    r.toLowerCase() == c.toLowerCase())) {
                                  recentChips.insert(0, c);
                                  await DistractionService.instance
                                      .saveRecentChips(recentChips);
                                }
                              },
                              onLongPress: () async {
                                pinnedChips.removeWhere((item) =>
                                    item.toLowerCase() == c.toLowerCase());
                                await DistractionService.instance
                                    .savePinnedChips(pinnedChips);
                                setDialogState(() {});
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    Colors.teal.withValues(alpha: 0.15),
                                side: BorderSide(
                                    color:
                                        Colors.teal.withValues(alpha: 0.4)),
                                label: Text('📌 $c',
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (recentChips.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '🕒 Recent (Tap to track • Long-press to pin)',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: recentChips
                          .map(
                            (c) => InkWell(
                              onTap: () async {
                                Navigator.pop(ctx);
                                await DistractionService.instance
                                    .recordDistraction(c);
                              },
                              onLongPress: () async {
                                if (!pinnedChips.any((p) =>
                                    p.toLowerCase() == c.toLowerCase())) {
                                  pinnedChips.insert(0, c);
                                  await DistractionService.instance
                                      .savePinnedChips(pinnedChips);
                                  setDialogState(() {});
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Theme.of(ctx)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                label: Text(c,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (pinnedChips.isEmpty && recentChips.isEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Type any reason above and tap "📌 Pin" or "Save". Pinned items stay permanently on your clipboard.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final text = customController.text.trim();
                if (text.isNotEmpty) {
                  await DistractionService.instance.recordDistraction(text);
                  if (!recentChips
                      .any((r) => r.toLowerCase() == text.toLowerCase())) {
                    recentChips.insert(0, text);
                    await DistractionService.instance
                        .saveRecentChips(recentChips);
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save ⚡'),
            ),
          ],
        ),
      ),
    );
  }

  String _cleanNoteSummary(String raw) {
    if (raw.trim().startsWith('{"version":')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['blocks'] is List) {
          final list = (decoded['blocks'] as List)
              .whereType<Map>()
              .map((m) {
                final t = m['type']?.toString() ?? 'text';
                final text = m['text']?.toString() ?? '';
                if (t == 'bullet') return '• $text';
                if (t == 'checkbox') {
                  final checked = m['isChecked'] == true ? '✓' : '□';
                  return '$checked $text';
                }
                if (t == 'image') return '🖼️ [Photo]';
                return text;
              })
              .where((t) => t.trim().isNotEmpty)
              .toList();
          return list.join('\n');
        }
      } catch (_) {}
    }
    return raw;
  }

  Widget _buildMemorableDayCardInSheet(SampleDay day) {
    final hasNote = (day.emoji != null && day.emoji!.isNotEmpty) ||
        (day.memoryTitle != null && day.memoryTitle!.isNotEmpty) ||
        (day.memoryNote != null && day.memoryNote!.isNotEmpty);

    if (hasNote) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.10),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    day.emoji ?? '⭐',
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        day.memoryTitle?.isNotEmpty == true
                            ? day.memoryTitle!
                            : 'Memorable Day',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Memory Note & Graph Mark',
                        style: TextStyle(fontSize: 11, color: Colors.amber),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.edit_note_rounded),
                  tooltip: 'Open / Edit Note',
                  onPressed: () {
                    Navigator.pop(context);
                    _openJournalNotepadForDay(day);
                  },
                ),
              ],
            ),
            if (day.memoryNote != null && day.memoryNote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _cleanNoteSummary(day.memoryNote!),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
            if (day.memoryImages != null && day.memoryImages!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.photo_library_outlined,
                      size: 16, color: Colors.teal),
                  const SizedBox(width: 6),
                  Text(
                    '${day.memoryImages!.length} attached photo(s)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.bookmark_add_outlined, color: Colors.amber),
        label: const Text('Mark as Memorable Day (Add Emoji & Note)'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.6)),
        ),
        onPressed: () {
          Navigator.pop(context);
          _openJournalNotepadForDay(day);
        },
      ),
    );
  }

  Widget _buildDistractionsSectionInSheet(
    SampleDay day, {
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    final isToday = _dateKey(day.date) == _dateKey(now);
    final list = isToday
        ? _todayDistractions.map((d) => d.toJson()).toList()
        : (day.distractions ?? const <Map<String, dynamic>>[]);
    final count = list.length;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: count > 0
              ? const Color(0xFFE53935).withValues(alpha: 0.45)
              : Colors.grey.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: count > 0
                          ? const Color(0xFFE53935).withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.radar_rounded,
                      size: 20,
                      color: count > 0 ? const Color(0xFFE53935) : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Distraction Tracker',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          count > 0
                              ? '$count distraction${count == 1 ? '' : 's'} logged'
                              : '0 distractions (100% focused day!)',
                          style: TextStyle(
                            fontSize: 12,
                            color: count > 0
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isExpanded ? 'Hide' : 'Details',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: list.isEmpty
                  ? const Text(
                      'No distractions were recorded on this day. Great job!',
                      style: TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: list.map((item) {
                        final name = item['name']?.toString() ?? 'Distraction';
                        final timeLabel = item['timeLabel']?.toString() ?? '';
                        return Chip(
                          backgroundColor:
                              Colors.redAccent.withValues(alpha: 0.12),
                          side: BorderSide(
                              color:
                                  Colors.redAccent.withValues(alpha: 0.3)),
                          avatar: const Icon(Icons.block,
                              size: 14, color: Colors.redAccent),
                          label: Text(
                            timeLabel.isNotEmpty
                                ? '$name • $timeLabel'
                                : name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  void _showDayDetailsSheet(
    SampleDay day,
    int index,
    List<SampleDay> allDays,
  ) {
    var openPts = 0.0;
    for (var i = 0; i < index; i++) {
      openPts += allDays[i].progress;
    }
    final closePts = openPts + day.progress;

    final Color candleColor;
    if (day.progress < 40.0) {
      candleColor = kCandleRed;
    } else if (day.progress < 60.0) {
      candleColor = kCandleYellow;
    } else {
      candleColor = kGreen;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        var distractionsExpanded = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.35,
              maxChildSize: 0.92,
              expand: false,
              builder: (context, scrollController) {
                final tasks = day.tasks;
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_month(day.date.month)} ${day.date.day}, ${day.date.year}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Mode: ${day.mode} Mode (Historical Read-Only)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: candleColor.withValues(alpha: 0.18),
                            border: Border.all(color: candleColor, width: 1.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${day.progress.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: candleColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Open',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${openPts.toStringAsFixed(1)} pts',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              width: 1,
                              height: 28,
                              color: Theme.of(context).dividerColor,
                            ),
                            Column(
                              children: [
                                Text(
                                  'Close',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${closePts.toStringAsFixed(1)} pts',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              width: 1,
                              height: 28,
                              color: Theme.of(context).dividerColor,
                            ),
                            Column(
                              children: [
                                Text(
                                  'Tracked Time',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatHms((day.progress / 100 * 86400).round()),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildMemorableDayCardInSheet(day),
                    _buildDistractionsSectionInSheet(
                      day,
                      isExpanded: distractionsExpanded,
                      onToggle: () {
                        setSheetState(() {
                          distractionsExpanded = !distractionsExpanded;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Tasks Snapshot',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (tasks != null && tasks.isNotEmpty)
                          TextButton.icon(
                            icon: const Icon(Icons.favorite_rounded,
                                size: 16, color: Colors.pinkAccent),
                            label: const Text('Save as Favorite'),
                            onPressed: () =>
                                _promptSaveSnapshotAsFavorite(tasks, day.mode),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (tasks == null || tasks.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                day.progress == 0
                                    ? 'No tasks were recorded for this day (0% progress / App not opened).'
                                    : 'No task list snapshot stored for this date (legacy record before task snapshots were enabled).',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...tasks.map(
                        (taskMap) => _buildHistoricalTaskItem(taskMap, 0),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHistoricalTaskItem(Map<String, dynamic> task, int depth) {
    final title = task['title']?.toString() ?? 'Task';
    final isDone = task['done'] == true;
    final startMin = (task['startMinute'] as num?)?.toInt() ?? 0;
    final endMin = (task['endMinute'] as num?)?.toInt() ?? 60;
    final rawChildren = task['children'];
    final children = rawChildren is List
        ? rawChildren
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDone
                    ? Icons.check_circle_rounded
                    : Icons.cancel_outlined,
                color: isDone ? kGreen : kCandleRed,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isDone ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                '${_formatMinute(startMin, use24Hour: use24Hour)} – ${_formatMinute(endMin, use24Hour: use24Hour)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDone
                      ? kGreen.withValues(alpha: 0.15)
                      : kCandleRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isDone ? 'DONE' : 'MISSED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDone ? kGreen : kCandleRed,
                  ),
                ),
              ),
            ],
          ),
          if (children.isNotEmpty)
            ...children.map(
              (child) => _buildHistoricalTaskItem(child, depth + 1),
            ),
        ],
      ),
    );
  }

  void _showHistoricalDetailsList() {
    final todayKey = _dateKey(now);
    final pastRecords =
        _savedHistory.where((r) => r.dateKey != todayKey).toList();
    if (pastRecords.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Historical Details'),
          content: const Text(
            'No past days recorded yet. Today\'s tasks and progress will be saved into history automatically at midnight.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final sample = pastRecords
        .map(
          (record) => SampleDay(
            record.date,
            record.progress,
            record.mode,
            tasks: record.tasks,
            emoji: record.emoji,
            memoryTitle: record.memoryTitle,
            memoryNote: record.memoryNote,
            memoryImages: record.memoryImages,
            distractions: record.distractions,
          ),
        )
        .toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.70,
          minChildSize: 0.40,
          maxChildSize: 0.94,
          expand: false,
          builder: (context, scrollController) {
            return ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              itemCount: sample.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                // Show most recent first in the list
                final revIndex = sample.length - 1 - index;
                final day = sample[revIndex];
                final Color candleColor;
                if (day.progress < 40.0) {
                  candleColor = kCandleRed;
                } else if (day.progress < 60.0) {
                  candleColor = kCandleYellow;
                } else {
                  candleColor = kGreen;
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: candleColor.withValues(alpha: 0.2),
                    child: Icon(Icons.show_chart_rounded, color: candleColor),
                  ),
                  title: Text(
                    '${_month(day.date.month)} ${day.date.day}, ${day.date.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Mode: ${day.mode} • Progress: ${day.progress.toStringAsFixed(1)}%',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showDayDetailsSheet(day, revIndex, sample);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _exportHistory() async {
    try {
      final favoritesJson = await _templateStore.exportAllToJson();
      final consistencyJson = await ConsistencyStore().exportData();
      final file = await _historyStore.exportToFile(
        favoriteTemplates: favoritesJson,
        consistencyData: consistencyJson,
      );

      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'dayaura_backup_$timestamp.json';

      // 1. Directly auto-save to Download/DayAura/ folder without manual picking
      String? savedPath;
      try {
        final content = await file.readAsString();
        savedPath = await DistractionService.instance.saveBackupFile(
          fileName: fileName,
          content: content,
        );
      } catch (e) {
        debugPrint('Direct save to DayAura folder failed: $e');
      }

      final displayPath = savedPath ?? 'Download/DayAura/$fileName';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to $displayPath'),
          backgroundColor: kGreen,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(
                  files: [XFile(file.path, mimeType: 'application/json')],
                  subject: 'DayAura Backup',
                  text: 'DayAura backup file.',
                ),
              );
            },
          ),
        ),
      );
    } catch (error) {
      debugPrint('Download error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $error'),
            backgroundColor: kCandleRed,
          ),
        );
      }
    }
  }

  Future<void> _importHistory() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: '/storage/emulated/0/Download/DayAura',
      );

      if (files.isEmpty) return;
      final filePath = files.first.path;
      if (filePath == null) return;

      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          _showErrorDialog(
            title: 'File Not Found',
            message: 'The selected backup file could not be read.',
          );
        }
        return;
      }

      final content = await file.readAsString();
      final records = _historyStore.validateImportData(content);

      if (records == null) {
        if (mounted) {
          _showErrorDialog(
            title: 'Invalid Backup File',
            message:
                'The selected file is not a valid DayAura backup file. Please select a valid .json backup file.',
          );
        }
        return;
      }

      if (!mounted) return;

      // English Confirmation Dialog (per requirement)
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Confirm Upload & Restore'),
          content: const Text(
            'Uploading this backup will restore the graph and history data from the file. Your User ID and app settings will remain unchanged.\n\nDo you want to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kGreen),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      // Fill any gap between the latest imported record and today with 0% progress
      var missingDaysFilled = 0;
      if (records.isNotEmpty) {
        records.sort((a, b) => a.date.compareTo(b.date));
        final lastRecordDate = records.last.date;
        final lastDateOnly = DateTime(lastRecordDate.year, lastRecordDate.month, lastRecordDate.day);
        final todayOnly = DateTime(now.year, now.month, now.day);
        final daysDiff = todayOnly.difference(lastDateOnly).inDays;

        if (daysDiff > 1) {
          final lastMode = records.last.mode;
          for (var d = 1; d < daysDiff; d++) {
            final missedDate = lastDateOnly.add(Duration(days: d));
            records.add(
              RoutineDayRecord(
                date: missedDate,
                progress: 0.0,
                mode: lastMode.isNotEmpty ? lastMode : 'Auto',
                tasks: null,
              ),
            );
            missingDaysFilled++;
          }
          records.sort((a, b) => a.date.compareTo(b.date));
        }
      }

      await _historyStore.importHistory(records);
      await _loadRoutineHistory();
      _currentRoutineDate = _dateKey(now);
      await _saveRoutineTasks();

      // Restore favorites if present in the backup JSON
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic> && decoded['favorites'] is List) {
          final favList = (decoded['favorites'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          await _templateStore.importMultiple(favList);
        }
        if (decoded is Map<String, dynamic> && decoded['consistency'] is Map) {
          await ConsistencyStore().importData(
            Map<String, dynamic>.from(decoded['consistency']),
          );
        }
      } catch (_) {}

      if (mounted) {
        setState(() {});
        final msg = missingDaysFilled > 0
            ? 'Backup uploaded and restored successfully! (${records.length} days loaded, including $missingDaysFilled missed days at 0%)'
            : 'Backup uploaded and restored successfully! (${records.length} days loaded)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: kGreen,
          ),
        );
      }
    } catch (error) {
      debugPrint('Upload error: $error');
      if (mounted) {
        _showErrorDialog(
          title: 'Upload Failed',
          message: 'An error occurred while uploading: $error',
        );
      }
    }
  }

  void _showErrorDialog({required String title, required String message}) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _promptSaveCurrentAsFavorite() {
    if (currentTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one task before saving as favorite.'),
        ),
      );
      return;
    }
    _promptSaveTasksAsFavorite(
      tasks: currentTasks.map((t) => t.toJson()).toList(),
      mode: activeMode,
      defaultTitle: 'My $activeMode Routine',
    );
  }

  void _promptSaveSnapshotAsFavorite(
      List<Map<String, dynamic>> tasks, String mode) {
    _promptSaveTasksAsFavorite(
      tasks: tasks,
      mode: mode,
      defaultTitle: '$mode Routine Template',
    );
  }

  void _promptSaveTasksAsFavorite({
    required List<Map<String, dynamic>> tasks,
    required String mode,
    required String defaultTitle,
  }) {
    final controller = TextEditingController(text: defaultTitle);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
            SizedBox(width: 8),
            Text('Save Favorite Routine'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Give this routine a memorable name (e.g. Focus Study Day, Exam Rush, Sunday Chill):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Routine Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mode: $mode • ${tasks.length} top-level tasks',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(dialogContext);

              final template = RoutineTemplate(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: title,
                createdAt: DateTime.now(),
                mode: mode,
                tasks: tasks,
              );
              await _templateStore.save(template);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Saved "$title" as a Favorite Routine!'),
                    backgroundColor: kGreen,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showFavoriteRoutinesSheet() {
    final Set<String> expandedRoutineIds = <String>{};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<RoutineTemplate>>(
              future: _templateStore.load(),
              builder: (context, snapshot) {
                final templates = snapshot.data ?? [];
                return DraggableScrollableSheet(
                  initialChildSize: 0.70,
                  minChildSize: 0.40,
                  maxChildSize: 0.94,
                  expand: false,
                  builder: (context, scrollController) {
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.favorite_rounded,
                                color: Colors.pinkAccent),
                            const SizedBox(width: 10),
                            Text(
                              'Favorite Routines',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Import Routine from file',
                              icon: const Icon(Icons.file_open_rounded),
                              onPressed: () async {
                                await _importSingleRoutine();
                                setSheetState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Apply saved templates directly to today, or share single routines with friends.',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (templates.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.favorite_border_rounded,
                                    size: 48,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No favorite routines saved yet',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tap the heart icon in Today Setup to save your day as a reusable template.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await _importSingleRoutine();
                                      setSheetState(() {});
                                    },
                                    icon: const Icon(Icons.file_open_rounded),
                                    label: const Text('Import Routine File'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ...templates.map((tpl) {
                            final isExpanded =
                                expandedRoutineIds.contains(tpl.id);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setSheetState(() {
                                    if (isExpanded) {
                                      expandedRoutineIds.remove(tpl.id);
                                    } else {
                                      expandedRoutineIds.add(tpl.id);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const CircleAvatar(
                                            radius: 18,
                                            backgroundColor: Color(0x22E91E63),
                                            child: Icon(Icons.favorite_rounded,
                                                size: 20,
                                                color: Colors.pinkAccent),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  tpl.title,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16),
                                                ),
                                                Text(
                                                  '${tpl.mode} mode • ${tpl.totalTasksCount} tasks ${isExpanded ? "• Tap to collapse" : "• Tap to view schedule"}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: isExpanded
                                                ? 'Hide Details'
                                                : 'View Details',
                                            icon: Icon(
                                              isExpanded
                                                  ? Icons.keyboard_arrow_up_rounded
                                                  : Icons
                                                      .keyboard_arrow_down_rounded,
                                              size: 24,
                                            ),
                                            onPressed: () {
                                              setSheetState(() {
                                                if (isExpanded) {
                                                  expandedRoutineIds
                                                      .remove(tpl.id);
                                                } else {
                                                  expandedRoutineIds
                                                      .add(tpl.id);
                                                }
                                              });
                                            },
                                          ),
                                          IconButton(
                                            tooltip: 'Share Routine (.json)',
                                            icon: const Icon(
                                                Icons.share_rounded,
                                                size: 20),
                                            onPressed: () =>
                                                _shareSingleRoutine(tpl),
                                          ),
                                          IconButton(
                                            tooltip: 'Delete',
                                            icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20),
                                            onPressed: () async {
                                              await _templateStore
                                                  .delete(tpl.id);
                                              setSheetState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                      if (isExpanded) ...[
                                        const SizedBox(height: 10),
                                        const Divider(height: 1),
                                        const SizedBox(height: 8),
                                        _buildRoutineTemplateTasksPreview(tpl),
                                      ],
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.tonalIcon(
                                        icon: const Icon(
                                            Icons.play_arrow_rounded),
                                        label: const Text('Apply to Today'),
                                        onPressed: () async {
                                          String selectedTarget = _planningTab;
                                          final chosenTarget =
                                              await showDialog<String>(
                                            context: context,
                                            builder: (ctx) => StatefulBuilder(
                                              builder:
                                                  (dialogCtx, setDialogState) {
                                                return AlertDialog(
                                                  title: const Text(
                                                      'Apply Routine'),
                                                  content: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Applying "${tpl.title}" will replace tasks with this template. All tasks will start fresh.',
                                                        style: const TextStyle(
                                                            fontSize: 13),
                                                      ),
                                                      const SizedBox(
                                                          height: 16),
                                                      const Text(
                                                        'Apply to which routine?',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      RadioListTile<String>(
                                                        dense: true,
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        title: const Text(
                                                            'Today Routine'),
                                                        subtitle: const Text(
                                                          'Apply to today\'s active timeline',
                                                          style: TextStyle(
                                                              fontSize: 11),
                                                        ),
                                                        value: 'Today',
                                                        groupValue:
                                                            selectedTarget,
                                                        onChanged: (val) {
                                                          if (val != null) {
                                                            setDialogState(() =>
                                                                selectedTarget =
                                                                    val);
                                                          }
                                                        },
                                                      ),
                                                      RadioListTile<String>(
                                                        dense: true,
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        title: const Text(
                                                            'Tomorrow Routine'),
                                                        subtitle: const Text(
                                                          'Plan for tomorrow; activates at midnight',
                                                          style: TextStyle(
                                                              fontSize: 11),
                                                        ),
                                                        value: 'Tomorrow',
                                                        groupValue:
                                                            selectedTarget,
                                                        onChanged: (val) {
                                                          if (val != null) {
                                                            setDialogState(() =>
                                                                selectedTarget =
                                                                    val);
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              dialogCtx, null),
                                                      child:
                                                          const Text('Cancel'),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              dialogCtx,
                                                              selectedTarget),
                                                      child:
                                                          const Text('Apply'),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          );
                                          if (chosenTarget != null &&
                                              sheetContext.mounted) {
                                            Navigator.pop(sheetContext);
                                            if (mounted) {
                                              _applyFavoriteRoutine(
                                                  tpl, chosenTarget);
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRoutineTemplateTasksPreview(RoutineTemplate tpl) {
    if (tpl.tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No tasks in this routine.',
          style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
        ),
      );
    }

    Widget buildTaskItem(Map<String, dynamic> taskMap, {int depth = 0}) {
      final title = taskMap['title']?.toString() ?? 'Untitled';
      final startMin = (taskMap['startMinute'] as num?)?.toInt() ?? 0;
      final endMin = (taskMap['endMinute'] as num?)?.toInt() ?? 60;
      final duration = endMin - startMin;
      final h = duration ~/ 60;
      final m = duration % 60;
      final durStr = h == 0 ? '${m}m' : (m == 0 ? '${h}h' : '${h}h ${m}m');
      final timeStr =
          '${_formatMinute(startMin, use24Hour: use24Hour)} – ${_formatMinute(endMin, use24Hour: use24Hour, isEndTime: true)}';
      final rawChildren = taskMap['children'];
      final children = rawChildren is List
          ? rawChildren
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      return Padding(
        padding: EdgeInsets.only(left: depth * 14.0, top: 3, bottom: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  depth == 0
                      ? Icons.circle_outlined
                      : Icons.subdirectory_arrow_right_rounded,
                  size: depth == 0 ? 10 : 13,
                  color: depth == 0
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: depth == 0 ? 13 : 12,
                            fontWeight: depth == 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$timeStr ($durStr)',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty)
              ...children
                  .map((child) => buildTaskItem(child, depth: depth + 1)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt_rounded,
                  size: 14, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Schedule Overview (${tpl.totalTasksCount} tasks):',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...tpl.tasks.map((taskMap) => buildTaskItem(taskMap)),
        ],
      ),
    );
  }

  void _applyFavoriteRoutine(RoutineTemplate template, String targetTab) {
    List<TaskNode> parseNewTasks(List<dynamic> list) {
      return list.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);
        final rawChildren = map['children'];
        return TaskNode(
          title: map['title']?.toString() ?? 'Untitled task',
          startMinute: (map['startMinute'] as num?)?.toInt() ?? 0,
          endMinute: (map['endMinute'] as num?)?.toInt() ?? 60,
          done: false, // fresh
          alarmEnabled: map['alarmEnabled'] == true,
          alarmLeadSeconds: (map['alarmLeadSeconds'] as num?)?.toInt() ?? 300,
          children: rawChildren is List ? parseNewTasks(rawChildren) : [],
        );
      }).toList();
    }

    final newTasks = parseNewTasks(template.tasks);
    setState(() {
      if (targetTab == 'Tomorrow') {
        tomorrowTasks.clear();
        tomorrowTasks.addAll(newTasks);
      } else {
        autoTasks.clear();
        autoTasks.addAll(newTasks);
      }
    });
    _saveRoutineTasks();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied "${template.title}" to $targetTab!'),
        backgroundColor: kGreen,
      ),
    );
  }

  Future<void> _shareSingleRoutine(RoutineTemplate template) async {
    try {
      final file = await _templateStore.exportSingleToFile(template);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Routine Template: ${template.title}',
          text:
              'Here is my "${template.title}" routine template for Routine Tracker!',
        ),
      );
    } catch (error) {
      debugPrint('Error sharing routine template: $error');
    }
  }

  Future<void> _importSingleRoutine() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: '/storage/emulated/0/Download/DayAura',
      );
      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final template = _templateStore.validateAndParseSingle(content);
      if (template == null) {
        if (mounted) {
          _showErrorDialog(
            title: 'Invalid Routine File',
            message:
                'The selected file is not a valid Routine Tracker template.',
          );
        }
        return;
      }

      await _templateStore.save(template);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Imported "${template.title}" into Favorite Routines!'),
            backgroundColor: kGreen,
          ),
        );
      }
    } catch (error) {
      debugPrint('Error importing routine template: $error');
    }
  }

  void _showBackupRestoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Backup & Restore',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x2220B77A),
                    child: Icon(Icons.file_download_outlined, color: kGreen),
                  ),
                  title: const Text('Download Backup'),
                  subtitle: const Text(
                    'Directly auto-saves to Download/DayAura folder.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _exportHistory();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x2220B77A),
                    child: Icon(Icons.file_upload_outlined, color: kGreen),
                  ),
                  title: const Text('Upload Backup'),
                  subtitle: const Text(
                    'Select a backup file from your phone to restore history.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _importHistory();
                  },
                ),
              ],
            ),
          ),
        );
      },
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

class _InteractiveTrimTimeline extends StatelessWidget {
  const _InteractiveTrimTimeline({
    required this.rangeStartSeconds,
    required this.rangeEndSeconds,
    required this.selectedStartSeconds,
    required this.selectedEndSeconds,
    required this.occupied,
    required this.use24Hour,
    required this.isStartLocked,
    this.isTomorrow = false,
    required this.minAllowedStartSeconds,
    required this.minAllowedEndSeconds,
    required this.onRangeChanged,
  });

  final int rangeStartSeconds;
  final int rangeEndSeconds;
  final int selectedStartSeconds;
  final int selectedEndSeconds;
  final List<TaskNode> occupied;
  final bool use24Hour;
  final bool isStartLocked;
  final bool isTomorrow;
  final int minAllowedStartSeconds;
  final int minAllowedEndSeconds;
  final void Function(int newStart, int newEnd) onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final span = math.max(1, rangeEndSeconds - rangeStartSeconds);
    final start =
        selectedStartSeconds.clamp(rangeStartSeconds, rangeEndSeconds).toInt();
    final end = selectedEndSeconds.clamp(start, rangeEndSeconds).toInt();

    double leftFor(int s) => ((s - rangeStartSeconds) / span).clamp(0.0, 1.0);
    double widthFor(int a, int b) => ((b - a) / span).clamp(0.0, 1.0);

    final visibleOccupied = occupied
        .where((t) =>
            t.endMinute * 60 > rangeStartSeconds &&
            t.startMinute * 60 < rangeEndSeconds)
        .toList();

    final now = DateTime.now();
    final currentSeconds = now.hour * 3600 + now.minute * 60 + now.second;
    final showCurrentMarker = !isTomorrow &&
        currentSeconds >= rangeStartSeconds &&
        currentSeconds <= rangeEndSeconds;
    final currentMarkerFraction = leftFor(currentSeconds);

    // 5 Quarter tick marks
    final tickFractions = [0.0, 0.25, 0.50, 0.75, 1.0];
    final tickLabels = tickFractions.map((f) {
      final s = (rangeStartSeconds + span * f).round();
      if (f == 1.0) {
        if (s >= 86340) {
          return use24Hour ? '23:59' : '11:59 PM';
        }
        return _formatMinute(s ~/ 60, use24Hour: use24Hour, isEndTime: true);
      }
      return _formatMinute(s ~/ 60, use24Hour: use24Hour);
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Track box with video-editor style trim handles
        SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth;

              void onLeftDrag(double dx) {
                if (isStartLocked) return;
                final deltaSeconds = (dx * span / w).round();
                var newStart = selectedStartSeconds + deltaSeconds;
                newStart = ((newStart + 30) ~/ 60) * 60;
                newStart = newStart.clamp(
                  minAllowedStartSeconds,
                  selectedEndSeconds - 60,
                ).toInt();
                onRangeChanged(newStart, selectedEndSeconds);
              }

              void onRightDrag(double dx) {
                final deltaSeconds = (dx * span / w).round();
                var newEnd = selectedEndSeconds + deltaSeconds;
                newEnd = ((newEnd + 30) ~/ 60) * 60;
                newEnd = newEnd.clamp(
                  math.max(selectedStartSeconds + 60, minAllowedEndSeconds),
                  rangeEndSeconds,
                ).toInt();
                onRangeChanged(selectedStartSeconds, newEnd);
              }

              void onCenterDrag(double dx) {
                final duration = selectedEndSeconds - selectedStartSeconds;
                final deltaSeconds = (dx * span / w).round();
                var newStart = selectedStartSeconds + deltaSeconds;
                newStart = ((newStart + 30) ~/ 60) * 60;
                if (newStart < minAllowedStartSeconds) {
                  newStart = minAllowedStartSeconds;
                }
                if (newStart + duration > rangeEndSeconds) {
                  newStart = rangeEndSeconds - duration;
                }
                onRangeChanged(newStart, newStart + duration);
              }

              final selLeft = leftFor(start) * w;
              final selRight = leftFor(end) * w;
              final selWidth = math.max(2.0, selRight - selLeft);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track background
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 2,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF222725),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                    ),
                  ),

                  // Reserved Occupied intervals (Red)
                  ...visibleOccupied.map((t) {
                    final s = math.max(rangeStartSeconds, t.startMinute * 60);
                    final e = math.min(rangeEndSeconds, t.endMinute * 60);
                    return Positioned(
                      left: leftFor(s) * w,
                      width: math.max(2.0, widthFor(s, e) * w),
                      top: 2,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65A52),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),

                  // Current time indicator line
                  if (showCurrentMarker)
                    Positioned(
                      left: (currentMarkerFraction * w - 1).clamp(0.0, w - 2),
                      top: 2,
                      height: 26,
                      child: Container(
                        width: 2.2,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.7),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Selected Interval (Clean pink block without bulky interior handles)
                  Positioned(
                    left: selLeft,
                    width: selWidth,
                    top: 2,
                    height: 26,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) =>
                          onCenterDrag(details.delta.dx),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE86AB3).withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE86AB3).withValues(alpha: 0.3),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${_formatMinute(start ~/ 60, use24Hour: use24Hour)} - ${_formatMinute(end ~/ 60, use24Hour: use24Hour, isEndTime: true)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),

                  // Left Trim Handle: 44px wide x 44px tall generous touch area (line + dot + surrounding)
                  Positioned(
                    left: (selLeft - 22).clamp(-10.0, w - 10.0),
                    width: 44,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) =>
                          onLeftDrag(details.delta.dx),
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Positioned(
                            top: 2,
                            height: 26,
                            child: Container(
                              width: 2.5,
                              decoration: BoxDecoration(
                                color: isStartLocked
                                    ? Colors.amber.shade400
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(1.5),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 24,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isStartLocked
                                    ? Colors.amber.shade700
                                    : Colors.white,
                                border: Border.all(
                                  color: const Color(0xFF222725),
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 3,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: isStartLocked
                                  ? const Icon(
                                      Icons.lock,
                                      size: 9,
                                      color: Colors.black,
                                    )
                                  : Container(
                                      width: 5,
                                      height: 5,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFFE86AB3),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Right Trim Handle: 44px wide x 44px tall generous touch area (line + dot + surrounding)
                  Positioned(
                    left: ((selLeft + selWidth) - 22).clamp(-10.0, w - 10.0),
                    width: 44,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) =>
                          onRightDrag(details.delta.dx),
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Positioned(
                            top: 2,
                            height: 26,
                            child: Container(
                              width: 2.5,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(1.5),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 24,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFF222725),
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 3,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFE86AB3),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 4),

        // 5 Quarter tick marks & labels below the bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: tickLabels.map((lbl) {
            return Text(
              lbl,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.outline,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
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

class ChartCandleData {
  const ChartCandleData({
    required this.label,
    required this.progress,
    required this.open,
    required this.close,
    required this.high,
    required this.daysCount,
    this.day,
    this.year,
    this.month,
    this.emoji,
  });

  final String label;
  final double progress;
  final double open;
  final double close;
  final double high;
  final int daysCount;
  final SampleDay? day;
  final int? year;
  final int? month;
  final String? emoji;
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
    this.onDayTap,
    this.onOpenHistoricalList,
    this.onCandlesChanged,
  });

  final bool candles;
  final List<SampleDay> days;
  final Color labelColor;
  final Color gridColor;
  final Color bodyColor;
  final bool expandToParent;
  final bool initialRecentFiveDays;
  final void Function(int index)? onDayTap;
  final VoidCallback? onOpenHistoricalList;
  final ValueChanged<bool>? onCandlesChanged;

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
  static const double _timeframeBarHeight = 36.0;
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

  String _timeframe = '1D'; // '1D', '1M', '1Y'
  int? _drillDownYear;
  int? _drillDownMonth;

  @override
  void initState() {
    super.initState();
    _initialRecentApplied = !widget.initialRecentFiveDays || widget.days.isEmpty;
  }

  @override
  void didUpdateWidget(covariant _InteractiveCumulativeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.days.isEmpty && widget.days.isNotEmpty && widget.initialRecentFiveDays) {
      _initialRecentApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showRecentFiveDays();
      });
    }
  }

  List<ChartCandleData> _buildItems() {
    if (widget.days.isEmpty) return const [];

    final dayOpens = <double>[];
    final dayCloses = <double>[];
    var cumulative = 0.0;
    for (final d in widget.days) {
      dayOpens.add(cumulative);
      cumulative += d.progress;
      dayCloses.add(cumulative);
    }

    if (_timeframe == '1D') {
      final items = <ChartCandleData>[];
      for (var i = 0; i < widget.days.length; i++) {
        final d = widget.days[i];
        if (_drillDownYear != null && d.date.year != _drillDownYear) continue;
        if (_drillDownMonth != null && d.date.month != _drillDownMonth) continue;
        items.add(
          ChartCandleData(
            label: '${_shortMonth(d.date.month)} ${d.date.day}',
            progress: d.progress,
            open: dayOpens[i],
            close: dayCloses[i],
            high: dayOpens[i] + 100.0,
            daysCount: 1,
            day: d,
            year: d.date.year,
            month: d.date.month,
            emoji: d.emoji,
          ),
        );
      }
      return items;
    }

    if (_timeframe == '1M') {
      final monthMap = <String, List<int>>{};
      for (var i = 0; i < widget.days.length; i++) {
        final d = widget.days[i];
        if (_drillDownYear != null && d.date.year != _drillDownYear) continue;
        final key = '${d.date.year}-${d.date.month}';
        monthMap.putIfAbsent(key, () => []).add(i);
      }

      final items = <ChartCandleData>[];
      for (final entry in monthMap.entries) {
        final indices = entry.value;
        final firstIdx = indices.first;
        final firstDay = widget.days[firstIdx];
        final totalEarned = indices.fold(0.0, (sum, idx) => sum + widget.days[idx].progress);
        final count = indices.length;
        final progressPct = count == 0 ? 0.0 : (totalEarned / count).clamp(0.0, 100.0);
        final open = dayOpens[firstIdx];
        final close = open + totalEarned;
        final high = open + (count * 100.0);
        final label = _drillDownYear != null
            ? _shortMonth(firstDay.date.month)
            : '${_shortMonth(firstDay.date.month)} \'${firstDay.date.year.toString().substring(2)}';

        String? monthEmoji;
        for (final idx in indices) {
          final em = widget.days[idx].emoji;
          if (em != null && em.trim().isNotEmpty) {
            monthEmoji = em;
            break;
          }
        }

        items.add(
          ChartCandleData(
            label: label,
            progress: progressPct,
            open: open,
            close: close,
            high: high,
            daysCount: count,
            year: firstDay.date.year,
            month: firstDay.date.month,
            emoji: monthEmoji,
          ),
        );
      }
      return items;
    }

    // _timeframe == '1Y'
    final yearMap = <int, List<int>>{};
    for (var i = 0; i < widget.days.length; i++) {
      final d = widget.days[i];
      yearMap.putIfAbsent(d.date.year, () => []).add(i);
    }

    final items = <ChartCandleData>[];
    for (final entry in yearMap.entries) {
      final y = entry.key;
      final indices = entry.value;
      final firstIdx = indices.first;
      final totalEarned = indices.fold(0.0, (sum, idx) => sum + widget.days[idx].progress);
      final count = indices.length;
      final progressPct = count == 0 ? 0.0 : (totalEarned / count).clamp(0.0, 100.0);
      final open = dayOpens[firstIdx];
      final close = open + totalEarned;
      final high = open + (count * 100.0);

      String? yearEmoji;
      for (final idx in indices) {
        final em = widget.days[idx].emoji;
        if (em != null && em.trim().isNotEmpty) {
          yearEmoji = em;
          break;
        }
      }

      items.add(
        ChartCandleData(
          label: '$y',
          progress: progressPct,
          open: open,
          close: close,
          high: high,
          daysCount: count,
          year: y,
          emoji: yearEmoji,
        ),
      );
    }
    return items;
  }

  double _clampPanX(double value, double viewportWidth, int itemCount) {
    final count = itemCount <= 0 ? 1 : itemCount;
    final contentWidth = count * _dayWidth * _zoomX;
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
    setState(() {
      _drillDownYear = null;
      _drillDownMonth = null;
      _timeframe = '1D';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitView(targetCount: 5);
    });
  }

  void _fitView({int? targetCount}) {
    final viewportWidth = _lastPlotWidth;
    final viewportHeight = _lastPlotHeight;
    if (!mounted || viewportWidth <= 0 || viewportHeight <= 0) return;

    final items = _buildItems();
    if (items.isEmpty) return;

    final axis = _cumulativeAxisRangeFromItems(items);
    final count = targetCount ??
        (_timeframe == '1D'
            ? (_drillDownMonth != null ? items.length : 5)
            : items.length);
    final firstVisibleIndex = math.max(0, items.length - count).toInt();
    var visibleMin = double.infinity;
    var visibleMax = double.negativeInfinity;
    for (var i = firstVisibleIndex; i < items.length; i++) {
      final it = items[i];
      visibleMin = math.min(visibleMin, math.min(it.open, it.close)).toDouble();
      visibleMax = math.max(
        visibleMax,
        math.max(it.high, math.max(it.open, it.close)),
      ).toDouble();
    }
    if (!visibleMin.isFinite || !visibleMax.isFinite) {
      visibleMin = 0.0;
      visibleMax = axis.maxValue;
    }

    final rawSpan = math.max(1.0, visibleMax - visibleMin).toDouble();
    final fitTickStep = _niceTickStep(rawSpan / 5.0);
    final paddedMin = math
        .max(0.0, (visibleMin / fitTickStep).floor() * fitTickStep)
        .toDouble();
    var paddedMax = (visibleMax / fitTickStep).ceil() * fitTickStep;
    if (paddedMax <= paddedMin) paddedMax = paddedMin + fitTickStep;

    final baseTop = _baseChartY(paddedMax, axis.maxValue, viewportHeight);
    final baseBottom = _baseChartY(paddedMin, axis.maxValue, viewportHeight);
    final baseSpan = math.max(1.0, baseBottom - baseTop).toDouble();
    const targetTopFraction = 0.12;
    const targetBottomFraction = 0.88;
    final targetSpan =
        viewportHeight * (targetBottomFraction - targetTopFraction);
    final fittedZoomY = (targetSpan / baseSpan)
        .clamp(_minZoomY, _maxZoomY)
        .toDouble();
    final fittedPanY =
        viewportHeight * targetTopFraction - baseTop * fittedZoomY;

    final fittedCount = math.max(1, math.min(items.length, count));
    final fittedZoomX = (viewportWidth / (fittedCount * _dayWidth))
        .clamp(_minZoomX, _maxZoomX)
        .toDouble();

    setState(() {
      _zoomX = fittedZoomX;
      _zoomY = fittedZoomY;
      _panY = _clampPanY(fittedPanY, viewportHeight);
      final contentWidth = items.length * _dayWidth * _zoomX;
      _panX = _clampPanX(
        viewportWidth - contentWidth,
        viewportWidth,
        items.length,
      );
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
          onDayTap: widget.onDayTap,
          onOpenHistoricalList: widget.onOpenHistoricalList,
          onCandlesChanged: widget.onCandlesChanged,
        ),
      ),
    );
  }

  void _onChartGestureUpdate(
    _ChartGestureUpdate details, {
    required double viewportWidth,
    required double viewportHeight,
    required int itemCount,
  }) {
    setState(() {
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
        final oldX = details.previousFocalPoint.dx
            .clamp(0.0, viewportWidth)
            .toDouble();
        final newX = details.focalPoint.dx.clamp(0.0, viewportWidth).toDouble();
        _panX = newX - (oldX - _panX) * ratioX;
        _panY =
            details.focalPoint.dy -
            (details.previousFocalPoint.dy - _panY) * ratioY;
        _panX = _clampPanX(_panX, viewportWidth, itemCount);
        _panY = _clampPanY(_panY, viewportHeight);
      }
    });
  }

  void _handleItemTap(int index, List<ChartCandleData> items) {
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    if (_timeframe == '1Y') {
      // Drill-down from Year to Month
      setState(() {
        _drillDownYear = item.year;
        _drillDownMonth = null;
        _timeframe = '1M';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitView();
      });
    } else if (_timeframe == '1M') {
      // Drill-down from Month to Day
      setState(() {
        _drillDownYear = item.year;
        _drillDownMonth = item.month;
        _timeframe = '1D';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitView();
      });
    } else {
      // In 1D: open day details sheet
      if (item.day != null) {
        final globalIdx = widget.days.indexOf(item.day!);
        if (globalIdx >= 0) {
          widget.onDayTap?.call(globalIdx);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    final axis = _cumulativeAxisRangeFromItems(items);
    return SizedBox(
      // In fullscreen mode the parent Expanded supplies the finite height.
      height: widget.expandToParent ? null : 350,
      child: Column(
        children: [
          // Timeframe selector bar with in-chart drill-down back link
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_drillDownYear != null || _drillDownMonth != null)
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (_drillDownMonth != null) {
                          _drillDownMonth = null;
                          _timeframe = '1M';
                        } else {
                          _drillDownYear = null;
                          _timeframe = '1Y';
                        }
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _fitView();
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_back_ios_new_rounded, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            _drillDownMonth != null
                                ? '${_shortMonth(_drillDownMonth!)} $_drillDownYear'
                                : '$_drillDownYear',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    'TIMEFRAME',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '1D', label: Text('1D')),
                    ButtonSegment(value: '1M', label: Text('1M')),
                    ButtonSegment(value: '1Y', label: Text('1Y')),
                  ],
                  selected: {_timeframe},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (selection) {
                    final val = selection.first;
                    setState(() {
                      _timeframe = val;
                      if (val == '1Y') {
                        _drillDownYear = null;
                        _drillDownMonth = null;
                      } else if (val == '1M') {
                        _drillDownMonth = null;
                      }
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _fitView();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final plotHeight = math.max(1.0, constraints.maxHeight).toDouble();
                final bodyWidth = math
                    .max(1.0, constraints.maxWidth - _yAxisWidth)
                    .toDouble();
                final plotWidth = math
                    .max(1.0, bodyWidth - _rightScaleWidth)
                    .toDouble();
                _lastPlotWidth = plotWidth;
                _lastPlotHeight = plotHeight;

                if (!_initialRecentApplied && widget.days.isNotEmpty) {
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

                return Row(
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
                                          itemCount: items.length,
                                        );
                                    instance.onTap = (localPosition) {
                                      final step = _dayWidth * _zoomX;
                                      final index =
                                          ((localPosition.dx - _panX) / step)
                                              .floor();
                                      if (index >= 0 &&
                                          index < items.length) {
                                        _handleItemTap(index, items);
                                      }
                                    };
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
                                    items: items,
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
                );
              },
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
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) {
                              final step = _dayWidth * _zoomX;
                              final index =
                                  ((details.localPosition.dx - _panX) /
                                          step)
                                      .floor();
                              if (index >= 0 &&
                                  index < items.length) {
                                _handleItemTap(index, items);
                              }
                            },
                            child: CustomPaint(
                              painter: CumulativeXAxisPainter(
                                items: items,
                                zoomX: _zoomX,
                                panX: _panX,
                                labelColor: widget.labelColor,
                              ),
                              child: const SizedBox.expand(),
                            ),
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
    this.onDayTap,
    this.onOpenHistoricalList,
    this.onCandlesChanged,
  });

  final bool candles;
  final List<SampleDay> days;
  final Color labelColor;
  final Color gridColor;
  final Color bodyColor;
  final void Function(int index)? onDayTap;
  final VoidCallback? onOpenHistoricalList;
  final ValueChanged<bool>? onCandlesChanged;

  @override
  State<_CumulativeChartFullscreenPage> createState() =>
      _CumulativeChartFullscreenPageState();
}

class _CumulativeChartFullscreenPageState
    extends State<_CumulativeChartFullscreenPage> {
  final GlobalKey<_InteractiveCumulativeChartState> _chartKey =
      GlobalKey<_InteractiveCumulativeChartState>();
  late bool _isCandles;

  @override
  void initState() {
    super.initState();
    _isCandles = widget.candles;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isCandles ? 'Cumulative Candle Chart' : 'Cumulative Line Chart',
        ),
        actions: [
          if (widget.onOpenHistoricalList != null)
            IconButton(
              tooltip: 'Historical Details',
              onPressed: widget.onOpenHistoricalList,
              icon: const Icon(Icons.history_rounded),
            ),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isCandles
                          ? 'CUMULATIVE CANDLE CHART'
                          : 'CUMULATIVE LINE CHART',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Candle')),
                        ButtonSegment(value: false, label: Text('Line')),
                      ],
                      selected: {_isCandles},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onSelectionChanged: (selection) {
                        final val = selection.first;
                        setState(() => _isCandles = val);
                        widget.onCandlesChanged?.call(val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (_isCandles) _candleThresholdLegend(context),
              const SizedBox(height: 6),
              Expanded(
                child: _InteractiveCumulativeChart(
                  key: _chartKey,
                  candles: _isCandles,
                  days: widget.days,
                  labelColor: widget.labelColor,
                  gridColor: widget.gridColor,
                  bodyColor: widget.bodyColor,
                  expandToParent: true,
                  initialRecentFiveDays: true,
                  onDayTap: widget.onDayTap,
                  onOpenHistoricalList: widget.onOpenHistoricalList,
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

  void Function(_ChartGestureUpdate update)? onUpdate;
  void Function(Offset localPosition)? onTap;
  double viewportWidth = 0.0;
  double verticalScaleBandWidth = 0.0;

  final Map<int, Offset> _pointers = <int, Offset>{};
  Offset _previousFocalPoint = Offset.zero;
  double _previousSpan = 0.0;
  bool _verticalScaleGesture = false;
  Offset _downPosition = Offset.zero;
  int _primaryPointer = 0;
  bool _tapCandidate = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _primaryPointer = event.pointer;
      _downPosition = event.localPosition;
      _tapCandidate = true;
      _previousFocalPoint = event.localPosition;
      _previousSpan = 0.0;
      _verticalScaleGesture =
          viewportWidth > 0 &&
          event.localPosition.dx >= viewportWidth - verticalScaleBandWidth;
    } else {
      _tapCandidate = false;
      _previousFocalPoint = _computeFocalPoint();
      _previousSpan = _computeSpan();
      _verticalScaleGesture = false;
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _pointers[event.pointer] = event.localPosition;
      if (_tapCandidate &&
          (event.localPosition - _downPosition).distance > kTouchSlop) {
        _tapCandidate = false;
      }
      final focalPoint = _computeFocalPoint();
      final span = _computeSpan();
      double scaleFactor = 1.0;
      if (_pointers.length > 1 && _previousSpan > 0 && span > 0) {
        scaleFactor = span / _previousSpan;
      }
      onUpdate?.call(
        _ChartGestureUpdate(
          previousFocalPoint: _previousFocalPoint,
          focalPoint: focalPoint,
          scaleFactor: scaleFactor,
          verticalScaleGesture: _verticalScaleGesture,
        ),
      );
      _previousFocalPoint = focalPoint;
      _previousSpan = span;
    } else if (event is PointerUpEvent) {
      if (_tapCandidate && event.pointer == _primaryPointer) {
        onTap?.call(event.localPosition);
      }
      _pointers.remove(event.pointer);
      if (_pointers.isNotEmpty) {
        _previousFocalPoint = _computeFocalPoint();
        _previousSpan = _computeSpan();
      }
    } else if (event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
      _tapCandidate = false;
    }
  }

  Offset _computeFocalPoint() {
    var sum = Offset.zero;
    for (final pos in _pointers.values) {
      sum += pos;
    }
    return sum / _pointers.length.toDouble();
  }

  double _computeSpan() {
    if (_pointers.length < 2) return 0.0;
    final points = _pointers.values.toList();
    var maxDistance = 0.0;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final dist = (points[i] - points[j]).distance;
        if (dist > maxDistance) maxDistance = dist;
      }
    }
    return maxDistance;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers.clear();
    _tapCandidate = false;
  }

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

_CumulativeAxisRange _cumulativeAxisRangeFromItems(List<ChartCandleData> items) {
  var maxValue = 100.0;
  for (final it in items) {
    maxValue = math.max(maxValue, it.high).toDouble();
    maxValue = math.max(maxValue, it.close).toDouble();
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
  final rounded = value.round();
  final raw = rounded.toString();
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
    required this.items,
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
  final List<ChartCandleData> items;
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
    if (items.isEmpty || size.width <= 1 || size.height <= 1) return;
    final axisMax = maxAxis <= 0 ? 100.0 : maxAxis;
    double yFor(double value) =>
        _baseChartY(value, axisMax, size.height) * zoomY + panY;
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;

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

    final verticalGridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.14)
      ..strokeWidth = 0.7;
    for (var i = 0; i < items.length; i++) {
      final x = xFor(i);
      if (x < -step || x > size.width + step) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), verticalGridPaint);
    }

    if (candles) {
      final bodyWidth = (step * 0.76)
          .clamp(2.0, math.max(2.0, step * 0.88))
          .toDouble();
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final x = xFor(i);
        if (x < -step || x > size.width + step) continue;
        final yOpen = yFor(item.open);
        final yClose = yFor(item.close);
        final yHigh = yFor(item.high);
        final bodyTop = math.min(yOpen, yClose).toDouble();
        final bodyBottom = math.max(yOpen, yClose).toDouble();
        final bodyRect = Rect.fromLTRB(
          x - bodyWidth / 2,
          bodyTop,
          x + bodyWidth / 2,
          math.max(bodyTop + 2.0, bodyBottom).toDouble(),
        );

        final progress = item.progress;
        final Color candleColor;
        if (progress < 40.0) {
          candleColor = kCandleRed;
        } else if (progress < 60.0) {
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

        if (step >= 26) {
          final labelWidth = math.max(10.0, step - 3).toDouble();
          final label = TextPainter(
            text: TextSpan(
              text: '${item.progress.toStringAsFixed(0)}%',
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

        if (item.emoji != null && item.emoji!.trim().isNotEmpty) {
          final emojiPainter = TextPainter(
            text: TextSpan(
              text: item.emoji!.trim(),
              style: TextStyle(
                fontSize: (12.0 * zoomX.clamp(0.85, 1.25)).toDouble(),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final emojiY = yHigh - emojiPainter.height - 3;
          if (emojiY >= -20 && emojiY <= size.height) {
            emojiPainter.paint(
              canvas,
              Offset(x - emojiPainter.width / 2, emojiY),
            );
          }
        }
      }
    } else {
      final path = Path();
      var pathStarted = false;
      for (var i = 0; i < items.length; i++) {
        final point = Offset(xFor(i), yFor(items[i].close));
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
          ..strokeWidth = 2.0,
      );
      for (var i = 0; i < items.length; i++) {
        final point = Offset(xFor(i), yFor(items[i].close));
        canvas.drawCircle(point, 3, Paint()..color = bodyColor);
      }
    }

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
      oldDelegate.items != items ||
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
    if (size.width <= 1 || size.height <= 1 || maxAxis <= 0 || tickStep <= 0) {
      return;
    }
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
    required this.items,
    required this.zoomX,
    required this.panX,
    required this.labelColor,
  });

  final List<ChartCandleData> items;
  final double zoomX;
  final double panX;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || size.width <= 1 || size.height <= 1) return;
    final step = 38.0 * zoomX;
    final stride = math.max(1, ((44.0 / step).ceil())).toInt();
    final style = TextStyle(color: labelColor, fontSize: 10);
    for (var i = 0; i < items.length; i++) {
      if (i % stride != 0 && i != items.length - 1) continue;
      final labelText = items[i].label;
      final label = TextPainter(
        text: TextSpan(text: labelText, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = panX + step * (i + 0.5);
      if (x + label.width / 2 < 0 || x - label.width / 2 > size.width) continue;
      label.paint(
        canvas,
        Offset(x - label.width / 2, (size.height - label.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CumulativeXAxisPainter oldDelegate) =>
      oldDelegate.items != items ||
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
    this.targetPath = 'all',
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
  final String targetPath;

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
    targetPath:
        json['targetPath'] as String? ?? json['target_path'] as String? ?? 'all',
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
    'targetPath': targetPath,
  };
}

class AdvertisementTargetMatcher {
  const AdvertisementTargetMatcher._();

  static bool matchesTarget(String targetPath, Map<String, dynamic>? profile) {
    final target = targetPath.trim().toLowerCase();
    if (target.isEmpty ||
        target == 'all' ||
        target == 'root' ||
        target == 'root (all)') {
      return true;
    }
    if (profile == null) return false;

    final countryRaw = profile['country']?.toString() ?? 'Other';
    final countryCode = (profile['country_code'] ?? _isoCountryCode(countryRaw))
        .toString()
        .toLowerCase();
    final status = _statusCode(profile['status']?.toString() ?? 'other')
        .toLowerCase();
    final education = (profile['education']?.toString() ?? '').toLowerCase();
    final goal = _categorySlug(profile['goal']?.toString() ?? 'general')
        .toLowerCase();

    final segments = target
        .split('/')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return true;

    if (segments[0] != 'all' && segments[0] != countryCode) {
      return false;
    }
    if (segments.length == 1) return true;

    if (segments[1] != 'all' && segments[1] != status) {
      return false;
    }
    if (segments.length == 2) return true;

    final subTarget = segments[2];
    if (subTarget == 'all') return true;

    final matchesEdu = education.isNotEmpty &&
        (education.contains(subTarget) || subTarget.contains(education));
    final matchesGoal =
        goal.isNotEmpty && (goal.contains(subTarget) || subTarget.contains(goal));
    return matchesEdu || matchesGoal;
  }

  static int targetPriority(String targetPath) {
    final target = targetPath.trim().toLowerCase();
    if (target.isEmpty ||
        target == 'all' ||
        target == 'root' ||
        target == 'root (all)') {
      return 0;
    }
    final segments =
        target.split('/').where((s) => s.trim().isNotEmpty).toList();
    if (segments.length >= 3) return 300;
    if (segments.length == 2) return 200;
    if (segments.length == 1) return 100;
    return 50;
  }
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

  static bool matchesTarget(String targetPath, Map<String, dynamic>? profile) =>
      AdvertisementTargetMatcher.matchesTarget(targetPath, profile);

  static int targetPriority(String targetPath) =>
      AdvertisementTargetMatcher.targetPriority(targetPath);

  static Future<Map<String, dynamic>?> loadUserProfile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/routine_profile.json');
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

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
      List<dynamic> rows;
      try {
        rows = await client
            .from(_table)
            .select(
              'id,title,video_path,media_type,target_url,display_order,target_path',
            )
            .eq('is_active', true)
            .order('display_order', ascending: true)
            .order('created_at', ascending: true);
      } catch (_) {
        rows = await client
            .from(_table)
            .select('id,title,video_path,media_type,target_url,display_order')
            .eq('is_active', true)
            .order('display_order', ascending: true)
            .order('created_at', ascending: true);
      }
      final directory = await _cacheDirectory();
      final cachedById = <String, Advertisement>{
        for (final ad in cached) ad.id: ad,
      };
      final synced = <Advertisement>[];

      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id'] as String;
        final assetPath = row['video_path'] as String;
        final mediaType = (row['media_type'] as String?) == 'image'
            ? 'image'
            : 'video';
        final targetUrl = row['target_url'] as String? ?? '';
        final title = row['title'] as String? ?? 'Advertisement';
        final order = (row['display_order'] as num?)?.toInt() ?? 0;
        final targetPath = (row['target_path'] as String?)?.trim() ?? 'all';
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
            targetPath: targetPath,
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
  const AdvertisementBanner({
    super.key,
    required this.onOpenGallery,
    this.userProfile,
  });
  final ValueChanged<List<Advertisement>> onOpenGallery;
  final Map<String, dynamic>? userProfile;

  @override
  State<AdvertisementBanner> createState() => _AdvertisementBannerState();
}

class _AdvertisementBannerState extends State<AdvertisementBanner>
    with WidgetsBindingObserver {
  List<Advertisement> _rawAds = <Advertisement>[];
  List<Advertisement> _ads = <Advertisement>[];
  Map<String, dynamic>? _resolvedProfile;
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
  void didUpdateWidget(covariant AdvertisementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      _applyFilteredAds();
      if (mounted) setState(() {});
      _loadMedia();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAds();
  }

  void _applyFilteredAds() {
    final profile = widget.userProfile ?? _resolvedProfile;
    final matched = _rawAds
        .where(
          (ad) => _AdvertisementService.matchesTarget(
            ad.targetPath,
            profile,
          ),
        )
        .toList();
    final effective = matched.isNotEmpty
        ? matched
        : _rawAds.where((ad) => ad.targetPath == 'all').toList();

    effective.sort((a, b) {
      final prioA = _AdvertisementService.targetPriority(a.targetPath);
      final prioB = _AdvertisementService.targetPriority(b.targetPath);
      if (prioA != prioB) {
        return prioB.compareTo(prioA);
      }
      return a.displayOrder.compareTo(b.displayOrder);
    });

    _ads = effective;
    if (_ads.isEmpty || _index >= _ads.length) _index = 0;
  }

  Future<void> _loadAds() async {
    final cached = await _AdvertisementService.instance.loadCached();
    if (!mounted) return;
    _resolvedProfile =
        widget.userProfile ?? await _AdvertisementService.loadUserProfile();
    _rawAds = cached;
    _applyFilteredAds();
    setState(() {});
    await _loadMedia();
    await _refreshAds();
  }

  String _sequence(List<Advertisement> ads) => ads
      .map(
        (ad) =>
            '${ad.id}:${ad.mediaType}:${ad.assetPath}:${ad.targetUrl}:${ad.displayOrder}:${ad.targetPath}',
      )
      .join('|');

  Future<void> _refreshAds() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final oldSequence = _sequence(_rawAds);
      final updated = await _AdvertisementService.instance.syncFromServer();
      if (!mounted) return;
      final changed = _sequence(updated) != oldSequence;
      _rawAds = updated;
      _resolvedProfile =
          widget.userProfile ?? await _AdvertisementService.loadUserProfile();
      _applyFilteredAds();
      if (mounted) setState(() {});
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

class _DistractingAppsSheet extends StatefulWidget {
  final int initialTab;
  const _DistractingAppsSheet({this.initialTab = 0});

  @override
  State<_DistractingAppsSheet> createState() => _DistractingAppsSheetState();
}

class _DistractingAppsSheetState extends State<_DistractingAppsSheet>
    with WidgetsBindingObserver {
  late int _selectedTab; // 0 = Time Lock, 1 = Apps & Sites
  int _appsSitesSubTab = 0; // 0 = Apps, 1 = Remaining Quotas, 2 = Websites
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();

  Future<void> _refreshUsageStats() async {
    final usage = await DistractionService.instance.getAppDailyUsage();
    if (mounted) {
      setState(() {
        _appDailyUsage.addAll(usage);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screen time & remaining quotas refreshed!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // Permissions state
  bool _hasOverlay = false;
  bool _hasAccessibility = false;
  bool _hasDeviceAdmin = false;
  bool _hasBatteryOptimization = false;
  bool _hasDeviceOwner = false;
  bool _isActivatingShizuku = false;

  // Apps
  List<InstalledAppInfo> _allApps = [];
  final Set<String> _selectedPackages = {};
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // App daily usage limits (pkg -> limitMinutes)
  final Map<String, int> _appDailyLimits = {};
  final Map<String, int> _appDailyUsage = {};

  // Websites
  final Set<String> _blockedWebsites = {};
  bool _blockAdult = true;
  bool _blockGambling = true;
  bool _forceSafeSearch = true;
  final TextEditingController _websiteCtrl = TextEditingController();

  // Time Lock State: 'none', 'time_lock'
  String _lockedInMode = 'none';
  int _lockedInUntilEpoch = 0;
  DateTime _targetDateTime = DateTime.now().add(const Duration(days: 3));

  bool get _isTimeLock =>
      _lockedInMode == 'time_lock' &&
      _lockedInUntilEpoch > DateTime.now().millisecondsSinceEpoch;

  static const Map<String, List<String>> _commonAppPresets = {
    'Other Browsers': [
      'com.mi.globalbrowser',
      'com.android.browser',
      'com.miui.browser',
      'mark.via.gp',
      'com.opera.browser',
      'com.opera.mini.native',
      'com.sec.android.app.sbrowser',
      'org.mozilla.firefox',
      'com.brave.browser',
      'com.microsoft.emmx',
      'com.duckduckgo.mobile.android',
      'com.ucmobile.intl',
      'com.ucmobile.lite',
      'com.pure.mini.browser',
      'com.transsion.phoenix',
    ],
    'Facebook': ['com.facebook.katana', 'com.facebook.lite'],
    'Facebook Lite': ['com.facebook.lite'],
    'Messenger': ['com.facebook.orca', 'com.facebook.mlite'],
    'Instagram': ['com.instagram.android'],
    'YouTube': ['com.google.android.youtube'],
    'TikTok': ['com.zhiliaoapp.musically'],
    'X / Twitter': ['com.twitter.android'],
    'Reddit': ['com.reddit.frontpage'],
  };

  static const List<String> _popularSocialMediaDomains = [
    'youtube.com/shorts',
    'facebook.com/reel',
    'instagram.com/reels',
    'facebook.com',
    'instagram.com',
    'tiktok.com',
    'x.com',
    'twitter.com',
    'reddit.com',
    'youtube.com',
    'snapchat.com',
    'pinterest.com',
    'linkedin.com',
    'twitch.tv',
    'discord.com',
    'netflix.com',
    'quora.com',
    'tumblr.com',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedTab = widget.initialTab.clamp(0, 1);
    _loadAllData();
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _loadAllData();
    }
  }

  Future<void> _checkPermissions() async {
    final overlay = await DistractionService.instance.canDrawOverlays();
    final access =
        await DistractionService.instance.isAccessibilityServiceEnabled();
    final admin = await DistractionService.instance.isDeviceAdminActive();
    final battery =
        await DistractionService.instance.isBatteryOptimizationIgnored();
    final owner = await DistractionService.instance.isDeviceOwner();
    if (mounted) {
      setState(() {
        _hasOverlay = overlay;
        _hasAccessibility = access;
        _hasDeviceAdmin = admin;
        _hasBatteryOptimization = battery;
        _hasDeviceOwner = owner;
      });
    }
  }


  Future<void> _loadAllData() async {
    final installed = await DistractionService.instance.getInstalledApps();
    final savedApps = await DistractionService.instance.getDistractingApps();
    final savedLimits = await DistractionService.instance.getAppDailyLimits();
    final savedUsage = await DistractionService.instance.getAppDailyUsage();
    final siteData = await DistractionService.instance.getBlockedWebsites();
    final config = await DistractionService.instance.getLockedInConfig();

    if (mounted) {
      setState(() {
        _allApps = installed;
        _selectedPackages.addAll(savedApps);
        _appDailyLimits.addAll(savedLimits);
        _appDailyUsage.addAll(savedUsage);
        for (final pkg in savedApps) {
          if (!_appDailyLimits.containsKey(pkg)) {
            _appDailyLimits[pkg] = 0;
          }
        }
        _blockedWebsites
            .addAll(List<String>.from(siteData['websites'] as List? ?? []));
        _blockAdult = siteData['blockAdult'] as bool? ?? true;
        _blockGambling = siteData['blockGambling'] as bool? ?? true;
        _forceSafeSearch = siteData['forceSafeSearch'] as bool? ?? true;
        _lockedInMode = config['mode'] as String? ?? 'none';
        _lockedInUntilEpoch = config['untilEpoch'] as int? ?? 0;
        if (_isTimeLock) {
          _targetDateTime =
              DateTime.fromMillisecondsSinceEpoch(_lockedInUntilEpoch);
          _selectedTab = 0;
        }
        _loading = false;
      });
    }
  }

  Future<void> _saveAppsAndWebsites({bool showMessage = true}) async {
    await DistractionService.instance
        .saveDistractingApps(_selectedPackages.toList());
    await DistractionService.instance
        .saveAppDailyLimits(_appDailyLimits);
    await DistractionService.instance.saveBlockedWebsites(
      _blockedWebsites.toList(),
      blockAdult: _blockAdult,
      blockGambling: _blockGambling,
      forceSafeSearch: _forceSafeSearch,
    );
    if (showMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apps and website rules saved successfully!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAppLimitDialog(InstalledAppInfo app) {
    if (_isTimeLock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot change app daily quota while Time Lock is active!'),
        ),
      );
      return;
    }

    int currentLimit = _appDailyLimits[app.packageName] ?? 0;
    final usedSec = _appDailyUsage[app.packageName] ?? 0;
    final usedMin = (usedSec / 60).floor();
    final remainingSec = (currentLimit * 60) - usedSec;
    final isLocked = currentLimit > 0 && remainingSec <= 0;
    final remMin = (currentLimit > 0 && remainingSec > 0) ? (remainingSec / 60).ceil() : 0;
    final presetOptions = [0, 15, 20, 30, 45, 60, 90, 120];
    final TextEditingController customCtrl = TextEditingController(
      text: presetOptions.contains(currentLimit) ? '' : '$currentLimit',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.timer_outlined, color: Color(0xFF20B77A), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Daily Quota: ${app.appName}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usedMin > 0
                      ? 'Set daily quota.\nUsed today: ${usedMin}m • ${currentLimit > 0 ? (isLocked ? "Currently Locked (0m left)" : "$remMin mins left before lock") : "0m Full Block"}\n(e.g. 30m for classes, 0m for full block)'
                      : 'Set how many minutes this app can be used each day during Locked In mode.\n(e.g. 30m for classes, 0m for full block)',
                  style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...presetOptions.map((mins) {
                      final isSel = currentLimit == mins;
                      return ChoiceChip(
                        label: Text(mins == 0 ? '0m (Full Block)' : '${mins}m'),
                        selected: isSel,
                        selectedColor: mins == 0 ? Colors.red.withValues(alpha: 0.25) : const Color(0x3320B77A),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() => currentLimit = mins);
                            setState(() {
                              _appDailyLimits[app.packageName] = mins;
                            });
                            _saveAppsAndWebsites(showMessage: false);
                            Navigator.pop(ctx);
                          }
                        },
                      );
                    }),
                    if (!presetOptions.contains(currentLimit) && currentLimit > 0)
                      ChoiceChip(
                        label: Text('${currentLimit}m (Custom)'),
                        selected: true,
                        selectedColor: const Color(0x3320B77A),
                        onSelected: (_) {},
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 16),
                const Text(
                  'Or enter custom minutes:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF20B77A)),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: customCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g. 5, 10, 25, 180, 240',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF20B77A),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onPressed: () {
                        final val = int.tryParse(customCtrl.text.trim());
                        if (val != null && val >= 0 && val <= 1440) {
                          setDialogState(() => currentLimit = val);
                          setState(() {
                            _appDailyLimits[app.packageName] = val;
                          });
                          _saveAppsAndWebsites(showMessage: false);
                          Navigator.pop(ctx);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid number of minutes (0 - 1440).'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text('Set'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final m = months[dt.month - 1];
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$m ${dt.day}, ${dt.year} at ${h12.toString().padLeft(2, '0')}:$minute $ampm';
  }

  String _remainingTime() {
    final diff = _targetDateTime.difference(DateTime.now());
    if (diff.isNegative) return 'Completed';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    if (days > 0) return '$days days, $hours hrs remaining';
    if (hours > 0) return '$hours hrs, $mins mins remaining';
    return '$mins mins remaining';
  }

  Future<void> _pickTargetDateTime() async {
    if (_isTimeLock) return;
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _targetDateTime.isAfter(now)
          ? _targetDateTime
          : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_targetDateTime),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _targetDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Widget _buildPermissionCheckRow({
    required String title,
    required String description,
    required bool isGranted,
    required Future<void> Function() onFix,
    String? customActionText,
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isGranted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: isGranted ? const Color(0xFF20B77A) : Colors.orangeAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isGranted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x2220B77A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ACTIVE ✓',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF20B77A),
                ),
              ),
            )
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orangeAccent,
                side: const BorderSide(color: Colors.orangeAccent),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: isLoading
                  ? null
                  : () async {
                      await onFix();
                      Future.delayed(const Duration(seconds: 1), _checkPermissions);
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent),
                    )
                  : Text(customActionText ?? 'Turn ON', style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Future<void> _handleActivateShizuku({bool autoRemoveUsers = false}) async {
    setState(() => _isActivatingShizuku = true);
    try {
      final status = await DistractionService.instance.checkShizukuStatus();
      final isRunning = status['isRunning'] as bool? ?? false;
      final isOwner = status['isDeviceOwner'] as bool? ?? false;

      if (isOwner) {
        setState(() {
          _hasDeviceOwner = true;
          _isActivatingShizuku = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF20B77A),
              content: Text('🛡️ DayAura is already Device Owner!'),
            ),
          );
        }
        return;
      }

      if (!isRunning) {
        setState(() => _isActivatingShizuku = false);
        if (mounted) {
          _showShizukuNotRunningDialog();
        }
        return;
      }

      final res = await DistractionService.instance.activateDeviceOwnerViaShizuku(
        autoRemoveUsers: autoRemoveUsers,
      );
      final success = res['success'] as bool? ?? false;
      final isOwnerNow = res['isDeviceOwner'] as bool? ?? false;
      final output = res['output']?.toString() ?? '';
      final needPerm = res['needPermission'] as bool? ?? false;
      final severalUsers = res['severalUsers'] as bool? ?? false;
      final hasAccounts = res['hasAccounts'] as bool? ?? false;

      setState(() {
        _hasDeviceOwner = isOwnerNow;
        _isActivatingShizuku = false;
      });

      if (mounted) {
        if (isOwnerNow) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF20B77A),
              content: Text('🎉 Unbreakable Device Owner ACTIVATED successfully!'),
            ),
          );
        } else if (needPerm) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('Shizuku permission requested. Tap "Allow" in Shizuku, then tap Activate again.'),
              duration: Duration(seconds: 4),
            ),
          );
        } else if (severalUsers || output.toLowerCase().contains('several users')) {
          _showSeveralUsersDialog();
        } else if (hasAccounts || output.toLowerCase().contains('account')) {
          final accountsList = (res['accounts'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          _showAccountsRemovalDialog(accountsList);
        } else {
          _showShizukuErrorDialog(output.isNotEmpty ? output : (res['message']?.toString() ?? 'Failed to activate Device Owner.'));
        }
      }
    } catch (e) {
      setState(() => _isActivatingShizuku = false);
      if (mounted) {
        _showShizukuErrorDialog(e.toString());
      }
    }
  }

  void _showSeveralUsersDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.people_outline_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Dual Apps / Extra Profile Found')),
          ],
        ),
        content: const Text(
          'Android does not allow setting Device Owner while secondary user profiles exist on the phone.\n\n'
          'Common reasons on Xiaomi / MIUI:\n'
          '• Xiaomi Dual Apps (User 999 cloned profile)\n'
          '• Second Space or Guest User\n\n'
          'Quick 1-Click Fix:\n'
          'Tap "Auto-Remove & Activate" below to automatically remove secondary user profile via Shizuku, or manually delete Dual Apps in phone Settings.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              DistractionService.instance.openDualAppsSettings();
            },
            child: const Text('Dual Apps Settings'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF20B77A)),
            onPressed: () {
              Navigator.pop(ctx);
              _handleActivateShizuku(autoRemoveUsers: true);
            },
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: const Text('Auto-Remove & Activate'),
          ),
        ],
      ),
    );
  }

  void _showShizukuNotRunningDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Shizuku Not Running'),
          ],
        ),
        content: const Text(
          'Shizuku service is currently not running.\n\n'
          '1. Open the Shizuku app on your phone.\n'
          '2. Tap "Start" via Wireless Debugging.\n'
          '3. Once Shizuku says "Shizuku is running", come back here and tap "⚡ Activate" again.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF20B77A)),
            onPressed: () {
              Navigator.pop(ctx);
              DistractionService.instance.openShizukuApp();
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open Shizuku'),
          ),
        ],
      ),
    );
  }

  void _showAccountsRemovalDialog([List<String> detectedAccounts = const []]) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Unbreakable Lock Setup')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'To make DayAura 100% UNBREAKABLE so it CANNOT be deactivated from Device Admin settings, Android requires setting DayAura as "Device Owner".\n\n'
                'Android OS security allows setting Device Owner ONLY when "Accounts & Sync" is temporarily empty.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF20B77A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF20B77A).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF20B77A)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Removing accounts from Accounts & Sync DOES NOT delete your WhatsApp chats, photos, or messages! It only temporarily unlinks sync.',
                        style: TextStyle(fontSize: 12, color: Colors.white, height: 1.35, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              if (detectedAccounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Accounts currently blocking activation:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                ),
                const SizedBox(height: 4),
                ...detectedAccounts.map(
                  (acc) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_right_rounded, size: 18, color: Colors.grey),
                        Expanded(
                          child: Text(
                            acc,
                            style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Steps to complete:\n'
                '1. Tap "Open Accounts Settings" below.\n'
                '2. Tap each account (WhatsApp, MicroG, Telegram, FB) and choose "Remove account".\n'
                '3. Return to DayAura and tap "⚡ Activate".\n'
                '4. Once active, reopen WhatsApp/Telegram — they will re-sync immediately with 100% of your data intact!',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF20B77A)),
            onPressed: () {
              Navigator.pop(ctx);
              DistractionService.instance.openAccountsSettings();
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open Accounts Settings'),
          ),
        ],
      ),
    );
  }

  void _showShizukuErrorDialog(String error) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF20B77A), size: 24),
            SizedBox(width: 8),
            Text('Device Owner Info'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Owner is an OPTIONAL hardware layer.\n\n'
              'Android OS blocks Device Owner activation whenever personal accounts (Google, Xiaomi Account, Telegram, etc.) are logged into the phone.\n\n'
              '✅ DAYAURA IS ALREADY 100% ACTIVE!\n'
              'Your Accessibility Service, Screen Overlay, and Battery Exemption are all active. DayAura will strictly lock Facebook Lite, YouTube Shorts, and all distracting apps autonomously without needing Device Owner.\n\n'
              'You DO NOT need to remove your accounts or change any developer settings.',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF20B77A)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it! Continue Lock'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDialog() {
    final missing = <String>[];
    if (!_hasOverlay) missing.add('• 1. Screen Overlay (Display over other apps)');
    if (!_hasAccessibility) missing.add('• 2. DayAura Browser Guard (Accessibility Service)');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Colors.orangeAccent, size: 26),
            SizedBox(width: 8),
            Text('Permissions Needed'),
          ],
        ),
        content: Text(
          'To ensure distracting apps and websites are blocked autonomously even when DayAura is closed, the following permissions must be enabled:\n\n'
          '${missing.join('\n')}\n\n'
          'Please tap "Turn ON" in the checklist on this screen to activate them.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK, Got It'),
          ),
        ],
      ),
    );
  }

  Future<void> _activateTimeLock() async {
    final now = DateTime.now();
    if (_targetDateTime.isBefore(now.add(const Duration(minutes: 5)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Target time must be at least 5 minutes in the future.'),
        ),
      );
      return;
    }

    if (_selectedPackages.isEmpty && _blockedWebsites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one app or website to block first!'),
        ),
      );
      return;
    }

    await _checkPermissions();
    if (!mounted) return;
    if (!_hasOverlay || !_hasAccessibility) {
      _showPermissionDialog();
      return;
    }

    if (!_hasDeviceAdmin) {
      final proceedWithoutAdmin = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 26),
              SizedBox(width: 8),
              Text('Anti-Uninstall Shield'),
            ],
          ),
          content: const Text(
            'Device Administrator is not yet active.\n\n'
            'DayAura Accessibility Guard is ACTIVE and will prevent uninstallation and settings tampering.\n\n'
            'Would you like to activate Device Admin as an extra shield, or proceed now?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
                DistractionService.instance.requestDeviceAdmin();
              },
              child: const Text('Activate Shield'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed with Lock'),
            ),
          ],
        ),
      );
      if (proceedWithoutAdmin != true) return;
    }

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠️ STRICT HARDCORE TIME LOCK',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  '“যারা কোনোভাবেই নিজের ওপর কন্ট্রোল রাখতে পারতেছেন না তাদের জন্য Locked In অপশন। নরমাল ইউজারদের Locked In-এ ক্লিক করার জন্য নিরুৎসাহিত করতেছি। আবার বলছি, আপনি আপনার ওপর যদি ন্যূনতম কন্ট্রোল রাখতে পারেন তাহলে Locked In-এ একটা সিঙ্গেল ক্লিক করবেন না।”',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.redAccent,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'You are activating TIME LOCK until:\n${_formatDateTime(_targetDateTime)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 10),
              const Text(
                '• You CANNOT remove or edit blocked apps & websites.\n'
                '• You CANNOT snooze or bypass focus alerts (0 Snooze).\n'
                '• You CANNOT uninstall DayAura (Anti-Uninstall active).\n'
                '• Settings tampering & cleaner whitelist unlock are BLOCKED.\n'
                '• SafeSearch & Cloudflare Web Shield are FORCED.\n\n'
                '📌 Xiaomi/MIUI User Checklist:\n'
                '1. Recent Apps-e DayAura card long-press kore Padlock (Lock 🔒) icon din.\n'
                '2. Security ➔ Boost speed ➔ Lock apps theke DayAura on rakhun.\n'
                '3. Device Admin deactivate korar cheshta korle screen auto-lock hoye jabe.',
                style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Lock Me In'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await _saveAppsAndWebsites(showMessage: false);
    await DistractionService.instance.prepareVpn();

    final epoch = _targetDateTime.millisecondsSinceEpoch;
    await DistractionService.instance.registerTimeLockStart();
    await DistractionService.instance.setLockedInMode(
      mode: 'time_lock',
      untilEpoch: epoch,
    );

    setState(() {
      _lockedInMode = 'time_lock';
      _lockedInUntilEpoch = epoch;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFE53935),
          content: Text(
            '🔒 Time Lock is now ACTIVE until ${_formatDateTime(_targetDateTime)}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _emergencyUnlock() async {
    final passCtrl = TextEditingController();
    String? errorText;
    final gracePasscode =
        await DistractionService.instance.getGracePeriodPasscode();
    if (!mounted) return;

    final unlocked = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final now = DateTime.now();
          final months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          final dateStr = '${months[now.month - 1]} ${now.day}';

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.vpn_key_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Developer Unlock'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter emergency unlock passcode for $dateStr:',
                  style: const TextStyle(fontSize: 13),
                ),
                if (gracePasscode != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.key_rounded, size: 16, color: Colors.orangeAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Emergency passcode: $gracePasscode',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Formula: First 6 digits of (567673 * 12h time). E.g. 3:43 -> 194711.',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Enter 6-digit passcode (e.g. 194711)',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.password_rounded),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final input = passCtrl.text.trim();
                  if (DistractionService.verifyUnlockPasscode(input)) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDialogState(() {
                      errorText = 'Invalid passcode for today!';
                    });
                  }
                },
                child: const Text('Unlock'),
              ),
            ],
          );
        },
      ),
    );

    if (unlocked == true && mounted) {
      await DistractionService.instance.setLockedInMode(
        mode: 'none',
        untilEpoch: 0,
      );
      await DistractionService.instance.releaseDeviceOwner();
      if (!mounted) return;
      setState(() {
        _lockedInMode = 'none';
        _lockedInUntilEpoch = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF20B77A),
          content: Text('🔓 Time Lock successfully deactivated!'),
        ),
      );
    }
  }

  void _addCustomWebsite() {
    if (_isTimeLock) return;
    final text = _websiteCtrl.text.trim().toLowerCase();
    if (text.isEmpty) return;
    String clean = text
        .replaceAll('https://', '')
        .replaceAll('http://', '')
        .replaceAll('www.', '')
        .trim();
    clean = clean.replaceAll(RegExp(r'/+$'), '');
    if (clean.isNotEmpty) {
      setState(() {
        _blockedWebsites.add(clean);
        _websiteCtrl.clear();
      });
      _saveAppsAndWebsites(showMessage: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _allApps.where((app) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return app.appName.toLowerCase().contains(q) ||
          app.packageName.toLowerCase().contains(q);
    }).toList();

    final headerIcon = _isTimeLock
        ? Icons.lock_rounded
        : Icons.lock_clock_rounded;
    final headerColor = _isTimeLock
        ? const Color(0xFFE53935)
        : theme.colorScheme.primary;

    return PopScope<Object?>(
      canPop: _selectedTab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedTab == 1) {
          setState(() => _selectedTab = 0);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Top Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: headerColor.withValues(alpha: 0.2),
                      child: Icon(headerIcon, color: headerColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Locked In',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_isTimeLock)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'TIME LOCK ACTIVE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                )
                            ],
                          ),
                          Text(
                            _isTimeLock
                                ? 'Hardcore focus active: ${_remainingTime()}'
                                : 'Time Lock: Hardcore unbreakable distraction lock',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isTimeLock
                                  ? Colors.redAccent
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: _isTimeLock ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Tab bar switcher
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Time Lock'),
                      icon: Icon(Icons.lock_clock_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Apps & Sites'),
                      icon: Icon(Icons.grid_view_rounded, size: 16),
                    ),
                  ],
                  selected: {_selectedTab},
                  onSelectionChanged: (set) =>
                      setState(() => _selectedTab = set.first),
                ),
              ),

              const Divider(height: 12),

              // Tab Body
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _selectedTab == 0
                        ? _buildTimeLockTab(theme, _scrollController)
                        : _buildAppsAndWebsitesTab(theme, _scrollController, filtered),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 0: TIME LOCK (HARDCORE MODE)
  Widget _buildTimeLockTab(ThemeData theme, ScrollController scrollController) {
    final totalRules = _selectedPackages.length + _blockedWebsites.length;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (_isTimeLock) ...[
          // ACTIVE TIME LOCK CARD
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2C0A0A), Color(0xFF190505)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_rounded, color: Colors.redAccent, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'HARDCORE TIME LOCK ACTIVE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Locked until: ${_formatDateTime(_targetDateTime)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Time remaining: ${_remainingTime()}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.redAccent.shade100,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Divider(height: 24, color: Colors.white24),
                const Text(
                  '🛡️ Anti-Uninstall Protection: ACTIVE\n'
                  '🚫 Alert Snooze: STRICTLY DISABLED\n'
                  '🌐 Browser Tab Neutralizer: about:blank active\n'
                  '⚙️ System Settings Tampering: BLOCKED\n'
                  '🔄 Runs 24/7 even when DayAura is closed',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _emergencyUnlock,
                    icon: const Icon(Icons.vpn_key_rounded, size: 18),
                    label: const Text(
                      'Emergency Developer Unlock',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_selectedPackages.any((p) => (_appDailyLimits[p] ?? 0) > 0)) ...[
            const SizedBox(height: 14),
            _buildTimeLockQuotasCard(theme),
          ],
        ] else ...[
          // SETUP TIME LOCK CARD
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.redAccent, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Time Lock (Hardcore Mode)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Google Parental Control style self-imposed lock. Once enabled, the selected time controls you. You CANNOT remove blocked apps/sites, CANNOT snooze alerts, and CANNOT uninstall DayAura until the timer ends.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            'Select Target Unlock Time:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),

          // Quick Duration Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('+1 Day'),
                onPressed: () => setState(() =>
                    _targetDateTime = DateTime.now().add(const Duration(days: 1))),
              ),
              ActionChip(
                label: const Text('+3 Days'),
                onPressed: () => setState(() =>
                    _targetDateTime = DateTime.now().add(const Duration(days: 3))),
              ),
              ActionChip(
                label: const Text('+7 Days (1 Week)'),
                onPressed: () => setState(() =>
                    _targetDateTime = DateTime.now().add(const Duration(days: 7))),
              ),
              ActionChip(
                label: const Text('+30 Days (1 Month)'),
                onPressed: () => setState(() =>
                    _targetDateTime = DateTime.now().add(const Duration(days: 30))),
              ),
            ],
          ),

          const SizedBox(height: 12),
          // Target Date/Time Display & Picker Card
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickTargetDateTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Target Year : Month : Day : Hour',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          _formatDateTime(_targetDateTime),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_calendar_rounded, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Selected Distractions Summary Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.checklist_rounded, color: Colors.redAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Target Blocklist ($totalRules items)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        '${_selectedPackages.length} Apps • ${_blockedWebsites.length} Sites to strictly lock',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedTab = 1),
                  child: const Text('Edit ➔'),
                ),
              ],
            ),
          ),

          if (_selectedPackages.any((p) => (_appDailyLimits[p] ?? 0) > 0)) ...[
            const SizedBox(height: 14),
            _buildTimeLockQuotasCard(theme),
          ],

          const SizedBox(height: 14),

          // Psychological Warning & Mandatory Pre-Activation Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.report_problem_rounded, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'STRICT PSYCHOLOGICAL WARNING',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '“This Locked In feature is built exclusively for individuals struggling with severe digital addiction who cannot maintain self-control through willpower alone. If you possess even minimal restraint, you are strongly advised NOT to activate Time Lock.”',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: Colors.redAccent,
                    height: 1.4,
                  ),
                ),
                const Divider(height: 16, color: Colors.white24),
                const Text(
                  'Mandatory Pre-Activation Checklist:\n'
                  '1. Xiaomi / MIUI: In Recent Apps, long-press DayAura card and tap Padlock (🔒). In Security ➔ Boost Speed ➔ Lock apps, turn on DayAura.\n'
                  '2. All Brands: Set Battery Optimization to "Unrestricted" / "No Restrictions".\n'
                  '3. Anti-Deactivation: If Device Admin deactivation is attempted during Time Lock, the screen instantly locks.\n'
                  '4. Unbreakable Device Owner: 1-tap activation via Shizuku is available in the checklist below.\n'
                  '5. Single Browser Security: Only Google Chrome is permitted; all other browsers (Mi Browser, Firefox, Brave, etc.) are automatically hardware-frozen.',
                  style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.orangeAccent,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DayAuraPaperPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.menu_book_rounded, size: 16),
                    label: const Text(
                      'Read DayAura Paper & Setup Guide ➔',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Permissions Checklist
          _buildPermissionsCard(theme),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _activateTimeLock,
              icon: const Icon(Icons.lock_rounded),
              label: const Text(
                'ACTIVATE TIME LOCK 🔒',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBulletItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                desc,
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsCard(ThemeData theme) {
    final allGranted = _hasOverlay && _hasAccessibility && _hasDeviceAdmin && _hasBatteryOptimization;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allGranted
              ? const Color(0x6620B77A)
              : Colors.orangeAccent.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allGranted ? Icons.verified_rounded : Icons.security_rounded,
                size: 18,
                color: allGranted ? const Color(0xFF20B77A) : Colors.orangeAccent,
              ),
              const SizedBox(width: 8),
              const Text(
                'Background Engine Permissions:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildPermissionCheckRow(
            title: '1. Screen Overlay Warning',
            description: 'Display over other apps',
            isGranted: _hasOverlay,
            onFix: () => DistractionService.instance.requestOverlayPermission(),
          ),
          const Divider(height: 12),
          _buildPermissionCheckRow(
            title: '2. DayAura Browser Guard',
            description: 'Accessibility Service (blocks apps, sites & Settings)',
            isGranted: _hasAccessibility,
            onFix: () => DistractionService.instance.requestAccessibilityPermission(),
          ),
          const Divider(height: 12),
          _buildPermissionCheckRow(
            title: '3. Anti-Uninstall Shield (Device Admin)',
            description: _hasDeviceAdmin
                ? 'Active device administrator'
                : 'Extra shield against DayAura uninstallation',
            isGranted: _hasDeviceAdmin,
            onFix: () => DistractionService.instance.requestDeviceAdmin(),
          ),
          const Divider(height: 12),
          _buildPermissionCheckRow(
            title: '4. Battery Saver Exemption (Auto-Background)',
            description: _hasBatteryOptimization
                ? 'Unrestricted background execution active'
                : 'Allow unrestricted background execution',
            isGranted: _hasBatteryOptimization,
            onFix: () async {
              await DistractionService.instance.openBatteryOptimizationSettings();
              await DistractionService.instance.openAutostartSettings();
            },
          ),
          const Divider(height: 12),
          _buildPermissionCheckRow(
            title: '5. Unbreakable Device Owner (Hardcore Lock)',
            description: _hasDeviceOwner
                ? 'Device Owner Active 🛡️ (Hardware Freeze & Gray Icons)'
                : 'Enables OS-level kernel freeze, gray launcher icons & unbreakable distraction lock.',
            isGranted: _hasDeviceOwner,
            isLoading: _isActivatingShizuku,
            customActionText: '⚡ Activate Device Owner',
            onFix: _handleActivateShizuku,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF20B77A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF20B77A).withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.all_inclusive_rounded, size: 18, color: Color(0xFF20B77A)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🛡️ Universal Background Shield:\nDayAura runs autonomously via Android System Accessibility & Battery Exemption across all Android phones without needing manual app lock.',
                    style: TextStyle(fontSize: 11.5, color: Colors.white, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🔒 Xiaomi Cleaner Whitelist Tip:\nIn Recent Apps, long-press DayAura and tap the Padlock 🔒 icon so Xiaomi Cleaner & Memory Clean never kills DayAura.',
                    style: TextStyle(fontSize: 11.5, color: Colors.white, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeLockQuotasCard(ThemeData theme) {
    final quotaPkgs = _selectedPackages
        .where((p) => (_appDailyLimits[p] ?? 0) > 0)
        .toList();
    if (quotaPkgs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF20B77A).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, color: Color(0xFF20B77A), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Daily App Limits & Remaining Time',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Refresh Screen Time',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _refreshUsageStats,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Live screen time from Android OS. At 0m remaining, app is frozen via Device Owner (gray launcher icon). Automatic 2-min warning notification is sent before lock.',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 16),
          ...quotaPkgs.map((pkg) {
            final app = _allApps.cast<InstalledAppInfo?>().firstWhere(
                  (a) => a?.packageName == pkg,
                  orElse: () => null,
                );
            final name = app?.appName ?? pkg.split('.').last;
            final limitMin = _appDailyLimits[pkg] ?? 0;
            final usedSec = _appDailyUsage[pkg] ?? 0;
            final usedMin = (usedSec / 60).floor();
            final remainingSec = (limitMin * 60) - usedSec;
            final isLocked = remainingSec <= 0;
            final remMin = isLocked ? 0 : (remainingSec / 60).ceil();
            final progress = (usedSec / (limitMin * 60)).clamp(0.0, 1.0);

            final statusColor = isLocked
                ? Colors.redAccent
                : (remMin <= 2 ? Colors.amber : const Color(0xFF20B77A));

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          isLocked
                              ? '🔴 HARDWARE LOCKED (Gray Icon • 0m left)'
                              : (remMin <= 2
                                  ? '🟡 2-MIN WARNING (${remMin}m left)'
                                  : '🟢 ${remMin}m left before lock'),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Limit: ${limitMin}m/day',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'Used today: ${usedMin}m',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // TAB 2: APPS & WEBSITES
  Widget _buildAppsAndWebsitesTab(
    ThemeData theme,
    ScrollController scrollController,
    List<InstalledAppInfo> filtered,
  ) {
    final quotaCount = _selectedPackages
        .where((p) => (_appDailyLimits[p] ?? 0) > 0)
        .length;

    return Column(
      children: [
        if (_isTimeLock)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_rounded, size: 16, color: Colors.redAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Time Lock Active: Blocked apps & website rules cannot be modified.',
                    style: TextStyle(fontSize: 11.5, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),

        // Sub tab switcher [Apps] / [Remaining] / [Websites]
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: Text('Apps (${_selectedPackages.length})'),
                icon: const Icon(Icons.apps_rounded, size: 16),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Remaining ($quotaCount)'),
                icon: const Icon(Icons.timer_outlined, size: 16),
              ),
              ButtonSegment(
                value: 2,
                label: Text(
                  'Websites (${_blockedWebsites.length + (_blockAdult ? 1 : 0) + (_blockGambling ? 1 : 0) + (_forceSafeSearch ? 1 : 0)})',
                ),
                icon: const Icon(Icons.language_rounded, size: 16),
              ),
            ],
            selected: {_appsSitesSubTab},
            onSelectionChanged: (set) =>
                setState(() => _appsSitesSubTab = set.first),
          ),
        ),

        const Divider(height: 8),

        Expanded(
          child: _appsSitesSubTab == 0
              ? _buildAppsSubView(theme, scrollController, filtered)
              : _appsSitesSubTab == 1
                  ? _buildRemainingQuotaSubView(theme, scrollController)
                  : _buildWebsitesSubView(theme, scrollController),
        ),
      ],
    );
  }

  Widget _buildAppsSubView(
    ThemeData theme,
    ScrollController scrollController,
    List<InstalledAppInfo> filtered,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search installed apps...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
        ),
        // Quick Presets
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: _commonAppPresets.entries.map((entry) {
              final pkgs = entry.value;
              final isSelected =
                  pkgs.every((p) => _selectedPackages.contains(p));
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(entry.key),
                  avatar:
                      isSelected ? const Icon(Icons.check_rounded, size: 16) : null,
                  onSelected: (selected) {
                    if (_isTimeLock && isSelected && !selected) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Cannot uncheck apps while Time Lock is active!'),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      if (selected) {
                        _selectedPackages.addAll(pkgs);
                      } else {
                        _selectedPackages.removeAll(pkgs);
                      }
                    });
                    _saveAppsAndWebsites(showMessage: false);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _allApps.isEmpty
                        ? 'No apps detected.\nPlease grant Usage Access in Settings.'
                        : 'No matching apps found',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final app = filtered[index];
                    final isChecked =
                        _selectedPackages.contains(app.packageName);
                    return CheckboxListTile(
                      value: isChecked,
                      secondary: CircleAvatar(
                        backgroundColor: isChecked
                            ? const Color(0x33E53935)
                            : theme.colorScheme.surfaceContainerHighest,
                        child: Text(
                          app.appName.isNotEmpty
                              ? app.appName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isChecked
                                ? const Color(0xFFE53935)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              app.appName,
                              style: TextStyle(
                                fontWeight:
                                    isChecked ? FontWeight.bold : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isChecked) ...[
                            const SizedBox(width: 6),
                            Builder(
                              builder: (context) {
                                final limit = _appDailyLimits[app.packageName] ?? 0;
                                final usedSec = _appDailyUsage[app.packageName] ?? 0;
                                final usedMin = (usedSec / 60).floor();
                                final isFullBlock = limit <= 0;
                                final remainingSec = (limit * 60) - usedSec;
                                final isOver = limit > 0 && remainingSec <= 0;
                                final remMin = isOver ? 0 : (remainingSec / 60).ceil();
                                final badgeColor = (isFullBlock || isOver) ? Colors.redAccent : const Color(0xFF20B77A);

                                String label;
                                if (isFullBlock) {
                                  label = '0m (Blocked)';
                                } else if (isOver) {
                                  label = '${limit}m (Locked • 0m left)';
                                } else {
                                  label = '${limit}m (${remMin}m left)';
                                }

                                return InkWell(
                                  onTap: () => _showAppLimitDialog(app),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: badgeColor.withValues(alpha: 0.4),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          (isFullBlock || isOver)
                                              ? Icons.block_rounded
                                              : Icons.timer_outlined,
                                          size: 11,
                                          color: badgeColor,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.packageName,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isChecked)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Builder(
                                builder: (context) {
                                  final limit = _appDailyLimits[app.packageName] ?? 0;
                                  final usedSec = _appDailyUsage[app.packageName] ?? 0;
                                  final usedMin = (usedSec / 60).floor();
                                  if (limit <= 0) {
                                    return const Text(
                                      '⛔ 0m Full Block',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.redAccent,
                                      ),
                                    );
                                  }
                                  final remainingSec = (limit * 60) - usedSec;
                                  final isOver = remainingSec <= 0;
                                  final remMin = isOver ? 0 : (remainingSec / 60).ceil();
                                  return Text(
                                    isOver
                                        ? '🔴 Locked! Used ${usedMin}m / ${limit}m (0m left)'
                                        : '🟢 ${remMin}m left before lock (Used ${usedMin}m / ${limit}m)',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: isOver ? Colors.redAccent : const Color(0xFF20B77A),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      onChanged: (val) {
                        if (_isTimeLock && isChecked && val != true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Cannot uncheck apps while Time Lock is active!'),
                            ),
                          );
                          return;
                        }
                        setState(() {
                          if (val == true) {
                            _selectedPackages.add(app.packageName);
                            if (!_appDailyLimits.containsKey(app.packageName)) {
                              _appDailyLimits[app.packageName] = 0;
                            }
                          } else {
                            _selectedPackages.remove(app.packageName);
                          }
                        });
                        _saveAppsAndWebsites(showMessage: false);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRemainingQuotaSubView(
    ThemeData theme,
    ScrollController scrollController,
  ) {
    final quotaPkgs = _selectedPackages
        .where((p) => (_appDailyLimits[p] ?? 0) > 0)
        .toList();
    final fullBlockPkgs = _selectedPackages
        .where((p) => (_appDailyLimits[p] ?? 0) <= 0)
        .toList();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Live Screen Time Sync Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF20B77A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF20B77A).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_bottom_rounded,
                  color: Color(0xFF20B77A), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Quotas & Remaining Time',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Live sync with Android OS screen time. When remaining time hits 0m, app is frozen via Device Owner (gray icon).\n⚠️ Automatic 2-minute heads-up warning notification is sent before lock.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF20B77A)),
                tooltip: 'Refresh Screen Time',
                onPressed: _refreshUsageStats,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (quotaPkgs.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              children: [
                Icon(Icons.timer_outlined,
                    size: 40, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 10),
                const Text(
                  'No Daily Quotas Set Yet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  'Go to the "Apps" tab, select an app (e.g. Facebook Lite, YouTube), and tap its timer badge to set a daily quota (e.g. 15m, 30m).\n\nDayAura will then actively track usage and lock the app when remaining time runs out.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _appsSitesSubTab = 0),
                  icon: const Icon(Icons.apps_rounded, size: 16),
                  label: const Text('Go to Apps Tab'),
                ),
              ],
            ),
          ),
        ] else ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'APPS WITH ACTIVE DAILY QUOTA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Color(0xFF20B77A),
              ),
            ),
          ),
          ...quotaPkgs.map((pkg) {
            final app = _allApps.cast<InstalledAppInfo?>().firstWhere(
                  (a) => a?.packageName == pkg,
                  orElse: () => null,
                );
            final name = app?.appName ?? pkg.split('.').last;
            final limitMin = _appDailyLimits[pkg] ?? 0;
            final usedSec = _appDailyUsage[pkg] ?? 0;
            final usedMin = (usedSec / 60).floor();
            final remainingSec = (limitMin * 60) - usedSec;
            final isLocked = remainingSec <= 0;
            final remMin = isLocked ? 0 : (remainingSec / 60).ceil();
            final progress = (usedSec / (limitMin * 60)).clamp(0.0, 1.0);

            final statusColor = isLocked
                ? Colors.redAccent
                : (remMin <= 2 ? Colors.amber : const Color(0xFF20B77A));

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isLocked
                      ? Colors.redAccent.withValues(alpha: 0.4)
                      : theme.dividerColor,
                  width: isLocked ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        child: Icon(
                          isLocked
                              ? Icons.block_rounded
                              : Icons.timer_outlined,
                          size: 16,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              pkg,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          isLocked
                              ? '🔴 HARDWARE LOCKED (Gray Icon • 0m left)'
                              : (remMin <= 2
                                  ? '🟡 2-MIN WARNING (${remMin}m left)'
                                  : '🟢 ${remMin}m left before lock'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '⏱ Quota: ${limitMin}m/day',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '📱 Used: ${usedMin}m today',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        isLocked
                            ? '⏳ 0m left'
                            : '⏳ ${remMin}m left',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  if (app != null && !_isTimeLock) ...[
                    const Divider(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showAppLimitDialog(app),
                        icon: const Icon(Icons.edit_outlined, size: 13),
                        label: const Text('Change Quota',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],

        if (fullBlockPkgs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'FULL BLOCKED APPS (0m QUOTA - 100% LOCKED)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Colors.redAccent.shade100,
              ),
            ),
          ),
          ...fullBlockPkgs.map((pkg) {
            final app = _allApps.cast<InstalledAppInfo?>().firstWhere(
                  (a) => a?.packageName == pkg,
                  orElse: () => null,
                );
            final name = app?.appName ?? pkg.split('.').last;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block_rounded, size: 14, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text(
                    'Full Block (0m)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildWebsitesSubView(ThemeData theme, ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 0. Enforced SafeSearch Shield Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _forceSafeSearch
                ? const Color(0xFF20B77A).withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _forceSafeSearch
                  ? const Color(0xFF20B77A).withValues(alpha: 0.4)
                  : theme.dividerColor.withValues(alpha: 0.4),
            ),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: CircleAvatar(
              backgroundColor: _forceSafeSearch
                  ? const Color(0x3320B77A)
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.search_rounded,
                color: _forceSafeSearch ? const Color(0xFF20B77A) : Colors.grey,
              ),
            ),
            title: const Text(
              '🔍 Enforced SafeSearch (All Browsers)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: const Text(
              'Forces Google, Bing, and YouTube SafeSearch permanently locked on at network level across Chrome, Mi Browser & incognito. Explicit results are filtered out.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            value: _forceSafeSearch,
            onChanged: _isTimeLock
                ? null
                : (val) {
                    setState(() => _forceSafeSearch = val);
                    _saveAppsAndWebsites(showMessage: false);
                  },
          ),
        ),

        const SizedBox(height: 10),

        // 1. Adult Protection Shield Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _blockAdult
                ? const Color(0xFFE53935).withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _blockAdult
                  ? const Color(0xFFE53935).withValues(alpha: 0.4)
                  : theme.dividerColor.withValues(alpha: 0.4),
            ),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: CircleAvatar(
              backgroundColor: _blockAdult
                  ? const Color(0x33E53935)
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.shield_rounded,
                color: _blockAdult ? const Color(0xFFE53935) : Colors.grey,
              ),
            ),
            title: const Text(
              '🔞 Adult & 18+ Protection Shield',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: const Text(
              'DNS firewall & native engine automatically blocks 15,000+ porn and explicit domains across all browsers.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            value: _blockAdult,
            onChanged: _isTimeLock
                ? null
                : (val) {
                    setState(() => _blockAdult = val);
                    _saveAppsAndWebsites(showMessage: false);
                  },
          ),
        ),

        const SizedBox(height: 10),

        // 2. Casino & Gambling Shield Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _blockGambling
                ? const Color(0xFFFFA000).withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _blockGambling
                  ? const Color(0xFFFFA000).withValues(alpha: 0.4)
                  : theme.dividerColor.withValues(alpha: 0.4),
            ),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: CircleAvatar(
              backgroundColor: _blockGambling
                  ? const Color(0x33FFA000)
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.casino_rounded,
                color: _blockGambling ? const Color(0xFFFFA000) : Colors.grey,
              ),
            ),
            title: const Text(
              '🎰 Casino & Betting Protection Shield',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: const Text(
              'Blocks 1xBet, Bet365, Babu88, online casinos, betting platforms and gambling keywords.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            value: _blockGambling,
            onChanged: _isTimeLock
                ? null
                : (val) {
                    setState(() => _blockGambling = val);
                    _saveAppsAndWebsites(showMessage: false);
                  },
          ),
        ),

        const SizedBox(height: 14),

        // 3. Custom Domain Input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _websiteCtrl,
                enabled: !_isTimeLock,
                decoration: InputDecoration(
                  hintText: 'Add domain (e.g. facebook.com, youtube.com)',
                  prefixIcon: const Icon(Icons.add_link_rounded),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _addCustomWebsite(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.add_rounded),
              onPressed: _isTimeLock ? null : _addCustomWebsite,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 4. Popular Social Media & Platform Presets
        const Text(
          'Popular Platforms Quick Presets',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _popularSocialMediaDomains.map((domain) {
            final isChecked = _blockedWebsites.contains(domain);
            return FilterChip(
              selected: isChecked,
              visualDensity: VisualDensity.compact,
              label: Text(domain, style: const TextStyle(fontSize: 11.5)),
              selectedColor: const Color(0x3320B77A),
              checkmarkColor: const Color(0xFF20B77A),
              onSelected: (selected) {
                if (_isTimeLock && isChecked && !selected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cannot uncheck websites while Time Lock is active!'),
                    ),
                  );
                  return;
                }
                setState(() {
                  if (selected) {
                    _blockedWebsites.add(domain);
                  } else {
                    _blockedWebsites.remove(domain);
                  }
                });
                _saveAppsAndWebsites(showMessage: false);
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // 5. Custom Blocked Websites List
        Text(
          'Active Blocked Domains (${_blockedWebsites.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),

        if (_blockedWebsites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No custom domains added.\nAdult & Gambling Protection Shields protect automatically.',
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _blockedWebsites.map((site) {
              return Chip(
                avatar: const Icon(Icons.public_off_rounded, size: 16),
                label: Text(site),
                deleteIcon: _isTimeLock
                    ? null
                    : const Icon(Icons.close_rounded, size: 16),
                onDeleted: _isTimeLock
                    ? null
                    : () {
                        setState(() => _blockedWebsites.remove(site));
                        _saveAppsAndWebsites(showMessage: false);
                      },
              );
            }).toList(),
          ),

        const SizedBox(height: 16),
        // Browser Recommendation & Deep Guard Explanation
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF20B77A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF20B77A).withValues(alpha: 0.3)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_rounded, size: 18, color: Color(0xFF20B77A)),
                  SizedBox(width: 8),
                  Text(
                    'Single Authorized Browser: Google Chrome',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF20B77A),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                '• ONLY Google Chrome is permitted for browsing (research, study, clean YouTube videos). Incognito is permanently disabled via Enterprise Policy.\n• All other browsers in the world (Mi Browser, Firefox, Brave, Opera, Tor, Via, UC, etc.) are 100% automatically hardware-suspended (gray icons) to guarantee zero bypass.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
