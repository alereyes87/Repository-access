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
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wger/core/network/network_provider.dart';
import 'package:wger/core/snackbar.dart';
import 'package:wger/core/widgets/decimal_input.dart';
import 'package:wger/features/account/widgets/settings/anthropic_key.dart';
import 'package:wger/features/nutrition/ai/meal_parser.dart';
import 'package:wger/features/nutrition/models/ingredient.dart';
import 'package:wger/features/nutrition/models/meal_item.dart';
import 'package:wger/features/nutrition/models/nutritional_plan.dart';
import 'package:wger/features/nutrition/providers/ingredient_repository.dart';
import 'package:wger/features/nutrition/providers/nutrition_notifier.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

/// Picks a photo for [AiMealLogScreen]; swapped out in tests
typedef PhotoPicker = Future<XFile?> Function(ImageSource source);

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) =>
      (source) => ImagePicker().pickImage(source: source, maxWidth: 1568, imageQuality: 85),
);

/// English name of the language the search terms should be in
String languageNameFor(String languageCode) => switch (languageCode) {
  'es' => 'Spanish',
  'en' => 'English',
  'de' => 'German',
  'fr' => 'French',
  'it' => 'Italian',
  'pt' => 'Portuguese',
  _ => 'the language with the ISO code "$languageCode"',
};

class _FoodRow {
  final ParsedFood food;
  final List<Ingredient> matches;
  Ingredient? selected;
  num grams;
  bool include;

  _FoodRow(this.food, this.matches)
    : selected = matches.firstOrNull,
      grams = food.grams,
      include = matches.isNotEmpty;
}

/// Logs a meal to the diary of [plan] from a description or a photo, with
/// the foods and weights Claude reads from it matched to ingredients
class AiMealLogScreen extends ConsumerStatefulWidget {
  final NutritionalPlan plan;

  const AiMealLogScreen(this.plan, {super.key});

  @override
  ConsumerState<AiMealLogScreen> createState() => _AiMealLogScreenState();
}

class _AiMealLogScreenState extends ConsumerState<AiMealLogScreen> {
  final _logger = Logger('AiMealLogScreen');
  final _text = TextEditingController();
  bool _loading = false;
  String? _error;
  List<_FoodRow>? _rows;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _errorText(AppLocalizations i18n, MealParserError error) => switch (error) {
    MealParserError.invalidKey => i18n.aiErrorInvalidKey,
    MealParserError.rateLimited => i18n.aiErrorRateLimited,
    MealParserError.refusal => i18n.aiErrorRefusal,
    MealParserError.network => i18n.aiErrorNetwork,
    MealParserError.unknown => i18n.aiErrorUnknown,
  };

