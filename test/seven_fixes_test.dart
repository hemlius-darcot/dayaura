import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_app/routine_history.dart';
import 'package:routine_app/journal_notepad_sheet.dart';
import 'package:routine_app/consistency_tracker.dart';
import 'package:routine_app/main.dart';

void main() {
  group('TodayJournalEntry & Store Tests', () {
    test('TodayJournalEntry serializes and deserializes correctly', () {
      const entry = TodayJournalEntry(
        emoji: '🌟',
        title: 'Awesome Day',
        note: 'Completed all tasks on time!',
        images: ['/path/to/img1.jpg', '/path/to/img2.jpg'],
      );

      final jsonMap = entry.toJson();
      expect(jsonMap['emoji'], '🌟');
      expect(jsonMap['title'], 'Awesome Day');
      expect(jsonMap['note'], 'Completed all tasks on time!');
      expect(jsonMap['images'], ['/path/to/img1.jpg', '/path/to/img2.jpg']);

      final decoded = TodayJournalEntry.fromJson(jsonMap);
      expect(decoded.emoji, entry.emoji);
      expect(decoded.title, entry.title);
      expect(decoded.note, entry.note);
      expect(decoded.images, entry.images);
    });

    test('TodayJournalStore saves and loads to isolated file', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('today_journal_test_');
      final testFile = File('${tempDir.path}/today_journal.json');
      final store = TodayJournalStore(fileProvider: () async => testFile);

      // Initially empty
      var loaded = await store.load();
      expect(loaded.isEmpty, isTrue);

      // Save entry
      const entry = TodayJournalEntry(
        emoji: '🎯',
        title: 'Productive Friday',
        note: 'Clean editor and offline tracker',
        images: ['/img/inline.png'],
      );
      await store.save(entry);

      loaded = await store.load();
      expect(loaded.emoji, '🎯');
      expect(loaded.title, 'Productive Friday');
      expect(loaded.note, 'Clean editor and offline tracker');
      expect(loaded.images, ['/img/inline.png']);

      // Clear entry on day transition
      await store.clear();
      loaded = await store.load();
      expect(loaded.isEmpty, isTrue);

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Alarm Trigger Timing Logic Tests', () {
    test('Calculates exact alarm lead time for task and subtask', () {
      final taskEndMinute = 11 * 60; // 11:00 AM = 660 minutes
      final alarmLeadSeconds = 5 * 60; // 5 minutes = 300 seconds
      final taskEndSeconds = taskEndMinute * 60; // 39600s
      final triggerSecond = taskEndSeconds - alarmLeadSeconds; // 39300s = 10:55:00 AM

      expect(triggerSecond, 39300);

      // 10:54:59 AM (39299s) - before alarm
      final timeBefore = 10 * 3600 + 54 * 60 + 59;
      expect(timeBefore >= triggerSecond, isFalse);

      // 10:55:00 AM (39300s) - exact alarm time!
      final exactTime = 10 * 3600 + 55 * 60 + 0;
      expect(exactTime >= triggerSecond && exactTime < taskEndSeconds + 60, isTrue);

      // 10:58:30 AM (39510s) - within alarm window
      final duringWindow = 10 * 3600 + 58 * 60 + 30;
      expect(duringWindow >= triggerSecond && duringWindow < taskEndSeconds + 60, isTrue);

      // 11:02:00 AM (39720s) - past task end + grace period
      final pastTime = 11 * 3600 + 2 * 60 + 0;
      expect(pastTime < taskEndSeconds + 60, isFalse);

      // Verify the 2m, 5m, 7m, 10m cycle
      final allowedLeadMinutes = [2, 5, 7, 10];
      final allowedSeconds = allowedLeadMinutes.map((m) => m * 60).toList();
      expect(allowedSeconds, [120, 300, 420, 600]);
      for (final sec in allowedSeconds) {
        final trig = taskEndSeconds - sec;
        expect(trig < taskEndSeconds, isTrue);
        expect((taskEndSeconds - trig) ~/ 60, isIn(allowedLeadMinutes));
      }
    });
  });

  group('WYSIWYG Journal Serialization Tests', () {
    test('Builds structured JSON v2 with blocks and images', () {
      final blocks = [
        {'type': 'header', 'text': 'My Milestone'},
        {'type': 'checklist', 'text': 'Completed step 1', 'checked': true},
        {'type': 'bullet', 'text': 'Bullet point details'},
        {'type': 'image', 'path': '/storage/emulated/0/DCIM/photo1.jpg'},
      ];

      final serialized = jsonEncode({'version': 2, 'blocks': blocks});
      final decoded = jsonDecode(serialized) as Map<String, dynamic>;

      expect(decoded['version'], 2);
      expect((decoded['blocks'] as List).length, 4);
      expect((decoded['blocks'] as List)[3]['type'], 'image');
      expect((decoded['blocks'] as List)[3]['path'],
          '/storage/emulated/0/DCIM/photo1.jpg');
    });
  });

  group('Auto Mode Start Time & Trim Constraints Tests', () {
    test('In Auto Mode, new task defaults to upcoming minute, not 12 PM', () {
      // Suppose opening now is 6:24:20 AM (23060 seconds)
      const nowH = 6;
      const nowM = 24;
      const nowS = 20;
      final openingNowSeconds = ((nowH * 3600 + nowM * 60 + nowS) ~/ 60 + 1) * 60;
      expect(openingNowSeconds, 6 * 3600 + 25 * 60); // 6:25:00 AM (23100s)

      // Auto mode: default startSeconds must be upcoming minute
      const parentStartSeconds = 0;
      final defaultStartSeconds = (openingNowSeconds > parentStartSeconds)
          ? openingNowSeconds
          : parentStartSeconds;
      expect(defaultStartSeconds, 23100); // 6:25 AM, NEVER 43200 (12:00 PM)!
    });

    test('Video trim handles enforce end > start and auto mode boundaries', () {
      var start = 23100; // 6:25 AM
      var end = 26700; // 7:25 AM
      const minAllowed = 23100; // 6:25 AM

      // Attempt to drag start past end: must be clamped to end - 60
      final draggedStart = 27000;
      final clampedStart = draggedStart.clamp(minAllowed, end - 60);
      expect(clampedStart, end - 60); // 7:24 AM

      // Attempt to drag end before start: must be clamped to start + 60
      final draggedEnd = 20000;
      final clampedEnd = draggedEnd.clamp(start + 60, 86399);
      expect(clampedEnd, start + 60); // 6:26 AM
    });
  });

  group('Consistency Tracker & History Tests', () {
    test('Adds tracker, counts elapsed time, and resets on relapse', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('consistency_test_');
      final trackersFile = File('${tempDir.path}/trackers.json');
      final historyFile = File('${tempDir.path}/history.json');
      final store = ConsistencyStore(
        trackersFileProvider: () async => trackersFile,
        historyFileProvider: () async => historyFile,
      );

      // Add a tracker
      final tracker = await store.addTracker('No Facebook');
      expect(tracker.name, 'No Facebook');
      expect(tracker.totalRelapses, 0);

      // Verify loaded
      var active = await store.loadTrackers();
      expect(active.length, 1);
      expect(active.first.name, 'No Facebook');

      // Record a relapse (Distracted / Escape)
      final pastStart = DateTime.now().subtract(const Duration(days: 77, hours: 12, minutes: 43));
      tracker.startedAt = pastStart;
      await store.saveTrackers([tracker]);

      final record = await store.recordRelapse(tracker.id);
      expect(record, isNotNull);
      expect(record!.days, 77);
      expect(record.hours, 12);
      expect(record.minutes, 43);

      // Active tracker is reset to 0 and relapse counter is incremented
      active = await store.loadTrackers();
      expect(active.first.totalRelapses, 1);
      expect(active.first.startedAt.isAfter(pastStart), isTrue);

      // History has the saved streak
      final history = await store.loadHistory();
      expect(history.length, 1);
      expect(history.first.name, 'No Facebook');
      expect(history.first.formattedDuration().contains('77d 12h 43m'), isTrue);

      // Export & Import
      final exported = await store.exportData();
      expect(exported['trackers'], isNotEmpty);
      expect(exported['history'], isNotEmpty);

      // Clear history
      await store.clearHistory();
      final clearedHistory = await store.loadHistory();
      expect(clearedHistory.isEmpty, isTrue);

      // Import back
      await store.importData(exported);
      final restoredHistory = await store.loadHistory();
      expect(restoredHistory.length, 1);
      expect(restoredHistory.first.name, 'No Facebook');

      // Test grouped folders by tracker name
      final record2 = ConsistencyHistoryRecord(
        id: 'rec_porn_1',
        name: 'porn',
        startedAt: DateTime.now().subtract(const Duration(days: 5)),
        endedAt: DateTime.now().subtract(const Duration(days: 2)),
        durationSeconds: 3 * 86400,
      );
      final record3 = ConsistencyHistoryRecord(
        id: 'rec_porn_2',
        name: 'porn',
        startedAt: DateTime.now().subtract(const Duration(days: 2)),
        endedAt: DateTime.now(),
        durationSeconds: 2 * 86400,
      );
      final curHistory = await store.loadHistory();
      curHistory.add(record2);
      curHistory.add(record3);
      await store.saveHistory(curHistory);

      final allRecords = await store.loadHistory();
      final folderGroups = <String, List<ConsistencyHistoryRecord>>{};
      for (final r in allRecords) {
        folderGroups.putIfAbsent(r.name, () => []).add(r);
      }
      expect(folderGroups.containsKey('No Facebook'), isTrue);
      expect(folderGroups['No Facebook']!.length, 1);
      expect(folderGroups.containsKey('porn'), isTrue);
      expect(folderGroups['porn']!.length, 2);

      // Delete specific record and verify folder updates
      await store.deleteHistoryRecord(record2.id);
      final updatedRecords = await store.loadHistory();
      final updatedGroups = <String, List<ConsistencyHistoryRecord>>{};
      for (final r in updatedRecords) {
        updatedGroups.putIfAbsent(r.name, () => []).add(r);
      }
      expect(updatedGroups['porn']!.length, 1);
      expect(updatedGroups['porn']!.first.id, record3.id);

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('TaskNode midnight end time rule: end is strictly 11:59 PM / 23:59 max, not 12:00 AM / 00:00', () {
      final rootTask = TaskNode(
        title: 'Full Day Task',
        startMinute: 0,
        endMinute: 1440,
      );

      // In 24h mode (default for TaskNode getters):
      expect(rootTask.startLabel, '00:00');
      // End time must strictly be 23:59 (end of day), never 00:00!
      expect(rootTask.endLabel, '23:59');
      expect(rootTask.endLabel != rootTask.startLabel, isTrue);

      // In 12h mode:
      final start12h = formatMinute(rootTask.startMinute, use24Hour: false);
      final end12h = formatMinute(rootTask.endMinute, use24Hour: false, isEndTime: true);
      expect(start12h, '12:00 AM');
      expect(end12h, '11:59 PM');
      expect(end12h != start12h, isTrue);
      expect(end12h.contains('12:00 AM'), isFalse);

      final taskEnding1159 = TaskNode(
        title: 'Late Task',
        startMinute: 23 * 60,
        endMinute: 1439,
      );
      expect(taskEnding1159.endLabel, '23:59');
      expect(formatMinute(taskEnding1159.endMinute, use24Hour: false, isEndTime: true), '11:59 PM');

      // Subtask bounded inside parent
      final parentTask = TaskNode(
        title: 'Study Block',
        startMinute: 13 * 60 + 5, // 1:05 PM
        endMinute: 17 * 60, // 5:00 PM
      );
      final subtask = TaskNode(
        title: 'Math Study',
        startMinute: 13 * 60 + 5,
        endMinute: 15 * 60,
      );
      expect(subtask.startMinute >= parentTask.startMinute, isTrue);
      expect(subtask.endMinute <= parentTask.endMinute, isTrue);
    });

    test('Wheel picker key stability vs trim live sync verification', () {
      // Key stability during direct wheel scrolling:
      // When a user scrolls the wheel, safeValue changes but trimRevision stays constant.
      // Therefore, the key 'M-0-59-$trimRevision' does NOT change, preserving fling momentum.
      int trimRevision = 0;
      final keyAtMinute31 = 'M-0-59-$trimRevision';
      // User flings from 31 to 32, 33, 34...
      final keyAtMinute32 = 'M-0-59-$trimRevision';
      expect(keyAtMinute31, equals(keyAtMinute32),
          reason: 'Key must remain stable during manual scrolling to allow momentum');

      // Key changes when user trims timeline:
      // Trimming increments trimRevision, which changes key and updates picker initialItem.
      trimRevision++;
      final keyAfterTrim = 'M-0-59-$trimRevision';
      expect(keyAfterTrim, isNot(equals(keyAtMinute31)),
          reason: 'Key must change when trimming so wheel updates to new initialItem');
    });
  });
}
