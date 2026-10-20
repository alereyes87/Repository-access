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

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wger/core/app_settings_notifier.dart';
import 'package:wger/features/nutrition/models/nutritional_plan.dart';
import 'package:wger/features/nutrition/providers/nutrition_notifier.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

const PREFS_MEAL_REMINDERS_ENABLED = 'mealRemindersEnabled';

/// Notification ids of the reminders start here, one per meal of the plan
const _firstReminderId = 1000;

/// One daily notification for a meal of the current nutritional plan.
@immutable
class MealReminder {
  final int id;
  final String mealName;
  final int hour;
  final int minute;

  const MealReminder({
    required this.id,
    required this.mealName,
    required this.hour,
    required this.minute,
  });

  @override
  bool operator ==(Object other) =>
      other is MealReminder &&
      other.id == id &&
      other.mealName == mealName &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(id, mealName, hour, minute);
}

/// The reminders for the meals of [plan] that have a time set, in plan order.
List<MealReminder> mealRemindersFor(NutritionalPlan? plan) {
  if (plan == null) {
    return const [];
  }
  final meals = plan.meals.where((meal) => meal.time != null).sortedBy<num>((meal) => meal.order);
  return [
    for (final (index, meal) in meals.indexed)
      MealReminder(
        id: _firstReminderId + index,
        mealName: meal.name,
        hour: meal.time!.hour,
        minute: meal.time!.minute,
      ),
  ];
}

/// The next moment at [hour]:[minute] after [now], today or tomorrow.
tz.TZDateTime nextInstanceOf(int hour, int minute, tz.TZDateTime now) {
  var scheduled = tz.TZDateTime(now.location, now.year, now.month, now.day, hour, minute);
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

/// Whether the platform can show the reminders: only the mobile apps can.
bool get mealRemindersSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Schedules the reminders with the operating system. Override in tests.
abstract class MealReminderScheduler {
  /// Asks the user for permission to show notifications, true if granted
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with [reminders]
  Future<void> replaceAll(List<MealReminder> reminders, AppLocalizations i18n);

  Future<void> cancelAll();
}

class LocalNotificationsMealReminderScheduler implements MealReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) {
      return;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> replaceAll(List<MealReminder> reminders, AppLocalizations i18n) async {
    await _init();
    await _plugin.cancelAll();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'meal_reminders',
        i18n.mealReminders,
        channelDescription: i18n.mealRemindersDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    final now = tz.TZDateTime.now(tz.local);
    for (final reminder in reminders) {
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: i18n.mealReminderTitle(reminder.mealName),
        body: i18n.mealReminderBody,
        scheduledDate: nextInstanceOf(reminder.hour, reminder.minute, now),
        notificationDetails: details,
        // Inexact is fine for a meal and needs no exact-alarm permission
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }
}

final mealReminderSchedulerProvider = Provider<MealReminderScheduler>(
  (ref) => LocalNotificationsMealReminderScheduler(),
);

/// Whether meal reminders are on. While they are, the reminders follow the
/// meals of the current nutritional plan: a meal added, moved or deleted
/// reschedules them.
class MealRemindersNotifier extends AsyncNotifier<bool> {
  static final _logger = Logger('MealRemindersNotifier');

  List<MealReminder>? _scheduled;

  @override
  Future<bool> build() async {
    final enabled =
        await ref.read(appSettingsPrefsProvider).getBool(PREFS_MEAL_REMINDERS_ENABLED) ?? false;
    _scheduled = null;
    if (enabled && mealRemindersSupported) {
      ref.listen(
        nutritionProvider,
        (_, next) => _sync(next.value?.currentPlan),
        fireImmediately: true,
      );
    }
    return enabled;
  }

  AppLocalizations _localizations() {
    final locale =
        ref.read(appSettingsProvider).value?.userLocale ??
        WidgetsBinding.instance.platformDispatcher.locale;
    try {
      return lookupAppLocalizations(locale);
    } on FlutterError {
      return lookupAppLocalizations(const Locale('en'));
    }
  }

  Future<void> _sync(NutritionalPlan? plan) async {
    final reminders = mealRemindersFor(plan);
    if (const ListEquality<MealReminder>().equals(reminders, _scheduled)) {
      return;
    }
    _scheduled = reminders;
    try {
      await ref.read(mealReminderSchedulerProvider).replaceAll(reminders, _localizations());
    } catch (e, stack) {
      _logger.warning('Could not schedule the meal reminders', e, stack);
    }
  }

  /// Turns the reminders on or off; turning them on asks for the permission
  /// to notify first and stays off if it is refused. Returns the new state.
  Future<bool> setEnabled(bool value) async {
    final scheduler = ref.read(mealReminderSchedulerProvider);
    if (value && !await scheduler.requestPermission()) {
      return false;
    }
    if (!value) {
      await scheduler.cancelAll();
    }
    await ref.read(appSettingsPrefsProvider).setBool(PREFS_MEAL_REMINDERS_ENABLED, value);
    ref.invalidateSelf();
    return value;
  }
}

final mealRemindersProvider = AsyncNotifierProvider<MealRemindersNotifier, bool>(
  MealRemindersNotifier.new,
);
