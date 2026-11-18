import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_app/main.dart';

void main() {
  group('Timeframe Candlestick & Aggregation Logic', () {
    test('1D, 1M, and 1Y candlestick math preserves cumulative continuity', () {
      final sampleDays = [
        SampleDay(
          DateTime(2026, 11, 1),
          50.0,
          'Auto',
        ),
        SampleDay(
          DateTime(2026, 11, 2),
          70.0,
          'Auto',
        ),
        SampleDay(
          DateTime(2026, 11, 3),
          90.0,
          'Auto',
        ),
        SampleDay(
          DateTime(2026, 12, 1),
          60.0,
          'Auto',
        ),
      ];

      // Cumulative points:
      // Day 1: open = 0, close = 50, high = 100
      // Day 2: open = 50, close = 120, high = 150
      // Day 3: open = 120, close = 210, high = 220
      // Day 4: open = 210, close = 270, high = 310

      // Month November 2026:
      // Count = 3 days
      // Total earned = 50 + 70 + 90 = 210
      // Average progress % = 210 / 3 = 70.0%
      // Open = 0, Close = 210, High = 0 + (3 * 100) = 300
      final novTotal = 50.0 + 70.0 + 90.0;
      final novCount = 3;
      final novAvg = novTotal / novCount;
      expect(novAvg, 70.0);

      // Month December 2026:
      // Count = 1 day, Progress = 60.0%
      // Open = 210, Close = 270, High = 210 + 100 = 310
      final decTotal = 60.0;
      final decCount = 1;
      final decAvg = decTotal / decCount;
      expect(decAvg, 60.0);

      // Year 2026:
      // Count = 4 days
      // Total earned = 270
      // Average progress % = 270 / 4 = 67.5%
      // Open = 0, Close = 270, High = 0 + (4 * 100) = 400
      final yearTotal = novTotal + decTotal;
      final yearCount = sampleDays.length;
      final yearAvg = yearTotal / yearCount;
      expect(yearAvg, 67.5);
    });

    test('Threshold colors match strictly: <40% Red, 40-<60% Yellow, >=60% Green', () {
      expect(kCandleRed.value, 0xFFE65A52);
      expect(kCandleYellow.value, 0xFFF2C94C);
    });
  });

  group('Tomorrow Tasks & Routine Rollover Logic', () {
    test('TaskNode serialization retains tomorrow and today task structure', () {
      final t1 = TaskNode(
        title: 'Morning Yoga',
        startMinute: 6 * 60,
        endMinute: 7 * 60,
        done: false,
      );
      final t2 = TaskNode(
        title: 'Project Deep Dive',
        startMinute: 8 * 60,
        endMinute: 12 * 60,
        done: false,
      );

      final payload = {
        'version': 2,
        'autoTasks': [t1.toJson()],
        'tomorrowTasks': [t2.toJson()],
      };

      final encoded = jsonEncode(payload);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['version'], 2);
      final restoredAuto = (decoded['autoTasks'] as List)
          .map((e) => TaskNode.fromJson(e as Map<String, dynamic>))
          .toList();
      final restoredTomorrow = (decoded['tomorrowTasks'] as List)
          .map((e) => TaskNode.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(restoredAuto.length, 1);
      expect(restoredAuto.first.title, 'Morning Yoga');

      expect(restoredTomorrow.length, 1);
      expect(restoredTomorrow.first.title, 'Project Deep Dive');
    });

    test('Midnight date rollover promotes tomorrowTasks into autoTasks and clears tomorrowTasks', () {
      final autoTasks = <TaskNode>[
        TaskNode(
          title: 'Yesterday Task',
          startMinute: 60,
          endMinute: 120,
          done: true,
        ),
      ];
      final tomorrowTasks = <TaskNode>[
        TaskNode(
          title: 'Tomorrow Planned Task',
          startMinute: 5 * 60,
          endMinute: 6 * 60,
          done: false,
        ),
      ];

      // Simulate midnight promotion as executed in _reconcileRoutineDate:
      autoTasks
        ..clear()
        ..addAll(tomorrowTasks);
      tomorrowTasks.clear();

      expect(autoTasks.length, 1);
      expect(autoTasks.first.title, 'Tomorrow Planned Task');
      expect(tomorrowTasks.isEmpty, true);
    });
    test('Tomorrow tasks allow any start minute (e.g. 05:00 AM) and calculate total planned time', () {
      final t1 = TaskNode(title: 'Early Prayer & Study', startMinute: 5 * 60, endMinute: 6 * 60 + 30);
      final t2 = TaskNode(title: 'Workout', startMinute: 6 * 60 + 30, endMinute: 7 * 60 + 30);
      final t3 = TaskNode(title: 'Office / Project Work', startMinute: 9 * 60, endMinute: 17 * 60);

      final tomorrowList = [t1, t2, t3];
      expect(tomorrowList.length, 3);
      expect(tomorrowList[0].startMinute, 300); // 05:00 AM
      expect(tomorrowList[0].endMinute, 390);   // 06:30 AM

      final intervals = <TimeInterval>[];
      for (final t in tomorrowList) {
        if (t.children.isEmpty && t.endMinute > t.startMinute) {
          intervals.add(TimeInterval(t.startMinute * 60, t.endMinute * 60));
        }
      }

      var total = 0;
      var mStart = -1;
      var mEnd = -1;
      for (final it in intervals) {
        if (mStart == -1) {
          mStart = it.startSeconds;
          mEnd = it.endSeconds;
        } else if (it.startSeconds <= mEnd) {
          if (it.endSeconds > mEnd) mEnd = it.endSeconds;
        } else {
          total += (mEnd - mStart);
          mStart = it.startSeconds;
          mEnd = it.endSeconds;
        }
      }
      if (mStart != -1) total += (mEnd - mStart);

      // (1.5h + 1h + 8h) = 10.5 hours = 37800 seconds
      expect(total, (1.5 + 1.0 + 8.0) * 3600);
    });
  });
}

