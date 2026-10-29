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
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/app_settings_notifier.dart';
import 'package:wger/core/widgets/dashboard/widgets/welcome.dart';
import 'package:wger/features/account/models/user_profile.dart';
import 'package:wger/features/account/providers/user_profile_notifier.dart';
import 'package:wger/features/measurements/models/measurement_entry.dart';
import 'package:wger/features/measurements/providers/body_weight_provider.dart';
import 'package:wger/features/measurements/providers/measurement_notifier.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/l10n/localizations_delegates.dart';

import '../../../../test_data/body_weight.dart';

class _StubUserProfileNotifier extends UserProfileNotifier {
  static int? height;

  @override
  Stream<UserProfile?> build() =>
      Stream.value(UserProfile(id: 1, weightUnitStr: 'kg', height: height));
}

void main() {
  final category = getBodyWeightCategory();
  late SharedPreferencesAsync prefs;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
    _StubUserProfileNotifier.height = null;
  });

  Widget render({bool withWeight = false}) {
    return ProviderScope(
      overrides: [
        appSettingsPrefsProvider.overrideWithValue(prefs),
        userProfileProvider.overrideWith(_StubUserProfileNotifier.new),
        bodyWeightCategoryOnlyProvider.overrideWith((ref) => Stream.value(category)),
        latestMeasurementEntriesProvider.overrideWith(
          (ref) => Stream.value({
            if (withWeight)
              category.id!: MeasurementEntry(
                id: 'e1',
                categoryId: category.id!,
                date: DateTime(2026, 10, 1),
                value: 80,
                notes: '',
              ),
          }),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: DashboardWelcomeWidget()),
      ),
    );
  }

  testWidgets('shown while the height or the weight is missing', (tester) async {
    await tester.pumpWidget(render());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-welcome')), findsOneWidget);
    expect(find.text('Welcome!'), findsOneWidget);
  });

  testWidgets('hidden once height and weight are known', (tester) async {
    _StubUserProfileNotifier.height = 180;
    await tester.pumpWidget(render(withWeight: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-welcome')), findsNothing);
  });

  testWidgets('"Not now" hides it for good', (tester) async {
    await tester.pumpWidget(render());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dashboard-welcome-later')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-welcome')), findsNothing);
    expect(await prefs.getBool(PREFS_WELCOME_DONE), isTrue);
  });

  testWidgets('"Get started" opens the body data dialog', (tester) async {
    await tester.pumpWidget(render());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dashboard-welcome-start')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('field-calories-height')), findsOneWidget);
  });
}
