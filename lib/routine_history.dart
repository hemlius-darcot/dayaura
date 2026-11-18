import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RoutineDayRecord {
  const RoutineDayRecord({
    required this.date,
    required this.progress,
    required this.mode,
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

  String get dateKey =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool get hasMemorableNote =>
      (emoji != null && emoji!.trim().isNotEmpty) ||
      (memoryTitle != null && memoryTitle!.trim().isNotEmpty) ||
      (memoryNote != null && memoryNote!.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
    'date': dateKey,
    'progress': progress,
    'mode': mode,
    if (tasks != null) 'tasks': tasks,
    if (emoji != null && emoji!.isNotEmpty) 'emoji': emoji,
    if (memoryTitle != null && memoryTitle!.isNotEmpty) 'memoryTitle': memoryTitle,
    if (memoryNote != null && memoryNote!.isNotEmpty) 'memoryNote': memoryNote,
    if (memoryImages != null && memoryImages!.isNotEmpty) 'memoryImages': memoryImages,
    if (distractions != null && distractions!.isNotEmpty) 'distractions': distractions,
  };

  RoutineDayRecord copyWith({
    DateTime? date,
    double? progress,
    String? mode,
    List<Map<String, dynamic>>? tasks,
    String? emoji,
    String? memoryTitle,
    String? memoryNote,
    List<String>? memoryImages,
    List<Map<String, dynamic>>? distractions,
  }) {
    return RoutineDayRecord(
      date: date ?? this.date,
      progress: progress ?? this.progress,
      mode: mode ?? this.mode,
      tasks: tasks ?? this.tasks,
      emoji: emoji ?? this.emoji,
      memoryTitle: memoryTitle ?? this.memoryTitle,
      memoryNote: memoryNote ?? this.memoryNote,
      memoryImages: memoryImages ?? this.memoryImages,
      distractions: distractions ?? this.distractions,
    );
  }

  factory RoutineDayRecord.fromJson(Map<String, dynamic> json) {
    final parsedDate = DateTime.parse(json['date'] as String);
    final rawProgress = (json['progress'] as num).toDouble();
    final rawTasks = json['tasks'];
    List<Map<String, dynamic>>? taskSnapshots;
    if (rawTasks is List) {
      taskSnapshots = rawTasks
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final rawImages = json['memoryImages'];
    List<String>? parsedImages;
    if (rawImages is List) {
      parsedImages = rawImages.map((e) => e.toString()).toList();
    }

    final rawDistractions = json['distractions'];
    List<Map<String, dynamic>>? parsedDistractions;
    if (rawDistractions is List) {
      final list = rawDistractions
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final List<Map<String, dynamic>> deduped = [];
      for (final item in list) {
        final id = item['id']?.toString() ?? '';
        final name = (item['name']?.toString() ?? '').trim().toLowerCase();
        final tsStr = item['timestamp']?.toString() ?? '';
        final ts = DateTime.tryParse(tsStr);
        final isDup = deduped.any((existing) {
          if (id.isNotEmpty && existing['id']?.toString() == id) return true;
          if (name.isNotEmpty &&
              (existing['name']?.toString() ?? '').trim().toLowerCase() == name) {
            final exTsStr = existing['timestamp']?.toString() ?? '';
            final exTs = DateTime.tryParse(exTsStr);
            if (ts != null && exTs != null) {
              if (exTs.difference(ts).abs().inSeconds < 15) return true;
            } else if (existing['timeLabel'] == item['timeLabel']) {
              return true;
            }
          }
          return false;
        });
        if (!isDup) deduped.add(item);
      }
      parsedDistractions = deduped;
    }

    return RoutineDayRecord(
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      progress: rawProgress.clamp(0.0, 100.0).toDouble(),
      mode: json['mode'] as String? ?? 'Auto',
      tasks: taskSnapshots,
      emoji: json['emoji'] as String?,
      memoryTitle: json['memoryTitle'] as String?,
      memoryNote: json['memoryNote'] as String?,
      memoryImages: parsedImages,
      distractions: parsedDistractions,
    );
  }
}

class RoutineHistoryStore {
  Future<File> _historyFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/routine_history.json');
  }

  Future<List<RoutineDayRecord>> load() async {
    final file = await _historyFile();
    if (!await file.exists()) return <RoutineDayRecord>[];

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return <RoutineDayRecord>[];

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> || decoded['records'] is! List) {
        return <RoutineDayRecord>[];
      }

      final records = <RoutineDayRecord>[];
      for (final item in decoded['records'] as List) {
        if (item is Map) {
          try {
            records.add(
              RoutineDayRecord.fromJson(Map<String, dynamic>.from(item)),
            );
          } catch (_) {
            // Ignore an invalid individual record without discarding the rest.
          }
        }
      }

      records.sort((a, b) => a.date.compareTo(b.date));
      return records;
    } catch (_) {
      return <RoutineDayRecord>[];
    }
  }

  /// Atomically writes records to routine_history.json via a temporary file.
  Future<void> _writeAtomic(List<RoutineDayRecord> records) async {
    records.sort((a, b) => a.date.compareTo(b.date));

    final targetFile = await _historyFile();
    final tempFile = File('${targetFile.path}.tmp');

    final jsonPayload = jsonEncode({
      'version': 2,
      'records': records.map((item) => item.toJson()).toList(),
    });

    await tempFile.writeAsString(jsonPayload, flush: true);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tempFile.rename(targetFile.path);
  }

  Future<void> save(RoutineDayRecord record) async {
    final records = await load();
    final index = records.indexWhere((item) => item.dateKey == record.dateKey);

    if (index == -1) {
      records.add(record);
    } else {
      final old = records[index];
      records[index] = RoutineDayRecord(
        date: record.date,
        progress: record.progress,
        mode: record.mode,
        tasks: record.tasks ?? old.tasks,
        emoji: record.emoji ?? old.emoji,
        memoryTitle: record.memoryTitle ?? old.memoryTitle,
        memoryNote: record.memoryNote ?? old.memoryNote,
        memoryImages: record.memoryImages ?? old.memoryImages,
        distractions: record.distractions ?? old.distractions,
      );
    }

    await _writeAtomic(records);
  }

  Future<void> saveMultiple(List<RoutineDayRecord> newRecords) async {
    if (newRecords.isEmpty) return;
    final records = await load();

    for (final newRecord in newRecords) {
      final index = records.indexWhere((item) => item.dateKey == newRecord.dateKey);
      if (index == -1) {
        records.add(newRecord);
      } else {
        final old = records[index];
        records[index] = RoutineDayRecord(
          date: newRecord.date,
          progress: newRecord.progress,
          mode: newRecord.mode,
          tasks: newRecord.tasks ?? old.tasks,
          emoji: newRecord.emoji ?? old.emoji,
          memoryTitle: newRecord.memoryTitle ?? old.memoryTitle,
          memoryNote: newRecord.memoryNote ?? old.memoryNote,
          memoryImages: newRecord.memoryImages ?? old.memoryImages,
          distractions: newRecord.distractions ?? old.distractions,
        );
      }
    }

    await _writeAtomic(records);
  }

  /// Exports all saved history into a clean JSON file in the temporary directory
  /// ready for sharing via share_plus. Optional favorite templates can be included.
  Future<File> exportToFile({
    List<Map<String, dynamic>>? favoriteTemplates,
    Map<String, dynamic>? consistencyData,
  }) async {
    final records = await load();
    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    final timestamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    final exportFile =
        File('${tempDir.path}/routine_history_backup_$timestamp.json');

    final payload = jsonEncode({
      'app': 'RoutineTracker',
      'exportVersion': 2,
      'exportedAt': now.toIso8601String(),
      'recordCount': records.length,
      'records': records.map((item) => item.toJson()).toList(),
      if (favoriteTemplates != null && favoriteTemplates.isNotEmpty)
        'favorites': favoriteTemplates,
      if (consistencyData != null && consistencyData.isNotEmpty)
        'consistency': consistencyData,
    });

    await exportFile.writeAsString(payload, flush: true);
    return exportFile;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Validates an import JSON string and returns parsed records if valid,
  /// or null if the schema is malformed or invalid.
  List<RoutineDayRecord>? validateImportData(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic> || decoded['records'] is! List) {
        return null;
      }

      final records = <RoutineDayRecord>[];
      for (final item in decoded['records'] as List) {
        if (item is Map) {
          try {
            records.add(
              RoutineDayRecord.fromJson(Map<String, dynamic>.from(item)),
            );
          } catch (_) {
            return null; // Malformed record
          }
        } else {
          return null;
        }
      }

      records.sort((a, b) => a.date.compareTo(b.date));
      return records;
    } catch (_) {
      return null;
    }
  }

  /// Replaces current history with imported records.
  /// Automatically creates an internal safety backup before replacement.
  Future<void> importHistory(List<RoutineDayRecord> importedRecords) async {
    final currentFile = await _historyFile();
    if (await currentFile.exists()) {
      final dir = await getApplicationDocumentsDirectory();
      final safetyBackup =
          File('${dir.path}/routine_history_pre_import_backup.json');
      await currentFile.copy(safetyBackup.path);
    }

    await _writeAtomic(importedRecords);
  }
}

