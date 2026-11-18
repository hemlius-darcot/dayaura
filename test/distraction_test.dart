import 'package:flutter_test/flutter_test.dart';
import 'package:routine_app/routine_history.dart';
import 'package:routine_app/distraction_service.dart';

void main() {
  group('Distraction Deduplication Tests', () {
    test('RoutineDayRecord.fromJson deduplicates identical distractions and items within 15s', () {
      final json = {
        'date': '2026-10-30T00:00:00.000',
        'progress': 75.0,
        'mode': 'Auto',
        'distractions': [
          {
            'id': '1730300220000',
            'name': 'other',
            'timeLabel': '06:17 PM',
            'timestamp': '2026-10-30T18:17:00.000',
          },
          {
            'id': '1730300220050',
            'name': 'other',
            'timeLabel': '06:17 PM',
            'timestamp': '2026-10-30T18:17:02.000',
          },
          {
            'id': '1730300280000',
            'name': 'hhh',
            'timeLabel': '06:18 PM',
            'timestamp': '2026-10-30T18:18:00.000',
          },
          {
            'id': '1730300280050',
            'name': 'hhh',
            'timeLabel': '06:18 PM',
            'timestamp': '2026-10-30T18:18:01.000',
          },
        ],
      };

      final record = RoutineDayRecord.fromJson(json);
      expect(record.distractions, isNotNull);
      expect(record.distractions!.length, 2);
      expect(record.distractions![0]['name'], 'other');
      expect(record.distractions![1]['name'], 'hhh');
    });

    test('RoutineDayRecord.fromJson preserves distinct distractions', () {
      final json = {
        'date': '2026-10-30T00:00:00.000',
        'progress': 80.0,
        'mode': 'Auto',
        'distractions': [
          {
            'id': '1',
            'name': 'Facebook',
            'timeLabel': '10:00 AM',
            'timestamp': '2026-10-30T10:00:00.000',
          },
          {
            'id': '2',
            'name': 'YouTube',
            'timeLabel': '11:30 AM',
            'timestamp': '2026-10-30T11:30:00.000',
          },
        ],
      };

      final record = RoutineDayRecord.fromJson(json);
      expect(record.distractions!.length, 2);
      expect(record.distractions![0]['name'], 'Facebook');
      expect(record.distractions![1]['name'], 'YouTube');
    });

    test('DistractionService open-source emergency unlock passcode calculation and verification', () {
      // Test User Example 1: 12:00 (AM or PM) -> 567673 * 1200 = 681207600 -> 681207
      final t1200 = DateTime(2026, 11, 19, 12, 0);
      expect(DistractionService.calculateEmergencyPasscode(time: t1200), '681207');
      expect(DistractionService.verifyUnlockPasscode('681207', date: t1200), isTrue);

      // Test User Example 2: 3:43 PM (15:43) -> 567673 * 343 = 194711839 -> 194711
      final t1543 = DateTime(2026, 11, 19, 15, 43);
      expect(DistractionService.calculateEmergencyPasscode(time: t1543), '194711');
      expect(DistractionService.verifyUnlockPasscode('194711', date: t1543), isTrue);

      // Both with prefix and without prefix verify
      expect(DistractionService.verifyUnlockPasscode('DA-194711', date: t1543), isTrue);

      // Clock drift tolerance (within 2 minutes) verifies
      final t1544 = DateTime(2026, 11, 19, 15, 44);
      expect(DistractionService.verifyUnlockPasscode('194711', date: t1544), isTrue);

      // Random incorrect code fails
      expect(DistractionService.verifyUnlockPasscode('000000', date: t1543), isFalse);
    });

    test('Google Clipboard Mutual Exclusivity: Pinned chips are excluded from recent chips', () {
      final pinnedChips = ['facebook', 'instagram'];
      final rawRecentChips = ['facebook', 'youtube', 'reels', 'instagram'];

      // When filtering recent chips like Google Clipboard:
      final effectiveRecent = rawRecentChips
          .where((r) => pinnedChips.every((p) => p.toLowerCase() != r.toLowerCase()))
          .toList();

      expect(effectiveRecent, ['youtube', 'reels']);
      expect(effectiveRecent.contains('facebook'), isFalse);
      expect(effectiveRecent.contains('instagram'), isFalse);
    });
  });
}
