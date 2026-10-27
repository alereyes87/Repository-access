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

// Daily energy and macro targets from the user's body data, with the
// Mifflin-St Jeor equation for the basal metabolic rate.

enum Sex { male, female }

/// Physical activity level and its multiplier on the basal metabolic rate
enum ActivityLevel {
  sedentary(1.2),
  light(1.375),
  moderate(1.55),
  active(1.725),
  veryActive(1.9);

  final double factor;

  const ActivityLevel(this.factor);
}

/// What the user wants to do with their weight and the daily kcal it adds
/// to or takes from the maintenance calories
enum BodyGoal {
  lose(-500),
  maintain(0),
  gain(300);

  final int kcalAdjustment;

  const BodyGoal(this.kcalAdjustment);
}

/// The body data the calculation needs.
class CalorieProfile {
  final Sex sex;
  final int age;
  final double weightKg;
  final double heightCm;
  final ActivityLevel activity;
  final BodyGoal goal;

  const CalorieProfile({
    required this.sex,
    required this.age,
    required this.weightKg,
    required this.heightCm,
    required this.activity,
    required this.goal,
  });
}

/// Daily targets, energy in kcal and the macros in grams.
class DailyTargets {
  final double energy;
  final double protein;
  final double carbohydrates;
  final double fat;

  const DailyTargets({
    required this.energy,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
  });
}

const _kcalPerGramProtein = 4;
const _kcalPerGramCarbohydrates = 4;
const _kcalPerGramFat = 9;

/// Share of the energy that comes from fat
const _fatShare = 0.25;

/// Never suggest eating less than this, whatever the goal
const minDailyEnergy = 1200.0;

/// Basal metabolic rate in kcal per day (Mifflin-St Jeor).
double basalMetabolicRate(CalorieProfile p) {
  final base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age;
  return p.sex == Sex.male ? base + 5 : base - 161;
}

/// Calories burned per day at the profile's activity level.
double maintenanceCalories(CalorieProfile p) => basalMetabolicRate(p) * p.activity.factor;

/// Grams of protein per kg of body weight: more while losing (to keep muscle)
/// or gaining (to build it) than while maintaining
double _proteinPerKg(BodyGoal goal) => goal == BodyGoal.maintain ? 1.6 : 2.0;

DailyTargets dailyTargets(CalorieProfile p) {
  final energy = (maintenanceCalories(p) + p.goal.kcalAdjustment).clamp(
    minDailyEnergy,
    double.infinity,
  );
  final protein = _proteinPerKg(p.goal) * p.weightKg;
  final fat = energy * _fatShare / _kcalPerGramFat;
  final carbohydrates =
      ((energy - protein * _kcalPerGramProtein - fat * _kcalPerGramFat) / _kcalPerGramCarbohydrates)
          .clamp(0.0, double.infinity);

  return DailyTargets(
    energy: energy.roundToDouble(),
    protein: protein.roundToDouble(),
    carbohydrates: carbohydrates.roundToDouble(),
    fat: fat.roundToDouble(),
  );
}