  Future<void> _run(Future<List<ParsedFood>> Function(ClaudeMealParser, String) call) async {
    final i18n = AppLocalizations.of(context);
    final key = ref.read(anthropicKeyProvider).value;
    if (key == null) {
      return;
    }
    final languageCode = Localizations.localeOf(context).languageCode;
    final parser = ClaudeMealParser(ref.read(mealParserHttpClientProvider), key);

    setState(() {
      _loading = true;
      _error = null;
      _rows = null;
    });
    try {
      final foods = await call(parser, languageNameFor(languageCode));
      final repo = ref.read(ingredientRepositoryProvider);
      final isOnline = ref.read(networkStatusProvider);
      final rows = await Future.wait(
        foods.map((food) async {
          List<Ingredient> matches;
          try {
            matches = await repo.search(
              food.searchTerm,
              isOnline: isOnline,
              languageCode: languageCode,
            );
          } catch (e) {
            _logger.warning('Ingredient search for "${food.searchTerm}" failed', e);
            matches = [];
          }
          return _FoodRow(food, matches.take(5).toList());
        }),
      );
      if (mounted) {
        setState(() => _rows = rows);
      }
    } on MealParserException catch (e) {
      _logger.warning('Meal parsing failed', e);
      if (mounted) {
        setState(() => _error = _errorText(i18n, e.error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _analyzeText() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    await _run((parser, language) => parser.parseText(text, languageName: language));
  }

  Future<void> _analyzePhoto(ImageSource source) async {
    final file = await ref.read(photoPickerProvider)(source);
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final mediaType = name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    final note = _text.text.trim();
    await _run(
      (parser, language) =>
          parser.parsePhoto(bytes, mediaType: mediaType, note: note, languageName: language),
    );
  }

  Future<void> _log() async {
    final i18n = AppLocalizations.of(context);
    final rows = (_rows ?? []).where((r) => r.include && r.selected != null && r.grams > 0);
    final notifier = ref.read(nutritionProvider.notifier);
    final now = DateTime.now();
    var count = 0;
    for (final row in rows) {
      final item = MealItem(
        ingredientId: row.selected!.id,
        amount: row.grams,
        ingredient: row.selected,
      );
      await notifier.logIngredientToDiary(item, widget.plan.id!, now);
      count++;
    }
    if (!mounted) {
      return;
    }
    showSnackbar(context, i18n.aiLogged(count), center: true);
    Navigator.of(context).pop();
  }

  Widget _rowTile(_FoodRow row, AppLocalizations i18n) {
    final selected = row.selected;
    final kcal = selected == null ? null : (selected.energy * row.grams / 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: row.include,
                  onChanged: selected == null
                      ? null
                      : (v) => setState(() => row.include = v ?? false),
                ),
                Expanded(
                  child: Text(row.food.name, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (kcal != null) Text(i18n.kcalValue(kcal.toString())),
              ],
            ),
            if (row.matches.isEmpty)
              Text(i18n.aiNoMatch, style: TextStyle(color: Theme.of(context).colorScheme.error))
            else ...[
              DropdownButton<Ingredient>(
                isExpanded: true,
                value: selected,
                items: row.matches
                    .map(
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(i.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => row.selected = v),
              ),
              DecimalInputWidget(
                value: row.grams,
                labelText: i18n.weight,
                suffixText: 'g',
                min: 1,
                max: 5000,
                onChanged: (v) => setState(() => row.grams = v ?? 0),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final keyState = ref.watch(anthropicKeyProvider);
    final hasKey = keyState.value != null;
    final rows = _rows;

    return Scaffold(
      appBar: AppBar(title: Text(i18n.aiMealLog)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (keyState.hasValue && !hasKey)
            Card(
              key: const Key('ai-key-needed'),
              child: ListTile(
                title: Text(i18n.anthropicKeyNeeded),
                subtitle: Text(i18n.anthropicKeyDescription),
                trailing: const Icon(Icons.key),
                onTap: () => showAnthropicKeyDialog(context, ref),
              ),
            ),
          TextField(
            key: const Key('field-ai-meal'),
            controller: _text,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(hintText: i18n.aiMealLogHint),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('ai-analyze'),
                onPressed: hasKey && !_loading ? _analyzeText : null,
                icon: const Icon(Icons.auto_awesome),
                label: Text(i18n.aiAnalyze),
              ),
              OutlinedButton.icon(
                key: const Key('ai-camera'),
                onPressed: hasKey && !_loading ? () => _analyzePhoto(ImageSource.camera) : null,
                icon: const Icon(Icons.photo_camera),
                label: Text(i18n.aiTakePhoto),
              ),
              OutlinedButton.icon(
                key: const Key('ai-gallery'),
                onPressed: hasKey && !_loading ? () => _analyzePhoto(ImageSource.gallery) : null,
                icon: const Icon(Icons.photo_library),
                label: Text(i18n.aiPickPhoto),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(
              _error!,
              key: const Key('ai-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (rows != null && rows.isEmpty) Text(i18n.aiNothingFound),
          if (rows != null && rows.isNotEmpty) ...[
            Text(i18n.aiEstimateNote, style: Theme.of(context).textTheme.bodySmall),
            ...rows.map((r) => _rowTile(r, i18n)),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('ai-log'),
              onPressed: rows.any((r) => r.include && r.selected != null) ? _log : null,
              child: Text(i18n.aiLogSelected),
            ),
          ],
        ],
      ),
    );
  }
}
