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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wger/core/app_settings_notifier.dart';
import 'package:wger/core/widgets/decimal_input.dart';
import 'package:wger/features/account/models/user_profile.dart';
import 'package:wger/features/account/providers/user_profile_notifier.dart';
import 'package:wger/features/measurements/models/measurement_entry.dart';
import 'package:wger/features/measurements/models/unit_conversion.dart';
import 'package:wger/features/measurements/providers/body_weight_provider.dart';
import 'package:wger/features/measurements/providers/measurement_notifier.dart';
import 'package:wger/features/nutrition/models/calorie_needs.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

const PREFS_CALORIES_SEX = 'caloriesSex';
const PREFS_CALORIES_AGE = 'caloriesAge';
const PREFS_CALORIES_ACTIVITY = 'caloriesActivity';
const PREFS_CALORIES_GOAL = 'caloriesGoal';

extension on Sex {
  String label(AppLocalizations i18n) => switch (this) {
    Sex.male => i18n.sexMale,
    Sex.female => i18n.sexFemale,
  };
}

extension on ActivityLevel {
  String label(AppLocalizations i18n) => switch (this) {
    ActivityLevel.sedentary => i18n.activitySedentary,
    ActivityLevel.light => i18n.activityLight,
    ActivityLevel.moderate => i18n.activityModerate,
    ActivityLevel.active => i18n.activityActive,
    ActivityLevel.veryActive => i18n.activityVeryActive,
  };
}

extension on BodyGoal {
  String label(AppLocalizations i18n) => switch (this) {
    BodyGoal.lose => i18n.bodyGoalLose,
    BodyGoal.maintain => i18n.bodyGoalMaintain,
    BodyGoal.gain => i18n.bodyGoalGain,
  };
}

/// Asks for the body data the daily calories depend on, prefilled with the
/// latest body weight, the profile height and the answers of the last time,
/// and pops with the [DailyTargets] the user accepts.
///
/// With [saveBodyData] (the welcome flow) accepting also stores the weight as
/// a new body weight entry and the height in the profile, when they changed.
class CalorieCalculatorDialog extends ConsumerStatefulWidget {
  final bool saveBodyData;

  const CalorieCalculatorDialog({super.key, this.saveBodyData = false});

  @override
  ConsumerState<CalorieCalculatorDialog> createState() => _CalorieCalculatorDialogState();
}

class _CalorieCalculatorDialogState extends ConsumerState<CalorieCalculatorDialog> {
  bool _loaded = false;
  bool _prefilled = false;
  Sex _sex = Sex.male;
  ActivityLevel _activity = ActivityLevel.moderate;
  BodyGoal _goal = BodyGoal.maintain;
  num? _age;
  num? _weightKg;
  num? _heightCm;
  num? _initialWeightKg;
  String? _weightCategoryId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static T _byName<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;

  Future<void> _load() async {
    final prefs = ref.read(appSettingsPrefsProvider);
    final sex = await prefs.getString(PREFS_CALORIES_SEX);
    final activity = await prefs.getString(PREFS_CALORIES_ACTIVITY);
    final goal = await prefs.getString(PREFS_CALORIES_GOAL);
    final age = await prefs.getInt(PREFS_CALORIES_AGE);

    if (!mounted) {
      return;
    }
    setState(() {
      _sex = _byName(Sex.values, sex, _sex);
      _activity = _byName(ActivityLevel.values, activity, _activity);
      _goal = _byName(BodyGoal.values, goal, _goal);
      _age = age;
      _loaded = true;
    });
  }

  /// Fills in the latest body weight and the profile height once they are
  /// known. False while they are still loading. A value that cannot be read
  /// is left empty for the user to type in.
  bool _prefill() {
    if (_prefilled) {
      return true;
    }
    final profile = ref.watch(userProfileProvider);
    final category = ref.watch(bodyWeightCategoryOnlyProvider);
    final latest = ref.watch(latestMeasurementEntriesProvider);
    if (profile.isLoading || category.isLoading || latest.isLoading) {
      return false;
    }

    _heightCm = profile.value?.height;
    final weightCategory = category.value;
    final entry = weightCategory == null ? null : latest.value?[weightCategory.id];
    if (weightCategory != null && entry != null) {
      _weightKg = convertWeight(
        entry.value,
        from: unitOrFallback(entry.extraData?['unit'], weightCategory.unit),
        to: 'kg',
      );
    }
    _initialWeightKg = _weightKg;
    _weightCategoryId = weightCategory?.id;
    _prefilled = true;
    return true;
  }

