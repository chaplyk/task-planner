/// How often a recurring task comes back, and how its next due time is counted.
class Recurrence {
  const Recurrence({required this.every, required this.unit, this.mode = modeDone})
      : assert(every >= 1);

  static const units = ['hour', 'day', 'week', 'month'];

  /// Next due = when it was done + interval.
  static const modeDone = 'done';

  /// Next due = previous due + interval, whenever it was done.
  static const modeFixed = 'fixed';

  final int every;
  final String unit;
  final String mode;

  bool get fixed => mode == modeFixed;

  Recurrence withMode(String mode) => Recurrence(every: every, unit: unit, mode: mode);

  /// Validated parse; null for anything unusable (model output is untrusted).
  static Recurrence? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final every = raw['every'];
    final unit = raw['unit'];
    final mode = raw['mode'];
    if (unit is! String || !units.contains(unit)) return null;
    final n = every is num && every == every.roundToDouble() ? every.toInt() : (every == null ? 1 : null);
    if (n == null || n < 1 || n > 365) return null;
    return Recurrence(every: n, unit: unit, mode: mode == modeFixed ? modeFixed : modeDone);
  }

  Map<String, dynamic> toMap() => {'every': every, 'unit': unit, 'mode': mode};

  /// "Every day", "Every 2 weeks", "Hourly"-style label.
  String get label => every == 1 ? 'Every $unit' : 'Every $every ${unit}s';

  /// [from] moved forward by one interval. Months keep the day, clamped to the month's end.
  DateTime advance(DateTime from) => switch (unit) {
        'hour' => from.add(Duration(hours: every)),
        // Calendar arithmetic, so a daylight-saving change doesn't shift the time of day.
        'day' => _addDays(from, every),
        'week' => _addDays(from, 7 * every),
        _ => _addMonths(from, every),
      };

  /// The due time following a completion at [doneAt] of a cycle that was due at [prevDue].
  DateTime nextDueAfterDone({required DateTime prevDue, required DateTime doneAt}) {
    if (!fixed) return advance(doneAt);
    var next = advance(prevDue);
    // Skip missed cycles instead of letting them pile up.
    while (!next.isAfter(doneAt)) {
      next = advance(next);
    }
    return next;
  }

  @override
  bool operator ==(Object other) =>
      other is Recurrence && other.every == every && other.unit == unit && other.mode == mode;

  @override
  int get hashCode => Object.hash(every, unit, mode);

  @override
  String toString() => 'Recurrence($every $unit, $mode)';
}

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second);

DateTime _addMonths(DateTime d, int months) {
  final firstOfTarget = DateTime(d.year, d.month + months);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  final day = d.day > lastDay ? lastDay : d.day;
  return DateTime(firstOfTarget.year, firstOfTarget.month, day, d.hour, d.minute, d.second);
}

/// Share of the current cycle still left, from 1 (just done) to 0 (due).
double remainingShare(DateTime now, DateTime periodStart, DateTime nextDue) {
  final total = nextDue.difference(periodStart).inSeconds;
  if (total <= 0) return 0;
  final left = nextDue.difference(now).inSeconds / total;
  return left.clamp(0.0, 1.0);
}

/// "due in 4 days", "due in 3 h", "due in 20 min", "due now", "overdue 2 days".
String dueLabel(DateTime now, DateTime nextDue) {
  final diff = nextDue.difference(now);
  if (diff.inMinutes >= 1) return 'due in ${spanLabel(diff)}';
  if (diff.inMinutes > -1) return 'due now';
  return 'overdue ${spanLabel(-diff)}';
}

/// "3 days", "1 day", "5 h", "20 min".
String spanLabel(Duration d) {
  if (d.inDays >= 1) return d.inDays == 1 ? '1 day' : '${d.inDays} days';
  if (d.inHours >= 1) return '${d.inHours} h';
  return '${d.inMinutes} min';
}
