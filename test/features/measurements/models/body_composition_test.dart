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
import 'package:wger/features/measurements/models/body_composition.dart';

void main() {
  test('bmi', () {
    expect(bmi(70, 175), closeTo(22.86, 0.01));
    expect(bmi(100, 180), closeTo(30.86, 0.01));
  });

  test('bmiCategory follows the WHO bands', () {
    expect(bmiCategory(18.4), BmiCategory.underweight);
    expect(bmiCategory(18.5), BmiCategory.normal);
    expect(bmiCategory(24.99), BmiCategory.normal);
    expect(bmiCategory(25), BmiCategory.overweight);
    expect(bmiCategory(29.9), BmiCategory.overweight);
    expect(bmiCategory(30), BmiCategory.obese);
  });

  test('idealWeightRangeKg', () {
    final range = idealWeightRangeKg(175);
    expect(range.min, closeTo(56.66, 0.01));
    expect(range.max, closeTo(76.26, 0.01));
  });

  test('kgToIdealRange', () {
    expect(kgToIdealRange(70, 175), 0);
    expect(kgToIdealRange(86.26, 175), closeTo(-10, 0.01));
    expect(kgToIdealRange(50, 175), closeTo(6.66, 0.01));
  });
}