  CalorieProfile? get _profile {
    final age = _age;
    final weight = _weightKg;
    final height = _heightCm;
    if (age == null || weight == null || height == null || age <= 0 || weight <= 0 || height <= 0) {
      return null;
    }
    return CalorieProfile(
      sex: _sex,
      age: age.round(),
      weightKg: weight.toDouble(),
      heightCm: height.toDouble(),
      activity: _activity,
      goal: _goal,
    );
  }

  Future<void> _accept(DailyTargets targets) async {
    final prefs = ref.read(appSettingsPrefsProvider);
    await prefs.setString(PREFS_CALORIES_SEX, _sex.name);
    await prefs.setString(PREFS_CALORIES_ACTIVITY, _activity.name);
    await prefs.setString(PREFS_CALORIES_GOAL, _goal.name);
    await prefs.setInt(PREFS_CALORIES_AGE, _profile!.age);
    if (widget.saveBodyData) {
      await _saveBodyData();
    }
    if (mounted) {
      Navigator.of(context).pop(targets);
    }
  }

  Future<void> _saveBodyData() async {
    final weight = _weightKg;
    final categoryId = _weightCategoryId;
    if (weight != null && weight != _initialWeightKg && categoryId != null) {
      await ref
          .read(measurementProvider.notifier)
          .addEntry(
            MeasurementEntry(
              categoryId: categoryId,
              date: DateTime.now(),
              value: weight,
              notes: '',
              extraData: {'unit': 'kg'},
            ),
          );
    }

    final profile = ref.read(userProfileProvider).value;
    final height = _heightCm?.round();
    if (profile != null &&
        height != null &&
        height != profile.height &&
        height >= UserProfile.minHeightCm &&
        height <= UserProfile.maxHeightCm) {
      await ref
          .read(userProfileProvider.notifier)
          .updateProfile(
            UserProfile(
              id: profile.id,
              weightUnitStr: profile.weightUnitStr,
              height: height,
              timeZone: profile.timeZone,
            ),
          );
    }
  }

  Widget _dropdown<T extends Enum>(
    String label,
    T value,
    List<T> values,
    String Function(T) text,
    ValueChanged<T> onChanged,
  ) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values.map((v) => DropdownMenuItem(value: v, child: Text(text(v)))).toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() => onChanged(v));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final ready = _prefill() && _loaded;
    final profile = _profile;
    final targets = profile == null ? null : dailyTargets(profile);

    return AlertDialog(
      title: Text(widget.saveBodyData ? i18n.welcomeTitle : i18n.calorieCalculator),
      content: !ready
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.saveBodyData ? i18n.welcomeText : i18n.calorieCalculatorHelp),
                  _dropdown(i18n.sex, _sex, Sex.values, (v) => v.label(i18n), (v) => _sex = v),
                  DecimalInputWidget(
                    key: const Key('field-calories-age'),
                    value: _age,
                    labelText: i18n.age,
                    min: 1,
                    max: 120,
                    onChanged: (v) => setState(() => _age = v),
                  ),
                  DecimalInputWidget(
                    key: const Key('field-calories-weight'),
                    value: _weightKg,
                    labelText: i18n.weight,
                    suffixText: 'kg',
                    min: 1,
                    max: 400,
                    onChanged: (v) => setState(() => _weightKg = v),
                  ),
                  DecimalInputWidget(
                    key: const Key('field-calories-height'),
                    value: _heightCm,
                    labelText: i18n.height,
                    suffixText: 'cm',
                    min: 50,
                    max: 250,
                    onChanged: (v) => setState(() => _heightCm = v),
                  ),
                  _dropdown(
                    i18n.activityLevel,
                    _activity,
                    ActivityLevel.values,
                    (v) => v.label(i18n),
                    (v) => _activity = v,
                  ),
                  _dropdown(
                    i18n.bodyGoal,
                    _goal,
                    BodyGoal.values,
                    (v) => v.label(i18n),
                    (v) => _goal = v,
                  ),
                  const SizedBox(height: 16),
                  if (targets != null)
                    Text(
                      i18n.calculatedTargets(
                        targets.energy.round(),
                        targets.protein.round(),
                        targets.carbohydrates.round(),
                        targets.fat.round(),
                      ),
                      key: const Key('calories-result'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          key: const Key('calories-accept'),
          onPressed: targets == null ? null : () => _accept(targets),
          child: Text(widget.saveBodyData ? i18n.save : i18n.useTheseValues),
        ),
      ],
    );
  }
}
