/// Pure, production-used planner for recovering missing daily history records.
/// It intentionally does not modify storage; callers save only the returned days.
class RoutineRecoveredDay {
  const RoutineRecoveredDay({required this.date, required this.progress, required this.mode});

  final DateTime date;
  final double progress;
  final String mode;

  String get dateKey => routineDateKey(date);
}

String routineDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

List<RoutineRecoveredDay> planRoutineDateRecovery({
  required DateTime firstDate,
  required DateTime currentDate,
  required double firstDayProgress,
  required String mode,
  required Set<String> existingDateKeys,
}) {
  var day = DateTime(firstDate.year, firstDate.month, firstDate.day);
  final today = DateTime(currentDate.year, currentDate.month, currentDate.day);
  final existing = Set<String>.from(existingDateKeys);
  final result = <RoutineRecoveredDay>[];
  var isFirst = true;

  while (day.isBefore(today)) {
    final key = routineDateKey(day);
    if (!existing.contains(key)) {
      result.add(RoutineRecoveredDay(
        date: day,
        progress: isFirst ? firstDayProgress.clamp(0.0, 100.0).toDouble() : 0.0,
        mode: mode,
      ));
      existing.add(key);
    }
    isFirst = false;
    day = day.add(const Duration(days: 1));
  }
  return result;
}
