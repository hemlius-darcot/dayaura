import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DistractionItem {
  const DistractionItem({
    required this.id,
    required this.name,
    required this.timestamp,
    required this.timeLabel,
  });

  final String id;
  final String name;
  final DateTime timestamp;
  final String timeLabel;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'timestamp': timestamp.toIso8601String(),
    'timeLabel': timeLabel,
  };

  factory DistractionItem.fromJson(Map<String, dynamic> json) {
    return DistractionItem(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'Unspecified',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      timeLabel: json['timeLabel']?.toString() ?? '',
    );
  }
}

class InstalledAppInfo {
  final String packageName;
  final String appName;

  const InstalledAppInfo({
    required this.packageName,
    required this.appName,
  });

  factory InstalledAppInfo.fromMap(Map<dynamic, dynamic> map) {
    return InstalledAppInfo(
      packageName: map['packageName']?.toString() ?? '',
      appName: map['appName']?.toString() ?? '',
    );
  }
}

class AppVerificationNotice {
  final String packageName;
  final String appName;
  final bool approved;
  final String category;
  final String title;
  final String reason;
  final DateTime timestamp;

  const AppVerificationNotice({
    required this.packageName,
    required this.appName,
    required this.approved,
    required this.category,
    required this.title,
    required this.reason,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'appName': appName,
    'approved': approved,
    'category': category,
    'title': title,
    'reason': reason,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AppVerificationNotice.fromJson(Map<String, dynamic> json) => AppVerificationNotice(
    packageName: json['packageName']?.toString() ?? '',
    appName: json['appName']?.toString() ?? '',
    approved: json['approved'] == true,
    category: json['category']?.toString() ?? 'General',
    title: json['title']?.toString() ?? '',
    reason: json['reason']?.toString() ?? '',
    timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
  );
}

class DistractionService {
  static final DistractionService instance = DistractionService._();
  DistractionService._() {
    _platform.setMethodCallHandler(_handleNativeCall);
  }

  static const MethodChannel _platform =
      MethodChannel('com.example.routine_app/distraction_tracker');

  final List<VoidCallback> _listeners = [];
  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);
  void _notifyListeners() {
    for (final cb in _listeners) {
      cb();
    }
  }

  VoidCallback? _emergencyUnlockCallback;
  void registerEmergencyUnlockCallback(VoidCallback cb) {
    _emergencyUnlockCallback = cb;
  }
  void unregisterEmergencyUnlockCallback() {
    _emergencyUnlockCallback = null;
  }

  Function(AppVerificationNotice notice)? onAppVerificationNotice;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onShizukuStatusChanged' || call.method == 'onShizukuPermissionResult') {
      _notifyListeners();
      return;
    }
    if (call.method == 'openEmergencyUnlock') {
      _emergencyUnlockCallback?.call();
      return;
    }
    if (call.method == 'onAppInstalledDuringTimeLock') {
      final args = call.arguments;
      if (args is Map) {
        final pkg = args['packageName']?.toString() ?? '';
        final appName = args['appName']?.toString() ?? '';
        if (pkg.isNotEmpty) {
          verifyAndProcessInstalledApp(pkg, appName);
        }
      }
      return;
    }
    if (call.method == 'onDistractionLogged') {
      final args = call.arguments;
      if (args is Map) {
        final id = args['id']?.toString();
        final name = args['name']?.toString() ?? 'Distracted';
        final iso = args['timestamp']?.toString();
        final timeLabel = args['timeLabel']?.toString();
        final ts = (iso != null && iso.isNotEmpty) ? DateTime.tryParse(iso) : null;
        await recordDistraction(
          name,
          id: id,
          timestamp: ts,
          timeLabel: timeLabel,
          notifyNative: false,
        );
      }
    }
  }

  Future<bool> uninstallPackageSilently(String packageName) async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('uninstallPackageSilently', {
        'packageName': packageName,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('uninstallPackageSilently error: $e');
      return false;
    }
  }

  Future<bool> unfreezePackage(String packageName) async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('unfreezePackage', {
        'packageName': packageName,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('unfreezePackage error: $e');
      return false;
    }
  }

  Future<List<Map<String, String>>> getPendingInstalledApps() async {
    if (!Platform.isAndroid) return [];
    try {
      final res = await _platform.invokeListMethod<dynamic>('getPendingInstalledApps');
      if (res != null) {
        return res.map((m) {
          final map = m as Map<dynamic, dynamic>;
          return {
            'packageName': map['packageName']?.toString() ?? '',
            'appName': map['appName']?.toString() ?? '',
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('getPendingInstalledApps error: $e');
    }
    return [];
  }

  Future<void> removePendingInstalledApp(String packageName) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('removePendingInstalledApp', {
        'packageName': packageName,
      });
    } catch (_) {}
  }

  Future<File> _smartGuardNoticesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/smart_guard_notices.json');
  }

  Future<List<AppVerificationNotice>> loadVerificationNotices() async {
    try {
      final file = await _smartGuardNoticesFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list.map((e) => AppVerificationNotice.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveVerificationNotice(AppVerificationNotice notice) async {
    try {
      final list = await loadVerificationNotices();
      list.removeWhere((n) => n.packageName == notice.packageName);
      list.insert(0, notice);
      if (list.length > 20) list.removeRange(20, list.length);
      final file = await _smartGuardNoticesFile();
      await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> dismissVerificationNotice(String packageName) async {
    try {
      final list = await loadVerificationNotices();
      list.removeWhere((n) => n.packageName == packageName);
      final file = await _smartGuardNoticesFile();
      await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
      _notifyListeners();
    } catch (_) {}
  }

  Future<AppVerificationNotice?> verifyAndProcessInstalledApp(
    String packageName,
    String appName,
  ) async {
    try {
      final url = Uri.parse('https://lslabmeelnlzkqzaumkh.supabase.co/functions/v1/dayaura-bot');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'verify_app',
          'packageName': packageName,
          'appName': appName,
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final approved = data['approved'] == true;
        final category = data['category']?.toString() ?? (approved ? 'Educational' : 'Gaming / Distraction');
        final title = data['title']?.toString() ?? (approved ? 'Study App Approved' : 'Distraction App Detected');
        final reason = data['reason']?.toString() ?? '';

        final notice = AppVerificationNotice(
          packageName: packageName,
          appName: appName,
          approved: approved,
          category: category,
          title: title,
          reason: reason,
          timestamp: DateTime.now(),
        );

        if (!approved) {
          // ❌ Silent uninstall via Device Owner
          await uninstallPackageSilently(packageName);
        } else {
          // ✅ Unfreeze
          await unfreezePackage(packageName);
        }

        await removePendingInstalledApp(packageName);
        await saveVerificationNotice(notice);
        onAppVerificationNotice?.call(notice);
        _notifyListeners();
        return notice;
      }
    } catch (e) {
      debugPrint('verifyAndProcessInstalledApp error for $packageName: $e');
    }
    return null;
  }

  Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('canDrawOverlays');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking overlay permission: $e');
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
    }
  }

  Future<bool> startFloatingTracker() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('startFloatingService');
      return res ?? false;
    } catch (e) {
      debugPrint('Error starting floating service: $e');
      return false;
    }
  }

  Future<void> stopFloatingTracker() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('stopFloatingService');
    } catch (e) {
      debugPrint('Error stopping floating service: $e');
    }
  }

  Future<bool> isFloatingTrackerRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('isFloatingServiceRunning');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> canAccessUsageStats() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('canAccessUsageStats');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking usage stats permission: $e');
      return false;
    }
  }

  Future<void> requestUsageStatsPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('requestUsageStatsPermission');
    } catch (e) {
      debugPrint('Error requesting usage stats permission: $e');
    }
  }

  Future<List<InstalledAppInfo>> getInstalledApps() async {
    if (!Platform.isAndroid) return [];
    try {
      final res = await _platform.invokeListMethod<dynamic>('getInstalledApps');
      if (res == null) return [];
      return res.whereType<Map>().map((m) => InstalledAppInfo.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error getting installed apps: $e');
      return [];
    }
  }

  Future<List<String>> getDistractingApps() async {
    if (!Platform.isAndroid) return [];
    try {
      final res = await _platform.invokeListMethod<dynamic>('getDistractingApps');
      if (res == null) return [];
      return res.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Error getting distracting apps: $e');
      return [];
    }
  }

  Future<void> saveDistractingApps(List<String> packages) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('saveDistractingApps', {'packages': packages});
    } catch (e) {
      debugPrint('Error saving distracting apps: $e');
    }
  }

  Future<Map<String, int>> getAppDailyLimits() async {
    if (!Platform.isAndroid) return {};
    try {
      final res = await _platform.invokeMapMethod<String, dynamic>('getAppDailyLimits');
      if (res == null) return {};
      return res.map((key, value) => MapEntry(key, (value as num).toInt()));
    } catch (e) {
      debugPrint('Error getting app daily limits: $e');
      return {};
    }
  }

  Future<void> saveAppDailyLimits(Map<String, int> limits) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('saveAppDailyLimits', {'limits': limits});
    } catch (e) {
      debugPrint('Error saving app daily limits: $e');
    }
  }

  Future<Map<String, int>> getAppDailyUsage() async {
    if (!Platform.isAndroid) return {};
    try {
      final res = await _platform.invokeMapMethod<String, dynamic>('getAppDailyUsage');
      if (res == null) return {};
      return res.map((key, value) => MapEntry(key, (value as num).toInt()));
    } catch (e) {
      debugPrint('Error getting app daily usage: $e');
      return {};
    }
  }

  Future<bool> isDeviceAdminActive() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('isDeviceAdminActive');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking device admin: $e');
      return false;
    }
  }

  Future<void> requestDeviceAdmin() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('requestDeviceAdmin');
    } catch (e) {
      debugPrint('Error requesting device admin: $e');
    }
  }

  Future<bool> isAccessibilityServiceEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final res =
          await _platform.invokeMethod<bool>('isAccessibilityServiceEnabled');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking accessibility: $e');
      return false;
    }
  }

  Future<void> requestAccessibilityPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      debugPrint('Error requesting accessibility permission: $e');
    }
  }

  Future<bool> openAutostartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('openAutostartSettings');
      return res ?? false;
    } catch (e) {
      debugPrint('Error opening autostart settings: $e');
      return false;
    }
  }

  Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final res =
          await _platform.invokeMethod<bool>('openBatteryOptimizationSettings');
      return res ?? false;
    } catch (e) {
      debugPrint('Error opening battery optimization settings: $e');
      return false;
    }
  }

  Future<bool> isBatteryOptimizationIgnored() async {
    if (!Platform.isAndroid) return false;
    try {
      final res =
          await _platform.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking battery optimization: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getBlockedWebsites() async {
    if (!Platform.isAndroid) {
      return {'websites': <String>[], 'blockAdult': true, 'blockGambling': true, 'forceSafeSearch': true};
    }
    try {
      final res =
          await _platform.invokeMapMethod<String, dynamic>('getBlockedWebsites');
      if (res == null) {
        return {'websites': <String>[], 'blockAdult': true, 'blockGambling': true, 'forceSafeSearch': true};
      }
      final rawList = res['websites'];
      final list =
          (rawList is List) ? rawList.map((e) => e.toString()).toList() : <String>[];
      return {
        'websites': list,
        'blockAdult': res['blockAdult'] as bool? ?? true,
        'blockGambling': res['blockGambling'] as bool? ?? true,
        'forceSafeSearch': res['forceSafeSearch'] as bool? ?? true,
      };
    } catch (e) {
      debugPrint('Error getting blocked websites: $e');
      return {'websites': <String>[], 'blockAdult': true, 'blockGambling': true, 'forceSafeSearch': true};
    }
  }

  Future<void> saveBlockedWebsites(
    List<String> websites, {
    bool blockAdult = true,
    bool blockGambling = true,
    bool forceSafeSearch = true,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('saveBlockedWebsites', {
        'websites': websites,
        'blockAdult': blockAdult,
        'blockGambling': blockGambling,
        'forceSafeSearch': forceSafeSearch,
      });
    } catch (e) {
      debugPrint('Error saving blocked websites: $e');
    }
  }

  Future<bool> prepareVpn() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _platform.invokeMethod<bool>('prepareVpn');
      return res ?? true;
    } catch (e) {
      debugPrint('Error preparing VPN: $e');
      return true;
    }
  }

  Future<void> startVpn() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('startVpn');
    } catch (e) {
      debugPrint('Error starting VPN: $e');
    }
  }

  Future<void> stopVpn() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('stopVpn');
    } catch (e) {
      debugPrint('Error stopping VPN: $e');
    }
  }

  Future<bool> isVpnRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('isVpnRunning');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getLockedInConfig() async {
    if (!Platform.isAndroid) {
      return {'mode': 'none', 'untilEpoch': 0};
    }
    try {
      final res =
          await _platform.invokeMapMethod<String, dynamic>('getLockedInConfig');
      return {
        'mode': res?['mode']?.toString() ?? 'none',
        'untilEpoch': (res?['untilEpoch'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      debugPrint('Error getting locked in config: $e');
      return {'mode': 'none', 'untilEpoch': 0};
    }
  }

  Future<Map<String, dynamic>> getLockedInState() async {
    final cfg = await getLockedInConfig();
    final mode = cfg['mode'] as String? ?? 'none';
    final until = cfg['untilEpoch'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isTime = mode == 'time_lock' && now < until;
    return {
      'mode': mode,
      'active': isTime,
      'isTimeLock': isTime,
      'isMindLock': false,
      'untilEpoch': until,
    };
  }

  Future<void> setLockedInMode({
    required String mode, // 'none', 'time_lock'
    int untilEpoch = 0,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('setLockedInMode', {
        'mode': mode,
        'untilEpoch': untilEpoch,
      });
    } catch (e) {
      debugPrint('Error setting locked in mode: $e');
    }
  }

  Future<void> setLockedInState({
    required bool active,
    required int untilEpoch,
  }) async {
    await setLockedInMode(
      mode: active ? 'time_lock' : 'none',
      untilEpoch: untilEpoch,
    );
  }

  Future<Map<String, dynamic>> checkShizukuStatus() async {
    if (!Platform.isAndroid) {
      return {'isRunning': false, 'hasPermission': false, 'isDeviceOwner': false};
    }
    try {
      final res = await _platform.invokeMapMethod<String, dynamic>('checkShizukuStatus');
      return {
        'isRunning': res?['isRunning'] as bool? ?? false,
        'hasPermission': res?['hasPermission'] as bool? ?? false,
        'isDeviceOwner': res?['isDeviceOwner'] as bool? ?? false,
      };
    } catch (e) {
      debugPrint('Error checking Shizuku status: $e');
      return {'isRunning': false, 'hasPermission': false, 'isDeviceOwner': false};
    }
  }

  Future<Map<String, dynamic>> requestShizukuPermission() async {
    if (!Platform.isAndroid) return {'success': false};
    try {
      final res = await _platform.invokeMapMethod<String, dynamic>('requestShizukuPermission');
      return res ?? {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> activateDeviceOwnerViaShizuku({bool autoRemoveUsers = false}) async {
    if (!Platform.isAndroid) return {'success': false, 'message': 'Android only'};
    try {
      final res = await _platform.invokeMapMethod<String, dynamic>('activateDeviceOwnerViaShizuku', {
        'autoRemoveUsers': autoRemoveUsers,
      });
      return res ?? {'success': false, 'message': 'No response from system'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> removeSecondaryUsersViaShizuku() async {
    if (!Platform.isAndroid) return {'success': false};
    try {
      final res = await _platform.invokeMapMethod<String, dynamic>('removeSecondaryUsersViaShizuku');
      return res ?? {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> openDualAppsSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('openDualAppsSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAccountsSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('openAccountsSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isDeviceOwner() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('isDeviceOwner');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> releaseDeviceOwner() async {
    if (!Platform.isAndroid) return {'success': true};
    try {
      final res = await _platform.invokeMapMethod<String, dynamic>('releaseDeviceOwner');
      return res ?? {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> openShizukuApp() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _platform.invokeMethod<bool>('openShizukuApp');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  static String getDailyPasscode({
    required int month,
    required int day,
    int slot = 1,
  }) {
    final mStr = month.toString().padLeft(2, '0');
    final dStr = day.toString().padLeft(2, '0');
    final sStr = slot.toString().padLeft(2, '0');
    final key = '$mStr-$dStr-slot$sStr';
    final raw = utf8.encode('DayAura_LockedIn_MultiSlot_2026_Secure_$key');
    final digest = sha256.convert(raw).toString();
    final pin = int.parse(digest.substring(0, 8), radix: 16) % 900000 + 100000;
    return 'DA-$pin';
  }

  static List<String> getTodayPasscodes({DateTime? date}) {
    final dt = date ?? DateTime.now();
    return List.generate(
      10,
      (index) => getDailyPasscode(month: dt.month, day: dt.day, slot: index + 1),
    );
  }

  static String getTodayPasscode({DateTime? date, int slot = 1}) {
    final dt = date ?? DateTime.now();
    return getDailyPasscode(month: dt.month, day: dt.day, slot: slot);
  }

  static bool verifyUnlockPasscode(String input, {DateTime? date}) {
    final clean = input.trim().toUpperCase().replaceAll('DA-', '');
    if (clean.length != 6) return false;
    final validCodes = getTodayPasscodes(date: date);
    return validCodes.any((c) => c.replaceAll('DA-', '') == clean);
  }

  Future<File> _lockedInSessionFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/locked_in_session.json');
  }

  Future<int> registerTimeLockStart() async {
    try {
      final file = await _lockedInSessionFile();
      final now = DateTime.now();
      final today = _dateKey(now);
      int slot = 1;

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic> && decoded['date'] == today) {
            final prevSlot = (decoded['slot'] as num?)?.toInt() ?? 0;
            slot = prevSlot + 1;
          }
        }
      }

      await file.writeAsString(jsonEncode({
        'date': today,
        'startEpoch': now.millisecondsSinceEpoch,
        'slot': slot,
      }));
      return slot;
    } catch (e) {
      debugPrint('Error registering time lock start: $e');
      return 1;
    }
  }

  Future<String?> getGracePeriodPasscode() async {
    try {
      final state = await getLockedInState();
      final isTimeLock = state['isTimeLock'] == true;
      if (!isTimeLock) return null;

      final file = await _lockedInSessionFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;

      final now = DateTime.now();
      final today = _dateKey(now);
      final savedDate = decoded['date'] as String? ?? '';
      if (savedDate != today) return null; // Midnight has passed!

      final startEpoch = (decoded['startEpoch'] as num?)?.toInt() ?? 0;
      if (startEpoch <= 0) return null;

      final startDt = DateTime.fromMillisecondsSinceEpoch(startEpoch);
      final isSameDay = (now.year == startDt.year &&
          now.month == startDt.month &&
          now.day == startDt.day);
      if (!isSameDay) return null; // Midnight has passed!

      final slot = (decoded['slot'] as num?)?.toInt() ?? 1;
      if (slot < 1 || slot > 10) return null; // Limit of 10 daily slots exceeded

      return getDailyPasscode(month: now.month, day: now.day, slot: slot);
    } catch (e) {
      debugPrint('Error getting grace period passcode: $e');
      return null;
    }
  }

  Future<File> _storageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/today_distractions.json');
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _formatTimeLabel(DateTime dt) {
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${h12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  Future<List<DistractionItem>> loadTodayDistractions() async {
    // Also check for any native offline logged distractions
    await _syncPendingNativeDistractions();

    try {
      final file = await _storageFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return [];

      final today = _dateKey(DateTime.now());
      if (decoded['date'] != today) {
        // Different day - reset today file
        return [];
      }

      final list = decoded['items'];
      if (list is! List) return [];
      final rawItems = list
          .whereType<Map>()
          .map((m) => DistractionItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      final List<DistractionItem> deduplicated = [];
      for (final item in rawItems) {
        final isDup = deduplicated.any((d) =>
            d.id == item.id ||
            (d.name.trim().toLowerCase() == item.name.trim().toLowerCase() &&
                d.timestamp.difference(item.timestamp).abs().inSeconds < 15));
        if (!isDup) {
          deduplicated.add(item);
        }
      }

      if (deduplicated.length != rawItems.length) {
        final data = {
          'date': decoded['date'],
          'items': deduplicated.map((i) => i.toJson()).toList(),
        };
        await file.writeAsString(jsonEncode(data), flush: true);
      }

      if (Platform.isAndroid && deduplicated.isNotEmpty) {
        try {
          _platform.invokeMethod('syncTodayDistractions', {
            'items': deduplicated.map((i) => i.toJson()).toList(),
          });
        } catch (_) {}
      }

      return deduplicated;
    } catch (e) {
      debugPrint('Error loading today distractions: $e');
      return [];
    }
  }

  Future<void> recordDistraction(
    String name, {
    String? id,
    DateTime? timestamp,
    String? timeLabel,
    bool notifyNative = true,
  }) async {
    final now = timestamp ?? DateTime.now();
    final effectiveId =
        (id != null && id.isNotEmpty) ? id : '${now.millisecondsSinceEpoch}';
    final effectiveTimeLabel =
        (timeLabel != null && timeLabel.isNotEmpty)
            ? timeLabel
            : _formatTimeLabel(now);

    final cleanName = name.trim().isEmpty ? 'Distraction' : name.trim();

    final current = await loadTodayDistractions();

    final isDup = current.any((c) {
      if (c.id == effectiveId) return true;
      if (c.name.trim().toLowerCase() == cleanName.toLowerCase()) {
        final diff = c.timestamp.difference(now).abs().inSeconds;
        if (diff < 15) return true;
      }
      return false;
    });

    if (isDup) return;

    final newItem = DistractionItem(
      id: effectiveId,
      name: cleanName,
      timestamp: now,
      timeLabel: effectiveTimeLabel,
    );
    current.add(newItem);

    final file = await _storageFile();
    final data = {
      'date': _dateKey(now),
      'items': current.map((i) => i.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(data), flush: true);

    if (notifyNative && Platform.isAndroid) {
      try {
        await _platform.invokeMethod('distractionLogged', newItem.toJson());
      } catch (_) {}
    }

    _notifyListeners();
  }

  Future<void> deleteDistraction(String id) async {
    final current = await loadTodayDistractions();
    current.removeWhere((i) => i.id == id);
    final file = await _storageFile();
    final data = {
      'date': _dateKey(DateTime.now()),
      'items': current.map((i) => i.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(data), flush: true);
    _notifyListeners();
  }

  Future<void> clearToday() async {
    final file = await _storageFile();
    if (await file.exists()) {
      await file.delete();
    }
    _notifyListeners();
  }

  /// Checks if native Android background service wrote any distractions to disk while Flutter was suspended
  Future<void> _syncPendingNativeDistractions() async {
    if (!Platform.isAndroid) return;
    try {
      final res =
          await _platform.invokeMethod<List<dynamic>>('getPendingDistractions');
      if (res != null && res.isNotEmpty) {
        final current = await _loadRawItems();
        var addedAny = false;
        for (final item in res) {
          if (item is Map) {
            final parsed =
                DistractionItem.fromJson(Map<String, dynamic>.from(item));
            final isDup = current.any((c) =>
                c.id == parsed.id ||
                (c.name.trim().toLowerCase() == parsed.name.trim().toLowerCase() &&
                    c.timestamp.difference(parsed.timestamp).abs().inSeconds < 15));
            if (!isDup) {
              current.add(parsed);
              addedAny = true;
            }
          }
        }
        if (addedAny) {
          final file = await _storageFile();
          final data = {
            'date': _dateKey(DateTime.now()),
            'items': current.map((i) => i.toJson()).toList(),
          };
          await file.writeAsString(jsonEncode(data), flush: true);
        }
      }
    } catch (_) {}
  }

  Future<List<DistractionItem>> _loadRawItems() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> && decoded['items'] is List) {
        return (decoded['items'] as List)
            .whereType<Map>()
            .map((m) => DistractionItem.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<String>> getPinnedChips() async {
    if (!Platform.isAndroid) return [];
    try {
      final res = await _platform.invokeMethod<List<dynamic>>('getPinnedChips');
      return res?.map((e) => e.toString()).toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> savePinnedChips(List<String> list) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('savePinnedChips', {'chips': list});
    } catch (_) {}
  }

  Future<List<String>> getRecentChips() async {
    if (!Platform.isAndroid) return [];
    try {
      final res = await _platform.invokeMethod<List<dynamic>>('getRecentChips');
      return res?.map((e) => e.toString()).toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecentChips(List<String> list) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('saveRecentChips', {'chips': list});
    } catch (_) {}
  }

  Future<void> playAlarmSound() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('playAlarmSound');
    } catch (_) {}
  }

  Future<void> stopAlarmSound() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('stopAlarmSound');
    } catch (_) {}
  }

  Future<bool> canPostNotifications() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _platform.invokeMethod<bool>('canPostNotifications');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  Future<void> showAlarmNotification({
    required String title,
    required String timeLabel,
    required int leadMinutes,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('showAlarmNotification', {
        'title': title,
        'timeLabel': timeLabel,
        'leadMinutes': leadMinutes,
      });
    } catch (_) {}
  }

  Future<void> stopAlarmNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('stopAlarmNotification');
    } catch (_) {}
  }

  Future<String?> saveBackupFile({
    required String fileName,
    required String content,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _platform.invokeMethod<String>('saveBackupFile', {
        'fileName': fileName,
        'content': content,
      });
      return res;
    } catch (e) {
      debugPrint('Error saving backup file to DayAura folder: $e');
      return null;
    }
  }
}
