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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wger/core/app_settings_notifier.dart';
import 'package:wger/features/account/providers/user_profile_notifier.dart';
import 'package:wger/features/measurements/providers/body_weight_provider.dart';
import 'package:wger/features/measurements/providers/measurement_notifier.dart';
import 'package:wger/features/nutrition/widgets/calorie_calculator.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

const PREFS_WELCOME_DONE = 'welcomeDone';

/// Asks new users for their body data until they have a height and a body
/// weight entry, or say they want to do it later
class DashboardWelcomeWidget extends ConsumerStatefulWidget {
  const DashboardWelcomeWidget({super.key});

  @override
  ConsumerState<DashboardWelcomeWidget> createState() => _DashboardWelcomeWidgetState();
}

class _DashboardWelcomeWidgetState extends ConsumerState<DashboardWelcomeWidget> {
  bool? _done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final done = await ref.read(appSettingsPrefsProvider).getBool(PREFS_WELCOME_DONE);
    if (mounted) {
      setState(() => _done = done ?? false);
    }
  }

  Future<void> _finish() async {
    setState(() => _done = true);
    await ref.read(appSettingsPrefsProvider).setBool(PREFS_WELCOME_DONE, true);
  }

  Future<void> _start() async {
    final result = await showDialog(
      context: context,
      builder: (_) => const CalorieCalculatorDialog(saveBodyData: true),
    );
    if (result != null && mounted) {
      await _finish();
    }
  }

  /// Whether the profile still lacks a height or a body weight. Null while loading.
  bool? _missingData() {
    final profile = ref.watch(userProfileProvider);
    final category = ref.watch(bodyWeightCategoryOnlyProvider);
    final latest = ref.watch(latestMeasurementEntriesProvider);
    if (!profile.hasValue || !category.hasValue || !latest.hasValue) {
      return null;
    }
    final weightCategory = category.value;
    final hasWeight = weightCategory != null && latest.value!.containsKey(weightCategory.id);
    return profile.value?.height == null || !hasWeight;
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missingData();
    if (_done != false || missing != true) {
      return const SizedBox.shrink();
    }

    final i18n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      key: const Key('dashboard-welcome'),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n.welcomeTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(i18n.welcomeText),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('dashboard-welcome-later'),
                  onPressed: _finish,
                  child: Text(i18n.welcomeLater),
                ),
                FilledButton(
                  key: const Key('dashboard-welcome-start'),
                  onPressed: _start,
                  child: Text(i18n.welcomeStart),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
