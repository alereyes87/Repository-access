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
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/features/account/models/user_profile.dart';
import 'package:wger/features/account/providers/user_profile_notifier.dart';
import 'package:wger/features/measurements/models/measurement_entry.dart';
import 'package:wger/features/measurements/providers/body_weight_provider.dart';
import 'package:wger/features/measurements/providers/measurement_notifier.dart';
import 'package:wger/features/measurements/providers/measurement_repository.dart';
import 'package:wger/features/nutrition/models/calorie_needs.dart';
import 'package:wger/features/nutrition/widgets/calorie_calculator.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/l10n/localizations_delegates.dart';

import '../../../../test_data/body_weight.dart';
import '../../health/providers/health_sync_test.mocks.dart';

class _StubUserProfileNotifier extends UserProfileNotifier {
  static UserProfile? updated;

  @override
  Stream<UserProfile?> build() =>
      Stream.value(UserProfile(id: 1, weightUnitStr: 'kg', height: 180));

  @override
  Future<void> updateProfile(UserProfile profile) async {
    updated = profile;
  }
}

void main() {
  final category = getBodyWeightCategory();
  DailyTargets? result;
  late MockMeasurementRepository measurements;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    result = null;
    _StubUserProfileNotifier.updated = null;
    measurements = MockMeasurementRepository();
    when(measurements.addLocalDrift(any)).thenAnswer((_) async {});
  });

  Widget renderDialog({bool saveBodyData = false}) {
    return ProviderScope(
      overrides: [
        measurementRepositoryProvider.overrideWithValue(measurements),
        userProfileProvider.overrideWith(_StubUserProfileNotifier.new),
        bodyWeightCategoryOnlyProvider.overrideWith((ref) => Stream.value(category)),
        latestMeasurementEntriesProvider.overrideWith(
          (ref) => Stream.value({
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
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<DailyTargets>(
                  context: context,
                  builder: (_) => CalorieCalculatorDialog(saveBodyData: saveBodyData),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('prefills weight and height and returns the targets', (tester) async {
    await tester.pumpWidget(renderDialog());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('80'), findsOneWidget, reason: 'latest body weight');
    expect(find.text('180'), findsOneWidget, reason: 'profile height');

    // No result until the age is known
    expect(find.byKey(const Key('calories-result')), findsNothing);
    await tester.enterText(find.byKey(const Key('field-calories-age')), '30');
    await tester.pumpAndSettle();

    // Male, moderate activity and maintenance are the defaults
    expect(find.byKey(const Key('calories-result')), findsOneWidget);
    expect(find.textContaining('2759 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calories-accept')));
    await tester.pumpAndSettle();

    expect(result?.energy, 2759);
    expect(result?.protein, 128);
  });

  testWidgets('does not touch the body data by default', (tester) async {
    await tester.pumpWidget(renderDialog());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('field-calories-age')), '30');
    await tester.enterText(find.byKey(const Key('field-calories-weight')), '78');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calories-accept')));
    await tester.pumpAndSettle();

    verifyNever(measurements.addLocalDrift(any));
    expect(_StubUserProfileNotifier.updated, isNull);
  });

  testWidgets('the welcome flow saves the new weight and height', (tester) async {
    await tester.pumpWidget(renderDialog(saveBodyData: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome!'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-calories-age')), '30');
    await tester.enterText(find.byKey(const Key('field-calories-weight')), '78');
    await tester.enterText(find.byKey(const Key('field-calories-height')), '175');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calories-accept')));
    await tester.pumpAndSettle();

    final entry =
        verify(measurements.addLocalDrift(captureAny)).captured.single as MeasurementEntry;
    expect(entry.categoryId, category.id);
    expect(entry.value, 78);
    expect(entry.extraData?['unit'], 'kg');
    expect(_StubUserProfileNotifier.updated?.height, 175);
    expect(result, isNotNull);
  });
}
