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
import 'package:flutter_test/flutter_test.dart';
import 'package:wger/core/consts.dart';
import 'package:wger/features/routines/models/log.dart';
import 'package:wger/features/routines/models/weight_suggestion.dart';

Log _log(DateTime date, num weight, num reps, {num? target = 10, int unit = WEIGHT_UNIT_KG}) => Log(
  exerciseId: 1,
  date: date,
  weight: weight,
  repetitions: reps,
  repetitionsTarget: target,
  weightUnitId: unit,
);

void main() {
  final now = DateTime(2026, 10, 28, 18);
  final lastWeek = DateTime(2026, 10, 21, 18);
  final twoWeeksAgo = DateTime(2026, 10, 14, 18);

  WeightSuggestion? suggest(List<Log> logs, {num? targetRepetitions, num? rounding}) => withClock(
    Clock.fixed(now),
    () => suggestNextWeight(logs, targetRepetitions: targetRepetitions, rounding: rounding),
  );

  test('No logs, no suggestion', () {
    expect(suggest([]), isNull);
  });

  test('Goes up 2.5 kg when every set reached the target', () {
    final result = suggest([
      _log(lastWeek, 60, 10),
      _log(lastWeek.add(const Duration(minutes: 3)), 60, 11),
      _log(lastWeek.add(const Duration(minutes: 6)), 60, 10),
    ])!;
    expect(result.weight, 62.5);
    expect(result.lastWeight, 60);
    expect(result.reason, WeightSuggestionReason.increase);
  });

  test('Repeats the weight when a set fell short', () {
    final result = suggest([
      _log(lastWeek, 60, 10),
      _log(lastWeek.add(const Duration(minutes: 3)), 60, 8),
    ])!;
    expect(result.weight, 60);
    expect(result.reason, WeightSuggestionReason.repeat);
  });

  test('Only the heaviest sets of the last session count', () {
    final result = suggest([
      _log(twoWeeksAgo, 70, 2),
      _log(lastWeek, 40, 6), // warm-up
      _log(lastWeek.add(const Duration(minutes: 3)), 60, 10),
    ])!;
    expect(result.weight, 62.5);
  });

  test("Today's sets are ignored", () {
    final result = suggest([
      _log(lastWeek, 60, 10),
      _log(now.subtract(const Duration(minutes: 10)), 62.5, 4),
    ])!;
    expect(result.weight, 62.5);
    expect(result.lastWeight, 60);
  });

  test('Falls back to the routine target and uses 5 lb for pounds', () {
    final result = suggest(
      [_log(lastWeek, 135, 8, target: null, unit: WEIGHT_UNIT_LB)],
      targetRepetitions: 8,
    )!;
    expect(result.weight, 140);
    expect(result.weightUnitId, WEIGHT_UNIT_LB);
  });

  test('Without any target the weight is repeated', () {
    final result = suggest([_log(lastWeek, 60, 12, target: null)])!;
    expect(result.reason, WeightSuggestionReason.repeat);
  });

  test('Rounds to the configured step', () {
    final result = suggest([_log(lastWeek, 61, 10)], rounding: 2)!;
    expect(result.weight, 64);
  });
}
