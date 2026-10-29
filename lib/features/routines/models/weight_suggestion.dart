/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020 - 2026 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:clock/clock.dart';
import 'package:wger/core/consts.dart';
import 'package:wger/features/routines/models/log.dart';

/// Why a weight was suggested for the next set
enum WeightSuggestionReason {
  /// Every set of the last session at that weight reached the target, so go up
  increase,

  /// Some set fell short of the target, so stay at the same weight
  repeat,
}

/// A suggested working weight, based on the last session of an exercise
class WeightSuggestion {
  final num weight;
  final num lastWeight;
  final int? weightUnitId;
  final WeightSuggestionReason reason;

  const WeightSuggestion({
    required this.weight,
    required this.lastWeight,
    required this.weightUnitId,
    required this.reason,
  });
}

/// Default increment for a successful session, by weight unit
num defaultWeightIncrement(int? weightUnitId) => weightUnitId == WEIGHT_UNIT_LB ? 5 : 2.5;

/// Suggests the weight for the next session (simple double progression).
///
/// Looks at the most recent day before today with weighted logs and takes the
/// heaviest weight used. If every set at that weight reached its repetition
/// target ([Log.repetitionsTarget], falling back to [targetRepetitions]), it
/// suggests going up by [increment] (2.5 kg / 5 lb by default), otherwise it
/// suggests repeating the weight. Returns null when there is nothing to go by.
WeightSuggestion? suggestNextWeight(
  List<Log> logs, {
  num? targetRepetitions,
  num? increment,
  num? rounding,
}) {
  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  final candidates = logs
      .where(
        (l) =>
            l.weight != null &&
            l.weight! > 0 &&
            l.repetitions != null &&
            (l.repetitionsUnitId == null || l.repetitionsUnitId == REP_UNIT_REPETITIONS_ID) &&
            day(l.date).isBefore(today),
      )
      .toList();
  if (candidates.isEmpty) {
    return null;
  }

  final lastDay = candidates.map((l) => day(l.date)).reduce((a, b) => a.isAfter(b) ? a : b);
  final session = candidates.where((l) => day(l.date) == lastDay).toList();

  // Only compare sets that use the same unit as the latest one
  session.sort((a, b) => b.date.compareTo(a.date));
  final unitId = session.first.weightUnitId;
  final sameUnit = session.where((l) => l.weightUnitId == unitId).toList();

  final topWeight = sameUnit.map((l) => l.weight!).reduce((a, b) => a > b ? a : b);
  final topSets = sameUnit.where((l) => l.weight == topWeight);

  final allReached = topSets.every((l) {
    final target = l.repetitionsTarget ?? targetRepetitions;
    return target != null && l.repetitions! >= target;
  });

  if (!allReached) {
    return WeightSuggestion(
      weight: topWeight,
      lastWeight: topWeight,
      weightUnitId: unitId,
      reason: WeightSuggestionReason.repeat,
    );
  }

  var next = topWeight + (increment ?? defaultWeightIncrement(unitId));
  if (rounding != null && rounding > 0) {
    next = (next / rounding).round() * rounding;
  }

  return WeightSuggestion(
    weight: next,
    lastWeight: topWeight,
    weightUnitId: unitId,
    reason: WeightSuggestionReason.increase,
  );
}