class TodayJournalEntry {
  const TodayJournalEntry({
    this.emoji,
    this.title,
    this.note,
    this.images = const [],
  });

  final String? emoji;
  final String? title;
  final String? note;
  final List<String> images;

  bool get hasContent =>
      (emoji != null && emoji!.trim().isNotEmpty) ||
      (title != null && title!.trim().isNotEmpty) ||
      (note != null && note!.trim().isNotEmpty) ||
      images.isNotEmpty;

  bool get isEmpty => !hasContent;

  Map<String, dynamic> toJson() => {
    if (emoji != null && emoji!.isNotEmpty) 'emoji': emoji,
    if (title != null && title!.isNotEmpty) 'title': title,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (images.isNotEmpty) 'images': images,
  };

  factory TodayJournalEntry.fromJson(Map<String, dynamic> json) =>
      TodayJournalEntry(
        emoji: json['emoji'] as String?,
        title: json['title'] as String?,
        note: json['note'] as String?,
        images: (json['images'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

class TodayJournalStore {
  TodayJournalStore({Future<File> Function()? fileProvider})
      : _fileProvider = fileProvider;

  final Future<File> Function()? _fileProvider;

  Future<File> _file() async {
    final provider = _fileProvider;
    if (provider != null) return provider();
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/today_journal.json');
  }

  Future<TodayJournalEntry> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const TodayJournalEntry();
      final text = await f.readAsString();
      if (text.trim().isEmpty) return const TodayJournalEntry();
      final map = jsonDecode(text) as Map<String, dynamic>;
      return TodayJournalEntry.fromJson(map);
    } catch (_) {
      return const TodayJournalEntry();
    }
  }

  Future<void> save(TodayJournalEntry entry) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(entry.toJson()), flush: true);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

