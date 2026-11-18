import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Single active tracker (e.g., "Facebook", "Alcohol", etc.)
class ConsistencyTracker {
  ConsistencyTracker({
    required this.id,
    required this.name,
    required this.startedAt,
    this.totalRelapses = 0,
  });

  final String id;
  String name;
  DateTime startedAt;
  int totalRelapses;

  Duration elapsed(DateTime now) {
    if (now.isBefore(startedAt)) return Duration.zero;
    return now.difference(startedAt);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startedAt': startedAt.toIso8601String(),
    'totalRelapses': totalRelapses,
  };

  factory ConsistencyTracker.fromJson(Map<String, dynamic> json) =>
      ConsistencyTracker(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Tracker',
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        totalRelapses: (json['totalRelapses'] as num?)?.toInt() ?? 0,
      );
}

/// Past streak record saved when user taps "Distracted / Escape"
class ConsistencyHistoryRecord {
  ConsistencyHistoryRecord({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;

  int get days => durationSeconds ~/ 86400;
  int get hours => (durationSeconds % 86400) ~/ 3600;
  int get minutes => (durationSeconds % 3600) ~/ 60;
  int get seconds => durationSeconds % 60;

  String formattedDuration() {
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    parts.add('${minutes}m');
    parts.add('${seconds}s');
    return parts.join(' ');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'durationSeconds': durationSeconds,
  };

  factory ConsistencyHistoryRecord.fromJson(Map<String, dynamic> json) =>
      ConsistencyHistoryRecord(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Tracker',
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        endedAt: DateTime.tryParse(json['endedAt'] as String? ?? '') ??
            DateTime.now(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      );
}

/// Local persistence store for consistency trackers and history records
class ConsistencyStore {
  ConsistencyStore({
    Future<File> Function()? trackersFileProvider,
    Future<File> Function()? historyFileProvider,
  })  : _trackersFileProvider = trackersFileProvider,
        _historyFileProvider = historyFileProvider;

  final Future<File> Function()? _trackersFileProvider;
  final Future<File> Function()? _historyFileProvider;

  Future<File> _trackersFile() async {
    final provider = _trackersFileProvider;
    if (provider != null) return provider();
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/consistency_trackers.json');
  }

  Future<File> _historyFile() async {
    final provider = _historyFileProvider;
    if (provider != null) return provider();
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/consistency_history.json');
  }

  Future<List<ConsistencyTracker>> loadTrackers() async {
    try {
      final f = await _trackersFile();
      if (!await f.exists()) return <ConsistencyTracker>[];
      final text = await f.readAsString();
      if (text.trim().isEmpty) return <ConsistencyTracker>[];
      final decoded = jsonDecode(text);
      if (decoded is! List) return <ConsistencyTracker>[];
      return decoded
          .whereType<Map>()
          .map((m) =>
              ConsistencyTracker.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('Could not load consistency trackers: $e');
      return <ConsistencyTracker>[];
    }
  }

  Future<void> saveTrackers(List<ConsistencyTracker> list) async {
    try {
      final f = await _trackersFile();
      final data = list.map((t) => t.toJson()).toList();
      await f.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Could not save consistency trackers: $e');
    }
  }

  Future<ConsistencyTracker> addTracker(String name) async {
    final list = await loadTrackers();
    final tracker = ConsistencyTracker(
      id: '${DateTime.now().millisecondsSinceEpoch}_${name.hashCode}',
      name: name.trim(),
      startedAt: DateTime.now(),
      totalRelapses: 0,
    );
    list.add(tracker);
    await saveTrackers(list);
    return tracker;
  }

  Future<void> deleteTracker(String id) async {
    final list = await loadTrackers();
    list.removeWhere((t) => t.id == id);
    await saveTrackers(list);
  }

  /// User was distracted or escaped: saves completed streak into history and resets streak to zero
  Future<ConsistencyHistoryRecord?> recordRelapse(String id) async {
    final list = await loadTrackers();
    final index = list.indexWhere((t) => t.id == id);
    if (index == -1) return null;

    final tracker = list[index];
    final now = DateTime.now();
    final durationSeconds = mathMax(1, now.difference(tracker.startedAt).inSeconds);

    final record = ConsistencyHistoryRecord(
      id: '${now.millisecondsSinceEpoch}_${tracker.id}',
      name: tracker.name,
      startedAt: tracker.startedAt,
      endedAt: now,
      durationSeconds: durationSeconds,
    );

    // Save into history
    final history = await loadHistory();
    history.insert(0, record);
    await saveHistory(history);

    // Reset tracker counter to 0 (now) and increment relapse count
    tracker.startedAt = now;
    tracker.totalRelapses += 1;
    await saveTrackers(list);

    return record;
  }

  Future<List<ConsistencyHistoryRecord>> loadHistory() async {
    try {
      final f = await _historyFile();
      if (!await f.exists()) return <ConsistencyHistoryRecord>[];
      final text = await f.readAsString();
      if (text.trim().isEmpty) return <ConsistencyHistoryRecord>[];
      final decoded = jsonDecode(text);
      if (decoded is! List) return <ConsistencyHistoryRecord>[];
      return decoded
          .whereType<Map>()
          .map((m) => ConsistencyHistoryRecord.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('Could not load consistency history: $e');
      return <ConsistencyHistoryRecord>[];
    }
  }

  Future<void> saveHistory(List<ConsistencyHistoryRecord> list) async {
    try {
      final f = await _historyFile();
      final data = list.map((r) => r.toJson()).toList();
      await f.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Could not save consistency history: $e');
    }
  }

  Future<void> deleteHistoryRecord(String recordId) async {
    final list = await loadHistory();
    list.removeWhere((r) => r.id == recordId);
    await saveHistory(list);
  }

  Future<void> clearHistory() async {
    try {
      final f = await _historyFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> exportData() async {
    final trackers = await loadTrackers();
    final history = await loadHistory();
    return {
      'trackers': trackers.map((t) => t.toJson()).toList(),
      'history': history.map((r) => r.toJson()).toList(),
    };
  }

  Future<void> importData(Map<String, dynamic> data) async {
    try {
      if (data['trackers'] is List) {
        final existing = await loadTrackers();
        final importedTrackers = (data['trackers'] as List)
            .whereType<Map>()
            .map((m) =>
                ConsistencyTracker.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        for (final item in importedTrackers) {
          final idx = existing.indexWhere((e) => e.id == item.id);
          if (idx >= 0) {
            existing[idx] = item;
          } else {
            existing.add(item);
          }
        }
        await saveTrackers(existing);
      }

      if (data['history'] is List) {
        final existing = await loadHistory();
        final importedRecords = (data['history'] as List)
            .whereType<Map>()
            .map((m) => ConsistencyHistoryRecord.fromJson(
                Map<String, dynamic>.from(m)))
            .toList();
        for (final item in importedRecords) {
          if (!existing.any((e) => e.id == item.id)) {
            existing.add(item);
          }
        }
        existing.sort((a, b) => b.endedAt.compareTo(a.endedAt));
        await saveHistory(existing);
      }
    } catch (e) {
      debugPrint('Error importing consistency data: $e');
    }
  }
}

int mathMax(int a, int b) => a > b ? a : b;

/// Main UI Screen for Consistency Track
class ConsistencyTrackScreen extends StatefulWidget {
  const ConsistencyTrackScreen({super.key});

  @override
  State<ConsistencyTrackScreen> createState() =>
      _ConsistencyTrackScreenState();
}

class _ConsistencyTrackScreenState extends State<ConsistencyTrackScreen> {
  final ConsistencyStore _store = ConsistencyStore();
  List<ConsistencyTracker> _trackers = <ConsistencyTracker>[];
  bool _loading = true;
  Timer? _liveTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _store.loadTrackers();
    if (mounted) {
      setState(() {
        _trackers = list;
        _loading = false;
      });
    }
  }

  Future<void> _promptAddTracker() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Consistency Tracker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Habit or target you want to stay consistent with (e.g. No Facebook, Quit Alcohol, Daily Gym):',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Tracker name...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Start Tracking'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _store.addTracker(result);
      _load();
    }
  }

  Future<void> _handleDistracted(ConsistencyTracker tracker) async {
    final elapsed = tracker.elapsed(_now);
    final days = elapsed.inDays;
    final hours = elapsed.inHours % 24;
    final minutes = elapsed.inMinutes % 60;
    final seconds = elapsed.inSeconds % 60;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Distracted / Escape?'),
          ],
        ),
        content: Text(
          'Target: "${tracker.name}"\n'
          'Current Streak: ${days}d ${hours}h ${minutes}m ${seconds}s.\n\n'
          'Ei streak-ti History-te save hobe ebong counter 0 theke notun kore shuru hobe. Apni ki nishchit?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Distracted'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final record = await _store.recordRelapse(tracker.id);
      _load();
      if (mounted && record != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Streak saved (${record.formattedDuration()})! New streak started from 0.',
            ),
            backgroundColor: const Color(0xFF20B77A),
          ),
        );
      }
    }
  }

