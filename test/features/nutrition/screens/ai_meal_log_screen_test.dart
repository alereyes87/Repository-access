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

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mockito/mockito.dart';
import 'package:wger/features/nutrition/ai/meal_parser.dart';
import 'package:wger/features/nutrition/models/log.dart';
import 'package:wger/features/nutrition/providers/ingredient_repository.dart';
import 'package:wger/features/nutrition/providers/nutrition_repository.dart';
import 'package:wger/features/nutrition/screens/ai_meal_log_screen.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/l10n/localizations_delegates.dart';

import '../../../../test_data/nutritional_plans.dart';
import '../../../helpers/fake_connectivity.dart';
import '../widgets/nutritional_meal_form_test.mocks.dart';

class _StubKeyNotifier extends AnthropicKeyNotifier {
  static String? key;

  @override
  Future<String?> build() async => key;
}

void main() {
  installFakeConnectivity();

  late MockNutritionRepository mockRepo;
  late MockIngredientRepository mockIngredientRepo;
  late http.Request? sent;

  setUp(() {
    _StubKeyNotifier.key = 'sk-test';
    sent = null;
    mockRepo = MockNutritionRepository();
    mockIngredientRepo = MockIngredientRepository();
    when(mockRepo.watchAllDrift()).thenAnswer((_) => Stream.value([getNutritionalPlan()]));
    when(mockRepo.watchAllMealsHydrated()).thenAnswer((_) => Stream.value(const []));
    when(mockRepo.watchAllLogsHydrated()).thenAnswer((_) => Stream.value(const []));
    when(mockRepo.addLogLocalDrift(any)).thenAnswer((_) async {});
    when(
      mockIngredientRepo.search(
        any,
        isOnline: anyNamed('isOnline'),
        languageCode: anyNamed('languageCode'),
      ),
    ).thenAnswer((_) async => [milk]);
  });

  Widget render() {
    final client = MockClient((request) async {
      sent = request;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {
                'type': 'text',
                'text': '{"foods":[{"name":"leche","search_term":"leche","grams":250}]}',
              },
            ],
          }),
        ),
        200,
      );
    });

    return ProviderScope(
      overrides: [
        anthropicKeyProvider.overrideWith(_StubKeyNotifier.new),
        mealParserHttpClientProvider.overrideWithValue(client),
        nutritionRepositoryProvider.overrideWithValue(mockRepo),
        ingredientRepositoryProvider.overrideWithValue(mockIngredientRepo),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiMealLogScreen(getNutritionalPlan()),
      ),
    );
  }

  testWidgets('asks for the key when there is none', (tester) async {
    _StubKeyNotifier.key = null;
    await tester.pumpWidget(render());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-key-needed')), findsOneWidget);
    final analyze = tester.widget<FilledButton>(find.byKey(const Key('ai-analyze')));
    expect(analyze.onPressed, isNull);
  });

  testWidgets('analyzes a description and logs the matched foods', (tester) async {
    await tester.pumpWidget(render());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-key-needed')), findsNothing);

    await tester.enterText(find.byKey(const Key('field-ai-meal')), 'un vaso de leche');
    await tester.tap(find.byKey(const Key('ai-analyze')));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(find.text('leche'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget, reason: 'matched ingredient');
    expect(find.text('1250 kcal'), findsOneWidget, reason: '500 kcal/100 g x 250 g');
    verify(
      mockIngredientRepo.search('leche', isOnline: anyNamed('isOnline'), languageCode: 'en'),
    ).called(1);

    await tester.tap(find.byKey(const Key('ai-log')));
    await tester.pumpAndSettle();

    final log = verify(mockRepo.addLogLocalDrift(captureAny)).captured.single as LogItem;
    expect(log.ingredientId, milk.id);
    expect(log.amount, 250);
  });
}
