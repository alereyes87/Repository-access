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
import 'package:wger/features/nutrition/models/calorie_needs.dart';

void main() {
  const man = CalorieProfile(
    sex: Sex.male,
    age: 30,
    weightKg: 80,
    heightCm: 180,
    activity: ActivityLevel.moderate,
    goal: BodyGoal.maintain,
  );

  test('basalMetabolicRate follows Mifflin-St Jeor', () {
    // 10*80 + 6.25*180 - 5*30 + 5
    expect(basalMetabolicRate(man), 1780);

    const woman = CalorieProfile(
      sex: Sex.female,
      age: 25,
      weightKg: 60,
      heightCm: 165,
      activity: ActivityLevel.sedentary,
      goal: BodyGoal.maintain,
    );
    // 10*60 + 6.25*165 - 5*25 - 161
    expect(basalMetabolicRate(woman), closeTo(1345.25, 0.001));
  });

  test('maintenanceCalories applies the activity factor', () {
    expect(maintenanceCalories(man), closeTo(1780 * 1.55, 0.001));
  });

  test('dailyTargets for maintenance', () {
    final targets = dailyTargets(man);
    expect(targets.energy, 2759);
    expect(targets.protein, 128); // 1.6 g/kg
    expect(targets.fat, 77); // 25 % of the energy
    // The rest: (2759 - 128*4 - 76.64*9) / 4
    expect(targets.carbohydrates, 389);
  });

  test('dailyTargets for losing and gaining weight', () {
    const losing = CalorieProfile(
      sex: Sex.male,
      age: 30,
      weightKg: 80,
      heightCm: 180,
      activity: ActivityLevel.moderate,
      goal: BodyGoal.lose,
    );
    const gaining = CalorieProfile(
      sex: Sex.male,
      age: 30,
      weightKg: 80,
      heightCm: 180,
      activity: ActivityLevel.moderate,
      goal: BodyGoal.gain,
    );
    expect(dailyTargets(losing).energy, 2259);
    expect(dailyTargets(losing).protein, 160); // 2 g/kg
    expect(dailyTargets(gaining).energy, 3059);
  });

  test('dailyTargets never goes below the minimum energy', () {
    const small = CalorieProfile(
      sex: Sex.female,
      age: 70,
      weightKg: 45,
      heightCm: 150,
      activity: ActivityLevel.sedentary,
      goal: BodyGoal.lose,
    );
    expect(dailyTargets(small).energy, minDailyEnergy);
    expect(dailyTargets(small).carbohydrates, greaterThanOrEqualTo(0));
  });
}
