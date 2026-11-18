import 'routine_date_recovery.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('FAIL: $message');
  print('PASS: $message');
}

void main() {
  // These tests call the same planner used by main_history_daily_tasks_fixed.dart.
  final sameDay = planRoutineDateRecovery(
    firstDate: DateTime(2026, 10, 28),
    currentDate: DateTime(2026, 10, 28),
    firstDayProgress: 70,
    mode: 'Auto',
    existingDateKeys: <String>{},
  );
  check(sameDay.isEmpty, 'same date creates no recovered records');

  final nextDay = planRoutineDateRecovery(
    firstDate: DateTime(2026, 10, 28),
    currentDate: DateTime(2026, 10, 29),
    firstDayProgress: 70,
    mode: 'Auto',
    existingDateKeys: <String>{},
  );
  check(nextDay.length == 1, 'next day creates one recovered record');
  check(nextDay[0].dateKey == '2026-10-28' && nextDay[0].progress == 70,
      'previous day retains 70% progress');

  final gap = planRoutineDateRecovery(
    firstDate: DateTime(2026, 10, 28),
    currentDate: DateTime(2026, 10, 31),
    firstDayProgress: 70,
    mode: 'Auto',
    existingDateKeys: <String>{},
  );
  check(gap.length == 3, 'three prior dates are recovered for a three-day gap');
  check(gap[0].dateKey == '2026-10-28' && gap[0].progress == 70,
      'first recovered day retains calculated progress');
  check(gap[1].dateKey == '2026-10-29' && gap[1].progress == 0,
      'next missing day is 0%');
  check(gap[2].dateKey == '2026-10-30' && gap[2].progress == 0,
      'following missing day is 0%');

  final existing = planRoutineDateRecovery(
    firstDate: DateTime(2026, 10, 28),
    currentDate: DateTime(2026, 10, 30),
    firstDayProgress: 70,
    mode: 'Auto',
    existingDateKeys: <String>{'2026-10-28'},
  );
  check(existing.length == 1 && existing[0].dateKey == '2026-10-29',
      'existing history date is skipped and not replaced');
  check(existing[0].progress == 0, 'new missing date receives 0%');

  print('\nAll production-planner tests passed.');
}
