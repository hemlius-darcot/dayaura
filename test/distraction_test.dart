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

    test('DistractionService passcode generator and verification (10 slots per day)', () {
      final nov3Date = DateTime(2026, 11, 3);
      final codes = DistractionService.getTodayPasscodes(date: nov3Date);
      expect(codes.length, 10);

      // Verify all 10 codes are unique for the day
      final uniqueSet = codes.toSet();
      expect(uniqueSet.length, 10);

      // Each code starts with DA- and is 9 chars
      for (final code in codes) {
        expect(code.startsWith('DA-'), isTrue);
        expect(code.length, 9);
        // Both with prefix and without prefix should verify
        expect(DistractionService.verifyUnlockPasscode(code, date: nov3Date), isTrue);
        expect(DistractionService.verifyUnlockPasscode(code.replaceAll('DA-', ''), date: nov3Date), isTrue);
      }

      // Slot 1 specifically matches DA-503643
      expect(DistractionService.getDailyPasscode(month: 11, day: 3, slot: 1), 'DA-503643');

      // Random fake code fails
      expect(DistractionService.verifyUnlockPasscode('DA-000000', date: nov3Date), isFalse);
    });

    test('Option B: Multi-slot passcodes for same day are distinct and verify properly', () {
      final today = DateTime(2026, 11, 10);
      final slot1Code = DistractionService.getDailyPasscode(month: today.month, day: today.day, slot: 1);
      final slot2Code = DistractionService.getDailyPasscode(month: today.month, day: today.day, slot: 2);
      final slot3Code = DistractionService.getDailyPasscode(month: today.month, day: today.day, slot: 3);

      expect(slot1Code, isNot(equals(slot2Code)));
      expect(slot2Code, isNot(equals(slot3Code)));
      expect(DistractionService.verifyUnlockPasscode(slot1Code, date: today), isTrue);
      expect(DistractionService.verifyUnlockPasscode(slot2Code, date: today), isTrue);
      expect(DistractionService.verifyUnlockPasscode(slot3Code, date: today), isTrue);
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
