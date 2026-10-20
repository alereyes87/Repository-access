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

import 'package:material_ui/material_ui.dart';
import 'package:wger/core/formatting/formatting.dart';
import 'package:wger/features/measurements/models/body_composition.dart';
import 'package:wger/features/measurements/models/unit_conversion.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

/// BMI, its WHO band and the ideal weight range for the latest body weight.
class BodyCompositionSummary extends StatelessWidget {
  /// Latest body weight, in [unit]
  final num weight;

  /// The unit [weight] is in, kg or lb
  final String unit;

  /// Body height in cm, null when the profile has none
  final int? heightCm;

  const BodyCompositionSummary({
    required this.weight,
    required this.unit,
    required this.heightCm,
  });

  String _categoryLabel(AppLocalizations i18n, BmiCategory category) => switch (category) {
    BmiCategory.underweight => i18n.bmiUnderweight,
    BmiCategory.normal => i18n.bmiNormal,
    BmiCategory.overweight => i18n.bmiOverweight,
    BmiCategory.obese => i18n.bmiObese,
  };

  Color _categoryColor(ColorScheme colors, BmiCategory category) => switch (category) {
    BmiCategory.normal => colors.primary,
    BmiCategory.underweight || BmiCategory.overweight => colors.tertiary,
    BmiCategory.obese => colors.error,
  };

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final height = heightCm;

    if (height == null) {
      return ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(i18n.setHeightForBmi),
      );
    }

    final weightKg = convertWeight(weight, from: unit, to: 'kg');
    final value = bmi(weightKg, height);
    final category = bmiCategory(value);
    final range = idealWeightRangeKg(height);
    final diff = convertWeight(kgToIdealRange(weightKg, height).abs(), from: 'kg', to: unit);
    final min = convertWeight(range.min, from: 'kg', to: unit);
    final max = convertWeight(range.max, from: 'kg', to: unit);

    final String progress;
    if (diff == 0) {
      progress = i18n.idealWeightReached;
    } else if (weightKg > range.max) {
      progress = i18n.idealWeightToLose(measurementWithUnit(context, diff, unit, decimals: 1));
    } else {
      progress = i18n.idealWeightToGain(measurementWithUnit(context, diff, unit, decimals: 1));
    }

    return Column(
      children: [
        ListTile(
          title: Text(i18n.calculationNameBmi),
          trailing: Text(
            measurementValue(context, value, 'kg/m²', decimals: 1),
            style: theme.textTheme.titleLarge,
          ),
          subtitle: Text(
            _categoryLabel(i18n, category),
            style: TextStyle(color: _categoryColor(theme.colorScheme, category)),
          ),
        ),
        ListTile(
          title: Text(i18n.idealWeight),
          trailing: Text(
            '${measurementValue(context, min, unit, decimals: 1)} – '
            '${measurementWithUnit(context, max, unit, decimals: 1)}',
            style: theme.textTheme.titleMedium,
          ),
          subtitle: Text(progress),
        ),
      ],
    );
  }
}
