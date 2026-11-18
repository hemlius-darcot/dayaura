import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_app/routine_history.dart';

class TimeInterval {
  const TimeInterval(this.startSeconds, this.endSeconds);
  final int startSeconds;
  final int endSeconds;
}

int activeElapsedSeconds(List<TimeInterval> intervals, int elapsedSeconds) {
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

void main() {
  group('Phase A: Routine History & Path 2 Snapshot Tests', () {
    test('RoutineDayRecord preserves task snapshot (Path 2)', () {
      final sampleTasks = [
        {
          'title': 'Flutter Coding',
          'startMinute': 540, // 09:00
          'endMinute': 660, // 11:00
          'done': true,
          'children': [
            {
              'title': 'Build UI',
              'startMinute': 540,
              'endMinute': 600,
              'done': true,
              'children': [],
            }
          ],
        },
        {
          'title': 'Lunch Break',
          'startMinute': 720, // 12:00
          'endMinute': 780, // 13:00
          'done': false,
          'children': [],
        }
      ];

      final original = RoutineDayRecord(
        date: DateTime(2026, 10, 28),
        progress: 75.5,
        mode: 'Auto',
        tasks: sampleTasks,
        emoji: '🎓',
        memoryTitle: 'Physics Exam Day',
        memoryNote: '# Great Day\nScored high marks and had fun!',
        memoryImages: ['/storage/img1.jpg', '/storage/img2.jpg'],
        distractions: [
          {'id': 'd1', 'name': 'Facebook', 'timeLabel': '11:30 AM'},
          {'id': 'd2', 'name': 'TikTok', 'timeLabel': '04:15 PM'},
        ],
      );

      final json = original.toJson();
      final restored = RoutineDayRecord.fromJson(json);

      expect(restored.dateKey, '2026-10-28');
      expect(restored.progress, 75.5);
      expect(restored.mode, 'Auto');
      expect(restored.tasks, isNotNull);
      expect(restored.tasks!.length, 2);
      expect(restored.tasks![0]['title'], 'Flutter Coding');
      expect(restored.tasks![0]['done'], true);
      expect((restored.tasks![0]['children'] as List).length, 1);
      expect(restored.tasks![1]['title'], 'Lunch Break');
      expect(restored.tasks![1]['done'], false);

      // Verify Memorable Day Journal fields
      expect(restored.hasMemorableNote, isTrue);
      expect(restored.emoji, '🎓');
      expect(restored.memoryTitle, 'Physics Exam Day');
      expect(restored.memoryNote, contains('Great Day'));
      expect(restored.memoryImages, isNotNull);
      expect(restored.memoryImages!.length, 2);
      expect(restored.memoryImages![0], '/storage/img1.jpg');

      // Verify Distractions
      expect(restored.distractions, isNotNull);
      expect(restored.distractions!.length, 2);
      expect(restored.distractions![0]['name'], 'Facebook');
      expect(restored.distractions![1]['name'], 'TikTok');
    });

    test('RoutineDayRecord handles empty or null tasks for missed days (0% Red)', () {
      final missedDay = RoutineDayRecord(
        date: DateTime(2026, 10, 27),
        progress: 0.0,
        mode: 'Manual',
        tasks: null,
      );

      final json = missedDay.toJson();
      expect(json.containsKey('tasks'), isFalse);

      final restored = RoutineDayRecord.fromJson(json);
      expect(restored.dateKey, '2026-10-27');
      expect(restored.progress, 0.0);
      expect(restored.mode, 'Manual');
      expect(restored.tasks, isNull);
    });

    test('Overlapping intervals merge correctly without double counting', () {
      // Interval 1: 08:00 - 10:00 (28800s - 36000s) = 2 hours
      // Interval 2: 09:00 - 11:00 (32400s - 39600s) = 2 hours
      // Overlap: 09:00 - 10:00. Union should be 08:00 - 11:00 = 3 hours (10800s), NOT 4 hours!
      final intervals = [
        const TimeInterval(28800, 36000),
        const TimeInterval(32400, 39600),
      ];
      final unionSeconds = activeElapsedSeconds(intervals, 86400);
      expect(unionSeconds, 10800); // exactly 3 hours

      // Progress formula: union_seconds / 86400 * 100
      final progress = unionSeconds / 86400 * 100;
      expect(progress, 12.5); // 3 hours = 12.5% of 24h
    });
  });

  group('Phase B: Export & Import Validation Tests', () {
    test('validateImportData accepts valid export JSON and orders by date', () {
      final store = RoutineHistoryStore();
      final validJson = jsonEncode({
        'app': 'RoutineTracker',
        'exportVersion': 1,
        'records': [
          {'date': '2026-10-29', 'progress': 80.0, 'mode': 'Auto'},
          {'date': '2026-10-27', 'progress': 50.0, 'mode': 'Manual'},
          {
            'date': '2026-10-28',
            'progress': 65.0,
            'mode': 'Auto',
            'tasks': [
              {
                'title': 'Test Task',
                'startMinute': 600,
                'endMinute': 700,
                'done': true,
              }
            ]
          },
        ]
      });

      final records = store.validateImportData(validJson);
      expect(records, isNotNull);
      expect(records!.length, 3);
      // Verify sorted by date
      expect(records[0].dateKey, '2026-10-27');
      expect(records[1].dateKey, '2026-10-28');
      expect(records[2].dateKey, '2026-10-29');
      expect(records[1].tasks, isNotNull);
      expect(records[1].tasks!.first['title'], 'Test Task');
    });

    test('validateImportData rejects malformed or invalid JSON', () {
      final store = RoutineHistoryStore();
      expect(store.validateImportData('not valid json'), isNull);
      expect(store.validateImportData('{}'), isNull);
      expect(store.validateImportData('{"records": "not a list"}'), isNull);
      expect(
        store.validateImportData(
          '{"records": [{"invalid": "no date or progress"}]}',
        ),
        isNull,
      );
    });
  });
}
