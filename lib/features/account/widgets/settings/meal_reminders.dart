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
import 'package:wger/features/nutrition/providers/meal_reminders.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

/// "Meal reminders" toggle: a daily notification at the time of every meal of
/// the current nutritional plan.
class SettingsMealReminders extends ConsumerWidget {
  const SettingsMealReminders({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!mealRemindersSupported) {
      return const SizedBox.shrink();
    }
    final i18n = AppLocalizations.of(context);
    final enabled = ref.watch(mealRemindersProvider).value ?? false;

    return SwitchListTile(
      key: const ValueKey('mealRemindersSwitch'),
      title: Text(i18n.mealReminders),
      subtitle: Text(i18n.mealRemindersDescription),
      value: enabled,
      onChanged: (value) async {
        final result = await ref.read(mealRemindersProvider.notifier).setEnabled(value);
        if (value && !result && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(i18n.mealRemindersPermissionDenied)));
        }
      },
    );
  }
}
