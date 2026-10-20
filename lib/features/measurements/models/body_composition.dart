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

/// BMI bands as defined by the WHO for adults.
enum BmiCategory { underweight, normal, overweight, obese }

/// Lower and upper BMI of the WHO "normal" band, used for the ideal weight.
const healthyBmiMin = 18.5;
const healthyBmiMax = 24.9;

/// Body mass index for [weightKg] and [heightCm].
double bmi(num weightKg, num heightCm) {
  final heightM = heightCm / 100;
  return weightKg / (heightM * heightM);
}

BmiCategory bmiCategory(double bmi) {
  if (bmi < healthyBmiMin) {
    return BmiCategory.underweight;
  }
  if (bmi < 25) {
    return BmiCategory.normal;
  }
  if (bmi < 30) {
    return BmiCategory.overweight;
  }
  return BmiCategory.obese;
}

/// The weight range in kg that keeps [heightCm] inside the healthy BMI band.
({double min, double max}) idealWeightRangeKg(num heightCm) {
  final heightM = heightCm / 100;
  return (min: healthyBmiMin * heightM * heightM, max: healthyBmiMax * heightM * heightM);
}

/// How many kg [weightKg] is away from the ideal range: negative to lose,
/// positive to gain, zero when already inside it.
double kgToIdealRange(num weightKg, num heightCm) {
  final range = idealWeightRangeKg(heightCm);
  if (weightKg > range.max) {
    return range.max - weightKg;
  }
  if (weightKg < range.min) {
    return range.min - weightKg;
  }
  return 0;
}
