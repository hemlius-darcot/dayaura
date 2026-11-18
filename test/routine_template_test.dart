import 'package:flutter_test/flutter_test.dart';
import 'package:routine_app/routine_template.dart';

void main() {
  group('RoutineTemplate & RoutineTemplateStore Tests', () {
    test('RoutineTemplate serializes and deserializes properly', () {
      final sampleTasks = [
        {
          'title': 'Morning Workout',
          'startMinute': 360,
          'endMinute': 420,
          'done': false,
          'children': [],
        },
        {
          'title': 'Coding Session',
          'startMinute': 480,
          'endMinute': 660,
          'done': true, // should be preserved in template
          'children': [
            {
              'title': 'Review PRs',
              'startMinute': 480,
              'endMinute': 540,
              'done': true,
              'children': [],
            }
          ],
        }
      ];

      final template = RoutineTemplate(
        id: 'tpl_101',
        title: 'Productive Workday',
        createdAt: DateTime(2026, 10, 30, 9, 30),
        mode: 'Auto',
        tasks: sampleTasks,
      );

      expect(template.totalTasksCount, 3);

      final json = template.toJson();
      final restored = RoutineTemplate.fromJson(json);

      expect(restored.id, 'tpl_101');
      expect(restored.title, 'Productive Workday');
      expect(restored.mode, 'Auto');
      expect(restored.tasks.length, 2);
      expect(restored.totalTasksCount, 3);
    });

    test('Single template export JSON validation', () {
      final store = RoutineTemplateStore();

      final validExportJson = '''
      {
        "app": "RoutineTracker",
        "type": "routine_template",
        "exportVersion": 1,
        "exportedAt": "2026-10-30T10:00:00.000",
        "template": {
          "id": "tpl_shared_1",
          "title": "Exam Rush",
          "createdAt": "2026-10-30T10:00:00.000",
          "mode": "Manual",
          "tasks": [
            {
              "title": "Study Chapter 1",
              "startMinute": 600,
              "endMinute": 720,
              "children": []
            }
          ]
        }
      }
      ''';

      final parsed = store.validateAndParseSingle(validExportJson);
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Exam Rush');
      expect(parsed.mode, 'Manual');
      expect(parsed.tasks.length, 1);
    });

    test('Rejects invalid JSON for template', () {
      final store = RoutineTemplateStore();
      expect(store.validateAndParseSingle('invalid json string'), isNull);
      expect(store.validateAndParseSingle('{"app":"OtherApp"}'), isNull);
      expect(store.validateAndParseSingle('{"type":"routine_template"}'), isNull);
    });
  });

  group('Auto Mode Lock Rules for Routine Templates & Tasks', () {
    // Helper replicating lock logic from main.dart
    bool isTimeExpired(int endMinute, int elapsedSeconds, {String mode = 'Auto'}) {
      if (mode != 'Auto') return false;
      final endSec = endMinute == 1440 ? 86400 : endMinute * 60;
      return elapsedSeconds >= endSec;
    }

    bool isUpcoming(int startMinute, int elapsedSeconds, {String mode = 'Auto'}) {
      if (mode != 'Auto') return false;
      return elapsedSeconds < startMinute * 60;
    }

    bool isActive(int startMinute, int endMinute, int elapsedSeconds, {String mode = 'Auto'}) {
      if (mode != 'Auto') return true;
      final endSec = endMinute == 1440 ? 86400 : endMinute * 60;
      return elapsedSeconds >= startMinute * 60 && elapsedSeconds < endSec;
    }

    bool isCheckboxLocked(int startMinute, int endMinute, int elapsedSeconds, {String mode = 'Auto'}) {
      if (mode != 'Auto') return false;
      return isTimeExpired(endMinute, elapsedSeconds, mode: mode) ||
          isUpcoming(startMinute, elapsedSeconds, mode: mode);
    }

    test('Routine applied at 2:28 PM (52080s): past tasks are expired and locked', () {
      const currentSeconds = 14 * 3600 + 28 * 60; // 2:28 PM = 52080s

      // Task 1: 08:00 AM - 09:00 AM (end = 540 min = 32400s)
      expect(isTimeExpired(540, currentSeconds), isTrue);
      expect(isCheckboxLocked(480, 540, currentSeconds), isTrue);
      expect(isActive(480, 540, currentSeconds), isFalse);

      // Task 2: 01:00 PM - 02:00 PM (end = 840 min = 50400s)
      expect(isTimeExpired(840, currentSeconds), isTrue);
      expect(isCheckboxLocked(780, 840, currentSeconds), isTrue);
      expect(isActive(780, 840, currentSeconds), isFalse);
    });

    test('Routine applied at 2:28 PM (52080s): upcoming tasks cannot be pre-checked', () {
      const currentSeconds = 14 * 3600 + 28 * 60; // 2:28 PM = 52080s

      // Task: "rise" 11:05 PM - 12:00 AM (start = 1385 min = 83100s, end = 1440 min = 86400s)
      expect(isUpcoming(1385, currentSeconds), isTrue);
      expect(isTimeExpired(1440, currentSeconds), isFalse);
      // Bug fix verification: Checkbox MUST be locked for upcoming tasks!
      expect(isCheckboxLocked(1385, 1440, currentSeconds), isTrue);
      expect(isActive(1385, 1440, currentSeconds), isFalse);
    });

    test('Active task at 2:28 PM (52080s) has enabled checkbox', () {
      const currentSeconds = 14 * 3600 + 28 * 60; // 2:28 PM = 52080s

      // Task: 02:00 PM - 03:00 PM (start = 840 min = 50400s, end = 900 min = 54000s)
      expect(isUpcoming(840, currentSeconds), isFalse);
      expect(isTimeExpired(900, currentSeconds), isFalse);
      expect(isActive(840, 900, currentSeconds), isTrue);
      expect(isCheckboxLocked(840, 900, currentSeconds), isFalse);
    });

    test('Manual mode has no checkbox locks', () {
      const currentSeconds = 14 * 3600 + 28 * 60;
      expect(isCheckboxLocked(480, 540, currentSeconds, mode: 'Manual'), isFalse);
      expect(isCheckboxLocked(1385, 1440, currentSeconds, mode: 'Manual'), isFalse);
    });

    test('Earliest allowed start time in Auto Mode cannot be in the past', () {
      final now = DateTime(2026, 10, 30, 14, 28, 30);
      final nowSeconds = now.hour * 3600 + now.minute * 60 + now.second;
      final earliestAllowedStart = (nowSeconds ~/ 60 + 1) * 60;

      // 14:29:00 = 52140s
      expect(earliestAllowedStart, 14 * 3600 + 29 * 60);

      // Attempting to select 10:00 AM (36000s) is strictly before earliestAllowedStart
      const pastCandidate = 10 * 3600;
      expect(pastCandidate < earliestAllowedStart, isTrue);

      // Valid future time (15:00:00 = 54000s) is allowed
      const futureCandidate = 15 * 3600;
      expect(futureCandidate >= earliestAllowedStart, isTrue);
    });
  });
}