  Future<void> _deleteTracker(ConsistencyTracker tracker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Tracker?'),
        content: Text('Remove "${tracker.name}" permanently from active trackers?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _store.deleteTracker(tracker.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consistency Track'),
        actions: [
          IconButton(
            tooltip: 'Consistency History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ConsistencyHistoryScreen(),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _promptAddTracker,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Tracker'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trackers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.radar_rounded,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Consistency Trackers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Track habits or addictions you want to avoid (e.g. Facebook, Alcohol, TikTok).\n'
                          'Tap + to start counting days, hours, and minutes continuously.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                  itemCount: _trackers.length,
                  itemBuilder: (ctx, i) {
                    final tracker = _trackers[i];
                    final elapsed = tracker.elapsed(_now);
                    final days = elapsed.inDays;
                    final hours = elapsed.inHours % 24;
                    final minutes = elapsed.inMinutes % 60;
                    final seconds = elapsed.inSeconds % 60;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    tracker.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (tracker.totalRelapses > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Streak #${tracker.totalRelapses + 1}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 20),
                                  color: Colors.grey,
                                  onPressed: () => _deleteTracker(tracker),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Live Counter Boxes
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _counterBox('Days', days.toString()),
                                _counterDivider(),
                                _counterBox('Hours', hours.toString().padLeft(2, '0')),
                                _counterDivider(),
                                _counterBox('Mins', minutes.toString().padLeft(2, '0')),
                                _counterDivider(),
                                _counterBox('Secs', seconds.toString().padLeft(2, '0')),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Started: ${_formatDate(tracker.startedAt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 36,
                              child: FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.orange.withValues(alpha: 0.15),
                                  foregroundColor: Colors.orange.shade900,
                                ),
                                onPressed: () => _handleDistracted(tracker),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.report_problem_rounded, size: 16),
                                    SizedBox(width: 6),
                                    Text(
                                      'Distracted / Escape',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _counterBox(String label, String value) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF20B77A).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF20B77A).withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF20B77A),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _counterDivider() => const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text(':', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );

  String _formatDate(DateTime dt) {
    final m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][dt.month - 1];
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $m ${dt.year}, $h12:$min $ampm';
  }
}

/// Screen showing past saved streaks
class ConsistencyHistoryScreen extends StatefulWidget {
  const ConsistencyHistoryScreen({super.key});

  @override
  State<ConsistencyHistoryScreen> createState() =>
      _ConsistencyHistoryScreenState();
}

class _ConsistencyHistoryScreenState extends State<ConsistencyHistoryScreen> {
  final ConsistencyStore _store = ConsistencyStore();
  List<ConsistencyHistoryRecord> _records = <ConsistencyHistoryRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.loadHistory();
    if (mounted) {
      setState(() {
        _records = list;
        _loading = false;
      });
    }
  }

  Future<void> _deleteRecord(ConsistencyHistoryRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Streak Record?'),
        content: Text(
          'Delete streak of ${record.formattedDuration()} for "${record.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _store.deleteHistoryRecord(record.id);
      _load();
    }
  }

  Future<void> _deleteFolder(
    String folderName,
    List<ConsistencyHistoryRecord> folderRecords,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Folder "$folderName"?'),
        content: Text(
          'Delete all ${folderRecords.length} streak history records in this folder?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Folder'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final r in folderRecords) {
        await _store.deleteHistoryRecord(r.id);
      }
      _load();
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Consistency History?'),
        content: const Text('Delete all saved streaks? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _store.clearHistory();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consistency History'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              tooltip: 'Clear All',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Consistency History',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When you tap "Distracted / Escape" on any active tracker, your streak will be saved here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final groups = <String, List<ConsistencyHistoryRecord>>{};
                    for (final r in _records) {
                      groups.putIfAbsent(r.name, () => <ConsistencyHistoryRecord>[]).add(r);
                    }
                    final folderNames = groups.keys.toList();

                    return ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: folderNames.length,
                      itemBuilder: (ctx, i) {
                        final folderName = folderNames[i];
                        final recordsInFolder = groups[folderName]!;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            initiallyExpanded: folderNames.length == 1,
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF20B77A).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.folder_rounded,
                                color: Color(0xFF20B77A),
                                size: 24,
                              ),
                            ),
                            title: Text(
                              folderName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              '${recordsInFolder.length} ${recordsInFolder.length == 1 ? 'streak record' : 'streak records'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                  tooltip: 'Delete folder',
                                  onPressed: () => _deleteFolder(
                                    folderName,
                                    recordsInFolder,
                                  ),
                                ),
                                const Icon(Icons.expand_more_rounded),
                              ],
                            ),
                            children: [
                              ...recordsInFolder.map((r) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withValues(alpha: 0.15),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.history_rounded,
                                      color: Color(0xFF20B77A),
                                      size: 20,
                                    ),
                                    title: Text(
                                      'Streak: ${r.formattedDuration()}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: Color(0xFF20B77A),
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_fmt(r.startedAt)} → ${_fmt(r.endedAt)}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                      tooltip: 'Delete record',
                                      onPressed: () => _deleteRecord(r),
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 8),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }

  String _fmt(DateTime dt) {
    final m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][dt.month - 1];
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $m, $h12:$min $ampm';
  }
}
