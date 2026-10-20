/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2026 wger Team
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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wger/features/nutrition/models/meal.dart';
import 'package:wger/features/nutrition/models/nutritional_plan.dart';
import 'package:wger/features/nutrition/providers/meal_reminders.dart';

void main() {
  group('mealRemindersFor', () {
    test('is empty without a plan', () {
      expect(mealRemindersFor(null), isEmpty);
    });

    test('has one reminder per meal with a time, in plan order', () {
      final plan = NutritionalPlan(
        description: 'Plan',
        startDate: DateTime(2026, 1, 1),
        meals: [
          Meal(name: 'Cena', time: const TimeOfDay(hour: 21, minute: 0))..order = 3,
          Meal(name: 'Merienda')..order = 2,
          Meal(name: 'Desayuno', time: const TimeOfDay(hour: 8, minute: 30))..order = 1,
        ],
      );

      expect(mealRemindersFor(plan), const [
        MealReminder(id: 1000, mealName: 'Desayuno', hour: 8, minute: 30),
        MealReminder(id: 1001, mealName: 'Cena', hour: 21, minute: 0),
      ]);
    });
  });

  group('nextInstanceOf', () {
    late tz.Location location;

    setUpAll(() {
      tzdata.initializeTimeZones();
      location = tz.getLocation('America/Argentina/Buenos_Aires');
    });

    test('is today when the time is still ahead', () {
      final now = tz.TZDateTime(location, 2026, 10, 20, 7, 0);
      expect(nextInstanceOf(8, 30, now), tz.TZDateTime(location, 2026, 10, 20, 8, 30));
    });

    test('is tomorrow when the time has passed', () {
      final now = tz.TZDateTime(location, 2026, 10, 20, 9, 0);
      expect(nextInstanceOf(8, 30, now), tz.TZDateTime(location, 2026, 10, 21, 8, 30));
    });

    test('is tomorrow at exactly the time', () {
      final now = tz.TZDateTime(location, 2026, 10, 20, 8, 30);
      expect(nextInstanceOf(8, 30, now), tz.TZDateTime(location, 2026, 10, 21, 8, 30));
    });
  });
}
